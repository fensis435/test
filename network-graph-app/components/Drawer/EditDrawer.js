// src/components/Drawer/EditDrawer.js
import { useCallback } from 'react';
import Drawer from '@mui/material/Drawer';
import Box from '@mui/material/Box';
import Typography from '@mui/material/Typography';
import IconButton from '@mui/material/IconButton';
import CloseIcon from '@mui/icons-material/Close';
import Divider from '@mui/material/Divider';
import NodeEditForm from './NodeEditForm';
import EdgeEditForm from './EdgeEditForm';

const DRAWER_WIDTH = 400;

export default function EditDrawer({ open, selectedItem, onClose }) {
  const handleSave = useCallback((data) => {
    // ここでデータを保存する処理を実装
    console.log('Save data:', data);
    onClose();
  }, [onClose]);

  const renderContent = () => {
    if (!selectedItem) return null;

    if (selectedItem.type === 'node') {
      return <NodeEditForm node={selectedItem.data} onSave={handleSave} />;
    } else if (selectedItem.type === 'edge') {
      return <EdgeEditForm edge={selectedItem.data} onSave={handleSave} />;
    }

    return null;
  };

  const getTitle = () => {
    if (!selectedItem) return '';

    if (selectedItem.type === 'node') {
      return `ノード編集: ${selectedItem.data.label || selectedItem.data.id}`;
    } else if (selectedItem.type === 'edge') {
      return `エッジ編集: ${selectedItem.data.label || selectedItem.data.id}`;
    }

    return '編集';
  };

  return (
    <Drawer
      anchor="right"
      open={open}
      variant="persistent"
      sx={{
        width: open ? DRAWER_WIDTH : 0,
        flexShrink: 0,
        '& .MuiDrawer-paper': {
          width: DRAWER_WIDTH,
          boxSizing: 'border-box',
        },
      }}
    >
      <Box sx={{ p: 2, display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
        <Typography variant="h6">{getTitle()}</Typography>
        <IconButton onClick={onClose}>
          <CloseIcon />
        </IconButton>
      </Box>
      <Divider />
      <Box sx={{ p: 2 }}>
        {renderContent()}
      </Box>
    </Drawer>
  );
}

