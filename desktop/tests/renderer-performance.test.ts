import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { firstAddedTask, formatTime, resetTimeFormatter } from '../src/renderer/performance';
import { ROW_CHUNK_SIZE, WindowedRows } from '../src/renderer/WindowedRows';
import { createTask, emptyDatabase } from '../src/domain';

const db = emptyDatabase();
const task = createTask(db, { title: 'Task', workspaceID: db.workspaces[0].id }).tasks[0];
test('added-task lookup preserves first new task and case-insensitive identity', () => {
  const other = { ...task, id: 'aaaaaaab-0000-4000-8000-000000000001' };
  assert.equal(firstAddedTask([task], [{ ...task, id: task.id.toUpperCase() }, other]), other);
  assert.equal(firstAddedTask([task], [task]), undefined);
  assert.equal(firstAddedTask([], [task]), task);
});
test('large variable-height lists only mount their first chunk initially', () => {
  const items = Array.from({length:10000}, (_,i)=>i);
  const markup = renderToStaticMarkup(createElement(WindowedRows<number>, { items, renderRow: item=>createElement('button', {key:item}, `Task ${item}`) }));
  assert.equal((markup.match(/<button/g)||[]).length, ROW_CHUNK_SIZE);
  assert.equal((markup.match(/data-chunk=/g)||[]).length, Math.ceil(items.length/ROW_CHUNK_SIZE));
  assert.match(markup, /data-total-rows="10000"/);
});
test('short lists preserve every row and unrestricted multiline content', () => {
  const items = Array.from({length:150}, (_,i)=>i);
  const markup = renderToStaticMarkup(createElement(WindowedRows<number>, { items, renderRow: item=>createElement('div', {key:item}, createElement('strong', null, `A long title ${item}`), createElement('button', null, '08:00–09:00'), createElement('button', null, '10:00–11:00')) }));
  assert.equal((markup.match(/<strong/g)||[]).length, 150);
  assert.equal((markup.match(/<button/g)||[]).length, 300);
});
test('cached time labels retain locale and DST semantics after timezone invalidation', () => {
  const old=process.env.TZ;
  try {
    for (const zone of ['UTC','America/New_York','Asia/Shanghai']) {
      process.env.TZ=zone;resetTimeFormatter();
      for (const value of ['2026-03-08T06:59:00Z','2026-03-08T07:01:00Z','2026-11-01T05:30:00Z','2026-11-01T06:30:00Z']) {
        assert.equal(formatTime(value),new Date(value).toLocaleTimeString('zh-CN',{hour:'2-digit',minute:'2-digit',hour12:false}));
      }
    }
  } finally {if(old===undefined)delete process.env.TZ;else process.env.TZ=old;resetTimeFormatter();}
});
test('ordinary selection does not mount closed move controls; tree memo excludes search and collapse', () => {
  const app=readFileSync(new URL('../src/renderer/App.tsx',import.meta.url),'utf8');
  assert.match(app, /onToggle=\{event=>setMoveOpen\(event.currentTarget.open\)\}/);
  assert.match(app, /<\/summary>\{moveOpen&&<>/);
  assert.match(app, /\[database\?\.tasks,effectiveWorkspaceID,treeProjectID,showsTaskTree\]/);
  assert.doesNotMatch(app, /next.tasks.find\(t=>!db.tasks.some/);
});
test('selected task outside the viewport remains mounted for keyboard focus', () => {
  const items=Array.from({length:10000},(_,i)=>i);
  const markup=renderToStaticMarkup(createElement(WindowedRows<number>,{items,pinnedIndex:9999,renderRow:item=>createElement('input',{key:item,type:'radio',checked:item===9999,readOnly:true,'data-task':item})}));
  assert.match(markup,/data-task="9999"/);
  assert.equal((markup.match(/checked=""/g)||[]).length,1);
  assert.ok((markup.match(/<input/g)||[]).length<=64);
});
