import {writeFile} from 'node:fs/promises';
import {demoDatabase,type GTDTask} from '../src/domain/index.js';
const db=demoDatabase(),source=db.tasks[0];
db.tasks=Array.from({length:1000},(_,i):GTDTask=>({...source,id:`10000000-0000-4000-8000-${String(i+1).padStart(12,'0')}`,title:`Synthetic task ${String(i+1).padStart(4,'0')}`,parentID:i%10===0?null:`10000000-0000-4000-8000-${String(Math.floor(i/10)*10+1).padStart(12,'0')}`,order:i,plannedStart:'2026-10-02',plannedEnd:null,plannedPrecision:'date',deadline:null,deadlinePrecision:'none',recurrence:'',executionSlots:[],note:'Synthetic QA only',completedInstances:[],skippedInstances:[],status:'open'}));
db.timeEntries=[];db.trashItems=[];db.activeTimer=null;
const output=process.argv[2];if(!output)throw new Error('Usage: node --import tsx scripts/create-qa-import.ts OUTPUT.json');
await writeFile(output,JSON.stringify(db));
