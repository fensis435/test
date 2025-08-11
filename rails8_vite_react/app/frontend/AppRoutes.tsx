import { FC } from "react";
import { Routes, Route } from "react-router-dom";

import { Layout } from "./layouts/Layout";

import { TopPage } from "./pages/TopPage";
import { ImageListPage } from "./pages/ImageListPage";
import { ImageNewPage } from "./pages/ImageNewPage";
import { SettingPlanPage } from "./pages/SettingPlanPage";
import { SettingEmailPage } from "./pages/SettingEmailPage";
import { SettingPasswordPage } from "./pages/SettingPasswordPage";
import { SettingNotificationDesktopPage } from "./pages/SettingNotificationDesktopPage";
import { SettingNotificationEmailPage } from "./pages/SettingNotificationEmailPage";

export const AppRoutes: FC = () => {
  return (
    <Routes>
      <Route element={<Layout />}>
        <Route path="/" element={<TopPage />} />
        <Route path="/images" element={<ImageListPage />} />
        <Route path="/images/new" element={<ImageNewPage />} />
        <Route path="/settings/plan" element={<SettingPlanPage />} />
        <Route path="/settings/email" element={<SettingEmailPage />} />
        <Route path="/settings/password" element={<SettingPasswordPage />} />
        <Route
          path="/settings/notification-desktop"
          element={<SettingNotificationDesktopPage />}
        />
        <Route
          path="/settings/notification-email"
          element={<SettingNotificationEmailPage />}
        />
      </Route>
    </Routes>
  );
};
