#!/usr/bin/env python3
"""
生成升级物品与配方条目。

用法:
    python scripts/gen_item_upgrades.py                 # 只更新 npc_items_custom.txt 的自动生成区
    python scripts/gen_item_upgrades.py --item sheepstick --preview   # 只预览羊刀

设计要点
--------
* 升级物品用 "BaseClass" "item_xxx" 直接 override 原物品，继承其全部 C++ 行为，
  不需要 lua 复刻主动技能（参见 ModDota: Item KeyValues -> BaseClass）。
* 默认 --full-copy：把原物品的 AbilityValues 整块抄全、只替换目标值。
  这样无论引擎的 KV 继承是「递归合并」还是「整体替换」，结果都正确。
* 只覆盖数值，不新增原物品没有的 key（新增 key 在 override 模式下不生效）。
* 三叉戟和蝶翼之殇在 npc_items_custom.txt 的手工区，不属于本文件生成范围。
* 被融合取代的升级物品从生成清单移除，但原 ID 槽位继续保留。
"""

import argparse
import json
import os
import re
import sys
from pathlib import Path
from project_paths import GAME

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ITEMS_TXT = os.path.join(REPO, 'pak01_dir', 'scripts', 'npc', 'items.txt')
OUT_FILE = GAME / 'scripts/npc/npc_items_custom.txt'
BEGIN_GENERATED = '// BEGIN GENERATED UPGRADES -- scripts/gen_item_upgrades.py'
END_GENERATED = '// END GENERATED UPGRADES'

# commit 04f0e8e 的实质改动：{item_name: {字段路径: 目标值}}
# 字段路径中 AbilityValues. 前缀表示 AbilityValues 块内的键
UPGRADES = json.loads(Path(__file__).with_name('item_upgrades.json').read_text(encoding='utf-8'))

ID_START = 10005

# 已发布过的条目、以及移到标准物品文件手工区的条目，都保留 ID 槽位，
# 避免后续自动生成物品的 ID 整体漂移。
RESERVED_ID_SLOTS = {
	'item_abyssal_blade',
	'item_bfury',
	'item_butterfly',
    'item_greater_crit',
    'item_heart',
    'item_kaya_and_sange',
    'item_monkey_king_bar',
    'item_octarine_core',
    'item_sange_and_yasha',
    'item_satanic',
    'item_skadi',
    'item_travel_boots',
    'item_travel_boots_2',
    'item_trident',
    'item_yasha_and_kaya',
}

# ---------------------------------------------------------------- KV 解析

def tokenize(text):
    text = re.sub(r'//[^\n]*', '', text)
    toks, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if c in '{}':
            toks.append((c, None))
            i += 1
        elif c == '"':
            j = text.find('"', i + 1)
            while j != -1 and text[j - 1] == '\\':
                j = text.find('"', j + 1)
            toks.append(('STR', text[i + 1:j]))
            i = j + 1
        else:
            i += 1
    return toks


class Parser:
    def __init__(self, text):
        self.toks = tokenize(text)
        self.pos = 0

    def peek(self):
        return self.toks[self.pos] if self.pos < len(self.toks) else (None, None)

    def take(self):
        t = self.toks[self.pos]
        self.pos += 1
        return t

    def block(self, opened=False):
        if not opened:
            self.take()
        out = []
        while True:
            k, v = self.peek()
            if k is None:
                break
            if k == '}':
                self.take()
                break
            if k == '{':
                self.take()
                self.block(opened=True)
                continue
            if k == 'STR':
                self.take()
                k2, v2 = self.peek()
                if k2 == '{':
                    self.take()
                    out.append((v, self.block(opened=True)))
                elif k2 == 'STR':
                    self.take()
                    out.append((v, v2))
                else:
                    out.append((v, None))
                continue
            self.take()
        return out

    def root(self):
        root = []
        while self.pos < len(self.toks):
            k, v = self.peek()
            if k == 'STR':
                self.take()
                k2, v2 = self.peek()
                if k2 == '{':
                    self.take()
                    root.append((v, self.block(opened=True)))
                elif k2 == 'STR':
                    self.take()
                    root.append((v, v2))
            else:
                self.take()
        return root


def find_items(root):
    found = {}

    def walk(node):
        for k, v in node:
            if isinstance(v, list) and k and k.startswith('item_'):
                found[k] = v
            if isinstance(v, list):
                walk(v)

    walk(root)
    return found


# ---------------------------------------------------------------- 生成

def render(block, indent=1, drop=()):
    """把 KV 块渲染回文本，drop 里的顶层键会被跳过（改由覆盖值提供）"""
    pad = '\t' * indent
    lines = []
    for k, v in block:
        if k in drop:
            continue
        if isinstance(v, list):
            lines.append('%s"%s"' % (pad, k))
            lines.append('%s{' % pad)
            lines.append(render(v, indent + 1))
            lines.append('%s}' % pad)
        else:
            lines.append('%s"%s"\t\t"%s"' % (pad, k, v if v is not None else ''))
    return '\n'.join(lines)


def set_nested(block, path, value):
    """按点分路径在 KV 块里递归设值，支持 AbilityValues.cleave_ending_width.value 这类嵌套。
    返回 True 表示命中。"""
    head, rest = path[0], path[1:]
    for i, (k, v) in enumerate(block):
        if k != head:
            continue
        if not rest:
            if isinstance(v, list):
                # 目标是个块，而覆盖值是个标量 —— 语义不匹配，跳过
                return False
            block[i] = (k, value)
            return True
        if isinstance(v, list):
            return set_nested(v, rest, value)
        return False
    return False


# 这些字段由生成器自己决定，不从原物品复制
SKIP_COPY = {
    'ID',                  # 新分配
    'BaseClass',           # 指向原物品
    'AbilityTextureName',  # 显式写成原物品图标
    'ItemPurchasable',     # 固定 1，进升级树
    'ItemCost',            # 原物品价 + 卷轴价
    'AbilityValues',       # 单独做「抄全 + 覆盖」
    'ItemRecipe', 'ItemResult', 'ItemRequirements',  # 配方专用
}


def gen_item(name, src_block, overrides, item_id, recipe_id, full_copy=True, scroll_cost=1000):
    """返回一个物品的 (recipe_text, item_text)"""
    short = name[5:]  # 去掉 item_ 前缀
    av_overrides = {k[len('AbilityValues.'):]: v
                    for k, v in overrides.items() if k.startswith('AbilityValues.')}
    top_overrides = {k: v for k, v in overrides.items() if not k.startswith('AbilityValues.')}

    # 重要：BaseClass 只继承原物品的 C++ 行为实现，**不继承 KV 字段**。
    # 实测代价：漏掉 AbilityBehavior 时，纯被动物品（代达罗斯之殇）升级后变成可主动释放，
    # 因为 KV 的默认值是 DOTA_ABILITY_BEHAVIOR_UNIT_TARGET。
    # 所以把原物品的标量字段全部显式复制过来，不依赖任何继承行为。
    copied = [(k, v) for k, v in src_block
              if not isinstance(v, list)      # 嵌套块不复制，AbilityValues 单独处理
              and k not in SKIP_COPY
              and k not in top_overrides      # 要覆盖的留给下面统一输出
              and v is not None]

    # 升级物品
    lines = []
    lines.append('\t"item_lv_%s"' % short)
    lines.append('\t{')
    lines.append('\t\t"ID"\t\t\t\t"%d"' % item_id)
    lines.append('\t\t"BaseClass"\t\t\t"%s"\t\t// 继承原物品全部行为，无需 lua' % name)
    lines.append('\t\t"AbilityTextureName"\t\t"%s"' % name)
    for k, v in copied:
        lines.append('\t\t"%s"\t\t\t"%s"' % (k, v))
    # ItemPurchasable 必须为 1：这决定它是否出现在原物品的商店升级树里。
    # 参照 item_lv_gem（commit 77d9811）——升级物品靠 ItemRequirements 关系进升级树，
    # 不需要也不可能通过 shops.txt 列出。
    lines.append('\t\t"ItemPurchasable"\t\t"1"\t\t// 出现在原物品的商店升级树中')
    # 总价 = 原物品 + 卷轴，与 item_lv_gem(900+800=1700) 一致
    base_cost = next((int(v) for k, v in src_block
                      if k == 'ItemCost' and isinstance(v, str) and v.strip().isdigit()), 0)
    lines.append('\t\t"ItemCost"\t\t\t"%d"\t\t// %d 原物品 + %d 卷轴'
                 % (base_cost + scroll_cost, base_cost, scroll_cost))
    for k, v in sorted(top_overrides.items()):
        lines.append('\t\t"%s"\t\t\t"%s"' % (k, v))

    if full_copy:
        # 抄全 AbilityValues，规避「合并 vs 替换」的语义风险
        av = next((v for k, v in src_block if k == 'AbilityValues' and isinstance(v, list)), [])
        av = [(k, [list(x) for x in v] if isinstance(v, list) else v) for k, v in av]
        missing = set()
        for path, val in av_overrides.items():
            if not set_nested(av, path.split('.'), val):
                missing.add(path)
        if av:
            lines.append('')
            lines.append(render([('AbilityValues', av)], indent=2))
        if missing:
            print('  ! %s 原物品缺少字段（override 下不会生效）: %s'
                  % (name, ', '.join(sorted(missing))), file=sys.stderr)
    else:
        if av_overrides:
            lines.append('')
            lines.append('\t\t"AbilityValues"')
            lines.append('\t\t{')
            for kk, vv in sorted(av_overrides.items()):
                lines.append('\t\t\t"%s"\t\t"%s"' % (kk, vv))
            lines.append('\t\t}')
    lines.append('\t}')

    # 升级配方
    rlines = []
    rlines.append('\t"item_recipe_lv_%s"' % short)
    rlines.append('\t{')
    rlines.append('\t\t"ID"\t\t\t\t"%d"' % recipe_id)
    rlines.append('\t\t"BaseClass"\t\t\t"item_datadriven"')
    rlines.append('\t\t"AbilityTextureName"\t\t"item_recipe_ultimate_scepter_2"')
    rlines.append('\t\t"Model"\t\t\t\t"models/props_gameplay/recipe.vmdl"')
    rlines.append('\t\t"ItemCost"\t\t\t"%d"' % scroll_cost)
    rlines.append('\t\t"ItemPurchasable"\t\t"1"')
    rlines.append('\t\t"ItemRecipe"\t\t\t"1"')
    rlines.append('\t\t"ItemResult"\t\t\t"item_lv_%s"' % short)
    rlines.append('\t\t"ItemRequirements"')
    rlines.append('\t\t{')
    rlines.append('\t\t\t"01"\t\t\t\t"%s"' % name)
    rlines.append('\t\t}')
    rlines.append('\t}')

    return '\n'.join(rlines), '\n'.join(lines)


def split_generated(text):
    """Return prefix/body/suffix; refuse missing, repeated or reversed markers."""
    markers = []
    for marker in (BEGIN_GENERATED, END_GENERATED):
        matches = list(re.finditer(r'(?m)^[ \t]*' + re.escape(marker) + r'[ \t]*(?=\r?$)', text))
        if len(matches) != 1:
            raise ValueError('Expected exactly one generated-section marker: ' + marker)
        markers.append(matches[0])
    start, end = markers
    if start.end() >= end.start():
        raise ValueError('Reversed generated-section markers')
    return text[:start.end()], text[start.end():end.start()], text[end.start():]


def replace_generated(text, body):
    prefix, _, suffix = split_generated(text)
    newline = '\r\n' if '\r\n' in text else '\n'
    return prefix + newline + body.strip('\r\n').replace('\r\n', '\n').replace('\n', newline) + newline + suffix


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--item', help='只生成某一个（item_ 前缀可省略）')
    ap.add_argument('--preview', action='store_true', help='打印到 stdout，不写文件')
    ap.add_argument('--no-full-copy', action='store_true',
                    help='不抄全 AbilityValues，只写要覆盖的键（用于验证继承语义）')
    ap.add_argument('--scroll-cost', type=int, default=1000,
                    help='升级卷轴价格，默认 1000（升级物品总价 = 原物品价 + 此值）')
    args = ap.parse_args()
    if args.item and not args.preview:
        ap.error('--item requires --preview; a partial run must not erase other generated items')

    items = find_items(Parser(Path(ITEMS_TXT).read_text(encoding='utf-8-sig')).root())

    id_slots = sorted(set(UPGRADES) | RESERVED_ID_SLOTS)
    targets = sorted(UPGRADES)
    if args.item:
        key = args.item if args.item.startswith('item_') else 'item_' + args.item
        if key not in UPGRADES:
            sys.exit('未在升级清单中找到 %s' % key)
        targets = [key]

    out = ['"DOTAAbilities"', '{', '\t"Version"\t\t"1"', '']
    for name in targets:
        if name not in items:
            sys.exit('items.txt 中找不到 %s；未写入生成区' % name)
        slot = id_slots.index(name)
        rid, iid = ID_START + 2 * slot, ID_START + 2 * slot + 1
        recipe, item = gen_item(name, items[name], UPGRADES[name], iid, rid,
                                full_copy=not args.no_full_copy,
                                scroll_cost=args.scroll_cost)
        out.append('\t//=================================================================================')
        out.append('\t// Upgrade: %s' % name)
        out.append('\t//=================================================================================')
        out.append(item)
        out.append('')
        out.append(recipe)
        out.append('')
    out.append('}')

    text = '\n'.join(out)
    if args.preview:
        print(text)
        return
    # Exclude the standalone preview wrapper/Version. Preserve the manual area verbatim.
    with open(OUT_FILE, encoding='utf-8', newline='') as f:
        current = f.read()
    updated = replace_generated(current, '\n'.join(out[4:-1]))
    with open(OUT_FILE, 'w', encoding='utf-8', newline='') as f:
        f.write(updated)
    print('已生成 %d 个升级物品 -> %s' % (len(targets), os.path.relpath(OUT_FILE, REPO)))
    print('注意：生成后需核对 addon 本地化；VPK 构建直接读取这份 Workshop 源文件。')


if __name__ == '__main__':
    main()
