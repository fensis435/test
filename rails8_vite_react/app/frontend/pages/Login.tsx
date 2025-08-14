import React, { useState } from 'react';
import {
  Container,
  Typography,
  TextField,
  Button,
  Paper,
  Box,
  CircularProgress,
  Checkbox,
  FormControlLabel,
  Alert,
  Link
} from '@mui/material';
import { useNavigate } from 'react-router-dom';
import { useSignIn } from 'react-auth-kit';
import { Link as RouterLink } from 'react-router-dom';
import { InputAdornment, IconButton } from '@mui/material';
import { Visibility, VisibilityOff } from '@mui/icons-material';
import AuthService from '../auth/authService';

export default function Login() {
  const [loading, setLoading] = useState(false);
  const [form, setForm] = useState({ email: '', password: '' });
  const [errors, setErrors] = useState({ email: '', password: '' });
  const [serverError, setServerError] = useState('');
  const signIn = useSignIn();
  const navigate = useNavigate();
  const [showPassword, setShowPassword] = useState(false);

  const togglePasswordVisibility = () => {
    setShowPassword((prev) => !prev);
  };

  const validate = () => {
    const newErrors = { email: '', password: '' };
    let isValid = true;

    if (!form.email) {
      newErrors.email = 'Email is required';
      isValid = false;
    } else if (form.email.includes('@') && !/\S+@\S+\.\S+/.test(form.email)) {
      newErrors.email = 'Invalid email format';
      isValid = false;
    }

    if (!form.password) {
      newErrors.password = 'Password is required';
      isValid = false;
    }

    setErrors(newErrors);
    return isValid;
  };

  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setForm({ ...form, [e.target.name]: e.target.value });
    setErrors({ ...errors, [e.target.name]: '' });
    setServerError('');
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!validate()) return;

    setLoading(true);
    setServerError('');

    try {
      console.log('form', form, e);
      const response = await AuthService.login(form.email, form.password);

      // リフレッシュトークンをローカルストレージに保存
      localStorage.setItem('refreshToken', response.refresh_token);

      // react-auth-kitでサインイン
      const signInSuccess = signIn({
        token: response.access_token,
        expiresIn: 1440, // 24時間（分単位）
        tokenType: 'Bearer',
        authState: {
          id: response.user.id,
          name: response.user.name,
          email: response.user.email
        }
      });

      if (signInSuccess) {
        navigate('/');
      } else {
        setServerError(
          data.message || 'Login failed. Please check your credentials.'
        );
      }
    } catch (error) {
      setServerError('Network error. Please try again later.');
      console.log(error);
    }

    setLoading(false);
  };

  return (
    <Container maxWidth='xs'>
      <Box sx={{ position: 'relative', mt: 8 }}>
        {loading && (
          <Box
            sx={{
              position: 'absolute',
              top: 0,
              left: 0,
              zIndex: 1,
              width: '100%',
              height: '100%',
              bgcolor: 'rgba(255,255,255,0.7)',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center'
            }}
          >
            <CircularProgress />
          </Box>
        )}
        <Paper elevation={3} sx={{ p: 4 }}>
          <Typography variant='h5' align='center' gutterBottom>
            Welcome back!
          </Typography>

          {serverError && (
            <Alert severity='error' sx={{ mb: 2 }}>
              {serverError}
            </Alert>
          )}

          <form onSubmit={handleSubmit}>
            <TextField
              label='Username or Email'
              name='email'
              type='email'
              fullWidth
              required
              margin='normal'
              value={form.email}
              onChange={handleChange}
              error={!!errors.email}
              helperText={errors.email}
            />
            <TextField
              label='Password'
              name='password'
              type={showPassword ? 'text' : 'password'}
              fullWidth
              required
              margin='normal'
              value={form.password}
              onChange={handleChange}
              error={!!errors.password}
              helperText={errors.password}
              InputProps={{
                endAdornment: (
                  <InputAdornment
                    position='end'
                    sx={{ backgroundColor: 'transparent' }}
                  >
                    <IconButton
                      aria-label='toggle password visibility'
                      onClick={togglePasswordVisibility}
                      edge='end'
                      disableRipple
                      sx={{ backgroundColor: 'transparent !important' }}
                    >
                      {showPassword ? <VisibilityOff /> : <Visibility />}
                    </IconButton>
                  </InputAdornment>
                )
              }}
            />

            <FormControlLabel
              control={<Checkbox />}
              label='Remember me'
              sx={{ mt: 1 }}
            />
            <Button
              type='submit'
              variant='contained'
              color='primary'
              fullWidth
              sx={{ mt: 3 }}
              disabled={loading}
            >
              Sign in
            </Button>
            <Typography align='center' sx={{ mt: 2 }}>
              Don't have an account?{' '}
              <Link component={RouterLink} to='/signup'>
                Sign up
              </Link>
            </Typography>
          </form>
        </Paper>
      </Box>
    </Container>
  );
}
