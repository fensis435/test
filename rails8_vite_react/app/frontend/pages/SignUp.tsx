import React, { useState } from 'react';
import {
  Container,
  Typography,
  TextField,
  Button,
  Paper,
  Box,
  CircularProgress,
  Alert
} from '@mui/material';
import { useNavigate } from 'react-router-dom';
import { useSignIn } from 'react-auth-kit';

export default function SignUp() {
  const [loading, setLoading] = useState(false);
  const [form, setForm] = useState({
    name: '',
    email: '',
    password: '',
    password_confirmation: ''
  });
  const [errors, setErrors] = useState({
    name: '',
    email: '',
    password: '',
    password_confirmation: ''
  });
  const [serverError, setServerError] = useState('');
  const signIn = useSignIn();
  const navigate = useNavigate();

  const validate = () => {
    const newErrors = { name: '', email: '', password: '', password_confirmation: '' };
    let isValid = true;

    if (!form.name) {
      newErrors.name = 'Name is required';
      isValid = false;
    }

    if (!form.email) {
      newErrors.email = 'Email is required';
      isValid = false;
    } else if (!/\S+@\S+\.\S+/.test(form.email)) {
      newErrors.email = 'Invalid email format';
      isValid = false;
    }

    if (!form.password) {
      newErrors.password = 'Password is required';
      isValid = false;
    }

    if (form.password !== form.password_confirmation) {
      newErrors.password_confirmation = 'Passwords do not match';
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
      const res = await fetch('/api/v1/users', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          user: {
            name: form.name,
            email: form.email,
            password: form.password,
            password_confirmation: form.password_confirmation
          }
        })
      });

      const data = await res.json();

      if (res.ok && data.token) {
        const success = signIn({
          token: data.token,
          expiresIn: 3600,
          tokenType: 'Bearer',
          authState: { email: form.email }
        });

        if (success) {
          navigate('/');
        } else {
          setServerError('Sign-in failed after registration.');
        }
      } else {
        setServerError(data.errors?.join(', ') || 'Registration failed.');
      }
    } catch (error) {
      setServerError('Network error. Please try again later.');
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
            Create your account
          </Typography>

          {serverError && (
            <Alert severity='error' sx={{ mb: 2 }}>
              {serverError}
            </Alert>
          )}

          <form onSubmit={handleSubmit}>
            <TextField
              label='Name'
              name='name'
              type='namej'
              fullWidth
              required
              margin='normal'
              value={form.name}
              onChange={handleChange}
              error={!!errors.name}
              helperText={errors.name}
            />
            <TextField
              label='Email'
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
              type='password'
              fullWidth
              required
              margin='normal'
              value={form.password}
              onChange={handleChange}
              error={!!errors.password}
              helperText={errors.password}
            />
            <TextField
              label='Confirm Password'
              name='password_confirmation'
              type='password'
              fullWidth
              required
              margin='normal'
              value={form.password_confirmation}
              onChange={handleChange}
              error={!!errors.password_confirmation}
              helperText={errors.password_confirmation}
            />
            <Button
              type='submit'
              variant='contained'
              color='primary'
              fullWidth
              sx={{ mt: 3 }}
              disabled={loading}
            >
              Sign Up
            </Button>
          </form>
        </Paper>
      </Box>
    </Container>
  );
}
