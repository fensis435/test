// src/api.ts
import { v4 as uuid } from 'uuid';

type AppStatus = 'stopped' | 'running';
type Phase = 'installing' | 'uninstalling' | 'starting' | 'stopping' | 'restarting' | 'idle' | 'failed';

interface App {
  name: string;
  namespace: string;
  status: AppStatus;
}

interface Operation {
  phase: Phase;
  progress: number;
  targetApp: string;
}

const apps: Record<string, App> = {};
const operations: Record<string, Operation> = {};

// 疑似的な遅延
function delay(ms: number) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

function simulateOperation(opId: string, targetPhase: Phase, endStatus: AppStatus) {
  let p = 0;
  const interval = setInterval(() => {
    p += Math.floor(Math.random() * 20) + 10;
    if (p >= 100) {
      clearInterval(interval);
      const op = operations[opId];
      op.phase = 'idle';
      op.progress = 100;

      // ← アンインストール完了時はレコードを削除
      if (targetPhase === 'uninstalling') {
        delete apps[op.targetApp];
      } else {
        apps[op.targetApp].status = endStatus;
      }
    } else {
      operations[opId].phase = targetPhase;
      operations[opId].progress = p;
    }
  }, 500);
}

export async function installApp(name: string): Promise<{ operationId: string }> {
  await delay(800); // ネットワーク+開始待ち
  const ns = `${name}-${uuid().slice(0, 6)}`;
  apps[name] = { name, namespace: ns, status: 'stopped' };

  const opId = uuid();
  operations[opId] = { phase: 'installing', progress: 0, targetApp: name };
  simulateOperation(opId, 'installing', 'running');
  return { operationId: opId };
}


export async function uninstallApp(name: string): Promise<{ operationId: string }> {
  await delay(600);
  const opId = uuid();
  operations[opId] = { phase: 'uninstalling', progress: 0, targetApp: name };
  simulateOperation(opId, 'uninstalling', 'stopped');
  return { operationId: opId };
}

export async function startApp(name: string): Promise<{ operationId: string }> {
  await delay(500);
  const opId = uuid();
  operations[opId] = { phase: 'starting', progress: 0, targetApp: name };
  simulateOperation(opId, 'starting', 'running');
  return { operationId: opId };
}

export async function stopApp(name: string): Promise<{ operationId: string }> {
  await delay(500);
  const opId = uuid();
  operations[opId] = { phase: 'stopping', progress: 0, targetApp: name };
  simulateOperation(opId, 'stopping', 'stopped');
  return { operationId: opId };
}

export async function restartApp(name: string): Promise<{ operationId: string }> {
  await delay(500);
  const opId = uuid();
  operations[opId] = { phase: 'restarting', progress: 0, targetApp: name };
  simulateOperation(opId, 'restarting', 'running');
  return { operationId: opId };
}

export async function getOperationStatus(operationId: string): Promise<Operation> {
  await delay(100);
  const op = operations[operationId];
  return { ...op };
}

export async function listApps(): Promise<App[]> {
  console.log('[API] listApps() 呼ばれました', apps);
  await delay(200);
  return Object.values(apps);
}
