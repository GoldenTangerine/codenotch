/**
 @name: Windows 刘海本地化回归
 @Descripttion: 验证实际页面翻译入口的语言切换与占位符。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-14 12:00:00
 @LastEditTime: 2026-09-14 12:00:00
 @FilePath: Scripts/test-notch-localization.mjs
 */
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const html = readFileSync(new URL('../windows/codenotch/ui/notch.html', import.meta.url), 'utf8');
const russian = html.slice(html.indexOf('const RU_TEXT='), html.indexOf('// "Is it working?"'));
const translations = html.slice(html.indexOf('const ZH ='), html.indexOf('function resetCopy('));
assert.ok(russian && translations, 'Page translation entry points must exist');
const context = vm.createContext({ stateSnap: { lang: 'en' }, navigator: { language: 'en-US' } });
vm.runInContext(russian + '\n' + translations, context);
const evaluate = code => vm.runInContext(code, context);
assert.equal(evaluate("tr('Usage')"), 'Usage');
context.stateSnap.lang = 'zh';
assert.equal(evaluate("tr('Resets in {n} min', {n: 3})"), '3 分钟后重置');
assert.equal(evaluate("providerCopy('5h limit')"), '5 小时限额');
context.stateSnap.lang = 'ru';
assert.equal(evaluate("tr('Usage')"), 'Использование');
assert.equal(evaluate("tr('{n}% Used', {n: 80})"), 'Использовано 80%');
assert.equal(evaluate("tr('Resets in {n} min', {n: 3})"), 'Сброс через 3 мин');
assert.equal(evaluate("providerCopy('5h limit')"), 'Лимит на 5 ч');
assert.equal(evaluate('locale()'), 'ru-RU');
context.stateSnap.lang = 'auto';
context.navigator.language = 'ru-RU';
assert.equal(evaluate("tr('Usage')"), 'Использование');
context.stateSnap.lang_resolved = 'zh';
assert.equal(evaluate("tr('Usage')"), '用量');
const readings = html.slice(html.indexOf('function smallPct('), html.indexOf('let usage='));
const reset = html.slice(html.indexOf('function resetCopy('), html.indexOf('const STATE_DOT='));
vm.runInContext(readings + '\n' + reset, context);
assert.equal(evaluate('pctText(0.003)'), '0.3');
assert.equal(evaluate('usedCopy({used:0.003})'), '已用 0.3% · 剩余 99.7%');
context.stateSnap.lang_resolved = 'en';
assert.match(evaluate('resetCopy(Date.now()+59*60000+40000)'), /^Resets at /);
assert.match(evaluate('resetCopy(Date.now()+26*86400000)'), /^Resets /);
assert.doesNotMatch(evaluate('resetCopy(Date.now()+26*86400000)'), /Mon|Tue|Wed|Thu|Fri|Sat|Sun/);
for (const page of ['notch', 'settings']) {
  const source = readFileSync(new URL(`../windows/codenotch/ui/${page}.html`, import.meta.url), 'utf8');
  for (const block of source.matchAll(/<script[^>]*>([\s\S]*?)<\/script>/g)) new vm.Script(block[1]);
}
const settings = readFileSync(new URL('../windows/codenotch/ui/settings.html', import.meta.url), 'utf8');
let stored = false, failWrite = false, writes = 0;
const errors = [];
const switches = vm.createContext({
  call: async () => stored,
  invoke: async (_command, args) => {
    writes++;
    if (failWrite) throw new Error('write rejected');
    stored = args.on;
  },
  strip: message => errors.push(message),
  errText: String,
  toast: () => {},
});
vm.runInContext(settings.slice(settings.indexOf('function remote('), settings.indexOf('function drawSwitch(')), switches);
vm.runInContext("var toggle = remote('read', 'write', 'Test', () => {}); toggle.toggle(); toggle.toggle();", switches);
await new Promise(resolve => setImmediate(resolve));
assert.equal(writes, 1, 'A busy switch must reject duplicate clicks');
assert.equal(vm.runInContext('toggle.value', switches), true);
failWrite = true;
vm.runInContext('toggle.toggle()', switches);
await new Promise(resolve => setImmediate(resolve));
assert.equal(vm.runInContext('toggle.value', switches), true, 'Failed writes must restore the actual stored state');
assert.equal(vm.runInContext('toggle.busy', switches), false);
assert.equal(errors.length, 1);
context.stateSnap.lang = 'uk';
delete context.stateSnap.lang_resolved;
assert.equal(evaluate("tr('Usage')"), 'Використання');
assert.equal(evaluate("tr('Resets in {n} min', {n:3})"), 'Скидання через 3 хв');
assert.equal(evaluate("providerCopy('5h limit')"), 'Ліміт на 5 год');
assert.equal(evaluate('usedCopy({used:0.2})'), 'Використано 20% · лишилось 80%');
assert.equal(evaluate('locale()'), 'uk-UA');
assert.deepEqual(evaluate('Object.keys(TEXT.ru).filter(key => !TEXT.uk[key])'), vm.runInContext('[]', context));
for (const key of evaluate('Object.keys(ZH)')) {
  context.testKey = key;
  assert.notEqual(evaluate('tr(testKey)'), key, `Missing Ukrainian notch copy: ${key}`);
}
context.stateSnap.lang = 'auto';
context.navigator.language = 'uk-UA';
assert.equal(evaluate("tr('Usage')"), 'Використання');

const langContext = vm.createContext({
  navigator: {language:'uk-UA'}, NodeFilter:{SHOW_TEXT:4},
  document: {documentElement:{}, createTreeWalker:() => ({nextNode:() => false}), querySelectorAll:() => []},
  renderAll:() => {},
});
vm.runInContext(settings.slice(settings.indexOf('const RU_STATIC ='), settings.indexOf('/* ---- small chrome')), langContext);
vm.runInContext("setUiLanguage('uk')", langContext);
assert.equal(vm.runInContext("ui('Accounts','Accounts')", langContext), 'Акаунти');
vm.runInContext("setUiLanguage('auto')", langContext);
assert.equal(langContext.document.documentElement.lang, 'uk');
assert.equal(vm.runInContext('Object.keys(ZH_STATIC).filter(key => !UK_STATIC[key]).join()', langContext), '');

const elements = new Map();
function element(id) {
  if(!elements.has(id)) elements.set(id, {handlers:{}, addEventListener(type, fn){this.handlers[type]=fn;}});
  return elements.get(id);
}
let trayStored = {mode:'bars',slots:[{provider:'cursor'},{provider:'claude'},{provider:'gemini'}]};
let trayWrites = 0, trayFail = false, previewDeferred = false;
const previewResolvers = [];
const trayContext = vm.createContext({
  document:{getElementById:element}, ORDER:['claude','codex','cursor','gemini'],
  providerList:() => ['claude','codex','cursor','gemini'].map(id => ({id,label:id})),
  ui:(_key,fallback) => fallback, esc:String, strip:() => {}, errText:String, toast:() => {},
  invoke:async (command,args) => {
    if(command === 'get_tray_config') return structuredClone(trayStored);
    if(command === 'set_tray_config') {
      trayWrites++;
      if(trayFail) throw new Error('write rejected');
      trayStored = structuredClone(args.cfg);
      return;
    }
    if(previewDeferred) return new Promise(resolve => previewResolvers.push(resolve));
    return command === 'get_app_icon' ? 'data:image/png;base64,icon' : 'data:image/png;base64,preview';
  },
});
const trayEval = code => vm.runInContext(code, trayContext);
vm.runInContext(settings.slice(settings.indexOf('let trayConfig ='), settings.indexOf('/* ---- Appearance: size')), trayContext);
await trayEval('loadTray()');
assert.equal(trayWrites, 0, 'Opening settings must not overwrite the existing layout');
assert.equal(trayEval('JSON.stringify(trayConfig)'), JSON.stringify(trayStored));
const flush = () => new Promise(resolve => setImmediate(resolve));
const layout = async mode => {element('tray-layout').handlers.change({target:{value:mode}}); await flush();};
await layout('numbers');
assert.equal(trayStored.slots.length, 2);
element('tray-slots').handlers.change({target:{dataset:{traySlot:'0'},value:'codex'}});
await flush();
assert.equal(trayStored.slots[0].provider, 'codex');
await layout('off');
assert.equal(element('tray-preview').src, 'data:image/png;base64,icon');
assert.equal(trayStored.slots[0].provider, 'codex');
await layout('bars');
for(let i=0;i<8;i++){element('tray-add').handlers.click(); await flush();}
assert.equal(trayStored.slots.length, 5);
for(let i=0;i<8;i++){
  element('tray-slots').handlers.click({target:{closest:() => ({dataset:{trayRemove:'0'}})}});
  await flush();
}
assert.equal(trayStored.slots.length, 1);
trayFail = true;
const beforeFailure = JSON.stringify(trayStored);
const beforeWrites = trayWrites;
element('tray-add').handlers.click();
element('tray-add').handlers.click();
await flush();
assert.equal(trayWrites, beforeWrites+1, 'Busy edits must not race');
assert.equal(trayEval('JSON.stringify(trayConfig)'), beforeFailure, 'Failed edits must roll back');
assert.equal(trayEval('trayBusy'), false);
previewDeferred = true;
const oldPreview = trayEval('refreshTrayPreview()');
const newPreview = trayEval('refreshTrayPreview()');
previewResolvers[1]('data:image/png;base64,new');
await newPreview;
previewResolvers[0]('data:image/png;base64,old');
await oldPreview;
assert.equal(element('tray-preview').src, 'data:image/png;base64,new', 'Old previews must not overwrite newer ones');
console.log('Windows localization, tray settings and switch regression checks passed');
