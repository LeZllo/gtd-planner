import React from 'react';
import { createRoot } from 'react-dom/client';
import App, { recordCommit } from './App';
import './styles.css';
import './reference.css';

createRoot(document.getElementById('root')!).render(<React.StrictMode><React.Profiler id="planner" onRender={recordCommit}><App /></React.Profiler></React.StrictMode>);
