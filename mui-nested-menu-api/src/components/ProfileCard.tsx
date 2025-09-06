// src/components/ProfileCard.tsx
import React from 'react';
import {
  Box,
  Typography,
  Button,
  TextField,
  Avatar,
  Divider,
  Paper,
} from '@mui/material';
import EditIcon from '@mui/icons-material/Edit';
import SaveIcon from '@mui/icons-material/Save';
import CancelIcon from '@mui/icons-material/Close';
import EmailOutlinedIcon from '@mui/icons-material/EmailOutlined';
import BusinessOutlinedIcon from '@mui/icons-material/BusinessOutlined';
import WorkOutlineOutlinedIcon from '@mui/icons-material/WorkOutlineOutlined';

export interface ProfileData {
  id: number;
  name: string;
  email: string;
  organization: string;
  position: string;
}

interface ProfileCardProps {
  data: ProfileData;
  onSave: (data: ProfileData) => void;
  /** 編集ボタンを出すかどうか */
  editable?: boolean;
}

const ProfileCard: React.FC<ProfileCardProps> = ({
  data,
  onSave,
  editable = false,
}) => {
  const [editMode, setEditMode] = React.useState(false);
  const [form, setForm] = React.useState({ ...data });

  const initials = data.name
    .split(' ')
    .map((w) => w[0])
    .join('')
    .slice(0, 2)
    .toUpperCase();

  const handleChange = (field: keyof ProfileData) => (
    e: React.ChangeEvent<HTMLInputElement>
  ) => {
    setForm((p) => ({ ...p, [field]: e.target.value }));
  };

  const handleSave = () => {
    onSave(form);
    setEditMode(false);
  };

  return (
    <Paper elevation={3} sx={{ p: 2, borderRadius: 2, width: 320 }}>
      <Box display="flex" alignItems="center" mb={2}>
        <Avatar sx={{ bgcolor: 'primary.main', mr: 2 }}>
          {initials}
        </Avatar>
        {!editMode ? (
          <Typography variant="h6">{data.name}</Typography>
        ) : (
          <TextField
            fullWidth
            variant="standard"
            value={form.name}
            onChange={handleChange('name')}
          />
        )}
      </Box>

      <Box mb={1} display="flex" alignItems="center">
        <EmailOutlinedIcon sx={{ mr: 1, color: 'text.secondary' }} />
        {!editMode ? (
          <Typography variant="body2">{data.email}</Typography>
        ) : (
          <TextField
            fullWidth
            variant="standard"
            value={form.email}
            onChange={handleChange('email')}
          />
        )}
      </Box>

      <Box mb={1} display="flex" alignItems="center">
        <BusinessOutlinedIcon sx={{ mr: 1, color: 'text.secondary' }} />
        {!editMode ? (
          <Typography variant="body2">{data.organization}</Typography>
        ) : (
          <TextField
            fullWidth
            variant="standard"
            value={form.organization}
            onChange={handleChange('organization')}
          />
        )}
      </Box>

      <Box mb={2} display="flex" alignItems="center">
        <WorkOutlineOutlinedIcon sx={{ mr: 1, color: 'text.secondary' }} />
        {!editMode ? (
          <Typography variant="body2">{data.position}</Typography>
        ) : (
          <TextField
            fullWidth
            variant="standard"
            value={form.position}
            onChange={handleChange('position')}
          />
        )}
      </Box>

      <Divider sx={{ mb: 2 }} />

      {editable && !editMode && (
        <Button
          variant="contained"
          startIcon={<EditIcon />}
          fullWidth
          onClick={() => setEditMode(true)}
        >
          Edit Profile
        </Button>
      )}

      {editMode && (
        <Box display="flex" justifyContent="flex-end" gap={1}>
          <Button
            variant="contained"
            startIcon={<SaveIcon />}
            onClick={handleSave}
          >
            Save
          </Button>
          <Button
            variant="outlined"
            startIcon={<CancelIcon />}
            onClick={() => setEditMode(false)}
          >
            Cancel
          </Button>
        </Box>
      )}
    </Paper>
  );
};

export default ProfileCard;
