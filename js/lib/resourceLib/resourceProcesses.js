import { get } from 'lodash';

export function makeResourceProcesses() {
  return {};
}

export function processesUpdate(processes, processName, action, status, extra = {}) {
  // We don't return an updated processes if the action doesn't have the initiated flag set,
  // i.e. it was an error that occurred before the request was made. This way, errors due to
  // badly constructed actions (e.g. pid collision) can't clobber the state of currently running actions.
  if (!get(action, ['meta', 'initiated'])) { return processes; }

  processes = processes || {};
  const origProcess = processes[processName] || {};

  const pid = action.meta.originalAction.meta.pid;
  const entry = { status, ...extra };
  const updatedProcess = { ...origProcess, [pid]: entry };
  return { ...processes, [processName]: updatedProcess };
}
