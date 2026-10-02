import type { CSSProperties } from 'react';
export type IconName = 'sun'|'tomorrow'|'week'|'grid'|'calendar'|'inbox'|'layers'|'search'|'plus'|'chevron'|'more'|'check'|'close'|'play'|'pause'|'stop'|'clock'|'settings'|'download'|'upload'|'folder'|'flag'|'arrow'|'menu'|'grip'|'copy'|'trash'|'edit'|'bolt'|'restore';
const paths: Record<IconName, string> = {
 sun:'M12 3v2m0 14v2M3 12h2m14 0h2M5.6 5.6 7 7m10 10 1.4 1.4M5.6 18.4 7 17M17 7l1.4-1.4M16 12a4 4 0 1 1-8 0 4 4 0 0 1 8 0',
 tomorrow:'M3 16h18M5 20h14M12 3v2M4.2 7.2 6 9m12 0 1.8-1.8M7 16a5 5 0 0 1 10 0',
 week:'M5 4h14a2 2 0 0 1 2 2v13a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2M7 2v4m10-4v4M3 10h18M8 14h2m4 0h2m-8 3h2',
 grid:'M3 3h7v7H3zM14 3h7v7h-7zM3 14h7v7H3zM14 14h7v7h-7z',
 calendar:'M5 4h14a2 2 0 0 1 2 2v13a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2M7 2v4m10-4v4M3 10h18M8 14h.01M12 14h.01M16 14h.01M8 18h.01M12 18h.01',
 inbox:'M3 13 6 4h12l3 9v7H3zM3 13h5l2 3h4l2-3h5',
 layers:'m12 3 9 5-9 5-9-5 9-5Zm-9 9 9 5 9-5M3 16l9 5 9-5',
 search:'M21 21l-5-5M18 10.5a7.5 7.5 0 1 1-15 0 7.5 7.5 0 0 1 15 0',
 plus:'M12 5v14M5 12h14', chevron:'m9 5 7 7-7 7', more:'M5 12h.01M12 12h.01M19 12h.01', check:'m5 12 4 4L19 6', close:'m6 6 12 12M6 18 18 6',
 play:'m8 4 12 8-12 8V4Z', pause:'M8 5v14M16 5v14', stop:'M6 6h12v12H6z', clock:'M12 8v5l3 2M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0',
 settings:'M9 3h6l1 3 3 1 2 5-2 5-3 1-1 3H9l-1-3-3-1-2-5 2-5 3-1 1-3Zm6 9a3 3 0 1 1-6 0 3 3 0 0 1 6 0',
 download:'M12 3v12m-5-5 5 5 5-5M4 16v5h16v-5', upload:'M12 16V4m-5 5 5-5 5 5M4 16v5h16v-5',
 folder:'M3 6V4h6l2 3h10v13H3V6Z', flag:'M5 22V3m0 1h7l2 2h6v10h-7l-2-2H5', arrow:'M5 12h14m-6-6 6 6-6 6', menu:'M4 6h16M4 12h16M4 18h16', grip:'M9 5h.01M15 5h.01M9 12h.01M15 12h.01M9 19h.01M15 19h.01',
 copy:'M9 9h12v12H9zM15 9V3H3v12h6', trash:'M3 6h18M9 6V3h6v3M5 6l1 15h12l1-15M10 10v7m4-7v7', edit:'m15 4 5 5M3 21l5-1L21 7l-5-5L3 15v6Z', bolt:'m13 2-9 12h7l-1 8 10-13h-7l1-7Z', restore:'M3 10V4m0 6h6M3 10a9 9 0 1 1 1 8'
};
export function Icon({name,size=18,className='',style}:{name:IconName;size?:number;className?:string;style?:CSSProperties}) { return <svg className={className} style={style} width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d={paths[name]}/></svg>; }
