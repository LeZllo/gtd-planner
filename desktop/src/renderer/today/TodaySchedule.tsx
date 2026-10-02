import { memo, useEffect, useLayoutEffect, useMemo, useRef, useState, type CSSProperties, type PointerEvent } from 'react';
import { dayKey, makeScheduleSelection, pauseTimer, resumeTimer, stopTimer, sameID, timerSeconds, type ActiveTimer, type GTDDatabase, type TimeEntry } from '../../domain';
import { usesFineSnap, visibleTimerInterval } from './drafts';
import { Icon } from '../icons';
import { clockLabel, formatClock, rangeLabel, wholeMinutes, type Mutation, type PlanBlock, type Selection, type TodaySnapshot } from './model';

export const HOUR_HEIGHT = 64;
const DAY_HEIGHT = HOUR_HEIGHT * 24;
function wallMinute(value: string | Date, day: string) {
  const date = typeof value === 'string' ? new Date(value) : value;
  const key = dayKey(date);
  return key < day ? 0 : key > day ? 1440 : date.getHours() * 60 + date.getMinutes() + date.getSeconds() / 60;
}
function topFor(value: string | Date, day: string) { return wallMinute(value, day) * HOUR_HEIGHT / 60; }

type LayoutItem = { start: string; end: string; id: string };
/** Overlapping cards get independent columns instead of hiding one another. */
function layoutBlocks<T extends LayoutItem>(blocks: T[], day: string) {
  const sorted = blocks.map(block => ({ block, top: topFor(block.start, day), bottom: Math.max(topFor(block.end, day), topFor(block.start, day) + 27), column: 0, columns: 1 })).sort((a, b) => a.top - b.top || b.bottom - a.bottom);
  let group: typeof sorted = [], ends: number[] = [], groupBottom = -1;
  const finish = () => { for (const item of group) item.columns = ends.length; group = []; ends = []; };
  for (const item of sorted) {
    if (item.top >= groupBottom) { finish(); groupBottom = -1; }
    let column = ends.findIndex(end => end <= item.top);
    if (column < 0) column = ends.length;
    item.column = column; ends[column] = item.bottom; group.push(item); groupBottom = Math.max(groupBottom, item.bottom);
  }
  finish();
  return sorted;
}
function blockStyle(item: { top: number; bottom: number; column: number; columns: number }): CSSProperties {
  return { top: item.top, height: Math.min(DAY_HEIGHT - item.top, Math.max(25, item.bottom - item.top - 2)), left: `calc(${item.column / item.columns * 100}% + 4px)`, width: `max(2px, calc(${100 / item.columns}% - 8px))` };
}

/** Drag movement lives here: refs + one RAF preview, no canonical writes or projections. */
function DragSurface({ day, lane, onSelect }: { day: string; lane: Selection['lane']; onSelect: (selection: Selection) => void }) {
  const drag = useRef<{ pointerID: number; anchor: number; current: number; fine: boolean; element: HTMLDivElement } | null>(null);
  const frame = useRef<number | null>(null);
  const [preview, setPreview] = useState<Selection | null>(null);
  const clear = () => {
    if (frame.current !== null) cancelAnimationFrame(frame.current);
    frame.current = null;
    const active = drag.current; drag.current = null;
    if (active?.element.hasPointerCapture(active.pointerID)) active.element.releasePointerCapture(active.pointerID);
    setPreview(null);
  };
  const selection = () => { const active = drag.current; return active ? { ...makeScheduleSelection(day, active.anchor, active.current, active.fine), lane } : null; };
  const paint = () => { if (frame.current === null) frame.current = requestAnimationFrame(() => { frame.current = null; setPreview(selection()); }); };
  const position = (event: PointerEvent<HTMLDivElement>) => Math.max(0, Math.min(1440, (event.clientY - event.currentTarget.getBoundingClientRect().top) / HOUR_HEIGHT * 60));
  useEffect(() => {
    const escape = (event: KeyboardEvent) => { if (event.key === 'Escape' && drag.current) { event.preventDefault(); event.stopPropagation(); clear(); } };
    document.addEventListener('keydown', escape, true);
    return () => { document.removeEventListener('keydown', escape, true); if (frame.current !== null) cancelAnimationFrame(frame.current); };
  }, []);
  return <div className={`today-drag-surface ${preview ? 'dragging' : ''}`} aria-label={`${lane === 'plan' ? '计划' : '实际'}轨，拖动选择时段`} data-lane={lane}
    onPointerDown={event => {
      if (event.button !== 0 || !event.isPrimary) return;
      event.preventDefault();
      const minute = position(event);
      drag.current = { pointerID: event.pointerId, anchor: minute, current: minute, fine: usesFineSnap(event), element: event.currentTarget };
      event.currentTarget.setPointerCapture(event.pointerId); paint();
    }}
    onPointerMove={event => { if (!drag.current || event.pointerId !== drag.current.pointerID) return; drag.current.current = position(event); drag.current.fine = usesFineSnap(event); paint(); }}
    onPointerUp={event => {
      if (!drag.current || event.pointerId !== drag.current.pointerID) return;
      drag.current.current = position(event); drag.current.fine = usesFineSnap(event);
      const result = selection(); clear(); if (result) onSelect(result);
    }}
    onPointerCancel={clear} onLostPointerCapture={() => { if (drag.current) clear(); }}>
    {preview && <div className={`today-drag-preview ${lane}`} style={{ top: topFor(preview.start, day), height: Math.max(5, topFor(preview.end, day) - topFor(preview.start, day)) }}><strong>{rangeLabel(preview.start, preview.end)}</strong><span>{preview.endMinute - preview.startMinute} 分钟 · 松开后确认</span></div>}
  </div>;
}

function LiveOverlay({ timer, tasks, workspaceID, day, mutate, onSelect }: { timer?: ActiveTimer | null; tasks: GTDDatabase['tasks']; workspaceID: string; day: string; mutate: Mutation; onSelect: (id: string) => void }) {
  const [now, setNow] = useState(() => new Date());
  useEffect(() => { const interval = setInterval(() => setNow(new Date()), 1000); return () => clearInterval(interval); }, []);
  const isToday = dayKey(now) === day;
  const interval = visibleTimerInterval(timer, tasks, workspaceID, day, now);
  const active = interval ? timer : null;
  const top = interval ? topFor(interval.start, day) : 0;
  const bottom = interval ? topFor(interval.end, day) : 0;
  const elapsed = active ? timerSeconds(active, now) : 0;
  const overtime = !!active && active.mode === 'pomodoro' && elapsed >= (active.targetSeconds || 1500);
  const seconds = active?.mode === 'pomodoro' ? Math.abs((active.targetSeconds || 1500) - elapsed) : elapsed;
  return <div className="today-live-overlay">{isToday && <div className="today-now-line" style={{ top: topFor(now, day) }}><span>{clockLabel(now.toISOString())}</span></div>}{active && <div className={`today-active-block ${active.pausedAt ? 'paused' : ''}`} style={{ top, height: Math.max(56, bottom - top), maxHeight: DAY_HEIGHT - top }}><button className="today-active-title" disabled={!active.taskID} onClick={() => active.taskID && onSelect(active.taskID)}>{active.title || '自由专注'}</button><strong>{active.pausedAt ? '已暂停 · ' : ''}{active.mode === 'pomodoro' ? overtime ? '超时 +' : '剩余 ' : ''}{formatClock(seconds)}</strong><div><button aria-label={active.pausedAt ? '继续计时' : '暂停计时'} onClick={() => mutate(db => active.pausedAt ? resumeTimer(db) : pauseTimer(db))}><Icon size={12} name={active.pausedAt ? 'play' : 'pause'}/></button><button aria-label="停止并记录" onClick={() => mutate(db => stopTimer(db))}><Icon size={12} name="stop"/></button></div></div>}</div>;
}

export const TodaySchedule = memo(function TodaySchedule({ snapshot, database, workspaceID, day, selectedID, mutate, onSelection, onPlan, onActual, onSelect }: { snapshot: TodaySnapshot; database: GTDDatabase; workspaceID: string; day: string; selectedID: string | null; mutate: Mutation; onSelection: (selection: Selection) => void; onPlan: (block: PlanBlock) => void; onActual: (entry: TimeEntry) => void; onSelect: (id: string) => void }) {
  const scroll = useRef<HTMLDivElement>(null);
  const planLayout = useMemo(() => layoutBlocks(snapshot.planBlocks, day), [snapshot.planBlocks, day]);
  const actualLayout = useMemo(() => layoutBlocks(snapshot.actualBlocks, day), [snapshot.actualBlocks, day]);
  useLayoutEffect(() => { if (scroll.current) scroll.current.scrollTop = 8 * HOUR_HEIGHT; }, [workspaceID, day]);
  return <section className="today-schedule" aria-label="今日计划与实际时间轴"><div className="today-lane-headings"><span>时间</span><div><strong>计划</strong><span>{wholeMinutes(snapshot.plannedDuration)} 分钟</span></div><div><strong>实际</strong><span>{wholeMinutes(snapshot.actualDuration)} 分钟{snapshot.actualEstimated ? '（估算）' : ''}</span></div></div><div className="today-timeline-scroll" ref={scroll}><div className="today-timeline" style={{ height: DAY_HEIGHT + 16 }}><div className="today-hour-labels">{Array.from({ length: 25 }, (_, hour) => <span key={hour} style={{ top: hour * HOUR_HEIGHT }}>{String(hour).padStart(2, '0')}:00</span>)}</div><div className="today-lanes" style={{ height: DAY_HEIGHT }}>
    <div className="today-lane plan"><DragSurface key={`${workspaceID}:${day}:plan`} lane="plan" day={day} onSelect={onSelection}/>{planLayout.map(item => <button key={item.block.id} className={`today-timeline-card plan ${item.block.isPoint ? 'point' : ''} ${sameID(selectedID, item.block.taskID) ? 'selected' : ''}`} style={blockStyle(item)} title={`${item.block.title} · ${item.block.isPoint ? `${clockLabel(item.block.start)} · 时间点` : rangeLabel(item.block.start, item.block.end)}`} onClick={() => { onSelect(item.block.taskID); onPlan(item.block); }}><strong>{item.block.title}</strong><small>{item.block.isPoint ? `${clockLabel(item.block.start)} · 时间点` : rangeLabel(item.block.start, item.block.end)}</small></button>)}{snapshot.deadlineTasks.map(task => <button key={task.id} className="today-deadline" style={{ top: Math.min(DAY_HEIGHT - 22, task.deadlinePrecision === 'date' ? DAY_HEIGHT - 22 : topFor(task.deadline!, day)) }} title={`${task.title} · 截止`} onClick={() => onSelect(task.id)}><Icon name="flag" size={11}/><span>{task.title} · {task.deadlinePrecision === 'date' ? '全天截止' : `${clockLabel(task.deadline!)} 截止`}</span></button>)}</div>
    <div className="today-lane actual"><DragSurface key={`${workspaceID}:${day}:actual`} lane="actual" day={day} onSelect={onSelection}/>{actualLayout.map(item => <button key={item.block.id} className={`today-timeline-card actual ${selectedID && sameID(selectedID, item.block.entry.taskID) ? 'selected' : ''}`} style={blockStyle(item)} title={`${item.block.entry.title} · ${rangeLabel(item.block.start, item.block.end)}`} onClick={() => onActual(item.block.entry)}><strong>{item.block.entry.title}</strong><small>{rangeLabel(item.block.start, item.block.end)}{item.block.entry.source === 'manual' ? ' · 补录' : ''}</small></button>)}</div>
    <LiveOverlay timer={database.activeTimer} tasks={database.tasks} workspaceID={workspaceID} day={day} mutate={mutate} onSelect={onSelect}/>
  </div></div></div><p className="today-timeline-hint">拖动空白处选择时段 · 默认 15 分钟，按住 Alt / Option 或 Shift 精调为 5 分钟 · Esc 取消</p></section>;
});
