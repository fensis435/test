import React, { useState, useEffect } from 'react';
import {
  Card,
  CardContent,
  Typography,
  Grid,
  Avatar,
  Chip,
  Box,
  Button,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  TextField,
  CircularProgress,
  Alert,
  Divider,
  IconButton,
  Tooltip
} from '@mui/material';
import {
  Person,
  Email,
  Edit,
  VpnKey,
  Visibility,
  VisibilityOff,
  Schedule,
  Update,
  Badge,
  Security
} from '@mui/icons-material';
import { useAuthHeader } from 'react-auth-kit';
import { useNotification } from '../context/NotificationContext';
import UserService from '../services/userService';

const UserProfile = ({ userId, isCurrentUser = false }) => {
  const [user, setUser] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [editDialogOpen, setEditDialogOpen] = useState(false);
  const [passwordDialogOpen, setPasswordDialogOpen] = useState(false);
  const [editForm, setEditForm] = useState({ name: '', email: '' });
  const [passwordForm, setPasswordForm] = useState({
    current_password: '',
    new_password: '',
    password_confirmation: ''
  });
  const [submitting, setSubmitting] = useState(false);
  const [showPasswords, setShowPasswords] = useState({
    current: false,
    new: false,
    confirmation: false
  });
  const [formErrors, setFormErrors] = useState({});

  const authHeader = useAuthHeader();
  const { addNotification } = useNotification();

  useEffect(() => {
    fetchUser();
  }, [userId]);

  const fetchUser = async () => {
    try {
      setError('');
      setLoading(true);
      const accessToken = authHeader?.replace('Bearer ', '');

      const response = isCurrentUser
        ? await UserService.getCurrentUser(accessToken)
        : await UserService.getUser(userId, accessToken);

      setUser(response.user);
      setEditForm({ name: response.user.name, email: response.user.email });
    } catch (error) {
      setError(error.message);
      addNotification(error.message, 'error');
    } finally {
      setLoading(false);
    }
  };

  const validateEditForm = () => {
    const errors = {};

    if (!editForm.name.trim()) {
      errors.name = 'Name is required';
    } else if (editForm.name.length < 2) {
      errors.name = 'Name must be at least 2 characters';
    }

    if (!editForm.email.trim()) {
      errors.email = 'Email is required';
    } else if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(editForm.email)) {
      errors.email = 'Please enter a valid email address';
    }

    setFormErrors(errors);
    return Object.keys(errors).length === 0;
  };

  const validatePasswordForm = () => {
    const errors = {};

    if (!passwordForm.current_password) {
      errors.current_password = 'Current password is required';
    }

    if (!passwordForm.new_password) {
      errors.new_password = 'New password is required';
    } else if (passwordForm.new_password.length < 6) {
      errors.new_password = 'New password must be at least 6 characters';
    }

    if (!passwordForm.password_confirmation) {
      errors.password_confirmation = 'Password confirmation is required';
    } else if (
      passwordForm.new_password !== passwordForm.password_confirmation
    ) {
      errors.password_confirmation = 'Password confirmation does not match';
    }

    setFormErrors(errors);
    return Object.keys(errors).length === 0;
  };

  const handleEditSubmit = async () => {
    if (!validateEditForm()) return;

    try {
      setSubmitting(true);
      const accessToken = authHeader?.replace('Bearer ', '');

      await UserService.updateUser(user.id, { user: editForm }, accessToken);

      addNotification('Profile updated successfully', 'success');
      setEditDialogOpen(false);
      setFormErrors({});
      fetchUser();
    } catch (error) {
      addNotification(error.message, 'error');
    } finally {
      setSubmitting(false);
    }
  };

  const handlePasswordSubmit = async () => {
    if (!validatePasswordForm()) return;

    try {
      setSubmitting(true);
      const accessToken = authHeader?.replace('Bearer ', '');

      await UserService.changePassword(user.id, passwordForm, accessToken);

      addNotification('Password changed successfully', 'success');
      setPasswordDialogOpen(false);
      setPasswordForm({
        current_password: '',
        new_password: '',
        password_confirmation: ''
      });
      setFormErrors({});
    } catch (error) {
      addNotification(error.message, 'error');
    } finally {
      setSubmitting(false);
    }
  };

  const handleCloseEditDialog = () => {
    setEditDialogOpen(false);
    setEditForm({ name: user?.name || '', email: user?.email || '' });
    setFormErrors({});
  };

  const handleClosePasswordDialog = () => {
    setPasswordDialogOpen(false);
    setPasswordForm({
      current_password: '',
      new_password: '',
      password_confirmation: ''
    });
    setFormErrors({});
    setShowPasswords({ current: false, new: false, confirmation: false });
  };

  const togglePasswordVisibility = (field) => {
    setShowPasswords((prev) => ({ ...prev, [field]: !prev[field] }));
  };

  const formatDate = (dateString) => {
    return new Date(dateString).toLocaleString('ja-JP', {
      year: 'numeric',
      month: 'long',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit'
    });
  };

  if (loading) {
    return (
      <Card>
        <CardContent>
          <Box display='flex' justifyContent='center' py={4}>
            <CircularProgress />
          </Box>
        </CardContent>
      </Card>
    );
  }

  if (error) {
    return (
      <Card>
        <CardContent>
          <Alert severity='error'>{error}</Alert>
        </CardContent>
      </Card>
    );
  }

  return (
    <>
      <Card>
        <CardContent>
          <Box
            display='flex'
            justifyContent='space-between'
            alignItems='flex-start'
            mb={3}
          >
            <Box display='flex' alignItems='center'>
              <Avatar
                sx={{ bgcolor: 'primary.main', mr: 2, width: 56, height: 56 }}
              >
                <Person />
              </Avatar>
              <Box>
                <Typography variant='h5' component='h2'>
                  {user.name}
                </Typography>
                <Typography variant='body2' color='text.secondary'>
                  {isCurrentUser ? 'Your Profile' : 'User Profile'}
                </Typography>
                {user.role && (
                  <Chip
                    label={user.role}
                    size='small'
                    color={user.role === 'admin' ? 'secondary' : 'default'}
                    sx={{ mt: 1 }}
                  />
                )}
              </Box>
            </Box>
            {isCurrentUser && (
              <Box
                display='flex'
                gap={1}
                flexDirection={{ xs: 'column', sm: 'row' }}
              >
                <Button
                  variant='outlined'
                  startIcon={<Edit />}
                  onClick={() => setEditDialogOpen(true)}
                  size='small'
                >
                  Edit Profile
                </Button>
                <Button
                  variant='outlined'
                  startIcon={<VpnKey />}
                  onClick={() => setPasswordDialogOpen(true)}
                  size='small'
                >
                  Change Password
                </Button>
              </Box>
            )}
          </Box>

          <Divider sx={{ mb: 3 }} />

          <Grid container spacing={3}>
            <Grid item xs={12} sm={6}>
              <Box display='flex' alignItems='center' gap={2} mb={2}>
                <Person color='action' />
                <Box>
                  <Typography variant='body2' color='text.secondary'>
                    Name
                  </Typography>
                  <Typography variant='body1'>{user.name}</Typography>
                </Box>
              </Box>
            </Grid>

            <Grid item xs={12} sm={6}>
              <Box display='flex' alignItems='center' gap={2} mb={2}>
                <Email color='action' />
                <Box>
                  <Typography variant='body2' color='text.secondary'>
                    Email
                  </Typography>
                  <Typography variant='body1'>{user.email}</Typography>
                </Box>
              </Box>
            </Grid>

            <Grid item xs={12} sm={6}>
              <Box display='flex' alignItems='center' gap={2} mb={2}>
                <Badge color='action' />
                <Box>
                  <Typography variant='body2' color='text.secondary'>
                    User ID
                  </Typography>
                  <Chip label={user.id} size='small' variant='outlined' />
                </Box>
              </Box>
            </Grid>

            {user.active_sessions_count !== undefined && (
              <Grid item xs={12} sm={6}>
                <Box display='flex' alignItems='center' gap={2} mb={2}>
                  <Security color='action' />
                  <Box>
                    <Typography variant='body2' color='text.secondary'>
                      Active Sessions
                    </Typography>
                    <Chip
                      label={user.active_sessions_count}
                      size='small'
                      color='primary'
                      variant='outlined'
                    />
                  </Box>
                </Box>
              </Grid>
            )}

            <Grid item xs={12} sm={6}>
              <Box display='flex' alignItems='center' gap={2}>
                <Schedule color='action' />
                <Box>
                  <Typography variant='body2' color='text.secondary'>
                    Member Since
                  </Typography>
                  <Typography variant='body1'>
                    {formatDate(user.created_at)}
                  </Typography>
                </Box>
              </Box>
            </Grid>

            <Grid item xs={12} sm={6}>
              <Box display='flex' alignItems='center' gap={2}>
                <Update color='action' />
                <Box>
                  <Typography variant='body2' color='text.secondary'>
                    Last Updated
                  </Typography>
                  <Typography variant='body1'>
                    {formatDate(user.updated_at)}
                  </Typography>
                </Box>
              </Box>
            </Grid>
          </Grid>
        </CardContent>
      </Card>

      {/* Edit Profile Dialog */}
      <Dialog
        open={editDialogOpen}
        onClose={handleCloseEditDialog}
        maxWidth='sm'
        fullWidth
      >
        <DialogTitle>Edit Profile</DialogTitle>
        <DialogContent>
          <Box sx={{ mt: 1 }}>
            <TextField
              autoFocus
              margin='normal'
              label='Name'
              fullWidth
              variant='outlined'
              value={editForm.name}
              onChange={(e) =>
                setEditForm({ ...editForm, name: e.target.value })
              }
              disabled={submitting}
              error={!!formErrors.name}
              helperText={formErrors.name}
              required
            />
            <TextField
              margin='normal'
              label='Email'
              type='email'
              fullWidth
              variant='outlined'
              value={editForm.email}
              onChange={(e) =>
                setEditForm({ ...editForm, email: e.target.value })
              }
              disabled={submitting}
              error={!!formErrors.email}
              helperText={formErrors.email}
              required
            />
          </Box>
        </DialogContent>
        <DialogActions>
          <Button onClick={handleCloseEditDialog} disabled={submitting}>
            Cancel
          </Button>
          <Button
            onClick={handleEditSubmit}
            variant='contained'
            disabled={submitting}
            startIcon={submitting && <CircularProgress size={16} />}
          >
            {submitting ? 'Saving...' : 'Save Changes'}
          </Button>
        </DialogActions>
      </Dialog>

      {/* Change Password Dialog */}
      <Dialog
        open={passwordDialogOpen}
        onClose={handleClosePasswordDialog}
        maxWidth='sm'
        fullWidth
      >
        <DialogTitle>Change Password</DialogTitle>
        <DialogContent>
          <Box sx={{ mt: 1 }}>
            <TextField
              autoFocus
              margin='normal'
              label='Current Password'
              type={showPasswords.current ? 'text' : 'password'}
              fullWidth
              variant='outlined'
              value={passwordForm.current_password}
              onChange={(e) =>
                setPasswordForm({
                  ...passwordForm,
                  current_password: e.target.value
                })
              }
              disabled={submitting}
              error={!!formErrors.current_password}
              helperText={formErrors.current_password}
              required
              InputProps={{
                endAdornment: (
                  <IconButton
                    aria-label='toggle password visibility'
                    onClick={() => togglePasswordVisibility('current')}
                    edge='end'
                  >
                    {showPasswords.current ? <VisibilityOff /> : <Visibility />}
                  </IconButton>
                )
              }}
            />
            <TextField
              margin='normal'
              label='New Password'
              type={showPasswords.new ? 'text' : 'password'}
              fullWidth
              variant='outlined'
              value={passwordForm.new_password}
              onChange={(e) =>
                setPasswordForm({
                  ...passwordForm,
                  new_password: e.target.value
                })
              }
              disabled={submitting}
              error={!!formErrors.new_password}
              helperText={
                formErrors.new_password || 'Must be at least 6 characters'
              }
              required
              InputProps={{
                endAdornment: (
                  <IconButton
                    aria-label='toggle password visibility'
                    onClick={() => togglePasswordVisibility('new')}
                    edge='end'
                  >
                    {showPasswords.new ? <VisibilityOff /> : <Visibility />}
                  </IconButton>
                )
              }}
            />
            <TextField
              margin='normal'
              label='Confirm New Password'
              type={showPasswords.confirmation ? 'text' : 'password'}
              fullWidth
              variant='outlined'
              value={passwordForm.password_confirmation}
              onChange={(e) =>
                setPasswordForm({
                  ...passwordForm,
                  password_confirmation: e.target.value
                })
              }
              disabled={submitting}
              error={!!formErrors.password_confirmation}
              helperText={formErrors.password_confirmation}
              required
              InputProps={{
                endAdornment: (
                  <IconButton
                    aria-label='toggle password visibility'
                    onClick={() => togglePasswordVisibility('confirmation')}
                    edge='end'
                  >
                    {showPasswords.confirmation ? (
                      <VisibilityOff />
                    ) : (
                      <Visibility />
                    )}
                  </IconButton>
                )
              }}
            />
          </Box>
        </DialogContent>
        <DialogActions>
          <Button onClick={handleClosePasswordDialog} disabled={submitting}>
            Cancel
          </Button>
          <Button
            onClick={handlePasswordSubmit}
            variant='contained'
            disabled={submitting}
            startIcon={submitting && <CircularProgress size={16} />}
          >
            {submitting ? 'Changing...' : 'Change Password'}
          </Button>
        </DialogActions>
      </Dialog>
    </>
  );
};

export default UserProfile;
