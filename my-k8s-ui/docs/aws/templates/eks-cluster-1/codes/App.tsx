// =============================================================================
// frontend/src/App.tsx
// React + Amplify JS v6 + MUI v5
// Cognito authentication with custom login UI (no Amplify UI components).
// JWT token is stored in memory (not localStorage) for XSS protection.
// Groups are treated as labels only; RBAC is handled server-side by Rails.
// =============================================================================

import React, { useEffect, useState, createContext, useContext } from 'react';
import { Amplify } from 'aws-amplify';
import {
  signIn,
  signOut,
  getCurrentUser,
  fetchAuthSession,
  confirmSignIn,
  type AuthUser,
} from 'aws-amplify/auth';
import {
  ThemeProvider,
  createTheme,
  CssBaseline,
  Box,
  Container,
  Paper,
  TextField,
  Button,
  Typography,
  Alert,
  CircularProgress,
  InputAdornment,
  IconButton,
  Divider,
  Chip,
  AppBar,
  Toolbar,
  Avatar,
  Menu,
  MenuItem,
  Snackbar,
} from '@mui/material';
import {
  Visibility,
  VisibilityOff,
  LockOutlined,
  AccountCircle,
  ExitToApp,
} from '@mui/icons-material';

// ── Amplify configuration (values injected at build time via env vars) ────────
Amplify.configure({
  Auth: {
    Cognito: {
      userPoolId:       process.env.REACT_APP_COGNITO_USER_POOL_ID!,
      userPoolClientId: process.env.REACT_APP_COGNITO_CLIENT_ID!,
      loginWith: {
        email: true,
      },
    },
  },
});

// ── MUI Theme ─────────────────────────────────────────────────────────────────
const theme = createTheme({
  palette: {
    mode: 'light',
    primary:   { main: '#1976d2' },
    secondary: { main: '#9c27b0' },
    background: { default: '#f5f5f5' },
  },
  shape:       { borderRadius: 8 },
  typography:  { fontFamily: '"Inter", "Roboto", "Helvetica", "Arial", sans-serif' },
  components: {
    MuiButton: {
      styleOverrides: {
        root: { textTransform: 'none', fontWeight: 600 },
      },
    },
  },
});

// ── Auth context ──────────────────────────────────────────────────────────────
interface AuthContextValue {
  user:        AuthUser | null;
  idToken:     string | null;    // JWT — sent as Bearer in API calls
  groups:      string[];         // Cognito groups (label-only)
  loading:     boolean;
  handleSignOut: () => Promise<void>;
  refreshToken:  () => Promise<void>;
}

const AuthContext = createContext<AuthContextValue>({
  user: null, idToken: null, groups: [], loading: true,
  handleSignOut: async () => {}, refreshToken: async () => {},
});

export const useAuth = () => useContext(AuthContext);

// ── Auth Provider ─────────────────────────────────────────────────────────────
function AuthProvider({ children }: { children: React.ReactNode }) {
  const [user,    setUser]    = useState<AuthUser | null>(null);
  const [idToken, setIdToken] = useState<string | null>(null);
  const [groups,  setGroups]  = useState<string[]>([]);
  const [loading, setLoading] = useState(true);

  const loadSession = async () => {
    try {
      const currentUser = await getCurrentUser();
      const session     = await fetchAuthSession();
      const token       = session.tokens?.idToken?.toString() ?? null;
      // Groups are in the 'cognito:groups' claim — label only
      const rawGroups   = (session.tokens?.idToken?.payload?.['cognito:groups'] as string[]) ?? [];
      setUser(currentUser);
      setIdToken(token);
      setGroups(rawGroups);
    } catch {
      setUser(null); setIdToken(null); setGroups([]);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { loadSession(); }, []);

  // Auto-refresh token 5 min before expiry
  useEffect(() => {
    if (!idToken) return;
    const payload = JSON.parse(atob(idToken.split('.')[1]));
    const expiresAt = payload.exp * 1000;
    const refreshAt = expiresAt - 5 * 60 * 1000;
    const delay = refreshAt - Date.now();
    if (delay <= 0) { loadSession(); return; }
    const timer = setTimeout(loadSession, delay);
    return () => clearTimeout(timer);
  }, [idToken]);

  const handleSignOut = async () => {
    await signOut();
    setUser(null); setIdToken(null); setGroups([]);
  };

  return (
    <AuthContext.Provider value={{ user, idToken, groups, loading, handleSignOut, refreshToken: loadSession }}>
      {children}
    </AuthContext.Provider>
  );
}

// ── Login Form ────────────────────────────────────────────────────────────────
type LoginStep = 'credentials' | 'new_password' | 'mfa';

function LoginPage() {
  const [step,            setStep]            = useState<LoginStep>('credentials');
  const [email,           setEmail]           = useState('');
  const [password,        setPassword]        = useState('');
  const [newPassword,     setNewPassword]     = useState('');
  const [mfaCode,         setMfaCode]         = useState('');
  const [showPassword,    setShowPassword]    = useState(false);
  const [submitting,      setSubmitting]      = useState(false);
  const [errorMsg,        setErrorMsg]        = useState<string | null>(null);

  const handleCredentials = async (e: React.FormEvent) => {
    e.preventDefault();
    setSubmitting(true); setErrorMsg(null);
    try {
      const result = await signIn({ username: email, password });
      if (result.nextStep.signInStep === 'CONFIRM_SIGN_IN_WITH_NEW_PASSWORD_REQUIRED') {
        setStep('new_password');
      } else if (result.nextStep.signInStep === 'CONFIRM_SIGN_IN_WITH_TOTP_CODE') {
        setStep('mfa');
      }
      // If isSignedIn=true, AuthProvider useEffect will pick it up
    } catch (err: any) {
      setErrorMsg(friendlyError(err));
    } finally {
      setSubmitting(false);
    }
  };

  const handleNewPassword = async (e: React.FormEvent) => {
    e.preventDefault();
    setSubmitting(true); setErrorMsg(null);
    try {
      await confirmSignIn({ challengeResponse: newPassword });
    } catch (err: any) {
      setErrorMsg(friendlyError(err));
    } finally {
      setSubmitting(false);
    }
  };

  const handleMFA = async (e: React.FormEvent) => {
    e.preventDefault();
    setSubmitting(true); setErrorMsg(null);
    try {
      await confirmSignIn({ challengeResponse: mfaCode });
    } catch (err: any) {
      setErrorMsg(friendlyError(err));
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <Box sx={{ minHeight: '100vh', display: 'flex', alignItems: 'center',
               background: 'linear-gradient(135deg, #1976d2 0%, #42a5f5 100%)' }}>
      <Container maxWidth="xs">
        <Paper elevation={8} sx={{ p: 4, borderRadius: 3 }}>
          {/* Logo / Title */}
          <Box sx={{ display: 'flex', flexDirection: 'column', alignItems: 'center', mb: 3 }}>
            <Avatar sx={{ bgcolor: 'primary.main', width: 56, height: 56, mb: 1 }}>
              <LockOutlined fontSize="large" />
            </Avatar>
            <Typography variant="h5" fontWeight={700}>Sign In</Typography>
            <Typography variant="body2" color="text.secondary">
              {step === 'new_password' ? 'Set your new password'
                : step === 'mfa'      ? 'Enter your MFA code'
                : 'Enter your credentials'}
            </Typography>
          </Box>

          {errorMsg && (
            <Alert severity="error" sx={{ mb: 2 }} onClose={() => setErrorMsg(null)}>
              {errorMsg}
            </Alert>
          )}

          {/* Step: credentials */}
          {step === 'credentials' && (
            <Box component="form" onSubmit={handleCredentials}>
              <TextField
                fullWidth required label="Email" type="email" value={email}
                onChange={e => setEmail(e.target.value)} sx={{ mb: 2 }}
                autoComplete="email" autoFocus
              />
              <TextField
                fullWidth required label="Password"
                type={showPassword ? 'text' : 'password'}
                value={password} onChange={e => setPassword(e.target.value)} sx={{ mb: 3 }}
                autoComplete="current-password"
                InputProps={{
                  endAdornment: (
                    <InputAdornment position="end">
                      <IconButton onClick={() => setShowPassword(p => !p)} edge="end">
                        {showPassword ? <VisibilityOff /> : <Visibility />}
                      </IconButton>
                    </InputAdornment>
                  ),
                }}
              />
              <Button fullWidth variant="contained" type="submit" size="large"
                      disabled={submitting} sx={{ py: 1.5 }}>
                {submitting ? <CircularProgress size={24} color="inherit" /> : 'Sign In'}
              </Button>
            </Box>
          )}

          {/* Step: force new password */}
          {step === 'new_password' && (
            <Box component="form" onSubmit={handleNewPassword}>
              <Alert severity="info" sx={{ mb: 2 }}>
                Your password has expired. Please set a new password.
              </Alert>
              <TextField
                fullWidth required label="New Password"
                type={showPassword ? 'text' : 'password'}
                value={newPassword} onChange={e => setNewPassword(e.target.value)}
                sx={{ mb: 3 }} autoFocus
                helperText="Min 12 chars, upper/lower/number/symbol required"
              />
              <Button fullWidth variant="contained" type="submit" size="large"
                      disabled={submitting} sx={{ py: 1.5 }}>
                {submitting ? <CircularProgress size={24} color="inherit" /> : 'Set Password'}
              </Button>
            </Box>
          )}

          {/* Step: TOTP MFA */}
          {step === 'mfa' && (
            <Box component="form" onSubmit={handleMFA}>
              <Alert severity="info" sx={{ mb: 2 }}>
                Enter the 6-digit code from your authenticator app.
              </Alert>
              <TextField
                fullWidth required label="MFA Code" value={mfaCode}
                onChange={e => setMfaCode(e.target.value.replace(/\D/g, '').slice(0, 6))}
                sx={{ mb: 3 }} autoFocus inputProps={{ maxLength: 6, inputMode: 'numeric' }}
              />
              <Button fullWidth variant="contained" type="submit" size="large"
                      disabled={submitting || mfaCode.length !== 6} sx={{ py: 1.5 }}>
                {submitting ? <CircularProgress size={24} color="inherit" /> : 'Verify'}
              </Button>
            </Box>
          )}
        </Paper>
      </Container>
    </Box>
  );
}

// ── Top App Bar with user info + sign out ─────────────────────────────────────
function TopBar() {
  const { user, groups, handleSignOut } = useAuth();
  const [anchorEl, setAnchorEl] = useState<HTMLElement | null>(null);
  const [snackbar, setSnackbar] = useState(false);

  const doSignOut = async () => {
    setAnchorEl(null);
    await handleSignOut();
    setSnackbar(true);
  };

  return (
    <>
      <AppBar position="fixed" elevation={1} sx={{ bgcolor: 'white', color: 'text.primary' }}>
        <Toolbar>
          <Typography variant="h6" fontWeight={700} sx={{ flexGrow: 1, color: 'primary.main' }}>
            Platform
          </Typography>
          {/* Group labels (Cognito groups = display-only labels) */}
          {groups.map(g => (
            <Chip key={g} label={g} size="small" variant="outlined"
                  color="primary" sx={{ mr: 1 }} />
          ))}
          <IconButton onClick={e => setAnchorEl(e.currentTarget)}>
            <AccountCircle />
          </IconButton>
          <Menu anchorEl={anchorEl} open={Boolean(anchorEl)}
                onClose={() => setAnchorEl(null)}>
            <MenuItem disabled>
              <Typography variant="body2" color="text.secondary">
                {user?.signInDetails?.loginId}
              </Typography>
            </MenuItem>
            <Divider />
            <MenuItem onClick={doSignOut}>
              <ExitToApp fontSize="small" sx={{ mr: 1 }} />
              Sign Out
            </MenuItem>
          </Menu>
        </Toolbar>
      </AppBar>
      <Snackbar open={snackbar} autoHideDuration={3000}
                onClose={() => setSnackbar(false)} message="Signed out" />
    </>
  );
}

// ── Authenticated app shell ───────────────────────────────────────────────────
function AuthenticatedApp() {
  return (
    <>
      <TopBar />
      <Box sx={{ mt: 8, p: 3 }}>
        {/* Rails-rendered content is embedded here via iframe or React Router.
            The idToken from useAuth() is passed as Authorization: Bearer <token>
            to all Rails API calls.  */}
        <Typography variant="body1">Application content loads here.</Typography>
      </Box>
    </>
  );
}

// ── Root ──────────────────────────────────────────────────────────────────────
function AppInner() {
  const { user, loading } = useAuth();

  if (loading) {
    return (
      <Box sx={{ display: 'flex', justifyContent: 'center', alignItems: 'center', height: '100vh' }}>
        <CircularProgress />
      </Box>
    );
  }

  return user ? <AuthenticatedApp /> : <LoginPage />;
}

export default function App() {
  return (
    <ThemeProvider theme={theme}>
      <CssBaseline />
      <AuthProvider>
        <AppInner />
      </AuthProvider>
    </ThemeProvider>
  );
}

// ── Helpers ───────────────────────────────────────────────────────────────────
function friendlyError(err: any): string {
  const code = err?.name ?? '';
  const map: Record<string, string> = {
    NotAuthorizedException:        'Incorrect email or password.',
    UserNotFoundException:         'User not found.',
    UserNotConfirmedException:     'Please verify your email before signing in.',
    PasswordResetRequiredException:'Password reset required. Contact your administrator.',
    TooManyRequestsException:      'Too many attempts. Please wait and try again.',
    CodeMismatchException:         'Invalid MFA code. Please try again.',
    ExpiredCodeException:          'MFA code has expired. Please try again.',
  };
  return map[code] ?? (err?.message ?? 'An unexpected error occurred.');
}

// =============================================================================
// frontend/src/hooks/useApiClient.ts
// Axios instance that auto-attaches the Cognito JWT to every request.
// Groups in JWT payload are label-only — RBAC is enforced by Rails.
// =============================================================================
export function useApiClient() {
  const { idToken, refreshToken } = useAuth();
  // Lazy import to keep this file self-contained
  const axiosRef = React.useRef<any>(null);

  useEffect(() => {
    import('axios').then(({ default: axios }) => {
      const instance = axios.create({ baseURL: '/api' });
      instance.interceptors.request.use(config => {
        if (idToken) config.headers['Authorization'] = `Bearer ${idToken}`;
        return config;
      });
      instance.interceptors.response.use(
        res => res,
        async err => {
          if (err.response?.status === 401) {
            await refreshToken();
          }
          return Promise.reject(err);
        }
      );
      axiosRef.current = instance;
    });
  }, [idToken, refreshToken]);

  return axiosRef.current;
}
