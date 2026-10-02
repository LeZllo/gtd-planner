import {spawn} from 'node:child_process';
const children=[];
function run(command,args){const child=spawn(command,args,{stdio:'inherit',env:{...process.env,PLANNER_DEV_URL:'http://127.0.0.1:5173'}});children.push(child);return child;}
const build=run('npx',['tsc','-p','tsconfig.electron.json']);
await new Promise((resolve,reject)=>build.on('exit',code=>code===0?resolve():reject(new Error('Electron compile failed'))));
run('npx',['vite','--host','127.0.0.1']);
for(let i=0;i<100;i++){try{if((await fetch('http://127.0.0.1:5173')).ok)break;}catch{}await new Promise(r=>setTimeout(r,100));}
const electron=run('npx',['electron','.']);
const stop=()=>{for(const child of children)child.kill();};
process.on('SIGINT',stop);process.on('SIGTERM',stop);electron.on('exit',()=>{stop();process.exit();});
