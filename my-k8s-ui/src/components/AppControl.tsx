// src/components/AppControl.tsx
import { useState, useEffect, useCallback } from 'react';
import {
  Box,
  Button,
  LinearProgress,
  Typography,
  Stack,
  Chip,
} from '@mui/material';
import {
  useInstallApp,
  useUninstallApp,
  useStartApp,
  useStopApp,
  useRestartApp,
  useOperationStatus,
} from '../hooks/useK8s';

type AppStatus = 'running' | 'stopped';
type Action = 'install' | 'start' | 'stop' | 'restart' | 'uninstall';

interface Props {
  name: string;
  status: AppStatus;
}

export function AppControl({ name, status }: Props) {
  // Mutation フック
  const install   = useInstallApp();
  const start     = useStartApp();
  const stop      = useStopApp();
  const restart   = useRestartApp();
  const uninstall = useUninstallApp();

  // 画面上のステータス
  const [localStatus, setLocalStatus]   = useState<AppStatus>(status);
  // 最後に発行した操作
  const [pendingAction, setPendingAction] = useState<Action | null>(null);
  // operationId とポーリング
  const [opId, setOpId]                 = useState<string>('');
  const { data: op }                    = useOperationStatus(opId);

  const processing = Boolean(opId) && op?.phase !== 'idle';

  // 完了を検知したら pendingAction を元に localStatus を更新
  useEffect(() => {
    if (opId && op?.phase === 'idle' && pendingAction) {
      switch (pendingAction) {
        case 'install':
        case 'start':
        case 'restart':
          setLocalStatus('running');
          break;
        case 'stop':
        case 'uninstall':
          setLocalStatus('stopped');
          break;
      }
      // 後片付け
      setOpId('');
      setPendingAction(null);
    }
  }, [op, opId, pendingAction]);

  // ボタン押下ハンドラ
  const handleOp = useCallback(
    async (action: Action) => {
      let res: { operationId: string };

      // pendingAction を先にセットしておく
      setPendingAction(action);

      switch (action) {
        case 'install':
          res = await install.mutateAsync(name);
          break;
        case 'start':
          res = await start.mutateAsync(name);
          break;
        case 'stop':
          res = await stop.mutateAsync(name);
          break;
        case 'restart':
          res = await restart.mutateAsync(name);
          break;
        case 'uninstall':
          res = await uninstall.mutateAsync(name);
          break;
      }
      setOpId(res.operationId);
    },
    [name, install, start, stop, restart, uninstall]
  );

  return (
    <Box p={2} mb={2} border="1px solid #ddd" borderRadius={2}>
      {/* タイトル行 */}
      <Stack direction="row" spacing={1} alignItems="center" mb={1}>
        <Typography variant="subtitle1">{name}</Typography>
        <Chip
          label={localStatus === 'running' ? '稼働中' : '停止中'}
          size="small"
          color={localStatus === 'running' ? 'success' : 'default'}
        />
        {processing && (
          <Chip
            label={
              op?.phase === 'installing'    ? 'インストール中' :
              op?.phase === 'starting'      ? '起動中' :
              op?.phase === 'stopping'      ? '停止中' :
              op?.phase === 'restarting'    ? '再起動中' :
              op?.phase === 'uninstalling'  ? 'アンインストール中' :
              ''
            }
            size="small"
            color="primary"
          />
        )}
      </Stack>

      {/* 操作ボタン */}
      <Stack direction="row" spacing={1} mb={1}>
        {!processing && localStatus === 'stopped' && (
          <>
            <Button variant="contained" onClick={() => handleOp('start')}>
              起動
            </Button>
            <Button onClick={() => handleOp('uninstall')}>
              アンインストール
            </Button>
          </>
        )}
        {!processing && localStatus === 'running' && (
          <>
            <Button onClick={() => handleOp('stop')}>停止</Button>
            <Button onClick={() => handleOp('restart')}>再起動</Button>
          </>
        )}
        {!processing && localStatus !== 'running' && localStatus !== 'stopped' && (
          <Button variant="contained" onClick={() => handleOp('install')}>
            インストール
          </Button>
        )}
      </Stack>

      {/* プログレスバー */}
      {opId && (
        op?.progress != null
          ? <LinearProgress variant="determinate" value={op.progress} />
          : <LinearProgress variant="indeterminate" />
      )}
    </Box>
  );
}
