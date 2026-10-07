/** Fictional renderer stress fixture. Never reads/replaces existing user data.
 * TZ=UTC node --import tsx scripts/create-renderer-qa.ts NEW_PATH [10000] */
import { writeFile } from 'node:fs/promises';
import { emptyDatabase, createTask, dayKey, exportDatabase } from '../src/domain';
const output=process.argv[2], count=Number(process.argv[3]||10000);
if(!output||!Number.isInteger(count)||count<1||count>10000)throw new Error('Provide a new output path and 1–10000 tasks');
const db=emptyDatabase(), day=dayKey(new Date()), workspaceID=db.workspaces[0].id;
db.workspaces[0].name=`Renderer QA · ${count}`;
const template=createTask(db,{title:'Synthetic',workspaceID}).tasks[0];
const id=(n:number)=>`cccccccc-0000-4000-8000-${String(n).padStart(12,'0')}`;
db.tasks=Array.from({length:count},(_,i)=>({...template,id:id(i+1),title:`Task ${String(i).padStart(5,'0')}${i%31===0?' · A deliberately long multiline task title to verify that readable content and every schedule button stay available after scrolling':''}`,note:'Fictional UI and performance QA only',status:i%17===0?'done':'open',order:i,plannedStart:day,plannedPrecision:'date',tags:i%3===0?['design','review']:[],executionSlots:i<80?[{id:id(count+i*2+1),start:`${day}T${String(8+Math.floor(i/8)).padStart(2,'0')}:00:00Z`,end:`${day}T${String(8+Math.floor(i/8)).padStart(2,'0')}:30:00Z`},{id:id(count+i*2+2),start:`${day}T18:00:00Z`,end:`${day}T18:15:00Z`}]:[]}));
await writeFile(output,exportDatabase(db),{flag:'wx',mode:0o600});console.log(`Created ${count} fictional records: ${output}`);
