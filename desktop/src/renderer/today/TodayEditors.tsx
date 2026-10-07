import { ArrangementEditor, planLabel } from '../TimeSettings';
import { effectiveTaskPlan, isMultiDayPlan, resolveTaskArrangements, type ArrangementRef } from '../../domain';
import { useLayoutEffect, useMemo, useRef, useState } from 'react';
import { addExecutionSlot, addTimeEntry, deleteTimeEntry, makeScheduleSelection, planConflicts, removeExecutionSlot, idKey, sameID, canScheduleTaskOnDay, startTimerSession, updateTimeEntry, type GTDDatabase, type GTDTask, type TimeEntry } from '../../domain';
import { buildActualEntryPatch, preferredSchedulableTaskID, resolveActualDraftRange } from './drafts';
import { TodayModal } from './TodayModal';
import { WindowedRows } from '../WindowedRows';
import { clockLabel, durationLabel, inputDateTime, rangeLabel, type Mutation, type PlanBlock, type Selection, type TodaySnapshot } from './model';

function TaskChoice({ tasks, database, value, onChange, optional = false }: { tasks: GTDTask[]; database: GTDDatabase; value: string; onChange: (id: string) => void; optional?: boolean }) {
  const [query, setQuery] = useState('');
  const list = useRef<HTMLDivElement>(null);
  const keyboardFocus = useRef(false);
  const projectNames = useMemo(() => new Map(database.projects.map(project => [idKey(project.id), project.name])), [database.projects]);
  const matches = useMemo(() => tasks.filter(task => `${task.title} ${task.note} ${task.tags.join(' ')} ${projectNames.get(idKey(task.projectID || '')) || ''}`.toLocaleLowerCase().includes(query.trim().toLocaleLowerCase())), [tasks, projectNames, query]);
  useLayoutEffect(() => {
    if (!keyboardFocus.current) return;
    keyboardFocus.current = false;
    const input = list.current?.querySelector<HTMLInputElement>('input:checked');
    input?.focus(); input?.scrollIntoView({ block: 'nearest' });
  }, [value]);
  return <fieldset className="today-task-choice"><legend>{optional ? '关联任务（可选）' : '选择任务'}</legend><input aria-label="搜索可安排任务" placeholder="搜索任务、项目、标签或笔记" value={query} onChange={event => setQuery(event.target.value)}/><div className="today-choice-list" ref={list} onKeyDown={event => {
    if (!(event.target instanceof HTMLInputElement) || event.target.type !== 'radio' || !['ArrowUp','ArrowDown','ArrowLeft','ArrowRight','Home','End'].includes(event.key)) return;
    const options = optional ? ['', ...matches.map(task => task.id)] : matches.map(task => task.id);
    if (!options.length) return;
    event.preventDefault();
    const current = options.findIndex(id => id === value || (!!id && sameID(id, value)));
    const next = event.key === 'Home' ? 0 : event.key === 'End' ? options.length - 1 : (current + (['ArrowUp','ArrowLeft'].includes(event.key) ? -1 : 1) + options.length) % options.length;
    keyboardFocus.current = true; onChange(options[next]);
  }}>{optional && <label className={!value ? 'selected' : ''}><input type="radio" name="today-task-choice" checked={!value} onChange={() => onChange('')}/><span>不关联任务<small>自由专注 / 独立实际记录</small></span></label>}{<WindowedRows key={query} items={matches} pinnedIndex={matches.findIndex(task => sameID(value, task.id))} estimatedHeight={60} renderRow={task => <label key={task.id} className={sameID(value, task.id) ? 'selected' : ''}><input type="radio" name="today-task-choice" checked={sameID(value, task.id)} onChange={() => onChange(task.id)}/><span>{task.title}<small>{projectNames.get(idKey(task.projectID || '')) || '无项目'}{task.tags.length ? ` · ${task.tags.map(tag => `#${tag}`).join(' ')}` : ''}</small></span></label>}/>} { !matches.length && <p className="muted">没有匹配的任务</p>}</div></fieldset>;
}
function IntervalFields({ start, end, onStart, onEnd }: { start: string; end: string; onStart: (value: string) => void; onEnd: (value: string) => void }) {
  return <div className="today-interval-fields"><label>开始时间<input aria-label="开始时间" type="datetime-local" required value={start} onChange={event => onStart(event.target.value)}/></label><label>结束时间<input aria-label="结束时间" type="datetime-local" required value={end} onChange={event => onEnd(event.target.value)}/></label></div>;
}
function parseInterval(start: string, end: string) {
  const from = new Date(start), to = new Date(end);
  return Number.isFinite(from.getTime()) && Number.isFinite(to.getTime()) && to > from ? { start: from.toISOString(), end: to.toISOString() } : null;
}

export function PlanEditor({ database, workspaceID, day, snapshot, selection, preferredTaskID, mutate, onClose, onSelect }: { database: GTDDatabase; workspaceID: string; day: string; snapshot: TodaySnapshot; selection?: Selection; preferredTaskID?: string | null; mutate: Mutation; onClose: () => void; onSelect: (id: string) => void }) {
  const candidates = useMemo(() => database.tasks.filter(task => sameID(task.workspaceID, workspaceID) && canScheduleTaskOnDay(task, day)), [database.tasks, workspaceID, day]);
  const [taskID, setTaskID] = useState(candidates.some(task => sameID(task.id, preferredTaskID)) ? preferredTaskID! : '');
  const [targetKey, setTargetKey] = useState('auto');
  const [editing, setEditing] = useState(false);
  const task = candidates.find(item => sameID(item.id, taskID));
  const plan = task ? effectiveTaskPlan(task, day) : null;
  const primaryDefault = !plan?.plannedStart || (plan.plannedPrecision === 'date' && !isMultiDayPlan(plan));
  const actualKey = targetKey === 'auto' ? primaryDefault ? 'plan' : 'additional' : targetKey;
  const target: ArrangementRef | 'additional' = actualKey === 'additional' ? 'additional' : actualKey === 'plan' ? { source: 'taskPlan' } : { source: 'executionSlot', slotID: actualKey };
  if (editing && task) return <ArrangementEditor task={task} day={day} target={target} initial={selection ? { plannedStart: selection.start, plannedEnd: selection.end, plannedPrecision: 'minute', planRangeIntent: 'progress' } : undefined} mutate={mutate} onClose={() => { onSelect(task.id); onClose(); }}/>;
  return <TodayModal title="安排已有任务" onClose={onClose}><TaskChoice tasks={candidates} database={database} value={taskID} onChange={id => { setTaskID(id); setTargetKey('auto'); }}/>{task && <label className="today-field">安排方式<select aria-label="安排方式" value={actualKey} onChange={event => setTargetKey(event.target.value)}><option value="plan">{plan?.plannedStart ? `修改安排：${planLabel(plan)}` : '选择日期 / 时间'}</option><option value="additional">添加独立时段，保留已有安排</option>{resolveTaskArrangements(task, day).filter(item => item.source === 'executionSlot').map(item => <option key={item.slotID} value={item.slotID}>{`修改独立时段：${planLabel(item.plan)}`}</option>)}</select></label>}{selection && <p className="muted">所选时段：{rangeLabel(selection.start, selection.end)}。下一步可核对范围，取消不会保存。</p>}{selection && planConflicts(selection, snapshot.planBlocks) && <p className="time-warning">所选时段与已有安排重叠，请核对是修改已有安排还是另加一段</p>}<div className="modal-actions"><button className="button" onClick={onClose}>取消</button><button className="button primary" disabled={!task} onClick={() => setEditing(true)}>下一步：编辑安排</button></div></TodayModal>;
}

export function ActualEditor({ database, workspaceID, day, selection, entry, preferredTaskID, mutate, onClose, onSelect }: { database: GTDDatabase; workspaceID: string; day: string; selection?: Selection; entry?: TimeEntry; preferredTaskID?: string | null; mutate: Mutation; onClose: () => void; onSelect: (id: string) => void }) {
  const now = new Date();
  const initial = selection || makeScheduleSelection(day, Math.max(0, now.getHours() * 60 + now.getMinutes() - 30), now.getHours() * 60 + now.getMinutes(), true);
  const originalStart = entry?.startedAt || initial.start, originalEnd = entry?.endedAt || initial.end;
  const [action, setAction] = useState<'manual' | 'pomodoro'>(entry || new Date(initial.end) <= now ? 'manual' : 'pomodoro');
  const [taskID, setTaskID] = useState(entry ? entry.taskID || '' : preferredSchedulableTaskID(database.tasks, workspaceID, day, preferredTaskID));
  const [title, setTitle] = useState(entry?.title || '');
  const [note, setNote] = useState(entry?.note || '');
  const [start, setStart] = useState(inputDateTime(originalStart));
  const [end, setEnd] = useState(inputDateTime(originalEnd));
  const [minutes, setMinutes] = useState(String(Math.max(1, Math.min(180, Math.round((new Date(initial.end).getTime() - new Date(initial.start).getTime()) / 60_000)))));
  const [error, setError] = useState('');
  const [confirmDelete, setConfirmDelete] = useState(false);
  const candidates = database.tasks.filter(task => sameID(task.workspaceID, workspaceID) && ((!!entry && sameID(task.id, taskID)) || canScheduleTaskOnDay(task, day)));
  const save = () => {
    let failure: string | null;
    if (action === 'pomodoro' && !entry) {
      const targetMinutes = Number(minutes);
      if (!Number.isInteger(targetMinutes) || targetMinutes < 1 || targetMinutes > 180) { setError('番茄钟时长需为 1–180 分钟的整数'); return; }
      failure = mutate(db => startTimerSession(db, { workspaceID, taskID: taskID || null, mode: 'pomodoro', targetMinutes, title: title.trim() || undefined }));
    } else {
      const interval = resolveActualDraftRange(start, end, originalStart, originalEnd);
      if (!interval) { setError('结束时间必须晚于开始时间'); return; }
      const entryTitle = title.trim() || database.tasks.find(task => sameID(task.id, taskID))?.title || '无任务专注';
      failure = entry
        ? mutate(db => updateTimeEntry(db, workspaceID, entry.id, buildActualEntryPatch(entry, { start, end, taskID, title, note }, entryTitle)!))
        : mutate(db => addTimeEntry(db, { workspaceID, taskID: taskID || null, ...interval, title: entryTitle, note }));
    }
    if (failure) setError(failure); else onClose();
  };
  const remove = () => { if (!entry) return; const failure = mutate(db => deleteTimeEntry(db, workspaceID, entry.id)); if (failure) setError(failure); else onClose(); };
  return <TodayModal title={entry ? '编辑实际记录' : '使用实际轨时间段'} onClose={onClose}><form onSubmit={event => { event.preventDefault(); save(); }}>{!entry && <div className="today-mode-switch" aria-label="实际轨操作">{(['manual', 'pomodoro'] as const).map(mode => <button type="button" key={mode} className={action === mode ? 'selected' : ''} aria-pressed={action === mode} onClick={() => { setAction(mode); setError(''); }}>{mode === 'manual' ? '补录实际' : '开始番茄钟'}</button>)}</div>}{action === 'manual' ? <><p className="muted">{entry ? `记录来源：${entry.source === 'manual' ? '手动补录' : entry.source === 'pomodoro' ? '番茄钟' : '正计时'}。修改仅影响实际记录。` : '按具体起止时间保存为手动补录。未来时间或与实际记录、活动计时重叠的时段不能保存。'}</p><IntervalFields start={start} end={end} onStart={setStart} onEnd={setEnd}/></> : <><p className="muted">从现在开始计时。到时后继续记录超时，直到手动停止；不会自动进入休息。</p><label className="today-field">番茄钟时长（分钟）<input aria-label="番茄钟时长（分钟）" type="number" min="1" max="180" step="1" required value={minutes} onChange={event => setMinutes(event.target.value)}/></label>{database.activeTimer && <p className="alert warning">已有计时正在运行或暂停，请先停止它</p>}</>}<TaskChoice database={database} tasks={candidates} value={taskID} onChange={setTaskID} optional/><label className="today-field">记录名称<input placeholder={taskID ? '默认使用任务名称' : '自由专注'} value={title} onChange={event => setTitle(event.target.value)}/></label>{action === 'manual' && <label className="today-field">备注<textarea rows={2} value={note} onChange={event => setNote(event.target.value)}/></label>}{error && <p role="alert" className="today-form-error">{error}</p>}{entry && confirmDelete && <div className="today-delete-confirm" role="alert"><strong>删除这条实际记录？</strong><p>只删除这条专注记录，任务与计划时段不会改变。此操作不能撤销。</p><button type="button" className="button" onClick={() => setConfirmDelete(false)}>保留记录</button><button type="button" className="button danger" onClick={remove}>确认删除实际记录</button></div>}<div className="modal-actions today-editor-actions">{entry && <><button type="button" className="text-button danger-text" onClick={() => setConfirmDelete(true)}>删除记录</button>{entry.taskID && <button type="button" className="text-button" onClick={() => { onSelect(entry.taskID!); onClose(); }}>查看任务</button>}</>}<span/><button type="button" className="button" onClick={onClose}>取消</button><button type="submit" className="button primary" disabled={!entry && action === 'pomodoro' && !!database.activeTimer}>{entry ? '保存修改' : action === 'manual' ? '保存实际记录' : '开始番茄钟'}</button></div></form></TodayModal>;
}

export function PlanDetails({ block, database, day, mutate, onClose }: { block: PlanBlock; database: GTDDatabase; day: string; workspaceID: string; mutate: Mutation; onSelect: (id: string) => void; onClose: () => void }) {
  const task = database.tasks.find(item => sameID(item.id, block.taskID));
  return task ? <ArrangementEditor task={task} day={day} target={{ source: block.source, slotID: block.slotID }} mutate={mutate} onClose={onClose}/> : <TodayModal title="安排已不存在" onClose={onClose}><p>请关闭后重新选择任务</p></TodayModal>;
}
