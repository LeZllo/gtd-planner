import test from 'node:test';
import assert from 'node:assert/strict';
import {demoDatabase,emptyDatabase,exportDatabase} from '../src/domain/index.js';
const values=new Map<string,string>();
Object.defineProperty(globalThis,'window',{value:{plannerHost:undefined},configurable:true});
Object.defineProperty(globalThis,'localStorage',{value:{getItem:(key:string)=>values.get(key)??null,setItem:(key:string,value:string)=>values.set(key,value)},configurable:true});
const {host}=await import('../src/renderer/host.js');
const key='gtd-planner-electron-preview-v1';
test('browser preview recovers good backup but never overwrites corrupt primary or backup',async()=>{
  values.clear();const backup=exportDatabase(demoDatabase());values.set(key,'corrupt');values.set(key+'-backup',backup);
  const result=await host.load();assert.equal(result.database?.tasks.length,12);assert.ok(result.recoveryNotice);
  await assert.rejects(host.save(emptyDatabase()));assert.equal(values.get(key),'corrupt');assert.equal(values.get(key+'-backup'),backup);
});
test('browser missing primary probes backup before first-run onboarding',async()=>{
  values.clear();values.set(key+'-backup',exportDatabase(demoDatabase()));assert.equal((await host.load()).database?.tasks.length,12);
  values.set(key+'-backup','corrupt');await assert.rejects(host.load());await assert.rejects(host.save(emptyDatabase()));values.clear();assert.equal((await host.load()).database,null);
});
