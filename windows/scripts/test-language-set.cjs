const {readFileSync} = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const {test} = require('node:test');

// The Windows build ships five languages. Spanish stays out of the picker and the page's language
// tables, so a stored 'es' must fall back to English rather than show a half-translated card.
const html = readFileSync(path.join(__dirname, '../codenotch/ui/notch.html'), 'utf8');
const settings = readFileSync(path.join(__dirname, '../codenotch/ui/settings.html'), 'utf8');

test('the settings language picker offers no Spanish', () => {
  const picker = settings.slice(settings.indexOf('<select id="lang"'), settings.indexOf('</select>', settings.indexOf('<select id="lang"')));
  assert.doesNotMatch(picker, /value="es"/);
  const list = settings.match(/const LANGS = (\[[^\]]*\]);/);
  assert.ok(list, 'the settings page keeps its language list');
  assert.ok(!JSON.parse(list[1].replace(/'/g, '"')).includes('es'));
});

test('the notch language list has no Spanish table', () => {
  assert.doesNotMatch(html, /const UI=\{[\s\S]*?\n  es:\{/);
  assert.doesNotMatch(html, /\n  es:\{locale:/);
});
