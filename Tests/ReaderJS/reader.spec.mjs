// Exercises ReaderRenderer's page scripts in WebKit (Safari's engine).
import { webkit } from 'playwright';
import { readFileSync } from 'fs';
import assert from 'assert/strict';
import { readerCSS } from './css.mjs';

const swift = readFileSync(process.env.RENDERER, 'utf8');
function plain(name) {   // static let x = """ ... """  (Swift escapes: \\ → \)
  const m = swift.match(new RegExp(`static let ${name} = """\\n([\\s\\S]*?)\\n    """`));
  return m[1].replace(/\\\\/g, '\\');
}
function raw(name) {     // static let x = #""" ... """#
  return swift.match(new RegExp(`static let ${name} = #"""\\n([\\s\\S]*?)\\n    """#`))[1];
}
const bootstrap = plain('bootstrapJS'), dual = plain('dualFontJS');
const punct = plain('punctuationJS'), nav = raw('navigationJS');

// The stylesheet the app ships, rebuilt from the Swift source.
const css = readerCSS(process.env.RENDERER);

const para = i => `<p>Paragraph ${i}: “Well,” said Darrow—quietly—“it’s time we went; don’t you think?” ` +
  `The ${i}th line keeps going with enough plain words to wrap several times across a phone screen.</p>`;
const body = `<h1>Chapter One</h1>` + Array.from({ length: 60 }, (_, i) => para(i)).join('') +
  `<p style="margin-bottom:2000px">Last<b>bold</b>word <a href="#x">link</a> ends here.</p>`;
const html = `<!doctype html><html><head><meta name="viewport" content="width=device-width">
<script>window.__msgs=[];window.webkit={messageHandlers:{cb:{postMessage:m=>window.__msgs.push(m)}}};</script>
<script>${bootstrap}</script><script>${nav}</script></head><body>${body}</body></html>`;

const browser = await webkit.launch();
const page = await browser.newPage({ viewport: { width: 390, height: 844 }, hasTouch: true });
await page.setContent(html);
await page.evaluate(c => { window.cbSetStyle(c); window.cbInstallBridge(); }, css);
const settle = () => page.evaluate(() => new Promise(r => window.cbAfterLayout(() => setTimeout(r, 200))));
const msgs = () => page.evaluate(() => window.__msgs.splice(0));
const last = async type => (await msgs()).filter(m => m.type === type).pop();
const current = () => page.evaluate(() => window.cbCurrentWord());
await settle();

// Word list: whitespace runs with a letter; em-dashes joined, “—” alone not a word.
const count = await page.evaluate(() => { window.cbSetMode({ mode: 'word', dual: false, punct: false });
  const n = document.querySelector('#cb-word .cb-word-count').textContent; window.cbSetMode({ mode: 'scroll' }); return n; });
const total = Number(count.split(' / ')[1]);
console.log('words in chapter:', total);
await settle();
assert.equal(total, 2 + 60 * 28 + 4, "word count");   // "Lastboldword" is one word

// 1. Scroll mode: position round-trips.
await page.evaluate(() => window.scrollTo(0, 5000));
await settle();
const k = await current();
assert.ok(k > 100, `first visible after scrolling: ${k}`);
await page.evaluate(() => window.scrollTo(0, 0));
await page.evaluate(i => window.cbGoToWord(i), k);
await settle();
assert.equal(await current(), k, 'scroll restore lands on the same word');
// Saving and restoring repeatedly must not drift.
for (let round = 0; round < 5; round++) {
  const saved = await current();
  await page.evaluate(() => window.scrollTo(0, 0));
  await page.evaluate(i => window.cbGoToWord(i), saved); await settle();
  assert.equal(await current(), saved, `round ${round} drifted`);
}
// A word mid-line restores to its line, which is then stable.
await page.evaluate(i => window.cbGoToWord(i), k + 3); await settle();
const lineStart = await current();
assert.ok(lineStart <= k + 3 && lineStart >= k + 3 - 12, `mid-line restore → ${lineStart}`);
await page.evaluate(i => window.cbGoToWord(i), k); await settle();
const pos = await last('position');
assert.equal(pos.word, k); assert.equal(pos.words, total); assert.equal(pos.page, -1);

// 2. Wrapping for two fonts and tinting punctuation doesn't move word indexes.
// Same order as ReaderModel.settingsChanged: restyle (which remembers the place), then wrap.
await page.evaluate(src => { window.cbSetStyle(src.css); eval(src.dual); eval(src.punct); }, { dual, punct, css });
await settle();
const kw = await current();
assert.ok(kw <= k && k - kw <= 12, `still on the same line after wrapping: ${k} → ${kw}`);
const wrappedTotal = await page.evaluate(() => { window.cbSetMode({ mode: 'word', dual: true, punct: true });
  return document.querySelector('#cb-word .cb-word-count').textContent; });
assert.equal(wrappedTotal, `${kw + 1} / ${total}`, 'word mode keeps the place and count after wrapping');
await settle();

// 3. Word mode: taps step, outer-left at 0 asks for the previous chapter.
const wordText = () => page.evaluate(() => {
  const el = document.querySelector('#cb-word .cb-word-text').cloneNode(true);
  el.querySelectorAll('rt').forEach(rt => rt.remove());   // main text only
  return el.textContent;
});
await page.evaluate(() => window.cbGoToWord(0));
assert.equal(await wordText(), 'Chapter');
await page.mouse.click(370, 400); await settle();
assert.equal(await wordText(), 'One');
await page.mouse.click(370, 400); await page.mouse.click(370, 400); await settle();
assert.equal(await wordText(), '0:', 'punctuation stays with its word');
await page.mouse.click(370, 400); await settle();
assert.equal(await wordText(), '“Well,”');
const ruby = await page.evaluate(() => document.querySelector('#cb-word .cb-word-text').innerHTML);
assert.match(ruby, /<ruby><span class="cb-punct">“<\/span>|<span class="cb-punct">“<\/span><ruby>/, 'punctuation outside the ruby pair');
assert.match(ruby, /<ruby>Well<rt>Well<\/rt><\/ruby>/);
await page.mouse.click(20, 400); await settle();
assert.equal(await wordText(), '0:');
await page.evaluate(() => window.cbGoToWord(0)); await msgs();
await page.mouse.click(20, 400); await settle();
assert.deepEqual((await msgs()).find(m => m.type === 'edge'), { type: 'edge', value: 'previous' });
await page.mouse.click(195, 400); await settle();
assert.ok((await msgs()).some(m => m.type === 'tap'), 'middle tap toggles chrome');
await page.evaluate(() => window.cbGoToWord(-1)); await settle();
assert.equal(await wordText(), 'here.', '-1 is the last word');
await page.mouse.click(370, 400); await settle();
assert.ok((await msgs()).some(m => m.type === 'edge' && m.value === 'next'));

// 4. Page mode: columns, turning, and restoring a word onto its page.
await page.evaluate(i => { window.cbGoToWord(i); window.cbSetMode({ mode: 'paged', dual: true, punct: true }); }, k);
await settle();
let p = await last('position');
console.log('pages:', p.pages, 'restored on page', p.page, 'first word', p.word);
assert.ok(p.pages > 5, 'several pages');
assert.ok(p.word <= k, 'restored page starts at or before the word');
const onPage = await page.evaluate(i => {
  // the word's rect must be on screen
  return window.cbCurrentWord() <= i;
}, k);
assert.ok(onPage);
const startPage = p.page;
await page.mouse.click(370, 400); await settle();
p = await last('position');
assert.equal(p.page, startPage + 1, 'right tap turns forward');
assert.ok(p.word > k, 'next page starts after the restored word');
await page.mouse.click(20, 400); await settle();
assert.equal((await last('position')).page, startPage, 'left tap turns back');
// swipe left = forward
await page.evaluate(() => {
  const t = (type, x) => {
    const e = new Event(type);
    const point = [{ clientX: x, clientY: 400 }];
    Object.defineProperty(e, 'touches', { value: type === 'touchend' ? [] : point });
    Object.defineProperty(e, 'changedTouches', { value: point });
    document.dispatchEvent(e);
  };
  t('touchstart', 300); t('touchend', 100);
  document.elementFromPoint(100, 400).click();   // the click iOS fires after a swipe that ends on the left
});
await settle();
const swiped = await last('position');
assert.equal(swiped.page, startPage + 1, 'swipe left turns forward');
// A swipe must not also count as a tap on the side it ended on.
assert.ok(!(await msgs()).some(m => m.type === 'tap'));
// last page → next chapter
await page.evaluate(() => window.cbGoToWord(-1)); await settle();
p = await last('position');
assert.equal(p.page, p.pages - 1, 'last word is on the last page');
await page.mouse.click(370, 400); await settle();
assert.ok((await msgs()).some(m => m.type === 'edge' && m.value === 'next'));

// 5. Every page's first word is later than the previous page's (no lost or repeated pages).
await page.evaluate(() => window.cbGoToWord(0)); await settle();
let prev = -1;
for (let i = 0; i < p.pages; i++) {
  const w = await current();
  assert.ok(w > prev, `page ${i} starts at ${w}, after ${prev}`);
  prev = w;
  await page.mouse.click(370, 400); await settle();
}

// 6. Back to scroll keeps the place; a restyle (bigger text) keeps it too.
await page.evaluate(i => window.cbGoToWord(i), 900); await settle();
const before = await current();
await page.evaluate(() => window.cbSetMode({ mode: 'scroll', dual: true, punct: true })); await settle();
const after = await current();
assert.ok(Math.abs(after - before) <= 30, `scroll after pages: ${before} → ${after}`);
await page.evaluate(c => window.cbSetStyle(c + 'body{font-size:30px !important}'), css); await settle();
const big = await current();
assert.ok(Math.abs(big - after) <= 3, `restyle keeps place: ${after} → ${big}`);

// 7. Entering pages or word mode must leave no vertical scroll behind: the document is
// then one screen tall, and iOS keeps the old offset (with scrolling off, showing blank).
for (const mode of ['paged', 'word']) {
  await page.evaluate(() => window.cbSetMode({ mode: 'scroll', dual: true, punct: true }));
  await settle();
  await page.evaluate(() => window.scrollTo(0, 4000));
  await page.evaluate(m => window.cbSetMode({ mode: m, dual: true, punct: true }), mode);
  await settle();
  assert.equal(await page.evaluate(() => window.pageYOffset), 0, `${mode} mode scrolled to top`);
}

console.log('all reader script checks passed');
await browser.close();
