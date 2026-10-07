/** Reproducible CPU/SSR comparison, not a browser frame-rate or paint measurement. */
import { performance } from 'node:perf_hooks';
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { firstAddedTask, formatTime } from '../src/renderer/performance';
import { WindowedRows } from '../src/renderer/WindowedRows';
import { createTask, emptyDatabase } from '../src/domain';
const db=emptyDatabase(), template=createTask(db,{title:'Task',workspaceID:db.workspaces[0].id}).tasks[0];
function measure(fn:()=>unknown){fn();const samples=Array.from({length:5},()=>{const start=performance.now();fn();return performance.now()-start;}).sort((a,b)=>a-b);return +samples[2].toFixed(2);}
for(const count of [1000,10000]){
  const tasks=Array.from({length:count},(_,i)=>({...template,id:`bbbbbbbb-0000-4000-8000-${String(i).padStart(12,'0')}`,title:`Task ${i}`}));
  const next=[...tasks,{...template,id:'ffffffff-0000-4000-8000-000000000000'}];
  const row=(task:typeof template)=>createElement('div',{key:task.id},createElement('button',null,task.title),createElement('small',null,'Project · #work'),createElement('button',null,'安排'));
  const value='2026-10-03T09:30:00Z';
  console.log(JSON.stringify({tasks:count,unit:'CPU milliseconds median of five',addedTaskLookup:{before:measure(()=>next.find(t=>!tasks.some(old=>old.id===t.id))),after:measure(()=>firstAddedTask(tasks,next))},initialListSSR:{before:measure(()=>renderToStaticMarkup(createElement('div',null,tasks.map(row)))),after:measure(()=>renderToStaticMarkup(createElement(WindowedRows<typeof template>,{items:tasks,renderRow:row})))},timeLabels:{before:measure(()=>tasks.forEach(()=>new Date(value).toLocaleTimeString('zh-CN',{hour:'2-digit',minute:'2-digit',hour12:false}))),after:measure(()=>tasks.forEach(()=>formatTime(value)))},initialMountedTaskRows:{before:count,after:32},hiddenMoveOptionsOnSelection:{before:count-1,after:0}}));
}
