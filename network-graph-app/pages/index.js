// src/pages/index.js
import dynamic from "next/dynamic";
import { styled, alpha } from '@mui/material/styles';
import { useState, useCallback } from 'react';
import Box from '@mui/material/Box';
import CssBaseline from '@mui/material/CssBaseline';
import AppBar from '@mui/material/AppBar';
import Toolbar from '@mui/material/Toolbar';
import Typography from '@mui/material/Typography';
import Drawer from '@mui/material/Drawer';
import { IconButton, List, ListItem, ListItemText } from "@mui/material";
import MenuIcon from "@mui/icons-material/Menu";
import InputBase from '@mui/material/InputBase';
import SearchIcon from '@mui/icons-material/Search';
const NetworkGraph = dynamic(() => import('../components/Graph/NetworkGraph'), {
    ssr: false,
});
import EditDrawer from '../components/Drawer/EditDrawer';

const DRAWER_WIDTH = 320;

const Search = styled('div')(({ theme }) => ({
  position: 'relative',
  borderRadius: theme.shape.borderRadius,
  backgroundColor: alpha(theme.palette.common.white, 0.15),
  '&:hover': {
    backgroundColor: alpha(theme.palette.common.white, 0.25),
  },
  marginLeft: 0,
  width: '100%',
  [theme.breakpoints.up('sm')]: {
    marginLeft: theme.spacing(1),
    width: 'auto',
  },
}));

const SearchIconWrapper = styled('div')(({ theme }) => ({
  padding: theme.spacing(0, 2),
  height: '100%',
  position: 'absolute',
  pointerEvents: 'none',
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'center',
}));

const StyledInputBase = styled(InputBase)(({ theme }) => ({
  color: 'inherit',
  width: '100%',
  '& .MuiInputBase-input': {
    padding: theme.spacing(1, 1, 1, 0),
    // vertical padding + font size from searchIcon
    paddingLeft: `calc(1em + ${theme.spacing(4)})`,
    transition: theme.transitions.create('width'),
    [theme.breakpoints.up('sm')]: {
      width: '12ch',
      '&:focus': {
        width: '20ch',
      },
    },
  },
}));

const Layout = () => {
  const [searchPattern, setSearchPattern] = useState(null);
  
  return (
    <Box sx={{ display: 'flex', flexDirection: 'column', height: '100vh' }}>
      <SearchAppBar onSearch={setSearchPattern} />
      <Box sx={{ flexGrow: 1 }}>
        <NetworkGraph searchPattern={searchPattern} />
      </Box>
    </Box>
  );
};

export default function Home() {
  const [selectedItem, setSelectedItem] = useState(null);
  const [editMode, setEditMode] = useState(false);
  const [isDrawerOpen, setDrawerOpen] = useState(false);
  const [searchTerm, setSearchTerm] = useState('');

  const toggleDrawer = () => {
    setDrawerOpen((prevState) => !prevState);
  };

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

  const handleMouseEnter = () => {
    setDrawerOpen(true);
  };

  const handleMouseLeave = () => {
    setDrawerOpen(false);
  };

  // 検索フィルタ適用
  const applySearchFilter = useCallback(() => {
    if (!sigmaInstance.current) return;

    const pattern = searchTerm ? new RegExp(searchTerm, 'i') : null;

    sigmaInstance.current.setSetting('nodeReducer', node => ({
      ...node,
      hidden: pattern ? !pattern.test(node.label) : false,
      color: pattern && !pattern.test(node.label) ? '#eee' : node.color
    }));

    sigmaInstance.current.setSetting('edgeReducer', edge => ({
      ...edge,
      hidden: pattern
        ? !pattern.test(graphData.nodes[edge.source].label) ||
          !pattern.test(graphData.nodes[edge.target].label)
        : false
    }));

    sigmaInstance.current.refresh();
  }, [searchTerm, graphData]);

  const handleSearch = (e) => {
    try {
      const pattern = new RegExp(e.target.value, 'i');
      onSearch(pattern);
    } catch {
      onSearch(null);
    }
  };

  return (
    <Box sx={{ display: 'flex' }}>
      <CssBaseline />
      <AppBar position="fixed" sx={{ zIndex: (theme) => theme.zIndex.drawer + 1 }} >
        <Toolbar>
          <Box sx={{ display: 'flex', alignItems: 'center' }}>
            <IconButton
             edge="start"
             color="inherit"
             aria-label="menu"
             onClick={toggleDrawer}
            >
              <MenuIcon />
            </IconButton>
            <Typography variant="h6" noWrap component="div">
              ネットワークグラフ
            </Typography>
          </Box>
          <Box sx={{ flexGrow: 1 }} />
          <Search>
            <SearchIconWrapper>
              <SearchIcon />
            </SearchIconWrapper>
            <StyledInputBase
              placeholder="Search…"
              onChange={handleSearch}
              inputProps={{ 'aria-label': 'search' }}
            />
          </Search>
        </Toolbar>
      </AppBar>
      <div
        style={{
          width: "10px",
          height: "100vh",
          position: "fixed",
          left: 0,
          top: 0,
          backgroundColor: "transparent",
          cursor: "pointer",
        }}
        onMouseEnter={handleMouseEnter}
      />
      <Drawer
        anchor="left"
        open={isDrawerOpen}
        onClose={toggleDrawer}
        variant="temporary"
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
