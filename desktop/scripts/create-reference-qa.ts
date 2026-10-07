/** Screenshot-alignment fixture with fictional reference labels. Refuses overwrite. */
import {writeFile} from 'node:fs/promises';
import {emptyDatabase,createTask,exportDatabase,dayKey,localDate} from '../src/domain';
const output=process.argv[2];if(!output)throw new Error('Provide a new output path');
const db=emptyDatabase(),w=db.workspaces[0].id, today=dayKey(new Date());db.workspaces[0].name='GTD Planner 示例';
const id=(n:number)=>`eeeeeeee-0000-4000-8000-${String(n).padStart(12,'0')}`;
const day=(add:number)=>{const d=localDate(today);d.setDate(d.getDate()+add);return dayKey(d);};
db.projectCategories=[{id:id(1),workspaceID:w,name:'示例分类 1',colorHex:'#28874B',order:0},{id:id(2),workspaceID:w,name:'示例分类 2',colorHex:'#327ACC',order:1}];
db.projects=[1,2,3,4].map((n)=>({id:id(10+n),workspaceID:w,name:`示例项目 ${n<3?'1':'2'}-${n%2||2}`,category:`示例分类 ${n<3?'1':'2'}`,colorHex:'#08A68F',symbolName:'folder',note:'',order:n}));
db.projectSections=[{id:id(21),projectID:id(11),name:'示例分区 1',colorHex:'#327ACC',order:0},{id:id(22),projectID:id(11),name:'示例分区 2',colorHex:'#327ACC',order:1}];
const template=createTask(db,{title:'示例任务',workspaceID:w,projectID:id(11)}).tasks[0];
db.tasks=[
 {...template,id:id(31),title:'示例任务 1',sectionID:id(21),plannedStart:today,plannedEnd:day(6),plannedPrecision:'date',priority:'medium',order:1},
 {...template,id:id(32),title:'示例任务 1-1',sectionID:id(21),parentID:id(31),plannedStart:today,plannedEnd:day(2),plannedPrecision:'date',deadline:day(3),deadlinePrecision:'date',priority:'high',order:2},
 {...template,id:id(33),title:'示例任务 1-1-1',sectionID:id(21),parentID:id(32),plannedStart:today,plannedEnd:day(5),plannedPrecision:'date',deadline:day(6),deadlinePrecision:'date',order:3},
 {...template,id:id(34),title:'示例任务 2',sectionID:id(21),order:4},
 {...template,id:id(35),title:'示例任务 2-1',sectionID:id(22),plannedStart:`${today}T14:00:00Z`,plannedEnd:`${today}T16:00:00Z`,plannedPrecision:'minute',deadline:`${today}T21:00:00Z`,deadlinePrecision:'minute',priority:'low',order:5},
 {...template,id:id(36),title:'示例任务 2-1-1',sectionID:id(22),parentID:id(35),order:6},
 {...template,id:id(37),title:'UI-03 快速创建验证任务',projectID:null,sectionID:null,tags:['UI-03 运行验证'],order:7},
];
db.tagCategories=[{id:id(41),workspaceID:w,name:'UI-03 验证分类',colorHex:'#08A68F',order:0,createdAt:new Date().toISOString(),updatedAt:new Date().toISOString()}];
db.tagDefinitions=[{id:id(42),workspaceID:w,name:'UI-03 运行验证',categoryID:null,colorHex:'#C7527A',note:'',order:0,createdAt:new Date().toISOString(),updatedAt:new Date().toISOString()}];
await writeFile(output,exportDatabase(db),{flag:'wx',mode:0o600});console.log(output);
