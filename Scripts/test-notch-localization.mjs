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
const russian = html.slice(html.indexOf('const RU_TEXT='), html.indexOf('// Notch size,'));
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
console.log('Windows notch localization checks passed');
