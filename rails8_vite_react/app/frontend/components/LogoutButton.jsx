import React, { useState } from 'react';
import {
  Button,
  Menu,
  MenuItem,
  ListItemIcon,
  ListItemText,
  CircularProgress
} from '@mui/material';
import {
  ExitToApp,
  PowerSettingsNew,
  KeyboardArrowDown
} from '@mui/icons-material';
import { useAuth } from '../hooks/useAuth';

const LogoutButton = ({ showLogoutAll = false, variant = 'contained' }) => {
  const [anchorEl, setAnchorEl] = useState(null);
  const [loading, setLoading] = useState(false);
  const { logout, logoutAll } = useAuth();

  const handleClick = (event) => {
    if (showLogoutAll) {
      setAnchorEl(event.currentTarget);
    } else {
      handleLogout();
    }
  };

  const handleClose = () => {
    setAnchorEl(null);
  };

  const handleLogout = async () => {
    setLoading(true);
    await logout();
    setLoading(false);
    handleClose();
  };

  const handleLogoutAll = async () => {
    setLoading(true);
    await logoutAll();
    setLoading(false);
    handleClose();
  };

  if (!showLogoutAll) {
    return (
      <Button
        onClick={handleLogout}
        variant={variant}
        color='error'
        disabled={loading}
        startIcon={loading ? <CircularProgress size={16} /> : <ExitToApp />}
      >
        {loading ? 'Logging out...' : 'Logout'}
      </Button>
    );
  }

  return (
    <>
      <Button
        onClick={handleClick}
        variant={variant}
        color='error'
        endIcon={<KeyboardArrowDown />}
        disabled={loading}
        startIcon={loading && <CircularProgress size={16} />}
      >
        {loading ? 'Processing...' : 'Logout'}
      </Button>
      <Menu
        anchorEl={anchorEl}
        open={Boolean(anchorEl)}
        onClose={handleClose}
        anchorOrigin={{
          vertical: 'bottom',
          horizontal: 'right'
        }}
        transformOrigin={{
          vertical: 'top',
          horizontal: 'right'
        }}
      >
        <MenuItem onClick={handleLogout}>
          <ListItemIcon>
            <ExitToApp fontSize='small' />
          </ListItemIcon>
          <ListItemText>Logout</ListItemText>
        </MenuItem>
        <MenuItem onClick={handleLogoutAll}>
          <ListItemIcon>
            <PowerSettingsNew fontSize='small' />
          </ListItemIcon>
          <ListItemText>Logout All Devices</ListItemText>
        </MenuItem>
      </Menu>
    </>
  );
};

export default LogoutButton;
