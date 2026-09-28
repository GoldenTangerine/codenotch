/**
 * @name: Windows 上游同步回归
 * @Descripttion: 使用模拟 DOM 与 Tauri 验证页面启动和本地托盘功能兼容。
 * @version: 1.0.0
 * @Author: sm
 * @Date: 2026-09-17 16:35:00
 * @LastEditTime: 2026-09-17 16:35:00
 * @FilePath: windows/scripts/upstream-sync.test.mjs
 */
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import { test } from 'node:test';

async function page(name) {
  const elements = new Map(), calls = [], events = new Map(), responses = new Map();
  function element(id = '') {
    const classes = new Set();
    return {
      id, dataset: {}, style: { setProperty() {} }, value: '', _html: '', _text: '',
      get textContent() { return this._text; },
      set textContent(value) {
        this._text = String(value);
        this._html = this._text.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
      },
      get innerHTML() { return this._html; },
      set innerHTML(value) { this._html = String(value); },
      hidden: false, disabled: false, children: [], listeners: {},
      classList: { add: x => classes.add(x), remove: x => classes.delete(x),
        contains: x => classes.has(x), toggle: (x, on) => on ? classes.add(x) : classes.delete(x) },
      addEventListener(type, callback) { this.listeners[type] = callback; },
      setAttribute() {}, getAttribute() { return null; }, hasAttribute() { return false; },
      appendChild(child) { this.children.push(child); }, remove() {},
      querySelectorAll() { return []; }, querySelector() { return null; }, closest() { return null; },
      getBoundingClientRect() { return { left: 0, top: 0, right: 70, bottom: 200, width: 70, height: 200 }; }
    };
  }
  const get = id => {
    if (!elements.has(id)) elements.set(id, element(id));
    return elements.get(id);
  };
  const invoke = async (command, args) => {
    calls.push({ command, args });
    if (responses.has(command)) return responses.get(command)(args);
    return ({ get_lang: 'auto', get_lang_resolved: 'uk', get_notch_edge: 'right',
      get_monitors: [], get_tray_options: [], get_notch_slots: [], get_glyphs: {},
      get_tray_config: { mode: 'bars', slots: [{ provider: 'claude' }, { provider: 'grok' }] }
    })[command] ?? null;
  };
  const document = { body: element(), documentElement: element(), getElementById: get,
    createElement: () => element(), querySelectorAll: () => [], addEventListener() {},
    createTreeWalker: () => ({ nextNode: () => false }) };
  const context = vm.createContext({ console, document, navigator: { language: 'zh-CN' },
    NodeFilter: { SHOW_TEXT: 4 }, localStorage: { getItem: () => null, setItem() {} },
    setTimeout: () => 0, clearTimeout() {}, setInterval: () => 0, clearInterval() {},
    requestAnimationFrame: () => 0, performance: { now: () => 0 },
    getComputedStyle: () => ({ getPropertyValue: () => '' }),
    innerWidth: 360, innerHeight: 520, devicePixelRatio: 1,
    matchMedia: () => ({ matches: false, addEventListener() {} }),
    __TAURI__: { core: { invoke }, event: { listen: async (name, cb) => { events.set(name, cb); } },
      window: { getCurrentWindow: () => ({ close: async () => {}, onFocusChanged: async () => {} }) } }
  });
  context.window = context;
  context.addEventListener = () => {};
  const html = readFileSync(new URL(`../codenotch/ui/${name}.html`, import.meta.url), 'utf8');
  const code = [...html.matchAll(/<script[^>]*>([\s\S]*?)<\/script>/g)].map(x => x[1]).join('\n');
  vm.runInContext(code, context, { filename: name + '.html' });
  const run = code => vm.runInContext(code, context);
  const flush = async () => { for (let i = 0; i < 15; i++) await Promise.resolve(); };
  await flush();
  return { run, get, calls, responses, events, flush };
}

test('settings starts with saved tray layout and resolved language without saving', async () => {
  const p = await page('settings');
  assert.equal(p.run('uiLang'), 'uk');
  assert.equal(p.run('trayConfig.mode'), 'bars');
  assert.equal(p.run('trayConfig.slots[1].provider'), 'grok');
  assert.equal(p.run('ui("Edge", "Edge")'), 'Край');
  assert.ok(!p.calls.some(x => x.command.startsWith('set_')));
  p.responses.set('set_tray_config', () => { throw new Error('save failed'); });
  await p.run('saveTray({mode:"numbers",slots:[{provider:"codex"}]})');
  await p.flush();
  assert.equal(p.run('trayConfig.mode'), 'bars');
  assert.equal(p.run('trayBusy'), false);
});

test('Grok uses its credit ring and edge changes preserve card rendering', async () => {
  const p = await page('notch');
  p.run('grokSnap={status:"ok",windows:[{id:"credits",label:"Weekly credits",used:0.3}],fetched_at:0}; hoverId="grok";');
  assert.equal(p.run('headlineOf(grokSnap,"grok").used'), 0.3);
  assert.equal(p.run('weeklyOf(grokSnap,"grok")'), null);
  p.run('stateSnap.lang_resolved="zh"; renderCard();');
  assert.match(p.get('card').innerHTML, /Grok/);
  for (const edge of ['left', 'right', 'top', 'bottom']) {
    p.run(`applyEdge(${JSON.stringify(edge)})`);
    assert.equal(p.run('notchEdge'), edge);
    assert.equal(p.run('edgeIsVertical()'), ['left', 'right'].includes(edge));
  }
  assert.match(p.run('tr("Run grok login to see usage.")'), /运行 grok login/);
});
