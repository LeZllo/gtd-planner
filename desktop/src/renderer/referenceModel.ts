import {idKey,dayKey, type GTDDatabase, type GTDTask, type TaskPlan} from '../domain';
export type TaskTreeRow={task:GTDTask;depth:number};
export type ReferenceListItem={kind:'heading';id:string;title:string;count:number;color:string}|{kind:'task';row:TaskTreeRow};
/** Group roots and their complete visible subtrees together; never split a hierarchy. */
export function referenceTaskGroups(rows:TaskTreeRow[],database:GTDDatabase,mode:'project'|'tags',projectID:string):Array<{id:string;title:string;color:string;rows:TaskTreeRow[]}>{
  const groups=new Map<string,{id:string;title:string;color:string;rows:TaskTreeRow[]}>();
  if(mode==='project')for(const section of database.projectSections.filter(s=>idKey(s.projectID)===idKey(projectID)).slice().sort((a,b)=>a.order-b.order))groups.set(idKey(section.id),{id:section.id,title:section.name,color:section.colorHex,rows:[]});
  const taskIndex=new Map(database.tasks.map(task=>[idKey(task.id),task]));
  const rootKeys=new Map<string,string>();
  for(const row of rows){
    let root=row.task;const path:GTDTask[]=[];
    while(root.parentID&&taskIndex.has(idKey(root.parentID))&&!rootKeys.has(idKey(root.id))){path.push(root);root=taskIndex.get(idKey(root.parentID))!;}
    const rootKey=rootKeys.get(idKey(root.id))??(mode==='project'?idKey(root.sectionID||''):idKey(root.projectID||''));
    rootKeys.set(idKey(root.id),rootKey);for(const task of path)rootKeys.set(idKey(task.id),rootKey);
    let group=groups.get(rootKey);
    if(!group){const project=mode==='tags'?database.projects.find(p=>idKey(p.id)===rootKey):undefined;group={id:rootKey,title:project?.name||(mode==='tags'?'无项目':'未分区'),color:project?.colorHex||'',rows:[]};groups.set(rootKey,group);}
    group.rows.push(row);
  }
  return [...groups.values()];
}
export function shortPlanLabel(task:TaskPlan){
  if(!task.plannedStart)return '';
  const date=(value:string)=>{const d=new Date(value.length===10?`${value}T12:00:00`:value);return `${d.getMonth()+1}/${d.getDate()}`;};
  const time=(value:string)=>{const d=new Date(value);return `${String(d.getHours()).padStart(2,'0')}:${String(d.getMinutes()).padStart(2,'0')}`;};
  const start=date(task.plannedStart);
  if(task.plannedPrecision==='minute')return `${dayKey(new Date(task.plannedStart))===dayKey(new Date())?'今天':start} ${time(task.plannedStart)}${task.plannedEnd?`–${date(task.plannedEnd)!==start?`${date(task.plannedEnd)} `:''}${time(task.plannedEnd)}`:''}`;
  return `${start}${task.plannedEnd&&date(task.plannedEnd)!==start?`–${date(task.plannedEnd)}`:''}`;
}

export function shortDeadlineLabel(task:GTDTask){if(!task.deadline)return '';return shortPlanLabel({...task,plannedStart:task.deadline,plannedEnd:null,plannedPrecision:task.deadlinePrecision});}
