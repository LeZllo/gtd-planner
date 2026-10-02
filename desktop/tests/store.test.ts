import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,readFile,writeFile,rm,readdir} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {PlannerStore} from '../electron/store.js';
import {demoDatabase,emptyDatabase,parseStoredDatabase,startTimer} from '../src/domain/index.js';
const temporary=()=>mkdtemp(path.join(tmpdir(),'gtd-electron-store-'));
test('new store stays empty; ordered saves persist newest snapshot and a valid previous backup',async()=>{
  const directory=await temporary();try{
    const store=new PlannerStore(directory);assert.equal((await store.load()).database,null);
    const a=emptyDatabase(),b=demoDatabase();
    await Promise.all([store.save(a),store.save(b)]);
    assert.equal((await store.load()).database?.tasks.length,b.tasks.length);
    assert.equal(parseStoredDatabase(await readFile(store.file+'.bak','utf8')).database.tasks.length,0);
    assert.ok((await readdir(directory)).every(name=>!name.includes('.tmp-')));
  }finally{await rm(directory,{recursive:true,force:true});}
});
test('invalid writes preserve the last good file',async()=>{
  const directory=await temporary();try{
    const store=new PlannerStore(directory);await store.save(demoDatabase());const before=await readFile(store.file,'utf8');
    await assert.rejects(store.save({schemaVersion:999}));assert.equal(await readFile(store.file,'utf8'),before);
  }finally{await rm(directory,{recursive:true,force:true});}
});
test('corrupt primary recovers read-only from good backup and prevents accidental replacement',async()=>{
  const directory=await temporary();try{
    const store=new PlannerStore(directory);await store.save(emptyDatabase());await store.save(demoDatabase());
    await writeFile(store.file,'{bad');const recovered=await store.load();assert.equal(recovered.database?.tasks.length,0);assert.ok(recovered.recoveryNotice);
    await assert.rejects(store.save(demoDatabase()));assert.equal(await readFile(store.file,'utf8'),'{bad');
  }finally{await rm(directory,{recursive:true,force:true});}
});
test('corrupt unbacked primary never silently becomes an empty database',async()=>{
  const directory=await temporary();try{
    const store=new PlannerStore(directory);await writeFile(store.file,'{bad');await assert.rejects(store.load());assert.equal(await readFile(store.file,'utf8'),'{bad');
  }finally{await rm(directory,{recursive:true,force:true});}
});
test('active timer survives a durable reopen',async()=>{
  const directory=await temporary();try{
    const database=demoDatabase();const running=startTimer(database,database.tasks[0].id,'stopwatch',new Date('2026-10-02T09:00:00Z'));
    await new PlannerStore(directory).save(running);const reopened=await new PlannerStore(directory).load();assert.deepEqual(reopened.database?.activeTimer,running.activeTimer);
  }finally{await rm(directory,{recursive:true,force:true});}
});
test('missing primary recovers backup and does not offer destructive fresh onboarding',async()=>{
  const directory=await temporary();try{
    const store=new PlannerStore(directory);const db=demoDatabase();await store.save(db);await store.save(db);await rm(store.file);
    const recovered=await store.load();assert.equal(recovered.database?.tasks.length,db.tasks.length);assert.ok(recovered.recoveryNotice);
    const backup=await readFile(store.file+'.bak','utf8');await store.save(recovered.database);assert.equal(await readFile(store.file+'.bak','utf8'),backup);
  }finally{await rm(directory,{recursive:true,force:true});}
});
test('missing primary with corrupt backup throws instead of initializing blank data',async()=>{
  const directory=await temporary();try{
    const store=new PlannerStore(directory);await writeFile(store.file+'.bak','corrupt');await assert.rejects(store.load());
  }finally{await rm(directory,{recursive:true,force:true});}
});
test('replacement creates a permanent pre-import snapshot that ordinary saves cannot rotate away',async()=>{
  const directory=await temporary();try{
    const store=new PlannerStore(directory),original=demoDatabase();await store.save(original);await store.replace(emptyDatabase());
    const files=await readdir(path.join(directory,'Backups'));assert.equal(files.length,1);
    const snapshot=path.join(directory,'Backups',files[0]),before=await readFile(snapshot,'utf8');
    assert.equal(parseStoredDatabase(before).database.tasks.length,original.tasks.length);
    await store.save(emptyDatabase());assert.equal(await readFile(snapshot,'utf8'),before);
  }finally{await rm(directory,{recursive:true,force:true});}
});
test('replacement rejects an active persisted timer without touching data or making a snapshot',async()=>{
  const directory=await temporary();try{
    const store=new PlannerStore(directory),db=demoDatabase();await store.save(startTimer(db,db.tasks[0].id,'stopwatch'));
    const before=await readFile(store.file,'utf8');await assert.rejects(store.replace(emptyDatabase()));assert.equal(await readFile(store.file,'utf8'),before);
    await assert.rejects(readdir(path.join(directory,'Backups')));
  }finally{await rm(directory,{recursive:true,force:true});}
});
