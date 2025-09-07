// src/components/AppList.tsx
import { CircularProgress, Stack, Typography } from '@mui/material';
import { useApps } from '../hooks/useK8s';
import { AppControl } from './AppControl';

export function AppList() {
  const { data, isLoading } = useApps();

  if (isLoading) {
    return <CircularProgress />;
  }

  return (
    <Stack spacing={2}>
      {data!.map(app => (
        <AppControl
          key={app.name}
          name={app.name}
          status={app.status}
        />
      ))}
      {data!.length === 0 && (
        <Typography>アプリがありません。install ボタンを押してください。</Typography>
      )}
    </Stack>
  );
}
