// src/components/ProfileCell.tsx
import React from 'react';
import { Box, Popover } from '@mui/material';
import ProfileCard, { ProfileData } from './ProfileCard';

interface ProfileCellProps {
  row: ProfileData;
  onSave: (data: ProfileData) => void;
}

const ProfileCell: React.FC<ProfileCellProps> = ({ row, onSave }) => {
  const [anchor, setAnchor] = React.useState<HTMLElement | null>(null);
  const open = Boolean(anchor);

  return (
    <Box>
      <Box
        sx={{ cursor: 'pointer', color: 'primary.main', fontWeight: 500 }}
        onClick={(e) => setAnchor(e.currentTarget)}
      >
        {row.name}
      </Box>

      <Popover
        open={open}
        anchorEl={anchor}
        onClose={() => setAnchor(null)}
        anchorOrigin={{ vertical: 'bottom', horizontal: 'left' }}
        transformOrigin={{ vertical: 'top', horizontal: 'left' }}
        PaperProps={{ sx: { p: 1 } }}
      >
        <ProfileCard data={row} onSave={onSave} editable />
      </Popover>
    </Box>
  );
};

export default ProfileCell;
