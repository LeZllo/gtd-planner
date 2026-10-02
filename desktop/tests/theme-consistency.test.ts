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
