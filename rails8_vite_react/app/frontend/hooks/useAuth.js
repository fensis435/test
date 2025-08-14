import { useSignOut, useAuthUser, useAuthHeader } from 'react-auth-kit';
import { useNavigate } from 'react-router-dom';
import { useMemo, useState, useEffect } from 'react';
import AuthService from '../auth/authService';
import UserService from '../services/userService';
import { useNotification } from '../context/NotificationContext';

export const useAuth = () => {
  const signOut = useSignOut();
  const getAuthUser = useAuthUser();
  const getAuthHeader = useAuthHeader();
  const navigate = useNavigate();
  const { addNotification } = useNotification();
  const [currentUser, setCurrentUser] = useState(getAuthUser());
  const authUser = useMemo(() => getAuthUser(), [getAuthUser]);

  useEffect(() => {
    if (authUser && !currentUser?.active_sessions_count) {
      fetchCurrentUser();
    }
  }, [authUser]);

  const fetchCurrentUser = async () => {
    try {
      const authHeader = getAuthHeader();
      const accessToken = authHeader?.replace('Bearer ', '');
      if (accessToken) {
        const response = await UserService.getCurrentUser(accessToken);
        setCurrentUser(response.user);
      }
    } catch (error) {
      console.error('Failed to fetch current user:', error);
    }
  };

  const logout = async () => {
    try {
      const authHeader = getAuthHeader();
      const accessToken = authHeader?.replace('Bearer ', '');
      const refreshToken = localStorage.getItem('refreshToken');

      if (accessToken) {
        await AuthService.logout(accessToken, refreshToken);
      }

      localStorage.removeItem('refreshToken');
      signOut();

      addNotification('Successfully logged out', 'success');
      navigate('/login');

      return true;
    } catch (error) {
      console.error('Logout error:', error);
      localStorage.removeItem('refreshToken');
      signOut();
      addNotification('Logged out (with errors)', 'warning');
      navigate('/login');
      return false;
    }
  };

  const logoutAll = async () => {
    try {
      const authHeader = getAuthHeader();
      const accessToken = authHeader?.replace('Bearer ', '');

      if (accessToken) {
        await AuthService.logoutAll(accessToken);
      }

      localStorage.removeItem('refreshToken');
      signOut();

      addNotification('Successfully logged out from all devices', 'success');
      navigate('/login');

      return true;
    } catch (error) {
      console.error('Logout all error:', error);
      localStorage.removeItem('refreshToken');
      signOut();
      addNotification('Logged out from all devices (with errors)', 'warning');
      navigate('/login');
      return false;
    }
  };

  return {
    user: currentUser || authUser,
    logout,
    logoutAll,
    isAuthenticated: !!authUser,
    refreshUser: fetchCurrentUser
  };
};
