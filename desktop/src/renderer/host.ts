import {parseStoredDatabase,parseImport,exportDatabase,type GTDDatabase} from '../domain';
interface HostAPI {load():Promise<{database:GTDDatabase|null;recoveryNotice?:string}>;save(db:GTDDatabase):Promise<void>;replace(db:GTDDatabase):Promise<void>;importFile():Promise<{text:string;name:string}|null>;exportFile(text:string):Promise<boolean>;onCloseRequest(handler:()=>Promise<void>):()=>void;}
declare global {interface Window {plannerHost?:HostAPI}}
const key='gtd-planner-electron-preview-v1';
const browser:HostAPI={
  onCloseRequest(handler){const listener=()=>{void handler().catch(()=>{});};window.addEventListener('beforeunload',listener);return()=>window.removeEventListener('beforeunload',listener);},
  async load(){
    const raw=localStorage.getItem(key),backup=localStorage.getItem(key+'-backup');
    if(raw===null&&backup===null)return{database:null};
    if(raw!==null){try{return{database:parseStoredDatabase(raw).database};}catch{/* Try retained backup without rewriting anything. */}}
    if(backup!==null){try{return{database:parseStoredDatabase(backup).database,recoveryNotice:'浏览器主数据缺失或校验失败，已读取上一次有效备份。原数据保留，请先导出备份。'};}catch{/* Both unreadable: block fresh initialization. */}}
    throw new Error('浏览器预览数据和备份无法读取，原数据已保留，未自动覆盖。');
  },
  async save(db){
    const data=exportDatabase(parseStoredDatabase(JSON.stringify(db)).database);
    const previous=localStorage.getItem(key);
    if(previous===null){const backup=localStorage.getItem(key+'-backup');if(backup!==null)parseStoredDatabase(backup);}
    if(previous!==null){try{parseStoredDatabase(previous);}catch{throw new Error('现有浏览器数据校验失败，已阻止覆盖。请先导出恢复的备份。');}}
    try{if(previous!==null)localStorage.setItem(key+'-backup',previous);localStorage.setItem(key,data);}
    catch{throw new Error('浏览器预览空间不足，未保存。请导出备份；桌面版使用本地文件。');}
  },
  async replace(db){
    parseImport(JSON.stringify(db));
    const old=localStorage.getItem(key)??localStorage.getItem(key+'-backup');
    if(old!==null){const current=parseStoredDatabase(old).database;if(current.activeTimer)throw new Error('请先停止当前计时，再替换数据');
      try{localStorage.setItem(key+'-before-import-'+Date.now()+'-'+crypto.randomUUID(),old);}catch{throw new Error('导入前备份失败，未替换当前数据');}}
    await browser.save(db);
  },
  importFile(){return new Promise((resolve,reject)=>{const input=document.createElement('input');input.type='file';input.accept='.json,application/json';input.oncancel=()=>resolve(null);input.onchange=async()=>{const file=input.files?.[0];if(!file)return resolve(null);if(file.size>32*1024*1024)return reject(new Error('JSON 文件超过 32 MB 原型导入上限'));try{resolve({text:await file.text(),name:file.name});}catch(error){reject(error);}};input.click();});},
  async exportFile(text){const blob=new Blob([text],{type:'application/json'});const url=URL.createObjectURL(blob);const link=document.createElement('a');link.href=url;link.download='gtd-planner-backup.json';link.click();setTimeout(()=>URL.revokeObjectURL(url),1000);return true;}
};
export const host:HostAPI&{kind:'electron'|'browser'}=window.plannerHost?{...window.plannerHost,kind:'electron'}:{...browser,kind:'browser'};
