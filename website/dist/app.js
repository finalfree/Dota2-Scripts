'use strict';

const data = window.OVERFORGED_DATA;
const featured = new Map(data.featured.map(item => [item.name, item]));
const weapons = [
  {name:'蝶翼之殇',key:'butterfly_crit',tag:'必然致命',recipe:'蝴蝶 + 代达罗斯之殇',description:'蝶翼引导锋刃，每一次挥击都通往终结。基础攻击间隔设为 1.2 秒，让锋芒更快抵达。',stats:[['1.2s','基础攻击间隔'],['100%','暴击概率'],['300%','暴击伤害'],['85%','闪避']]},
  {name:'不洁魔心',key:'satanic_heart',tag:'不灭狂热',recipe:'撒旦之邪力 + 恐鳌之心',description:'让从未停跳的心，驱动从未饱饮的利刃。吸血与生命恢复，化为持续作战的底气。',stats:[['175%','主动吸血'],['5s','主动冷却'],['+75','力量']]},
  {name:'深渊冰眼',key:'abyssal_skadi',tag:'冰封深渊',recipe:'深渊之刃 + 斯嘉蒂之眼',description:'当深渊也被冻结，每一次进攻都是压制。融合主动强击、被动重击与霜冻攻击。',stats:[['25%','重击概率'],['100%','减速抗性'],['+100','全属性']]},
  {name:'龙息溅射',key:'dragon_splash',tag:'永久攻击溅射',recipe:'狂战斧或行家阵列 + 升级配方',description:'将黑龙之息融入血脉。自动吸收，近战与远程攻击均可释放永久范围溅射。',stats:[['500','溅射范围'],['100%','溅射伤害'],['0','占用物品格']]}
];

function element(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

function itemIcon(item, className) {
  const image = element('img', className);
  image.src = item.icon;
  image.alt = `${item.name}游戏图标`;
  image.loading = 'lazy';
  image.width = 88;
  image.height = 64;
  return image;
}

document.querySelectorAll('.ascension-card').forEach(card => {
  const item = featured.get(card.dataset.detail);
  card.querySelector('.rune').replaceWith(itemIcon(item,'rune item-native-icon'));
});
document.querySelectorAll('.fusion-strip [data-detail]').forEach(button => {
  const item = featured.get(button.dataset.detail);
  button.querySelector('.fusion-symbol').replaceWith(itemIcon(item,'fusion-item-icon'));
});

const weaponGrid = document.querySelector('#weapon-grid');
weapons.forEach((weapon, index) => {
  const item = featured.get(weapon.name);
  const button = element('button','weapon-card');
  button.dataset.detail = weapon.name;
  button.setAttribute('aria-label', `查看${weapon.name}：配方、属性与效果`);
  const picture = element('div','weapon-image');
  const img = element('img');
  img.src = `assets/item_lv_${weapon.key}.png`;
  img.alt = `${weapon.name}专属原画`;
  img.loading = 'lazy';
  img.width = 1470;
  img.height = 1070;
  picture.append(img,element('span','item-tag',weapon.tag),element('span','weapon-number',`0${index+1} / 04`));
  const info = element('div','weapon-info');
  const title = element('div','weapon-title');
  title.append(element('h3','',weapon.name),element('span','price',item.price.toLocaleString('en-US')));
  const stats = element('div','weapon-stats');
  weapon.stats.forEach(([value,label]) => {
    const stat = element('span');
    stat.append(element('b','',value),element('span','',label));
    stats.append(stat);
  });
  info.append(title,element('p','recipe',weapon.recipe),element('p','weapon-description',weapon.description),stats,element('span','detail-arrow','↗'));
  button.append(picture,info);
  weaponGrid.append(button);
});

const dialog = document.querySelector('#item-dialog');
const dialogContent = document.querySelector('#dialog-content');
document.addEventListener('click', event => {
  const trigger = event.target.closest('[data-detail]');
  if (!trigger) return;
  const item = featured.get(trigger.dataset.detail);
  if (!item) return;
  dialogContent.replaceChildren();
  const artwork = weapons.find(weapon => weapon.name === item.name);
  if (artwork || item.name === '三元重戟·升级') {
    const img = element('img','dialog-art');
    img.src = artwork ? `assets/item_lv_${artwork.key}.png` : 'assets/trident-hero.png';
    img.alt = `${item.name}原画`;
    dialogContent.append(img);
  }
  const body = element('div','dialog-body');
  const title = element('h2','dialog-title',item.name);
  title.id = 'dialog-title';
  const identity = element('div','dialog-identity');
  identity.append(itemIcon(item,'dialog-item-icon'),title);
  body.append(element('p','eyebrow','OVERFORGED / EQUIPMENT ARCHIVE'),identity,element('p','dialog-price',`成品配置标价 · ${item.price.toLocaleString('en-US')} 金`));
  const recipe = item.details.find(detail => detail.startsWith('合成：'));
  if (recipe) body.append(element('p','dialog-recipe',recipe));
  const list = element('ul');
  item.highlights.forEach(highlight => {
    const point = element('li','ability-point');
    point.append(element('strong','',highlight.label),element('p','',highlight.text));
    list.append(point);
  });
  body.append(list);
  const attributes = item.details.find(detail => detail.startsWith('属性：'));
  if (attributes) body.append(element('p','dialog-attributes',attributes));
  const supplementary = item.details.filter(detail => !detail.startsWith('合成：') && !detail.startsWith('属性：')).join(' ');
  const notes = element('details','dialog-notes');
  notes.append(element('summary','','完整效果与使用说明'),element('p','',supplementary));
  body.append(notes,element('p','item-note','替代合成路线的实际材料花费可能不同。技能交互以游戏实际效果为准。'));
  dialogContent.append(body);
  dialog.showModal();
  document.body.style.overflow = 'hidden';
});
document.querySelector('.dialog-close').addEventListener('click',() => dialog.close());
dialog.addEventListener('close', () => { document.body.style.overflow = ''; });
dialog.addEventListener('click', event => {
  if (event.target !== dialog) return;
  const rect = dialog.getBoundingClientRect();
  if (event.clientX < rect.left || event.clientX > rect.right || event.clientY < rect.top || event.clientY > rect.bottom) dialog.close();
});

let category = '全部';
let expanded = false;
const search = document.querySelector('#item-search');
const rows = document.querySelector('#upgrade-rows');
const count = document.querySelector('#result-count');
const showMore = document.querySelector('#show-more');
function renderCatalog() {
  const query = search.value.trim().toLocaleLowerCase('zh-CN');
  const filtered = data.upgrades.filter(item => (category === '全部' || item.category === category) && `${item.name} ${item.stats} ${item.category}`.toLocaleLowerCase('zh-CN').includes(query));
  const visible = expanded || query || category !== '全部' ? filtered : filtered.slice(0,8);
  rows.replaceChildren();
  visible.forEach(item => {
    const row = element('tr');
    const title = element('td');
    const identity = element('div','catalog-item');
    const text = element('span','catalog-item-name',item.name);
    text.append(element('span','category',item.category));
    identity.append(itemIcon(item,'catalog-item-icon'),text);
    title.append(identity);
    row.append(title,element('td','',item.price),element('td','',item.stats));
    rows.append(row);
  });
  count.textContent = `${category === '全部' ? '全部' : category} · ${filtered.length} 件装备${visible.length < filtered.length ? `，当前展示 ${visible.length} 件` : ''}`;
  document.querySelector('#empty-state').hidden = filtered.length > 0;
  showMore.hidden = !!query || category !== '全部' || filtered.length <= 8;
  showMore.setAttribute('aria-expanded', String(expanded));
  showMore.textContent = expanded ? '收起装备列表  −' : `展开全部 ${filtered.length} 件装备  ＋`;
}
document.querySelectorAll('[data-filter]').forEach(button => {
  button.addEventListener('click',() => {
    category = button.dataset.filter;
    document.querySelectorAll('[data-filter]').forEach(other => {
      const active = other === button;
      other.classList.toggle('active', active);
      other.setAttribute('aria-pressed', String(active));
    });
    renderCatalog();
  });
});
search.addEventListener('input', renderCatalog);
showMore.addEventListener('click', () => {
  expanded = !expanded;
  renderCatalog();
  if (!expanded) document.querySelector('#upgrades').scrollIntoView({behavior:matchMedia('(prefers-reduced-motion: reduce)').matches?'instant':'smooth'});
});
document.addEventListener('keydown',event => {
  if (event.key === '/' && !dialog.open && !['INPUT','TEXTAREA'].includes(document.activeElement.tagName) && !event.ctrlKey && !event.metaKey && !event.altKey) {
    event.preventDefault();
    search.scrollIntoView({block:'center'});
    search.focus({preventScroll:true});
  }
});
renderCatalog();

if ('IntersectionObserver' in window) {
  const links = [...document.querySelectorAll('nav a')];
  const observer = new IntersectionObserver(entries => {
    entries.forEach(entry => {
      if (entry.isIntersecting) links.forEach(link => link.classList.toggle('current', link.hash === `#${entry.target.id}`));
    });
  }, {rootMargin:'-20% 0px -55% 0px'});
  ['ascension','arsenal','upgrades'].forEach(id => observer.observe(document.getElementById(id)));
}
