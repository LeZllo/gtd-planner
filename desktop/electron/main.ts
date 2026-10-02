import {app,BrowserWindow,dialog,ipcMain,protocol,net,session} from 'electron';
import type {IpcMainInvokeEvent,IpcMainEvent} from 'electron';
import {fileURLToPath,pathToFileURL} from 'node:url';
import path from 'node:path';
import {promises as fs} from 'node:fs';
import {PlannerStore,writeAtomicFile} from './store.js';
import {parseStoredDatabase} from '../src/domain/index.js';
const directory=path.dirname(fileURLToPath(import.meta.url));
const appRoot=path.resolve(directory,'../..');
const devURL=process.env.PLANNER_DEV_URL;
if(devURL && new URL(devURL).origin!=='http://127.0.0.1:5173') throw new Error('Unexpected development origin');
app.setName('GTD Planner Electron Preview');
if(process.env.GTD_PLANNER_DATA_DIR) app.setPath('userData',process.env.GTD_PLANNER_DATA_DIR);
protocol.registerSchemesAsPrivileged([{scheme:'planner',privileges:{standard:true,secure:true,supportFetchAPI:true,corsEnabled:true}}]);
const store=new PlannerStore(app.getPath('userData'));
let window:BrowserWindow|null=null;
let closeApproved=false,closeInProgress=false,rendererReady=false;
let closeTimeout:ReturnType<typeof setTimeout>|undefined;
let closeAttempt:string|null=null;
function authorized(event:IpcMainInvokeEvent|IpcMainEvent) {
  if(!window || event.sender!==window.webContents || event.senderFrame!==window.webContents.mainFrame) throw new Error('Unauthorized IPC sender');
  const url=new URL(event.senderFrame.url);
  if(devURL ? url.origin!==new URL(devURL).origin : !(url.protocol==='planner:'&&url.hostname==='app')) throw new Error('Unauthorized IPC origin');
}
function handle(channel:string, action:(...args:any[])=>unknown) {ipcMain.handle(channel,(event,...args)=>{authorized(event);return action(...args);});}
handle('planner:load',()=>store.load());
handle('planner:save',data=>store.save(data));
handle('planner:replace',data=>store.replace(data));
handle('planner:import',async()=>{
  const result=await dialog.showOpenDialog(window!,{title:'选择 GTD Planner JSON 备份',properties:['openFile'],filters:[{name:'JSON backup',extensions:['json']}]});
  if(result.canceled)return null; const file=result.filePaths[0];
  const info=await fs.stat(file); if(info.size>32*1024*1024)throw new Error('原型导入上限为 32 MB，请先缩小备份或等待批量迁移支持');
  return {text:await fs.readFile(file,'utf8'),name:path.basename(file)};
});
handle('planner:export',async(text:unknown)=>{
  if(typeof text!=='string'||text.length>64*1024*1024)throw new Error('Invalid export data');
  parseStoredDatabase(text);
  const result=await dialog.showSaveDialog(window!,{title:'导出 GTD Planner 备份',defaultPath:'gtd-planner-backup.json',filters:[{name:'JSON backup',extensions:['json']}]});
  if(result.canceled||!result.filePath)return false;
  await writeAtomicFile(result.filePath,text);return true;
});
function on(channel:string,action:(...args:any[])=>void){ipcMain.on(channel,(event,...args)=>{try{authorized(event);}catch{return;}action(...args);});}
on('planner:renderer-ready',()=>{rendererReady=true;});
on('planner:close-ready',(attempt:unknown)=>{if(attempt!==closeAttempt||!closeInProgress)return;clearTimeout(closeTimeout);closeAttempt=null;closeApproved=true;closeInProgress=false;window?.close();});
on('planner:close-failed',(attempt:unknown)=>{if(attempt!==closeAttempt)return;clearTimeout(closeTimeout);closeAttempt=null;closeInProgress=false;});
async function createWindow(){
  closeApproved=false;closeInProgress=false;rendererReady=false;
  window=new BrowserWindow({width:1575,height:980,minWidth:1280,minHeight:720,backgroundColor:'#f5f7fb',show:false,webPreferences:{preload:path.join(appRoot,'electron/preload.cjs'),nodeIntegration:false,contextIsolation:true,sandbox:true,webSecurity:true}});
  window.removeMenu();
  window.webContents.setWindowOpenHandler(()=>({action:'deny'}));
  window.webContents.on('will-navigate',event=>event.preventDefault());
  window.webContents.on('will-attach-webview',event=>event.preventDefault());
  window.once('ready-to-show',()=>window?.show());
  window.webContents.on('render-process-gone',()=>{rendererReady=false;closeInProgress=false;closeAttempt=null;clearTimeout(closeTimeout);});
  window.on('close',event=>{
    if(closeApproved||!rendererReady)return;
    event.preventDefault();
    if(!closeInProgress){
      closeInProgress=true;closeAttempt=crypto.randomUUID();const attempt=closeAttempt;window?.webContents.send('planner:prepare-close',attempt);
      closeTimeout=setTimeout(async()=>{
        if(!window||!closeInProgress||attempt!==closeAttempt)return;
        const response=await dialog.showMessageBox(window,{type:'warning',title:'尚未完成保存',message:'界面尚未确认数据保存。取消关闭，或放弃尚未保存的更改并关闭？',buttons:['取消关闭','放弃未保存更改并关闭'],defaultId:0,cancelId:0});
        closeInProgress=false;closeAttempt=null;if(response.response===1){closeApproved=true;window?.close();}
      },8000);
    }
  });
  window.on('closed',()=>{clearTimeout(closeTimeout);window=null;});
  await window.loadURL(devURL ?? 'planner://app/index.html');
}
if(!app.requestSingleInstanceLock()){app.quit();}else{
  app.on('second-instance',()=>{window?.show();window?.focus();});
  app.whenReady().then(async()=>{
    session.defaultSession.setPermissionRequestHandler((_contents,_permission,callback)=>callback(false));
    session.defaultSession.setPermissionCheckHandler(()=>false);
    protocol.handle('planner',request=>{
      const url=new URL(request.url); if(url.hostname!=='app')return new Response('Not found',{status:404});
      const root=path.join(appRoot,'dist');
      let target:string;
      try{target=path.resolve(root,'.'+decodeURIComponent(url.pathname));}catch{return new Response('Bad request',{status:400});}
      if(!target.startsWith(root+path.sep))return new Response('Forbidden',{status:403});
      return net.fetch(pathToFileURL(target).toString());
    });
    await createWindow();
  });
  app.on('activate',()=>{if(!window)void createWindow();});
  app.on('window-all-closed',()=>{if(process.platform!=='darwin')app.quit();});
  let exiting=false;
  app.on('before-quit',event=>{if(!exiting){event.preventDefault();void store.flush().finally(()=>{exiting=true;app.quit();});}});
}
