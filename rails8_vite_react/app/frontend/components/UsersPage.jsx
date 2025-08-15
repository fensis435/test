// src/components/UsersPage.jsx
import React, { useState, useEffect } from 'react';
import {
  Container,
  Paper,
  Tabs,
  Tab,
  Box,
  Typography,
  Breadcrumbs,
  Link,
  Dialog,
  DialogContent,
  Fade,
  Chip,
  IconButton,
  Tooltip
} from '@mui/material';
import {
  Person,
  Group,
  PersonAdd,
  Home,
  Close,
  AdminPanelSettings,
  Dashboard
} from '@mui/icons-material';
import { useAuthUser } from 'react-auth-kit';
import { useLocation, useNavigate } from 'react-router-dom';
import UserProfile from './UserProfile';
import UserList from './UserList';
import RegisterForm from './RegisterForm';

function TabPanel({ children, value, index, ...other }) {
  return (
    <div
      role="tabpanel"
      hidden={value !== index}
      id={`users-tabpanel-${index}`}
      aria-labelledby={`users-tab-${index}`}
      {...other}
    >
      {value === index && (
        <Box sx={{ pt: 3 }}>
          {children}
        </Box>
      )}
    </div>
  );
}

const UsersPage = () => {
  const [tabValue, setTabValue] = useState(0);
  const [registerDialogOpen, setRegisterDialogOpen] = useState(false);
  const [editUserDialogOpen, setEditUserDialogOpen] = useState(false);
  const [viewUserDialogOpen, setViewUserDialogOpen] = useState(false);
  const [selectedUser, setSelectedUser] = useState(null);
  
  const authUser = useAuthUser();
  const location = useLocation();
  const navigate = useNavigate();

  const isAdmin = authUser()?.role === 'admin';
  const currentUserId = authUser()?.id;

  // URLパラメータからタブを設定
  useEffect(() => {
    const searchParams = new URLSearchParams(location.search);
    const tab = searchParams.get('tab');
    
    switch (tab) {
      case 'profile':
        setTabValue(0);
        break;
      case 'manage':
        if (isAdmin) setTabValue(1);
        break;
      default:
        setTabValue(0);
    }
  }, [location.search, isAdmin]);

  const handleTabChange = (event, newValue) => {
    setTabValue(newValue);
    
    // URLを更新
    const tab = newValue === 0 ? 'profile' : 'manage';
    navigate(`/users?tab=${tab}`, { replace: true });
  };

  const handleRegisterUser = () => {
    setRegisterDialogOpen(true);
  };

  const handleEditUser = (user) => {
    setSelectedUser(user);
    setEditUserDialogOpen(true);
  };

  const handleViewUser = (user) => {
    setSelectedUser(user);
    setViewUserDialogOpen(true);
  };

  const handleCloseDialogs = () => {
    setRegisterDialogOpen(false);
    setEditUserDialogOpen(false);
    setViewUserDialogOpen(false);
    setSelectedUser(null);
  };

  const handleRegistrationSuccess = (newUser) => {
    setRegisterDialogOpen(false);
    // 管理者の場合は管理タブに切り替え
    if (isAdmin) {
      setTabValue(1);
      navigate('/users?tab=manage', { replace: true });
    }
  };

  const tabs = [
    {
      label: 'My Profile',
      icon: <Person />,
      value: 0,
      available: true
    },
    {
      label: 'Manage Users',
      icon: <Group />,
      value: 1,
      available: isAdmin
    }
  ];

  const availableTabs = tabs.filter(tab => tab.available);

  return (
    <Container maxWidth="lg" sx={{ mt: 4, mb: 4 }}>
      {/* Breadcrumbs */}
      <Breadcrumbs sx={{ mb: 3 }}>
        <Link
          underline="hover"
          color="inherit"
          href="/dashboard"
          sx={{ display: 'flex', alignItems: 'center' }}
        >
          <Dashboard sx={{ mr: 0.5 }} fontSize="inherit" />
          Dashboard
        </Link>
        <Typography
          color="text.primary"
          sx={{ display: 'flex', alignItems: 'center' }}
        >
          <Person sx={{ mr: 0.5 }} fontSize="inherit" />
          Users
        </Typography>
      </Breadcrumbs>

      {/* Page Header */}
      <Box sx={{ mb: 4 }}>
        <Box display="flex" justifyContent="space-between" alignItems="center">
          <Box>
            <Typography variant="h4" component="h1" gutterBottom>
              User Management
            </Typography>
            <Typography variant="body1" color="text.secondary">
              {isAdmin 
                ? 'Manage your profile and system users'
                : 'View and edit your profile information'
              }
            </Typography>
          </Box>
          <Box display="flex" alignItems="center" gap={1}>
            {isAdmin && (
              <Chip
                icon={<AdminPanelSettings />}
                label="Administrator"
                color="secondary"
                size="small"
              />
            )}
            <Chip
              label={`Welcome, ${authUser()?.name}`}
              variant="outlined"
              size="small"
            />
          </Box>
        </Box>
      </Box>

      {/* Main Content */}
      <Paper sx={{ width: '100%' }}>
        <Box sx={{ borderBottom: 1, borderColor: 'divider' }}>
          <Tabs
            value={tabValue}
            onChange={handleTabChange}
            aria-label="user management tabs"
            variant="fullWidth"
          >
            {availableTabs.map((tab) => (
              <Tab
                key={tab.value}
                label={tab.label}
                icon={tab.icon}
                iconPosition="start"
                id={`users-tab-${tab.value}`}
                aria-controls={`users-tabpanel-${tab.value}`}
                sx={{
                  minHeight: 64,
                  textTransform: 'none',
                  fontSize: '1rem',
                  fontWeight: tabValue === tab.value ? 600 : 400
                }}
              />
            ))}
          </Tabs>
        </Box>

        {/* Profile Tab */}
        <TabPanel value={tabValue} index={0}>
          <Box sx={{ p: 3 }}>
            <UserProfile
              userId={currentUserId}
              isCurrentUser={true}
            />
          </Box>
        </TabPanel>

        {/* Manage Users Tab (Admin only) */}
        {isAdmin && (
          <TabPanel value={tabValue} index={1}>
            <Box sx={{ p: 3 }}>
              <UserList
                onEditUser={handleEditUser}
                onRegisterUser={handleRegisterUser}
                onViewUser={handleViewUser}
              />
            </Box>
          </TabPanel>
        )}
      </Paper>

      {/* Register User Dialog */}
      <Dialog
        open={registerDialogOpen}
        onClose={handleCloseDialogs}
        maxWidth="sm"
        fullWidth
        TransitionComponent={Fade}
        PaperProps={{
          sx: { borderRadius: 2 }
        }}
      >
        <Box sx={{ position: 'relative' }}>
          <IconButton
            aria-label="close"
            onClick={handleCloseDialogs}
            sx={{
              position: 'absolute',
              right: 8,
              top: 8,
              zIndex: 1,
              color: 'grey.500'
            }}
          >
            <Close />
          </IconButton>
          <DialogContent sx={{ p: 0 }}>
            <RegisterForm
              onSuccess={handleRegistrationSuccess}
              onCancel={handleCloseDialogs}
              isAdminCreating={isAdmin}
            />
          </DialogContent>
        </Box>
      </Dialog>

      {/* Edit User Dialog */}
      <Dialog
        open={editUserDialogOpen}
        onClose={handleCloseDialogs}
        maxWidth="sm"
        fullWidth
        TransitionComponent={Fade}
        PaperProps={{
          sx: { borderRadius: 2 }
        }}
      >
        <Box sx={{ position: 'relative' }}>
          <IconButton
            aria-label="close"
            onClick={handleCloseDialogs}
            sx={{
              position: 'absolute',
              right: 8,
              top: 8,
              zIndex: 1,
              color: 'grey.500'
            }}
          >
            <Close />
          </IconButton>
          <DialogContent sx={{ p: 3 }}>
            {selectedUser && (
              <>
                <Typography variant="h6" gutterBottom>
                  Edit User: {selectedUser.name}
                </Typography>
                <UserProfile
                  userId={selectedUser.id}
                  isCurrentUser={selectedUser.id === currentUserId}
                />
              </>
            )}
          </DialogContent>
        </Box>
      </Dialog>

      {/* View User Dialog */}
      <Dialog
        open={viewUserDialogOpen}
        onClose={handleCloseDialogs}
        maxWidth="sm"
        fullWidth
        TransitionComponent={Fade}
        PaperProps={{
          sx: { borderRadius: 2 }
        }}
      >
        <Box sx={{ position: 'relative' }}>
          <IconButton
            aria-label="close"
            onClick={handleCloseDialogs}
            sx={{
              position: 'absolute',
              right: 8,
              top: 8,
              zIndex: 1,
              color: 'grey.500'
            }}
          >
            <Close />
          </IconButton>
          <DialogContent sx={{ p: 3 }}>
            {selectedUser && (
              <>
                <Typography variant="h6" gutterBottom>
                  User Profile: {selectedUser.name}
                </Typography>
                <UserProfile
                  userId={selectedUser.id}
                  isCurrentUser={false}
                />
              </>
            )}
          </DialogContent>
        </Box>
      </Dialog>
    </Container>
  );
};

export default UsersPage;
