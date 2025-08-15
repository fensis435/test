// src/components/UserList.jsx
import React, { useState, useEffect, useMemo } from 'react';
import {
  Card,
  CardContent,
  Typography,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Paper,
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
  TablePagination
} from '@mui/material';
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
  Schedule
} from '@mui/icons-material';
import { useAuthHeader, useAuthUser } from 'react-auth-kit';
import { useNotification } from '../context/NotificationContext';
import UserService from '../services/userService';

const UserList = ({ onEditUser, onRegisterUser, onViewUser }) => {
  const [users, setUsers] = useState([]);
  const [loading, setLoading] = useState(true);
  const [searchTerm, setSearchTerm] = useState('');
  const [searchResults, setSearchResults] = useState([]);
  const [deleteDialogOpen, setDeleteDialogOpen] = useState(false);
  const [userToDelete, setUserToDelete] = useState(null);
  const [deleting, setDeleting] = useState(false);
  const [menuAnchor, setMenuAnchor] = useState(null);
  const [selectedUser, setSelectedUser] = useState(null);
  const [page, setPage] = useState(0);
  const [rowsPerPage, setRowsPerPage] = useState(10);
  const [error, setError] = useState('');

  const getAuthHeader = useAuthHeader();
  const authHeader = useMemo(() => getAuthHeader(), [getAuthHeader]);
  const getAuthUser = useAuthUser();
  const authUser = useMemo(() => getAuthUser(), [getAuthUser]);
  const { addNotification } = useNotification();

  useEffect(() => {
    fetchUsers();
  }, []);

  useEffect(() => {
    if (searchTerm.trim()) {
      handleSearch();
    } else {
      setSearchResults(users);
    }
  }, [searchTerm, users]);

  const fetchUsers = async () => {
    try {
      setLoading(true);
      setError('');
      const accessToken = authHeader?.replace('Bearer ', '');
      const response = await UserService.getAllUsers(accessToken);
      setUsers(response.users || []);
      setSearchResults(response.users || []);
    } catch (error) {
      setError(error.message);
      addNotification('Failed to fetch users: ' + error.message, 'error');
    } finally {
      setLoading(false);
    }
  };

  const handleSearch = async () => {
    if (!searchTerm.trim()) {
      setSearchResults(users);
      return;
    }

    try {
      const accessToken = authHeader?.replace('Bearer ', '');
      const response = await UserService.searchUsers(searchTerm, accessToken);
      setSearchResults(response.users || []);
    } catch (error) {
      // フォールバック: クライアントサイドフィルタリング
      const filtered = users.filter(
        (user) =>
          user.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
          user.email.toLowerCase().includes(searchTerm.toLowerCase())
      );
      setSearchResults(filtered);
    }
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
      fetchUsers();
    } catch (error) {
      addNotification('Failed to delete user: ' + error.message, 'error');
    } finally {
      setDeleting(false);
    }
  };

  const openDeleteDialog = (user) => {
    setUserToDelete(user);
    setDeleteDialogOpen(true);
    handleCloseMenu();
  };

  const handleMenuOpen = (event, user) => {
    setMenuAnchor(event.currentTarget);
    setSelectedUser(user);
  };

  const handleCloseMenu = () => {
    setMenuAnchor(null);
    setSelectedUser(null);
  };

  const handleChangePage = (event, newPage) => {
    setPage(newPage);
  };

  const handleChangeRowsPerPage = (event) => {
    setRowsPerPage(parseInt(event.target.value, 10));
    setPage(0);
  };

  const formatDate = (dateString) => {
    return new Date(dateString).toLocaleDateString('ja-JP', {
      year: 'numeric',
      month: 'short',
      day: 'numeric'
    });
  };

  const isCurrentUser = (user) => {
    return authUser()?.id === user.id;
  };

  const paginatedUsers = searchResults.slice(
    page * rowsPerPage,
    page * rowsPerPage + rowsPerPage
  );

  if (loading) {
    return (
      <Card>
        <CardContent>
          <Box display='flex' justifyContent='center' py={4}>
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
          <Box
            display='flex'
            justifyContent='space-between'
            alignItems='center'
            mb={3}
          >
            <Typography variant='h5' component='h2'>
              User Management
            </Typography>
            <Button
              variant='contained'
              startIcon={<Add />}
              onClick={onRegisterUser}
            >
              Add New User
            </Button>
          </Box>

          <Box mb={3}>
            <TextField
              fullWidth
              variant='outlined'
              placeholder='Search users by name or email...'
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              InputProps={{
                startAdornment: (
                  <InputAdornment position='start'>
                    <Search />
                  </InputAdornment>
                )
              }}
            />
          </Box>

          {error && (
            <Alert severity='error' sx={{ mb: 2 }}>
              {error}
            </Alert>
          )}

          <TableContainer component={Paper}>
            <Table>
              <TableHead>
                <TableRow>
                  <TableCell>User</TableCell>
                  <TableCell>Email</TableCell>
                  <TableCell>Role</TableCell>
                  <TableCell>Status</TableCell>
                  <TableCell>Created</TableCell>
                  <TableCell align='right'>Actions</TableCell>
                </TableRow>
              </TableHead>
              <TableBody>
                {paginatedUsers.map((user) => (
                  <TableRow key={user.id} hover>
                    <TableCell>
                      <Box display='flex' alignItems='center' gap={2}>
                        <Avatar sx={{ bgcolor: 'primary.main' }}>
                          {user.role === 'admin' ? (
                            <AdminPanelSettings />
                          ) : (
                            <PersonOutline />
                          )}
                        </Avatar>
                        <Box>
                          <Typography variant='body1' fontWeight='medium'>
                            {user.name}
                            {isCurrentUser(user) && (
                              <Chip label='You' size='small' sx={{ ml: 1 }} />
                            )}
                          </Typography>
                          <Typography variant='body2' color='text.secondary'>
                            ID: {user.id}
                          </Typography>
                        </Box>
                      </Box>
                    </TableCell>
                    <TableCell>
                      <Box display='flex' alignItems='center' gap={1}>
                        <Email fontSize='small' color='action' />
                        {user.email}
                      </Box>
                    </TableCell>
                    <TableCell>
                      <Chip
                        label={user.role || 'user'}
                        color={user.role === 'admin' ? 'secondary' : 'default'}
                        size='small'
                      />
                    </TableCell>
                    <TableCell>
                      <Chip
                        label={
                          user.active_sessions_count > 0 ? 'Active' : 'Inactive'
                        }
                        color={
                          user.active_sessions_count > 0 ? 'success' : 'default'
                        }
                        size='small'
                        variant='outlined'
                      />
                    </TableCell>
                    <TableCell>
                      <Box display='flex' alignItems='center' gap={1}>
                        <Schedule fontSize='small' color='action' />
                        {formatDate(user.created_at)}
                      </Box>
                    </TableCell>
                    <TableCell align='right'>
                      <Tooltip title='More actions'>
                        <IconButton
                          onClick={(e) => handleMenuOpen(e, user)}
                          size='small'
                        >
                          <MoreVert />
                        </IconButton>
                      </Tooltip>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </TableContainer>

          <TablePagination
            rowsPerPageOptions={[5, 10, 25]}
            component='div'
            count={searchResults.length}
            rowsPerPage={rowsPerPage}
            page={page}
            onPageChange={handleChangePage}
            onRowsPerPageChange={handleChangeRowsPerPage}
          />

          {searchResults.length === 0 && !loading && (
            <Box textAlign='center' py={4}>
              <Person sx={{ fontSize: 64, color: 'text.secondary', mb: 2 }} />
              <Typography variant='h6' color='text.secondary'>
                {searchTerm ? 'No users found' : 'No users available'}
              </Typography>
              <Typography variant='body2' color='text.secondary'>
                {searchTerm
                  ? 'Try adjusting your search criteria'
                  : 'Add a new user to get started'}
              </Typography>
            </Box>
          )}
        </CardContent>
      </Card>

      {/* Action Menu */}
      <Menu
        anchorEl={menuAnchor}
        open={Boolean(menuAnchor)}
        onClose={handleCloseMenu}
        TransitionComponent={Fade}
      >
        <MenuItem
          onClick={() => {
            onViewUser(selectedUser);
            handleCloseMenu();
          }}
        >
          <Visibility fontSize='small' sx={{ mr: 1 }} />
          View Profile
        </MenuItem>
        <MenuItem
          onClick={() => {
            onEditUser(selectedUser);
            handleCloseMenu();
          }}
        >
          <Edit fontSize='small' sx={{ mr: 1 }} />
          Edit User
        </MenuItem>
        {selectedUser && !isCurrentUser(selectedUser) && (
          <MenuItem
            onClick={() => openDeleteDialog(selectedUser)}
            sx={{ color: 'error.main' }}
          >
            <Delete fontSize='small' sx={{ mr: 1 }} />
            Delete User
          </MenuItem>
        )}
      </Menu>

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
            color='error'
            variant='contained'
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
