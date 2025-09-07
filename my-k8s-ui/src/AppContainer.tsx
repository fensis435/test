// src/AppContainer.tsx
import { Container, Button } from '@mui/material';
import { useState } from 'react';
import { useInstallApp } from './hooks/useK8s';
import { AppTable } from './components/AppTable';

export default function AppContainer() {
  const [seed, setSeed] = useState(0);
  const install = useInstallApp();

  const addDefaultApp = () => {
    install.mutate(`demo-app-${seed}`, {
      onSuccess: () => setSeed(s => s + 1),
    });
  };

  return (
    <Container sx={{ py: 4 }}>
      <Button
        variant="contained"
        onClick={addDefaultApp}
        disabled={install.isLoading}
        sx={{ mb: 2 }}
      >
        新しいアプリをインストール
      </Button>
      <AppTable />
    </Container>
  );
}
