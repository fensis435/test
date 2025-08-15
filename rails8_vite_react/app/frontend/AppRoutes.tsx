import { FC } from 'react';
import { Routes, Route, Navigate } from 'react-router-dom';

import { Layout } from './layouts/Layout';

import { TopPage } from './pages/TopPage';
import { ImageListPage } from './pages/ImageListPage';
import { ImageNewPage } from './pages/ImageNewPage';
import { SettingPlanPage } from './pages/SettingPlanPage';
import { SettingEmailPage } from './pages/SettingEmailPage';
import { SettingPasswordPage } from './pages/SettingPasswordPage';
import { SettingNotificationDesktopPage } from './pages/SettingNotificationDesktopPage';
import { SettingNotificationEmailPage } from './pages/SettingNotificationEmailPage';
import { RequireAuth, useAuthUser, useIsAuthenticated } from 'react-auth-kit';
import { useNavigate } from 'react-router-dom';

import Login from './pages/Login';
import SignUp from './pages/SignUp';
import Dashboard from './pages/Dashboard';
import UsersPage from './components/UsersPage';
import NotFoundPage from './components/NotFoundPage';

// Protected Route wrapper for admin-only pages
const AdminRoute = ({ children }) => {
  const auth = useAuthUser();
  const isAuthenticated = useIsAuthenticated();
  const user = auth();

  console.log('authState', user);

  if (!isAuthenticated() || user?.role !== 'admin') {
    return <Navigate to='/dashboard' replace />;
  }

  return children;
};
//const AdminRoute = ({ children }) => {
//  return (
//    <RequireAuth loginPath='/login'>
//      {({ authState }) => {
//        console.log("authState", authState);
//        if (authState?.role !== 'admin') {
//          return <Navigate to='/dashboard' replace />;
//        }
//        return children;
//      }}
//    </RequireAuth>
//  );
//};

export const AppRoutes: FC = () => {
  const navigate = useNavigate();

  return (
    <Routes>
      <Route path='/login' element={<Login />} />
      <Route path='/signup' element={<SignUp />} />
      <Route element={<Layout />}>
        {/* Protected Routes */}
        <Route
          path='/*'
          element={
            <RequireAuth loginPath='/login'>
              <Routes>
                <Route path='/' element={<Dashboard />} />
                {/* Dashboard */}
                <Route path='/dashboard' element={<Dashboard />} />
                {/* Users Management */}
                <Route path='/users' element={<UsersPage />} />
                {/* Profile shortcut */}
                <Route
                  path='/profile'
                  element={<Navigate to='/users?tab=profile' replace />}
                />
                {/* Admin-only routes */}
                <Route
                  path='/admin/*'
                  element={
                    <AdminRoute>
                      <Routes>
                        <Route
                          path='/users'
                          element={<Navigate to='/users?tab=manage' replace />}
                        />
                        <Route
                          path='/*'
                          element={<Navigate to='/dashboard' replace />}
                        />
                      </Routes>
                    </AdminRoute>
                  }
                />
                {/* example page */}
                <Route path='/images' element={<ImageListPage />} />
                <Route path='/images/new' element={<ImageNewPage />} />
                <Route path='/settings/plan' element={<SettingPlanPage />} />
                <Route path='/settings/email' element={<SettingEmailPage />} />
                <Route
                  path='/settings/password'
                  element={<SettingPasswordPage />}
                />
                <Route
                  path='/settings/notification-desktop'
                  element={<SettingNotificationDesktopPage />}
                />
                <Route
                  path='/settings/notification-email'
                  element={<SettingNotificationEmailPage />}
                />
                {/* Default redirect */}
                <Route
                  path='/'
                  element={<Navigate to='/dashboard' replace />}
                />
                {/* 404 Page */}
                <Route path='*' element={<NotFoundPage />} />
              </Routes>
            </RequireAuth>
          }
        />
      </Route>
    </Routes>
  );
};
