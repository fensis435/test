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
// react-auth-kit configuration
const authConfig = {
  authType: 'cookie',
  authName: '_auth',
  cookieDomain: window.location.hostname,
  cookieSecure: window.location.protocol === 'https:',
  cookieSameSite: 'strict',
  refreshApi: {
    url: `${import.meta.env.VITE_API_BASE_URL}/auth/refresh`,
    method: 'POST'
  },
  refreshApiCallback: (result) => {
    console.log('Token refresh result:', result);
    return {
      isSuccess: result?.status === 200,
      newAuthToken: result?.data?.access_token,
      newAuthTokenExpireIn: result?.data?.access_token.exp || 3600,
      newRefreshTokenExpiresIn: result?.data?.refresh_token.exp || 86400
    };
  }
};

root.render(
  <React.StrictMode>
    <ThemeProvider theme={theme}>
      <CssBaseline />
      <NotificationProvider>
        <AuthProvider {...authConfig}>
          <App />
        </AuthProvider>
      </NotificationProvider>
    </ThemeProvider>
  </React.StrictMode>
);
