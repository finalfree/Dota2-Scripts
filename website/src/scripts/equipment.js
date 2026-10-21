'use strict';

import data from '../data/equipment.json';
import { weapons } from '../data/weapons.js';
const featured = new Map(data.featured.map(item => [item.name, item]));


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
  const recipe = item.details.find(detail => (detail.startsWith('合成：') || detail.startsWith('购买：')));
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
  const supplementary = item.details.filter(detail => !(detail.startsWith('合成：') || detail.startsWith('购买：')) && !detail.startsWith('属性：')).join(' ');
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

