const { contextBridge, ipcRenderer } = require('electron');
contextBridge.exposeInMainWorld('plannerHost', Object.freeze({
  load: () => ipcRenderer.invoke('planner:load'),
  save: database => ipcRenderer.invoke('planner:save', database),
  replace: database => ipcRenderer.invoke('planner:replace', database),
  importFile: () => ipcRenderer.invoke('planner:import'),
  exportFile: text => ipcRenderer.invoke('planner:export', text),
  onCloseRequest: callback => {
    const listener = async (_event,attempt) => {try {await callback();ipcRenderer.send('planner:close-ready',attempt);}catch {ipcRenderer.send('planner:close-failed',attempt);}};
    ipcRenderer.on('planner:prepare-close',listener);
    ipcRenderer.send('planner:renderer-ready');
    return () => ipcRenderer.removeListener('planner:prepare-close',listener);
  }
}));
