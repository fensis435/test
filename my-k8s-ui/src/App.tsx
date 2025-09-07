// src/App.tsx
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import AppContainer from './AppContainer';

const queryClient = new QueryClient();

export default function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <AppContainer />
    </QueryClientProvider>
  );
}
