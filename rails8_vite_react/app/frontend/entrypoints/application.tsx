import React from 'react';
import ReactDOM from 'react-dom/client';
import App from '../App';
import { CssBaseline } from '@mui/material';
import { ThemeProvider } from '@mui/material/styles';

import { theme } from '../theme';

const rootElement = document.getElementById('root')!;
const root = ReactDOM.createRoot(rootElement);

root.render(
  <React.StrictMode>
    <ThemeProvider theme={theme}>
      <App />
      <CssBaseline />
    </ThemeProvider>
  </React.StrictMode>
);
