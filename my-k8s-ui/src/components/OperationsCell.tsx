// src/components/OperationsCell.tsx
import { useState, useEffect, useCallback } from 'react';
import type { GridApi } from '@mui/x-data-grid';
import { Box, Button, LinearProgress, Stack, Chip } from '@mui/material';
import { useStartApp, useStopApp, useRestartApp, useUninstallApp, useOperationStatus } from '../hooks/useK8s';
import { useQueryClient } from '@tanstack/react-query';

type AppStatus = 'running' | 'stopped';
type Action    = 'start' | 'stop' | 'restart' | 'uninstall';

interface Props {
  name:   string;
  status: AppStatus;
  apiRef: React.MutableRefObject<GridApi>;
}

export default function OperationsCell({ name, status, apiRef }: Props) {
  const start     = useStartApp();
  const stop      = useStopApp();
  const restart   = useRestartApp();
  const uninstall = useUninstallApp();
  const qc        = useQueryClient();

  const [pendingAction, setPendingAction] = useState<Action | null>(null);
  const [opId, setOpId]                   = useState<string>('');
  const { data: op }                      = useOperationStatus(opId);

  const processing = Boolean(opId) && op?.phase !== 'idle';

  const handleOp = useCallback(async (action: Action) => {
    setPendingAction(action);
    let res: { operationId: string };
    switch (action) {
      case 'start':     res = await start.mutateAsync(name);     break;
      case 'stop':      res = await stop.mutateAsync(name);      break;
      case 'restart':   res = await restart.mutateAsync(name);   break;
      case 'uninstall': res = await uninstall.mutateAsync(name); break;
    }
    setOpId(res.operationId);
  }, [name, start, stop, restart, uninstall]);

  useEffect(() => {
    if (opId && op?.phase === 'idle' && pendingAction) {
      // 次のステータスを決定
      const nextStatus: AppStatus =
        pendingAction === 'start'   ||
        pendingAction === 'restart'
          ? 'running'
          : 'stopped';

      // ① DataGrid の該当行だけ更新
      apiRef.current.updateRows([{ id: name, status: nextStatus }]);

      // ② React Query キャッシュにもパッチ適用
      qc.setQueryData<{ name: string; status: AppStatus; namespace: string }[]>(
        ['apps'],
        old =>
          old?.map(a =>
            a.name === name ? { ...a, status: nextStatus } : a
          ) ?? []
      );

      // ③ AppTable に通知（必要なら）
      window.dispatchEvent(new CustomEvent('appsUpdated'));

      // 後片付け
      setOpId('');
      setPendingAction(null);
    }
  }, [op, opId, pendingAction, name, apiRef, qc]);

  const phaseLabel =
    op?.phase === 'starting'     ? '起動中' :
    op?.phase === 'stopping'     ? '停止中' :
    op?.phase === 'restarting'   ? '再起動中' :
    op?.phase === 'uninstalling' ? 'アンインストール中' :
    '';

  return (
    <Box width="100%">
      <Stack direction="row" spacing={1} alignItems="center" flexWrap="wrap" mb={1}>
        {!processing && status === 'stopped' && (
          <>
            <Button size="small" variant="contained" onClick={() => handleOp('start')}>起動</Button>
            <Button size="small" onClick={() => handleOp('uninstall')}>アンインストール</Button>
          </>
        )}
        {!processing && status === 'running' && (
          <>
            <Button size="small" onClick={() => handleOp('stop')}>停止</Button>
            <Button size="small" onClick={() => handleOp('restart')}>再起動</Button>
          </>
        )}
        {processing && <Chip label={phaseLabel} size="small" color="primary" />}
      </Stack>
      {opId && (
        <LinearProgress
          variant={op?.progress != null ? 'determinate' : 'indeterminate'}
          value={op?.progress ?? undefined}
        />
      )}
    </Box>
  );
}
