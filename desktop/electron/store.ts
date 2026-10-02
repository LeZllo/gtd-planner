import { promises as fs } from 'node:fs';
import path from 'node:path';
import { parseStoredDatabase, parseImport, exportDatabase, type GTDDatabase } from '../src/domain/index.js';

async function syncDirectory(directory:string):Promise<void> {
  let handle;
  try {handle=await fs.open(directory,'r');await handle.sync();}
  catch(error){
    // Windows and some filesystems cannot fsync directory handles. File fsync and
    // same-directory rename still apply; do not report a successful rename as failed.
    const code=(error as NodeJS.ErrnoException).code;
    if(!['EINVAL','ENOTSUP','EISDIR','EPERM','EACCES'].includes(code??''))throw error;
  }finally{await handle?.close();}
}
/** Stage bytes in the same directory, fsync, then atomically replace the target. */
export async function writeAtomicFile(file:string,text:string):Promise<void>{
  const temporary=file+'.tmp-'+crypto.randomUUID();let handle;
  try{
    handle=await fs.open(temporary,'wx',0o600);await handle.writeFile(text,'utf8');await handle.sync();await handle.close();handle=undefined;
    await fs.rename(temporary,file);await syncDirectory(path.dirname(file));
  }finally{await handle?.close();await fs.rm(temporary,{force:true});}
}
export class PlannerStore {
  readonly file:string;
  private pending:Promise<void>=Promise.resolve();
  constructor(readonly directory:string){this.file=path.join(directory,'planner-v1.json');}
  async load():Promise<{database:GTDDatabase|null;recoveryNotice?:string}>{
    await this.pending;
    let primaryMissing=false;
    try{return{database:parseStoredDatabase(await fs.readFile(this.file,'utf8')).database};}
    catch(error){primaryMissing=(error as NodeJS.ErrnoException).code==='ENOENT';}
    try{
      const database=parseStoredDatabase(await fs.readFile(this.file+'.bak','utf8')).database;
      return{database,recoveryNotice:'主数据文件缺失或无法读取，已加载上一次有效备份。原文件仍保留，请先导出备份再继续。'};
    }catch(error){
      if(primaryMissing&&(error as NodeJS.ErrnoException).code==='ENOENT')return{database:null};
      throw new Error('本地数据无法读取，且没有有效备份。文件已保留，未初始化或覆盖。');
    }
  }
  save(database:unknown):Promise<void>{return this.write(database,false);}
  replace(database:unknown):Promise<void>{return this.write(database,true);}
  private write(database:unknown,replacement:boolean):Promise<void>{
    const operation=this.pending.then(async()=>{
      const validated=(replacement?parseImport:parseStoredDatabase)(JSON.stringify(database)).database;
      const text=exportDatabase(validated);
      await fs.mkdir(this.directory,{recursive:true,mode:0o700});
      let old:string|undefined;let primaryExists=false;
      try{old=await fs.readFile(this.file,'utf8');parseStoredDatabase(old);primaryExists=true;}
      catch(error){if((error as NodeJS.ErrnoException).code!=='ENOENT')throw new Error('现有数据文件校验失败，已阻止覆盖。请先恢复备份或将文件交由人工检查。');}
      if(!primaryExists){
        try{old=await fs.readFile(this.file+'.bak','utf8');parseStoredDatabase(old);}
        catch(error){if((error as NodeJS.ErrnoException).code!=='ENOENT')throw new Error('备份数据校验失败，已阻止覆盖。请先人工检查。');}
      }
      if(replacement&&old!==undefined){
        if(parseStoredDatabase(old).database.activeTimer)throw new Error('请先停止并保存当前计时，再替换数据');
        const backups=path.join(this.directory,'Backups');await fs.mkdir(backups,{recursive:true,mode:0o700});
        const stamp=new Date().toISOString().replace(/:/g,'-');
        await writeAtomicFile(path.join(backups,`before-import-${stamp}-${crypto.randomUUID()}.json`),old);
      }
      // A separate atomic backup replacement cannot truncate a previous good
      // backup if copying/staging fails. Missing primaries preserve their backup.
      if(primaryExists&&old!==undefined)await writeAtomicFile(this.file+'.bak',old);
      await writeAtomicFile(this.file,text);
    });
    this.pending=operation.catch(()=>{});return operation;
  }
  async flush():Promise<void>{await this.pending;}
}
