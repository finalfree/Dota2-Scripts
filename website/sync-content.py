"""Refresh the static site's equipment data and original artwork from the repository."""
import json
from pathlib import Path
import re
import shutil
import sys

ROOT = Path(__file__).resolve().parents[1]
WEBSITE = Path(__file__).resolve().parent
DATA = WEBSITE / 'src/data'
PUBLIC = WEBSITE / 'public'
README = (ROOT / 'README.md').read_text(encoding='utf-8')
sys.path.insert(0, str(ROOT / 'scripts'))
from kv_tools import read, tokens

HIGHLIGHTS = {
    '真视宝石·永恒': [('全地图真视', '吸收后，己方队伍永久拥有全地图真视侦测。'), ('高空视野', '吸收者获得高空视野。'), ('永久吸收', '自动吸收，释放物品格。')],
    '玲珑心·精粹': [('冷却缩减', '永久获得 80% 冷却缩减。'), ('范围与距离', '施法距离 +600，作用范围 +400。'), ('持续时间增强', '自身限时增益及对敌人施加的适用限时负面效果持续时间增加 100%。')],
    '三元重戟·升级': [('状态抗性', '提供 80% 状态抗性。'), ('纯粹打击', '攻击不会落空，每次攻击额外造成 100 点纯粹伤害。'), ('攻击距离', '攻击距离 +200，可与其他装备及多件本装备叠加。')],
    '蝶翼之殇': [('基础攻击间隔', '将英雄的基础攻击间隔设为 1.2 秒。'), ('必然致命一击', '对非建筑单位每次攻击必定造成 300% 暴击伤害。'), ('闪避', '提供 85% 闪避。')],
    '不洁魔心': [('不洁狂热', '主动吸血提升至 175%，持续 6 秒，冷却 5 秒。'), ('持续恢复', '每秒恢复最大生命值的 2% 和缺失生命值的 1.5%。'), ('攻击吸血', '提供 30% 攻击吸血。')],
    '无间神镜盾': [('无间回音坚盾', '抵挡并反弹大多数指向性技能。'), ('零冷却', '法术抵挡与反弹效果没有冷却时间。'), ('永久吸收', '自动吸收后永久获得能力，释放物品格。')],
    '深渊冰眼': [('强击', '主动击晕目标 1.6 秒，无视减益免疫。'), ('近远程重击', '近战和远程攻击均有 25% 概率击晕目标 1.2 秒，额外造成 120 点物理伤害。'), ('霜冻攻击', '减缓目标移速和攻速，并降低 50% 生命恢复。')],
    '龙息溅射': [('永久溅射', '自动吸收，攻击对目标周围 500 范围造成 100% 攻击伤害。'), ('近远程适用', '近战和远程英雄都可以触发。'), ('基础属性', '攻击力 +50，生命恢复 +10/秒，魔法恢复 +5/秒。')],
    '怪蛇之息·升级': [('永久攻击距离', '吸收后永久增加 800 攻击距离。'), ('多重攻击', '远程攻击额外攻击周围最多 10 个可见目标，可触发攻击特效。'), ('死亡保留', '吸收效果死亡后保留，攻击距离可与其他装备叠加。')],
    '霜阳神铠': [('恒燃辉耀', '1200 范围持续灼烧，每秒造成 160 点魔法伤害；幻象每秒造成 100 点伤害。'), ('霜冷光环', '降低 1200 范围内敌人 140 攻击速度。'), ('防御属性', '提供 50 护甲、90% 闪避和 400 作用范围加成。')],
}


def plain(text):
    return re.sub(r'<[^>]*>', '', text).replace('**', '').strip()


def main():
    definitions = dict(dict(read(ROOT / 'game/dota_addons/overforged/scripts/npc/npc_items_custom.txt'))['DOTAAbilities'])
    localization = {k.lower(): v for k, v in tokens((ROOT / 'game/dota_addons/overforged/resource/addon_schinese.txt').read_text(encoding='utf-8'))}
    by_name = {localization[('DOTA_Tooltip_Ability_' + key).lower()]: dict(fields)
               for key, fields in definitions.items() if key.startswith('item_lv_')}

    def icon(name):
        definition = by_name['达贡之神力（5级）·升级' if name.startswith('达贡之神力') else name]
        texture = definition['AbilityTextureName'].removeprefix('item_')
        return f'assets/item_{texture}.png' if texture.startswith('lv_') else f'assets/items/{texture}.png'

    featured = []
    text = README.split('## 融合与永久吸收', 1)[1].split('## 升级装备速览', 1)[0]
    for section in re.split(r'^### ', text, flags=re.M)[1:]:
        name, body = section.split('\n', 1)
        price = re.search(r'价格：(\d+)', body)[1]
        lines = [plain(line[2:]) for line in body.splitlines() if line.startswith('- ')]
        name = name.strip()
        featured.append({'name': name, 'price': int(price), 'details': lines, 'icon': icon(name),
                         'highlights': [{'label': label, 'text': value} for label, value in HIGHLIGHTS[name]]})
    physical = {'血棘', '黯灭', '散魂剑', '鱼叉', '幻影斧', '雷神之锤', '银月之晶',
                '辉耀', '圣剑', '英灵胸针', '白银之锋', 'gunpowder_gauntlets'}
    defense = {'强袭胸甲', '永世法衣', '清莲宝珠', '奶酪块', '希瓦的守护', '林肯法球'}
    mobility = {'秘奥闪光', '盛势闪光', '迅疾闪光', '风之杖', '飓风长戟'}
    upgrades = []
    table = README.split('## 升级装备速览', 1)[1].split('## 打包与使用', 1)[0]
    for line in table.splitlines():
        if not line.startswith('| ') or line.startswith(('| 装备', '| ---')):
            continue
        name, price, stats = [s.strip() for s in line.strip('|').split('|')]
        base = name.split('·')[0]
        category = '物理输出' if base in physical else '防御续航' if base in defense else '机动控制' if base in mobility else '法术强化'
        upgrades.append({'name': name, 'price': price, 'stats': stats, 'category': category, 'icon': icon(name)})
    assert len(featured) == 10 and len(upgrades) == 31
    DATA.mkdir(parents=True, exist_ok=True)
    (DATA / 'equipment.json').write_text(json.dumps(
        {'featured': featured, 'upgrades': upgrades}, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    assets = PUBLIC / 'assets'
    assets.mkdir(exist_ok=True)
    for key in ('butterfly_crit', 'satanic_heart', 'abyssal_skadi', 'dragon_splash'):
        name = f'item_lv_{key}.png'
        shutil.copyfile(ROOT / 'artwork/item-icons' / name, assets / name)
    print('Updated 10 featured items, 31 upgrade rows and four original artworks.')


if __name__ == '__main__':
    main()
