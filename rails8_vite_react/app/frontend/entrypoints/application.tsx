import React from 'react';
import ReactDOM from 'react-dom/client';
import App from '../App';
import { CssBaseline } from '@mui/material';
import { ThemeProvider } from '@mui/material/styles';
import { AuthProvider } from 'react-auth-kit';

import { theme } from '../theme';

const rootElement = document.getElementById('root')!;
const root = ReactDOM.createRoot(rootElement);

root.render(
  <React.StrictMode>
    <AuthProvider
      //authType='localstorage'
      //authName='_auth'
      authType={'cookie'}
      authName={'_auth'}
      cookieDomain={window.location.hostname}
      cookieSecure={false}
    >
      <ThemeProvider theme={theme}>
        <App />
        <CssBaseline />
      </ThemeProvider>
    </AuthProvider>
  </React.StrictMode>
);
