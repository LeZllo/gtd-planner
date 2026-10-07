import { dateDay, emptyPlan, isDayKey, localDate, type TaskPlan } from '../domain';
import { inputDateTime } from './today/drafts';

export interface PlanDraft { precision: TaskPlan['plannedPrecision']; start: string; end: string; intent: TaskPlan['planRangeIntent']; exactEnd?: { input: string; instant: string } }
export function planDraft(plan: TaskPlan): PlanDraft {
  const format = (value?: string | null) => !value ? '' : plan.plannedPrecision === 'date' ? dateDay(value) : inputDateTime(value);
  return { precision: plan.plannedPrecision, start: format(plan.plannedStart), end: format(plan.plannedEnd), intent: plan.planRangeIntent };
}
/** Unchanged minute controls preserve original seconds, timezone offsets and DST fold choice. */
export function resolvePlanDraft(draft: PlanDraft, original: TaskPlan): TaskPlan {
  if (JSON.stringify(draft) === JSON.stringify(planDraft(original))) return original;
  if (draft.precision === 'none') return emptyPlan();
  const initial = planDraft(original);
  const resolve = (value: string, oldValue: string | null | undefined, oldDraft: string) => {
    if (!value) return null;
    if (draft.precision === original.plannedPrecision && value === oldDraft) return oldValue;
    if (draft.precision === 'date') { if (!isDayKey(value)) throw new Error('请选择有效日期'); return value; }
    const date = new Date(value);
    if (!Number.isFinite(date.getTime())) throw new Error('请选择有效时间');
    return date.toISOString();
  };
  const start = resolve(draft.start, original.plannedStart, initial.start);
  const end = draft.precision === 'minute' && draft.exactEnd?.input === draft.end ? draft.exactEnd.instant : resolve(draft.end, original.plannedEnd, initial.end);
  if (!start) throw new Error('请选择安排日期');
  if (end && localDate(end) < localDate(start)) throw new Error('结束不能早于开始');
  return { ...original, plannedStart: start, plannedEnd: end, plannedPrecision: draft.precision, planRangeIntent: draft.intent };
}
export function withPlanDuration(draft: PlanDraft, original: TaskPlan, minutes: number): PlanDraft {
  const plan = resolvePlanDraft(draft, original);
  if (!plan.plannedStart || plan.plannedPrecision !== 'minute' || !Number.isFinite(minutes) || minutes <= 0) throw new Error('请选择具体开始时间');
  const instant = new Date(Date.parse(plan.plannedStart) + minutes * 60_000).toISOString(), input = inputDateTime(instant);
  return { ...draft, end: input, exactEnd: { input, instant } };
}
