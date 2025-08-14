import { FC } from 'react';
import { Routes, Route } from 'react-router-dom';

import { Layout } from './layouts/Layout';

import { TopPage } from './pages/TopPage';
import { ImageListPage } from './pages/ImageListPage';
import { ImageNewPage } from './pages/ImageNewPage';
import { SettingPlanPage } from './pages/SettingPlanPage';
import { SettingEmailPage } from './pages/SettingEmailPage';
import { SettingPasswordPage } from './pages/SettingPasswordPage';
import { SettingNotificationDesktopPage } from './pages/SettingNotificationDesktopPage';
import { SettingNotificationEmailPage } from './pages/SettingNotificationEmailPage';
import { RequireAuth } from 'react-auth-kit';
import Login from './pages/Login';
import SignUp from './pages/SignUp';

export const AppRoutes: FC = () => {
  return (
    <Routes>
      <Route path='/login' element={<Login />} />
      <Route path='/signup' element={<SignUp />} />
      <Route element={<Layout />}>
        {/* 認証が必要なルート */}
        <Route
          path='/'
          element={
            <RequireAuth loginPath='/login'>
              <TopPage />
            </RequireAuth>
          }
        />
        <Route
          path='/images'
          element={
            <RequireAuth loginPath='/login'>
              <ImageListPage />
            </RequireAuth>
          }
        />
        <Route
          path='/images/new'
          element={
            <RequireAuth loginPath='/login'>
              <ImageNewPage />
            </RequireAuth>
          }
        />
        <Route
          path='/settings/plan'
          element={
            <RequireAuth loginPath='/login'>
              <SettingPlanPage />
            </RequireAuth>
          }
        />
        <Route
          path='/settings/email'
          element={
            <RequireAuth loginPath='/login'>
              <SettingEmailPage />
            </RequireAuth>
          }
        />
        <Route
          path='/settings/password'
          element={
            <RequireAuth loginPath='/login'>
              <SettingPasswordPage />
            </RequireAuth>
          }
        />
        <Route
          path='/settings/notification-desktop'
          element={
            <RequireAuth loginPath='/login'>
              <SettingNotificationDesktopPage />
            </RequireAuth>
          }
        />
        <Route
          path='/settings/notification-email'
          element={
            <RequireAuth loginPath='/login'>
              <SettingNotificationEmailPage />
            </RequireAuth>
          }
        />
      </Route>
    </Routes>
  );
};
