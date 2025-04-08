// src/pages/index.js
import dynamic from "next/dynamic";
import { useState, useCallback } from 'react';
import Box from '@mui/material/Box';
import CssBaseline from '@mui/material/CssBaseline';
import AppBar from '@mui/material/AppBar';
import Toolbar from '@mui/material/Toolbar';
import Typography from '@mui/material/Typography';
import Drawer from '@mui/material/Drawer';
import { IconButton, List, ListItem, ListItemText } from "@mui/material";
const NetworkGraph = dynamic(() => import('../components/Graph/NetworkGraph'), {
    ssr: false,
});
import EditDrawer from '../components/Drawer/EditDrawer';

const DRAWER_WIDTH = 320;

export default function Home() {
  const [selectedItem, setSelectedItem] = useState(null);
  const [editMode, setEditMode] = useState(false);
  const [isDrawerOpen, setDrawerOpen] = useState(false);

  const handleNodeSelect = useCallback((node) => {
    setSelectedItem({ type: 'node', data: node });
    setEditMode(true);
  }, []);

  const handleEdgeSelect = useCallback((edge) => {
    setSelectedItem({ type: 'edge', data: edge });
    setEditMode(true);
  }, []);

  const handleCloseEdit = useCallback(() => {
    setEditMode(false);
    setSelectedItem(null);
  }, []);

  return (
    <Box sx={{ display: 'flex' }}>
      <CssBaseline />
      <AppBar position="fixed" sx={{ zIndex: (theme) => theme.zIndex.drawer + 1 }} >
        <Toolbar>
          <IconButton
           edge="start"
           color="inherit"
           aria-label="menu"
           onClick={toggleDrawer(true)}
          >
           <MenuIcon />
          </IconButton>
          <Typography variant="h6" noWrap component="div">
            ネットワークグラフ
          </Typography>
        </Toolbar>
      </AppBar>
      <Drawer
        anchor="left"
        open={isDrawerOpen}
        onClose={toggleDrawer(false)}>
        variant="permanent"
        sx={{
          width: DRAWER_WIDTH,
          flexShrink: 0,
          [`& .MuiDrawer-paper`]: { width: DRAWER_WIDTH, boxSizing: 'border-box' },
        }}>
        <Toolbar />
        <Box sx={{ overflow: 'auto', p: 2 }}>
          <Typography variant="h6" sx={{ mb: 2 }}>
            ネットワーク管理
          </Typography>
          {/* ここにナビゲーションメニューなどを追加 */}
        </Box>
      </Drawer>
      <Box component="main" sx={{ flexGrow: 1, p: 3 }}>
        <Toolbar />
        <Box sx={{ display: 'flex', height: 'calc(100vh - 100px)' }}>
          <NetworkGraph 
            onNodeSelect={handleNodeSelect} 
            onEdgeSelect={handleEdgeSelect} 
          />
        </Box>
      </Box>
      <EditDrawer 
        open={editMode} 
        selectedItem={selectedItem} 
        onClose={handleCloseEdit} 
      />
    </Box>
  );
}
