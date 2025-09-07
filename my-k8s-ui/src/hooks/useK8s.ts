// src/hooks/useK8s.ts
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import * as api from '../api';

// アプリ一覧取得
export function useApps() {
  return useQuery({
    queryKey: ['apps'],
    queryFn: api.listApps,
    staleTime: 0,            // すぐ stale にする
    refetchOnMount: true,    // マウント時に必ず再フェッチ
    refetchOnWindowFocus: false,
    onSuccess(data) {
      console.log('[useApps] onSuccess', data);
    },
  });
}

// install / start / stop / restart / uninstall をまとめて作る
const makeOpMutation = (fn: (name: string) => Promise<{operationId:string}>) => {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: fn,
    onSuccess: () => {
      // どの操作でも完了時にアプリ一覧を再フェッチ
      qc.invalidateQueries({ queryKey: ['apps'] });
    },
  });
};

export const useInstallApp   = () => makeOpMutation(api.installApp);
export const useStartApp     = () => makeOpMutation(api.startApp);
export const useStopApp      = () => makeOpMutation(api.stopApp);
export const useRestartApp   = () => makeOpMutation(api.restartApp);
export const useUninstallApp = () => makeOpMutation(api.uninstallApp);

// operationId でポーリング＋idle検知 → apps invalidate
export function useOperationStatus(operationId: string) {
  const qc = useQueryClient();

  return useQuery({
    queryKey: ['operation', operationId],
    queryFn: () => api.getOperationStatus(operationId),
    enabled: Boolean(operationId),
    refetchInterval: data => (data?.phase === 'idle' ? false : 1000),
    onSuccess(data) {
      console.log('[useOperationStatus] onSuccess', data);
      if (data.phase === 'idle') {
        console.log('[useOperationStatus] invalidating apps');
        qc.invalidateQueries({ queryKey: ['apps'] });
      }
    },
  });
}


