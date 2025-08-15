// src/components/RegisterForm.jsx
import React, { useState } from 'react';
import {
  Card,
  CardContent,
  Typography,
  TextField,
  Button,
  Box,
  Alert,
  CircularProgress,
  IconButton,
  FormControl,
  InputLabel,
  Select,
  MenuItem,
  FormHelperText,
  Divider,
  Link
} from '@mui/material';
import {
  Visibility,
  VisibilityOff,
  PersonAdd,
  Email,
  Lock,
  Person,
  AdminPanelSettings
} from '@mui/icons-material';
import { useAuthHeader, useAuthUser } from 'react-auth-kit';
import { useNotification } from '../context/NotificationContext';
import UserService from '../services/userService';

const RegisterForm = ({ onSuccess, onCancel, isAdminCreating = false }) => {
  const [formData, setFormData] = useState({
    name: '',
    email: '',
    password: '',
    password_confirmation: '',
    role: 'user'
  });
  const [showPassword, setShowPassword] = useState(false);
  const [showConfirmPassword, setShowConfirmPassword] = useState(false);
  const [errors, setErrors] = useState({});
  const [submitting, setSubmitting] = useState(false);
  const [generalError, setGeneralError] = useState('');

  const authHeader = useAuthHeader();
  const authUser = useAuthUser();
  const { addNotification } = useNotification();

  const validateForm = () => {
    const newErrors = {};

    // Name validation
    if (!formData.name.trim()) {
      newErrors.name = 'Name is required';
    } else if (formData.name.length < 2) {
      newErrors.name = 'Name must be at least 2 characters';
    } else if (formData.name.length > 50) {
      newErrors.name = 'Name must be less than 50 characters';
    }

    // Email validation
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!formData.email.trim()) {
      newErrors.email = 'Email is required';
    } else if (!emailRegex.test(formData.email)) {
      newErrors.email = 'Please enter a valid email address';
    }

    // Password validation
    if (!formData.password) {
      newErrors.password = 'Password is required';
    } else if (formData.password.length < 6) {
      newErrors.password = 'Password must be at least 6 characters';
    } else if (formData.password.length > 128) {
      newErrors.password = 'Password must be less than 128 characters';
    }

    // Password confirmation
    if (!formData.password_confirmation) {
      newErrors.password_confirmation = 'Password confirmation is required';
    } else if (formData.password !== formData.password_confirmation) {
      newErrors.password_confirmation = 'Passwords do not match';
    }

    // Role validation (for admin)
    if (isAdminCreating && !formData.role) {
      newErrors.role = 'Role is required';
    }

    setErrors(newErrors);
    return Object.keys(newErrors).length === 0;
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    
    if (!validateForm()) {
      return;
    }

    setSubmitting(true);
    setGeneralError('');

    try {
      const accessToken = authHeader?.replace('Bearer ', '');
      
      const userData = {
        user: {
          name: formData.name.trim(),
          email: formData.email.trim(),
          password: formData.password,
          password_confirmation: formData.password_confirmation
        }
      };

      // 管理者が作成する場合はロールも含める
      if (isAdminCreating && authUser()?.role === 'admin') {
        userData.user.role = formData.role;
      }

      const response = await UserService.createUser(userData, accessToken);
      
      addNotification(
        `User ${formData.name} created successfully`,
        'success'
      );
      
      // フォームをリセット
      setFormData({
        name: '',
        email: '',
        password: '',
        password_confirmation: '',
        role: 'user'
      });
      setErrors({});

      if (onSuccess) {
        onSuccess(response.user);
      }
    } catch (error) {
      setGeneralError(error.message);
      
      // サーバーからのバリデーションエラーを処理
      if (error.errors) {
        setErrors(error.errors);
      }
      
      addNotification('Failed to create user: ' + error.message, 'error');
    } finally {
      setSubmitting(false);
    }
  };

  const handleInputChange = (field) => (e) => {
    const value = e.target.value;
    setFormData(prev => ({ ...prev, [field]: value }));
    
    // リアルタイムでエラーをクリア
    if (errors[field]) {
      setErrors(prev => ({ ...prev, [field]: '' }));
    }
    
    if (generalError) {
      setGeneralError('');
    }
  };

  const getPasswordStrength = (password) => {
    if (!password) return { strength: 0, label: '' };
    
    let strength = 0;
    let label = 'Weak';
    let color = 'error';
    
    if (password.length >= 6) strength += 1;
    if (password.length >= 8) strength += 1;
    if (/[A-Z]/.test(password)) strength += 1;
    if (/[a-z]/.test(password)) strength += 1;
    if (/[0-9]/.test(password)) strength += 1;
    if (/[^A-Za-z0-9]/.test(password)) strength += 1;
    
    if (strength >= 4) {
      label = 'Strong';
      color = 'success';
    } else if (strength >= 3) {
      label = 'Medium';
      color = 'warning';
    }
    
    return { strength: (strength / 6) * 100, label, color };
  };

  const passwordStrength = getPasswordStrength(formData.password);

  return (
    <Card>
      <CardContent>
        <Box sx={{ textAlign: 'center', mb: 3 }}>
          <PersonAdd sx={{ fontSize: 48, color: 'primary.main', mb: 2 }} />
          <Typography variant="h5" component="h2">
            {isAdminCreating ? 'Create New User' : 'Register New Account'}
          </Typography>
          <Typography variant="body2" color="text.secondary">
            {isAdminCreating 
              ? 'Add a new user to the system'
              : 'Create your account to get started'
            }
          </Typography>
        </Box>

        {generalError && (
          <Alert severity="error" sx={{ mb: 3 }}>
            {generalError}
          </Alert>
        )}

        <Box component="form" onSubmit={handleSubmit}>
          <TextField
            fullWidth
            label="Full Name"
            value={formData.name}
            onChange={handleInputChange('name')}
            error={!!errors.name}
            helperText={errors.name}
            margin="normal"
            required
            disabled={submitting}
            InputProps={{
              startAdornment: <Person sx={{ color: 'text.secondary', mr: 1 }} />
            }}
          />

          <TextField
            fullWidth
            label="Email Address"
            type="email"
            value={formData.email}
            onChange={handleInputChange('email')}
            error={!!errors.email}
            helperText={errors.email}
            margin="normal"
            required
            disabled={submitting}
            InputProps={{
              startAdornment: <Email sx={{ color: 'text.secondary', mr: 1 }} />
            }}
          />

          <TextField
            fullWidth
            label="Password"
            type={showPassword ? 'text' : 'password'}
            value={formData.password}
            onChange={handleInputChange('password')}
            error={!!errors.password}
            helperText={errors.password}
            margin="normal"
            required
            disabled={submitting}
            InputProps={{
              startAdornment: <Lock sx={{ color: 'text.secondary', mr: 1 }} />,
              endAdornment: (
                <IconButton
                  onClick={() => setShowPassword(!showPassword)}
                  edge="end"
                >
                  {showPassword ? <VisibilityOff /> : <Visibility />}
                </IconButton>
              )
            }}
          />

          {/* Password Strength Indicator */}
          {formData.password && (
            <Box sx={{ mt: 1, mb: 2 }}>
              <Box display="flex" justifyContent="space-between" alignItems="center">
                <Typography variant="caption" color="text.secondary">
                  Password Strength
                </Typography>
                <Typography 
                  variant="caption" 
                  color={`${passwordStrength.color}.main`}
                  fontWeight="medium"
                >
                  {passwordStrength.label}
                </Typography>
              </Box>
              <Box sx={{ width: '100%', bgcolor: 'grey.300', borderRadius: 1, height: 4, mt: 1 }}>
                <Box
                  sx={{
                    width: `${passwordStrength.strength}%`,
                    bgcolor: `${passwordStrength.color}.main`,
                    height: '100%',
                    borderRadius: 1,
                    transition: 'width 0.3s ease, background-color 0.3s ease'
                  }}
                />
              </Box>
            </Box>
          )}

          <TextField
            fullWidth
            label="Confirm Password"
            type={showConfirmPassword ? 'text' : 'password'}
            value={formData.password_confirmation}
            onChange={handleInputChange('password_confirmation')}
            error={!!errors.password_confirmation}
            helperText={errors.password_confirmation}
            margin="normal"
            required
            disabled={submitting}
            InputProps={{
              startAdornment: <Lock sx={{ color: 'text.secondary', mr: 1 }} />,
              endAdornment: (
                <IconButton
                  onClick={() => setShowConfirmPassword(!showConfirmPassword)}
                  edge="end"
                >
                  {showConfirmPassword ? <VisibilityOff /> : <Visibility />}
                </IconButton>
              )
            }}
          />

          {/* Role Selection (Admin only) */}
          {isAdminCreating && authUser()?.role === 'admin' && (
            <>
              <Divider sx={{ my: 2 }} />
              <FormControl fullWidth margin="normal" error={!!errors.role}>
                <InputLabel>User Role</InputLabel>
                <Select
                  value={formData.role}
                  onChange={handleInputChange('role')}
                  label="User Role"
                  disabled={submitting}
                  startAdornment={
                    <AdminPanelSettings sx={{ color: 'text.secondary', mr: 1, ml: 1 }} />
                  }
                >
                  <MenuItem value="user">Regular User</MenuItem>
                  <MenuItem value="admin">Administrator</MenuItem>
                </Select>
                {errors.role && <FormHelperText>{errors.role}</FormHelperText>}
              </FormControl>
            </>
          )}

          <Box sx={{ mt: 3, display: 'flex', gap: 2 }}>
            <Button
              type="submit"
              fullWidth
              variant="contained"
              disabled={submitting}
              startIcon={submitting ? <CircularProgress size={16} /> : <PersonAdd />}
            >
              {submitting ? 'Creating Account...' : 'Create Account'}
            </Button>
            
            {onCancel && (
              <Button
                fullWidth
                variant="outlined"
                onClick={onCancel}
                disabled={submitting}
              >
                Cancel
              </Button>
            )}
          </Box>

          {!isAdminCreating && (
            <Box sx={{ mt: 3, textAlign: 'center' }}>
              <Typography variant="body2" color="text.secondary">
                Already have an account?{' '}
                <Link href="/login" underline="hover">
                  Sign in here
                </Link>
              </Typography>
            </Box>
          )}
        </Box>
      </CardContent>
    </Card>
  );
};

export default RegisterForm;
