import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const baseCSS = readFileSync(new URL('../src/renderer/styles.css', import.meta.url), 'utf8');
const todayCSS = readFileSync(new URL('../src/renderer/today/today.css', import.meta.url), 'utf8');
function declarations(css: string, selector: string) {
  const rule = [...css.matchAll(/([^{}]+)\{([^{}]*)\}/g)].find(match => match[1].trim() === selector);
  assert.ok(rule, `Missing CSS rule: ${selector}`);
  return Object.fromEntries(rule[2].split(';').filter(Boolean).map(item => {
    const colon = item.indexOf(':');
    return [item.slice(0, colon).trim(), item.slice(colon + 1).trim()];
  }));
}

test('global and Today completion checks share the theme blue token and white glyph', () => {
  assert.equal(declarations(baseCSS, ':root')['--completion-blue'], 'var(--blue)');
  for (const [css, selector] of [
    [baseCSS, '.task-check.checked,.completed .task-check'],
    [todayCSS, '.today-task-row.completed .task-check'],
  ]) {
    const style = declarations(css, selector);
    assert.equal(style.background, 'var(--completion-blue)');
    assert.equal(style['border-color'], 'var(--completion-blue)');
    assert.equal(style.color, '#fff');
  }
  assert.equal(declarations(todayCSS, '.today-completion>svg').color, 'var(--completion-blue)');
});

test('actual-time category keeps its independent green styling', () => {
  const actual = declarations(todayCSS, '.today-timeline-card.actual');
  assert.equal(actual.background, '#eaf5ef');
  assert.equal(actual['border-left-color'], '#66a28c');
  assert.equal(actual.color, '#397b68');
});

test('refined selection uses shared tokens in light and dark modes', () => {
  assert.match(baseCSS, /\.task-row.selected,\.today-task-row.selected\{background:var\(--selection-bg\)/);
  assert.match(baseCSS, /:root\[data-theme="dark"\] \.task-row.selected\{background:var\(--selection-bg\)/);
  assert.match(baseCSS, /:root\{color:var\(--text\);background:var\(--canvas\)\}/);
  assert.match(todayCSS, /\.today-timeline-card\.compact-card\{[^}]*flex-direction:row/);
});
test('small key text and primary control labels meet 4.5:1 contrast; completion glyphs meet 3:1', () => {
  const luminance=(hex:string)=>hex.match(/../g)!.map(c=>parseInt(c,16)/255).map(c=>c<=.04045?c/12.92:((c+.055)/1.055)**2.4).reduce((n,c,i)=>n+c*[.2126,.7152,.0722][i],0);
  const contrast=(a:string,b:string)=>{const [lo,hi]=[luminance(a),luminance(b)].sort((a,b)=>a-b);return(hi+.05)/(lo+.05);};
  for(const [fg,bg] of [['596b83','ffffff'],['2155ad','edf3ff'],['ffffff','245fe3'],['508afa','1e2531'],['101a2c','508afa'],['c7ddff','223b62']])assert.ok(contrast(fg,bg)>=4.5,`${fg} on ${bg}`);
  assert.ok(contrast('ffffff','508afa')>=3);
});
