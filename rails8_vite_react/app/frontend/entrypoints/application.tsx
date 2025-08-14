import React from 'react';
import ReactDOM from 'react-dom/client';
import App from '../App';
import { CssBaseline } from '@mui/material';
import { ThemeProvider } from '@mui/material/styles';
import { AuthProvider } from 'react-auth-kit';
import { NotificationProvider } from '../context/NotificationContext';

import { theme } from '../theme';

const rootElement = document.getElementById('root')!;
const root = ReactDOM.createRoot(rootElement);

root.render(
  <React.StrictMode>
    <ThemeProvider theme={theme}>
      <CssBaseline />
      <NotificationProvider>
        <AuthProvider
          authType={'cookie'}
          authName={'_auth'}
          cookieDomain={window.location.hostname}
          cookieSecure={window.location.protocol === 'https:'}
        >
          <App />
        </AuthProvider>
      </NotificationProvider>
    </ThemeProvider>
  </React.StrictMode>
);
