/** Schema 11 values keep their original JSON keys and unknown extension fields. */
export interface Preserved { [key: string]: unknown }
export type TaskStatus = 'inbox' | 'open' | 'in-progress' | 'waiting' | 'someday' | 'done' | 'cancelled';
export type Priority = 'none' | 'low' | 'medium' | 'high';
export type DatePrecision = 'none' | 'date' | 'minute';
export type TimerMode = 'stopwatch' | 'pomodoro';
export interface Workspace extends Preserved { id: string; name: string; symbolName?: string; colorHex?: string }
export interface Project extends Preserved { id: string; workspaceID: string; name: string; colorHex: string; order: number; category?: string; symbolName?: string; note?: string }
export interface ProjectCategory extends Preserved { id: string; workspaceID: string; name: string; colorHex: string; order: number }
export interface ProjectSection extends Preserved { id: string; projectID: string; name: string; colorHex: string; order: number }
export interface TagCategory extends ProjectCategory { createdAt: string; updatedAt: string }
export interface TaskTagDefinition extends TagCategory { categoryID?: string | null; note: string }
export interface ExecutionSlot extends Preserved { id: string; start: string; end: string }
export interface GTDTask extends Preserved {
  id: string; title: string; workspaceID: string; projectID?: string | null; sectionID?: string | null; parentID?: string | null;
  status: TaskStatus; priority: Priority; actionList: 'next-action' | 'waiting' | 'someday-maybe';
  tags: string[]; contexts: string[]; plannedStart?: string | null; plannedEnd?: string | null;
  plannedPrecision: DatePrecision; planRangeIntent: 'progress' | 'complete-within'; executionSlots: ExecutionSlot[];
  deadline?: string | null; deadlinePrecision: DatePrecision; recurrence: string; note: string;
  createdAt: string; updatedAt: string; completedAt?: string | null; order: number;
  completedInstances: string[]; skippedInstances: string[];
}
export interface TimeEntry extends Preserved {
  id: string; workspaceID: string; taskID?: string | null; title: string; startedAt: string; endedAt: string;
  source: TimerMode | 'manual'; pomodoroPhase?: 'focus' | 'shortBreak' | 'longBreak' | null; note: string; activeSeconds?: number | null;
}
export interface ActiveTimer extends Preserved {
  mode: TimerMode; workspaceID?: string | null; taskID?: string | null; title: string;
  sessionStartedAt: string; startedAt: string; pausedAt?: string | null; accumulatedSeconds: number;
  targetSeconds?: number | null; phase?: 'focus' | 'shortBreak' | 'longBreak' | null; focusCount: number;
}
export interface ActivityLogEntry extends Preserved { id: string; timestamp: string; action: string; target: string; detail: string }
export interface TrashItem extends Preserved {
  id: string; kind: 'workspace' | 'project' | 'task'; objectID: string; workspaceID: string; name: string; deletedAt: string;
  workspace?: Workspace | null; project?: Project | null; projectCategories: ProjectCategory[]; projectSections?: ProjectSection[] | null;
  tagCategories?: TagCategory[] | null; tagDefinitions?: TaskTagDefinition[] | null; projects: Project[]; tasks: GTDTask[]; timeEntries: TimeEntry[];
}
export interface GTDDatabase extends Preserved {
  schemaVersion: number; workspaces: Workspace[]; workspaceOrder: string[]; pinnedWorkspaceIDs: string[];
  workspaceShortcutsConfigured: boolean; workspaceSortMode: 'manual' | 'name' | 'recent'; workspaceLastOpenedAt: Record<string, string>;
  projects: Project[]; projectCategories: ProjectCategory[]; projectSections: ProjectSection[];
  tagCategories: TagCategory[]; tagDefinitions: TaskTagDefinition[]; tasks: GTDTask[]; timeEntries: TimeEntry[];
  activeTimer?: ActiveTimer | null; trashItems: TrashItem[]; activityLog: ActivityLogEntry[];
}
