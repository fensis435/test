// src/App.tsx
import React from 'react';
import { BrowserRouter, Routes, Route, Link } from 'react-router-dom';
import { AppBar, Toolbar, Button, Box, Container } from '@mui/material';
import DataGridView from './components/DataGridView';
import ProfilePage from './pages/ProfilePage';

export default function App() {
  return (
    <BrowserRouter>
      {/* グローバルナビゲーション */}
      <AppBar position="static">
        <Toolbar>
          <Button color="inherit" component={Link} to="/">
            Data Grid
          </Button>
          <Button color="inherit" component={Link} to="/profile">
            Profile Page
          </Button>
        </Toolbar>
      </AppBar>

      {/* ルートごとのコンテンツ */}
      <Container sx={{ mt: 2 }}>
        <Routes>
          <Route path="/" element={<DataGridView />} />
          <Route path="/profile" element={<ProfilePage />} />
        </Routes>
      </Container>
    </BrowserRouter>
  );
}
