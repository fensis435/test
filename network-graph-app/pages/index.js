import dynamic from "next/dynamic";
import { useState, useCallback, useRef, useEffect } from 'react';
import Box from '@mui/material/Box';
import { Tabs, Tab } from '@mui/material';
import { ButtonGroup, Button } from '@mui/material';
import { FormatBold, FormatItalic, FormatUnderlined } from '@mui/icons-material';
import CssBaseline from '@mui/material/CssBaseline';
import AppBar from '@mui/material/AppBar';
import Toolbar from '@mui/material/Toolbar';
import Typography from '@mui/material/Typography';
import Drawer from '@mui/material/Drawer';
import { IconButton } from "@mui/material";
import MenuIcon from "@mui/icons-material/Menu";
import { ArrowDropDown } from '@mui/icons-material';
import { Menu, MenuItem, Divider, Tooltip, styled } from '@mui/material';
import { InsertPhoto, TableChart, Link } from '@mui/icons-material';

const NetworkGraph = dynamic(() => import('../components/Graph/NetworkGraph'), {
    ssr: false,
});
import EditDrawer from '../components/Drawer/EditDrawer';

const DRAWER_WIDTH = 320;
const RIBBON_HEIGHT = 112;

// カスタムタブコンポーネント
const WideTab = styled(Tab)({
    minWidth: 120,
    maxWidth: 160,
    padding: '12px 16px',
    borderBottom: '2px solid transparent',
    transition: 'all 0.3s ease',
    '&.Mui-selected': {
        backgroundColor: 'rgba(25, 118, 210, 0.08)',
        borderBottom: '2px solid #1976d2'
    }
});

// リボンドロワーコンポーネント
const RibbonDrawer = ({
    isOpen,
    tabValue,
    onTabChange,
    fontAnchorEl,
    onFontMenuOpen,
    onMenuClose,
    insertAnchorEl,
    onInsertMenuOpen
}) => {
    return (
        <Drawer
            variant="persistent"
            anchor="top"
            open={isOpen}
            sx={{
                width: '100%',
                flexShrink: 0,
                [`& .MuiDrawer-paper`]: {
                    top: 64,
                    height: RIBBON_HEIGHT,
                    boxSizing: 'border-box',
                },
            }}
        >
            <Tabs
                value={tabValue}
                onChange={onTabChange}
                variant="scrollable"
                scrollButtons="auto"
            >
                <WideTab label="ホーム" />
                <WideTab label="挿入" />
                <WideTab label="デザイン" />
            </Tabs>

            {tabValue === 0 && (
                <Box sx={{ px: 2, py: 1 }}>
                    <ButtonGroup variant="text" sx={{ mr: 2 }}>
                        <Tooltip title="太字 (Ctrl+B)">
                            <Button><FormatBold fontSize="small" /></Button>
                        </Tooltip>
                        <Tooltip title="斜体 (Ctrl+I)">
                            <Button><FormatItalic fontSize="small" /></Button>
                        </Tooltip>
                        <Tooltip title="下線 (Ctrl+U)">
                            <Button><FormatUnderlined fontSize="small" /></Button>
                        </Tooltip>
                        <Button
                            endIcon={<ArrowDropDown fontSize="small" />}
                            onClick={onFontMenuOpen}
                        >
                            フォント
                        </Button>
                    </ButtonGroup>

                    <Menu
                        anchorEl={fontAnchorEl}
                        open={Boolean(fontAnchorEl)}
                        onClose={onMenuClose}
                    >
                        <MenuItem>メイリオ</MenuItem>
                        <MenuItem>游ゴシック</MenuItem>
                        <Divider />
                        <MenuItem>フォント設定...</MenuItem>
                    </Menu>
                </Box>
            )}
        </Drawer>
    );
};

export default function Home() {
    const [selectedItem, setSelectedItem] = useState(null);
    const [editMode, setEditMode] = useState(false);
    const [isDrawerOpen, setDrawerOpen] = useState(false);
    const [isRibbonOpen, setRibbonOpen] = useState(false);
    const [ribbonTabValue, setRibbonTabValue] = useState(0);
    const [fontAnchorEl, setFontAnchorEl] = useState(null);
    const [insertAnchorEl, setInsertAnchorEl] = useState(null);
    const ribbonTimeoutRef = useRef(null);
    const leftDrawerTimeoutRef = useRef(null);
    const [isMouseOverRibbonArea, setIsMouseOverRibbonArea] = useState(false);

    // イベントハンドラ
    const toggleDrawer = () => {
        setDrawerOpen(!isDrawerOpen);
    };

    const toggleRibbon = () => {
        setRibbonOpen(!isRibbonOpen);
    };

    const handleRibbonTabChange = (_, newValue) => {
        setRibbonTabValue(newValue);
    };

    const handleFontMenuOpen = (e) => {
        setFontAnchorEl(e.currentTarget);
    };

    const handleMenuClose = () => {
        setFontAnchorEl(null);
        setInsertAnchorEl(null);
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

    // 左側ドロワーのホバー処理
    const handleLeftDrawerEnter = () => {
        clearTimeout(leftDrawerTimeoutRef.current);
        setDrawerOpen(true);
    };

    const handleLeftDrawerLeave = () => {
        leftDrawerTimeoutRef.current = setTimeout(() => {
            setDrawerOpen(false);
        }, 500);
    };

   // リボンドロワーのホバー処理
    const handleRibbonEnter = () => {
        clearTimeout(ribbonTimeoutRef.current);
        setRibbonOpen(true);
         setIsMouseOverRibbonArea(true);
    };

    const handleRibbonLeave = () => {
        setIsMouseOverRibbonArea(false);
        ribbonTimeoutRef.current = setTimeout(() => {
            setRibbonOpen(false);
        }, 500);
    };

    useEffect(() => {
        return () => {
            clearTimeout(ribbonTimeoutRef.current);
            clearTimeout(leftDrawerTimeoutRef.current);
        };
    }, []);

    return (
        <Box sx={{ display: 'flex' }}>
            <CssBaseline />

            {/* メインAppBar */}
            <AppBar position="fixed" sx={{ zIndex: (theme) => theme.zIndex.drawer + 2 }}>
                <Toolbar>
                    <IconButton
                        edge="start"
                        color="inherit"
                        aria-label="menu"
                        onClick={toggleDrawer}
                        sx={{ mr: 2 }}
                    >
                        <MenuIcon />
                    </IconButton>
                    <Typography variant="h6" noWrap component="div" sx={{ flexGrow: 1 }}>
                        ネットワークグラフ
                    </Typography>
                    <IconButton
                        edge="end"
                        color="inherit"
                        aria-label="ribbon"
                        onClick={toggleRibbon}
                    >
                        <MenuIcon />
                    </IconButton>
                </Toolbar>
            </AppBar>

            {/* 左サイドドロワー */}
            <Box
                onMouseEnter={handleLeftDrawerEnter}
                onMouseLeave={handleLeftDrawerLeave}
                sx={{
                    position: 'fixed',
                    left: 0,
                    top: 64,
                    width: 10,
                    height: `calc(100vh - 64px)`,
                    zIndex: (theme) => theme.zIndex.drawer + 1,
                    '&:hover': {
                        width: '20px',
                        backgroundColor: 'rgba(0,0,0,0.1)'
                    }
                }}
            />
            <Drawer
                anchor="left"
                open={isDrawerOpen}
                onClose={toggleDrawer}
                variant="temporary"
                sx={{
                    width: DRAWER_WIDTH,
                    flexShrink: 0,
                    [`& .MuiDrawer-paper`]: {
                        width: DRAWER_WIDTH,
                        boxSizing: 'border-box',
                        marginTop: 64,
                        height: `calc(100vh - 64px)`,
                    },
                }}
            >
                <Toolbar />
                <Box sx={{ overflow: 'auto', p: 2 }}>
                    <Typography variant="h6" sx={{ mb: 2 }}>
                        ネットワーク管理
                    </Typography>
                </Box>
            </Drawer>

            {/* リボンドロワー */}
                <Box
                    style={{
                        position: 'fixed',
                        top: 64,
                        left: 0,
                        width: '100%',
                        height: 16,
                        zIndex: 1200,
                    }}
                    onMouseEnter={handleRibbonEnter}
                    onMouseLeave={handleRibbonLeave}
                />

              <Box
                style={{ position: 'fixed', top: 64, width: '100%', zIndex: 1200,
                overflow: 'hidden',
                transition: 'height 0.3s ease',
                height: isRibbonOpen ? RIBBON_HEIGHT : 0
                 }}
                    onMouseEnter={handleRibbonEnter}
                    onMouseLeave={handleRibbonLeave}
              >
                <RibbonDrawer
                    isOpen={isRibbonOpen}
                    tabValue={ribbonTabValue}
                    onTabChange={handleRibbonTabChange}
                    fontAnchorEl={fontAnchorEl}
                    onFontMenuOpen={handleFontMenuOpen}
                    onMenuClose={handleMenuClose}
                    insertAnchorEl={insertAnchorEl}
                    onInsertMenuOpen={() => {
                    }}
                />
              </Box>

            {/* メインコンテンツ */}
            <Box
                component="main"
                sx={{
                    flexGrow: 1,
                    p: 3,
                    boxSizing: 'border-box',
                    marginTop: 64 + (isRibbonOpen ? RIBBON_HEIGHT : 0),
                    minHeight: `calc(100vh - 64px - ${isRibbonOpen ? RIBBON_HEIGHT : 0}px)`
                }}
            >
                <Toolbar />
                <Box sx={{ display: 'flex', height: 'calc(100% - 64px)' }}>
                    <NetworkGraph
                        onNodeSelect={handleNodeSelect}
                        onEdgeSelect={handleEdgeSelect}
                    />
                </Box>
            </Box>

            {/* 編集ドロワー */}
            <EditDrawer
                open={editMode}
                selectedItem={selectedItem}
                onClose={handleCloseEdit}
            />
        </Box>
    );
}
