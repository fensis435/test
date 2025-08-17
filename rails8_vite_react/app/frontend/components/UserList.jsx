// src/components/UserList.jsx
import React, { useState, useEffect, useMemo, useCallback } from 'react';
import {
  Card,
  CardContent,
  Typography,
  IconButton,
  Chip,
  Avatar,
  Box,
  TextField,
  InputAdornment,
  Button,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogContentText,
  DialogActions,
  CircularProgress,
  Alert,
  Tooltip,
  Menu,
  MenuItem,
  Fade,
  Select,
  FormControl,
  InputLabel,
  OutlinedInput
} from '@mui/material';
import {
  DataGrid,
  GridActionsCellItem,
  GridRowModes,
  GridRowModesModel,
  GridToolbarContainer,
  GridToolbarColumnsButton,
  GridToolbarFilterButton,
  GridToolbarExport,
  GridToolbarDensitySelector
} from '@mui/x-data-grid';
import {
  Person,
  Search,
  Delete,
  MoreVert,
  Edit,
  Visibility,
  Add,
  AdminPanelSettings,
  PersonOutline,
  Email,
  Schedule,
  Save,
  Cancel,
  Refresh
} from '@mui/icons-material';
import { useAuthHeader, useAuthUser } from 'react-auth-kit';
import { useNotification } from '../context/NotificationContext';
import UserService from '../services/userService';

// Custom toolbar component
const CustomToolbar = ({ onAddUser, onRefresh, refreshing }) => {
  return (
    <GridToolbarContainer>
      <Box display="flex" justifyContent="space-between" width="100%" alignItems="center">
        <Box>
          <GridToolbarColumnsButton />
          <GridToolbarFilterButton />
          <GridToolbarDensitySelector />
          <GridToolbarExport />
        </Box>
        <Box>
          <Button
            size="small"
            startIcon={refreshing ? <CircularProgress size={16} /> : <Refresh />}
            onClick={onRefresh}
            disabled={refreshing}
            sx={{ mr: 1 }}
          >
            Refresh
          </Button>
          <Button
            variant="contained"
            size="small"
            startIcon={<Add />}
            onClick={onAddUser}
          >
            Add User
          </Button>
        </Box>
      </Box>
    </GridToolbarContainer>
  );
};

const UserList = ({ onEditUser, onRegisterUser, onViewUser }) => {
  const [users, setUsers] = useState([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [deleteDialogOpen, setDeleteDialogOpen] = useState(false);
  const [userToDelete, setUserToDelete] = useState(null);
  const [deleting, setDeleting] = useState(false);
  const [rowModesModel, setRowModesModel] = useState({});
  const [error, setError] = useState('');

  const getAuthHeader = useAuthHeader();
  const authHeader = useMemo(() => getAuthHeader(), [getAuthHeader]);
  const getAuthUser = useAuthUser();
  const authUser = useMemo(() => getAuthUser(), [getAuthUser]);
  const { addNotification } = useNotification();

  useEffect(() => {
    fetchUsers();
  }, []);

  const fetchUsers = async (showRefreshing = false) => {
    try {
      if (showRefreshing) {
        setRefreshing(true);
      } else {
        setLoading(true);
      }
      setError('');
      const accessToken = authHeader?.replace('Bearer ', '');
      const response = await UserService.getAllUsers(accessToken);
      setUsers(response.users || []);
    } catch (error) {
      setError(error.message);
      addNotification('Failed to fetch users: ' + error.message, 'error');
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  };

  const handleRefresh = () => {
    fetchUsers(true);
  };

  const handleDeleteUser = async () => {
    if (!userToDelete) return;

    try {
      setDeleting(true);
      const accessToken = authHeader?.replace('Bearer ', '');
      await UserService.deleteUser(userToDelete.id, accessToken);

      addNotification(
        `User ${userToDelete.name} deleted successfully`,
        'success'
      );
      setDeleteDialogOpen(false);
      setUserToDelete(null);
      fetchUsers(true);
    } catch (error) {
      addNotification('Failed to delete user: ' + error.message, 'error');
    } finally {
      setDeleting(false);
    }
  };

  const openDeleteDialog = useCallback((user) => {
    setUserToDelete(user);
    setDeleteDialogOpen(true);
  }, []);

  const handleRowEditStart = useCallback((params, event) => {
    event.defaultMuiPrevented = true;
  }, []);

  const handleRowEditStop = useCallback((params, event) => {
    event.defaultMuiPrevented = true;
  }, []);

  const handleEditClick = useCallback((id) => () => {
    setRowModesModel({ ...rowModesModel, [id]: { mode: GridRowModes.Edit } });
  }, [rowModesModel]);

  const handleSaveClick = useCallback((id) => () => {
    setRowModesModel({ ...rowModesModel, [id]: { mode: GridRowModes.View } });
  }, [rowModesModel]);

  const handleCancelClick = useCallback((id) => () => {
    setRowModesModel({
      ...rowModesModel,
      [id]: { mode: GridRowModes.View, ignoreModifications: true },
    });
  }, [rowModesModel]);

  const handleViewClick = useCallback((user) => () => {
    onViewUser(user);
  }, [onViewUser]);

  const processRowUpdate = useCallback(async (newRow) => {
    try {
      const accessToken = authHeader?.replace('Bearer ', '');
      const updatedUser = await UserService.updateUser(newRow.id, {
        name: newRow.name,
        email: newRow.email,
        role: newRow.role,
      }, accessToken);

      addNotification('User updated successfully', 'success');
      
      // Update local state
      setUsers(users.map(user => 
        user.id === newRow.id ? { ...user, ...updatedUser } : user
      ));
      
      return newRow;
    } catch (error) {
      addNotification('Failed to update user: ' + error.message, 'error');
      throw error;
    }
  }, [authHeader, addNotification, users]);

  const handleProcessRowUpdateError = useCallback((error) => {
    console.error('Row update error:', error);
  }, []);

  const formatDate = (dateString) => {
    return new Date(dateString).toLocaleDateString('ja-JP', {
      year: 'numeric',
      month: 'short',
      day: 'numeric'
    });
  };

  const isCurrentUser = (userId) => {
    return authUser?.id === userId;
  };

  const columns = [
    {
      field: 'user',
      headerName: 'User',
      width: 250,
      renderCell: (params) => (
        <Box display="flex" alignItems="center" gap={2}>
          <Avatar sx={{ bgcolor: 'primary.main', width: 32, height: 32 }}>
            {params.row.role === 'admin' ? (
              <AdminPanelSettings fontSize="small" />
            ) : (
              <PersonOutline fontSize="small" />
            )}
          </Avatar>
          <Box>
            <Typography variant="body2" fontWeight="medium" component='span'>
              {params.row.name}
              {isCurrentUser(params.row.id) && (
                <Chip label="You" size="small" sx={{ ml: 1, height: 20 }} />
              )}
            </Typography>
            <Typography variant="caption" color="text.secondary">
              ID: {params.row.id}
            </Typography>
          </Box>
        </Box>
      ),
      sortable: false,
      filterable: false,
    },
    {
      field: 'name',
      headerName: 'Name',
      width: 180,
      editable: true,
    },
    {
      field: 'email',
      headerName: 'Email',
      width: 220,
      editable: true,
      renderCell: (params) => (
        <Box display="flex" alignItems="center" gap={1}>
          <Email fontSize="small" color="action" />
          {params.value}
        </Box>
      ),
    },
    {
      field: 'role',
      headerName: 'Role',
      width: 120,
      editable: true,
      type: 'singleSelect',
      valueOptions: ['user', 'admin'],
      renderCell: (params) => (
        <Chip
          label={params.value || 'user'}
          color={params.value === 'admin' ? 'secondary' : 'default'}
          size="small"
        />
      ),
      renderEditCell: (params) => (
        <FormControl fullWidth size="small">
          <Select
            value={params.value || 'user'}
            onChange={(event) => params.api.setEditCellValue({
              id: params.id,
              field: params.field,
              value: event.target.value
            })}
            input={<OutlinedInput />}
          >
            <MenuItem value="user">User</MenuItem>
            <MenuItem value="admin">Admin</MenuItem>
          </Select>
        </FormControl>
      ),
    },
    {
      field: 'status',
      headerName: 'Status',
      width: 120,
      renderCell: (params) => (
        <Chip
          label={params.row.active_sessions_count > 0 ? 'Active' : 'Inactive'}
          color={params.row.active_sessions_count > 0 ? 'success' : 'default'}
          size="small"
          variant="outlined"
        />
      ),
      sortable: false,
      filterable: false,
    },
    {
      field: 'created_at',
      headerName: 'Created',
      width: 140,
      renderCell: (params) => (
        <Box display="flex" alignItems="center" gap={1}>
          <Schedule fontSize="small" color="action" />
          <Typography variant="body2">
            {formatDate(params.value)}
          </Typography>
        </Box>
      ),
    },
    {
      field: 'actions',
      type: 'actions',
      headerName: 'Actions',
      width: 120,
      cellClassName: 'actions',
      getActions: ({ id, row }) => {
        const isInEditMode = rowModesModel[id]?.mode === GridRowModes.Edit;

        if (isInEditMode) {
          return [
            <GridActionsCellItem
              icon={<Save />}
              label="Save"
              onClick={handleSaveClick(id)}
              sx={{ color: 'primary.main' }}
            />,
            <GridActionsCellItem
              icon={<Cancel />}
              label="Cancel"
              onClick={handleCancelClick(id)}
              sx={{ color: 'inherit' }}
            />,
          ];
        }

        return [
          <GridActionsCellItem
            icon={<Visibility />}
            label="View"
            onClick={handleViewClick(row)}
            sx={{ color: 'info.main' }}
          />,
          <GridActionsCellItem
            icon={<Edit />}
            label="Edit"
            onClick={handleEditClick(id)}
            sx={{ color: 'primary.main' }}
          />,
          ...(!isCurrentUser(id) ? [
            <GridActionsCellItem
              icon={<Delete />}
              label="Delete"
              onClick={() => openDeleteDialog(row)}
              sx={{ color: 'error.main' }}
            />
          ] : []),
        ];
      },
    },
  ];

  if (loading) {
    return (
      <Card>
        <CardContent>
          <Box display="flex" justifyContent="center" py={4}>
            <CircularProgress />
          </Box>
        </CardContent>
      </Card>
    );
  }

  return (
    <>
      <Card>
        <CardContent>
          <Box mb={2}>
            <Typography variant="h5" component="h2" gutterBottom>
              User Management
            </Typography>
            {error && (
              <Alert severity="error" sx={{ mb: 2 }}>
                {error}
              </Alert>
            )}
          </Box>

          <Box sx={{ height: 600, width: '100%' }}>
            <DataGrid
              rows={users}
              columns={columns}
              pageSizeOptions={[5, 10, 25]}
              initialState={{
                pagination: { paginationModel: { pageSize: 10 } },
              }}
              editMode="row"
              rowModesModel={rowModesModel}
              onRowModesModelChange={setRowModesModel}
              onRowEditStart={handleRowEditStart}
              onRowEditStop={handleRowEditStop}
              processRowUpdate={processRowUpdate}
              onProcessRowUpdateError={handleProcessRowUpdateError}
              slots={{
                toolbar: CustomToolbar,
              }}
              slotProps={{
                toolbar: {
                  onAddUser: onRegisterUser,
                  onRefresh: handleRefresh,
                  refreshing: refreshing,
                },
              }}
              disableRowSelectionOnClick
              sx={{
                '& .MuiDataGrid-cell:focus': {
                  outline: 'none',
                },
                '& .MuiDataGrid-row:hover': {
                  backgroundColor: 'action.hover',
                },
                '& .MuiDataGrid-columnHeaders': {
                  backgroundColor: 'background.default',
                  borderBottom: '2px solid',
                  borderBottomColor: 'divider',
                },
              }}
            />
          </Box>
        </CardContent>
      </Card>

      {/* Delete Confirmation Dialog */}
      <Dialog
        open={deleteDialogOpen}
        onClose={() => setDeleteDialogOpen(false)}
      >
        <DialogTitle>Delete User</DialogTitle>
        <DialogContent>
          <DialogContentText>
            Are you sure you want to delete user "{userToDelete?.name}"? This
            action cannot be undone and will permanently remove all user data.
          </DialogContentText>
        </DialogContent>
        <DialogActions>
          <Button
            onClick={() => setDeleteDialogOpen(false)}
            disabled={deleting}
          >
            Cancel
          </Button>
          <Button
            onClick={handleDeleteUser}
            color="error"
            variant="contained"
            disabled={deleting}
            startIcon={deleting && <CircularProgress size={16} />}
          >
            {deleting ? 'Deleting...' : 'Delete'}
          </Button>
        </DialogActions>
      </Dialog>
    </>
  );
};

export default UserList;
