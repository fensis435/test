import React from 'react';
import {
  AppBar,
  Toolbar,
  Typography,
  Container,
  Grid,
  Card,
  CardContent,
  Box,
  Avatar,
  Chip,
  Button
} from '@mui/material';
import { Person, Email, Tag, ManageAccounts } from '@mui/icons-material';
import { useAuth } from '../hooks/useAuth';
import { useNavigate } from 'react-router-dom';
import LogoutButton from '../components/LogoutButton';
import SessionManager from '../components/SessionManager';

const Dashboard = () => {
  const { user } = useAuth();
  const navigate = useNavigate();

  const isAdmin = user?.admin || false;

  return (
    <Box sx={{ flexGrow: 1 }}>
      <Container maxWidth='lg' sx={{ mt: 4, mb: 4 }}>
        <Grid container spacing={3}>
          {/* User Information Card */}
          <Grid item xs={12} md={6}>
            <Card>
              <CardContent>
                <Box display='flex' alignItems='center' mb={3}>
                  <Avatar sx={{ bgcolor: 'secondary.main', mr: 2 }}>
                    <Person />
                  </Avatar>
                  <Typography variant='h6' component='h2'>
                    User Information
                  </Typography>
                </Box>

                <Box sx={{ '& > *': { mb: 2 } }}>
                  <Box display='flex' alignItems='center' gap={2}>
                    <Person color='action' />
                    <Box>
                      <Typography variant='body2' color='text.secondary'>
                        Name
                      </Typography>
                      <Typography variant='body1'>{user?.name}</Typography>
                    </Box>
                  </Box>

                  <Box display='flex' alignItems='center' gap={2}>
                    <Email color='action' />
                    <Box>
                      <Typography variant='body2' color='text.secondary'>
                        Email
                      </Typography>
                      <Typography variant='body1'>{user?.email}</Typography>
                    </Box>
                  </Box>

                  <Box display='flex' alignItems='center' gap={2}>
                    <Tag color='action' />
                    <Box>
                      <Typography variant='body2' color='text.secondary'>
                        User ID
                      </Typography>
                      <Chip label={user?.id} size='small' variant='outlined' />
                    </Box>
                  </Box>

                  {isAdmin && (
                    <Box display='flex' alignItems='center' gap={2}>
                      <Box>
                        <Typography variant='body2' color='text.secondary'>
                          Role
                        </Typography>
                        <Chip
                          label='Administrator'
                          size='small'
                          color='primary'
                          icon={<ManageAccounts />}
                        />
                      </Box>
                    </Box>
                  )}
                </Box>
              </CardContent>
            </Card>
          </Grid>

          {/* Quick Actions Card */}
          <Grid item xs={12} md={6}>
            <Card>
              <CardContent>
                <Typography variant='h6' component='h2' gutterBottom>
                  Quick Actions
                </Typography>
                <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
                  <Button
                    variant='outlined'
                    startIcon={<Person />}
                    onClick={() => navigate('/users')}
                  >
                    Manage Profile
                  </Button>

                  {isAdmin && (
                    <Button
                      variant='outlined'
                      startIcon={<ManageAccounts />}
                      onClick={() => navigate('/users')}
                    >
                      Manage Users
                    </Button>
                  )}

                  <LogoutButton variant='outlined' />
                </Box>
              </CardContent>
            </Card>
          </Grid>

          {/* Session Manager */}
          <Grid item xs={12}>
            <SessionManager />
          </Grid>
        </Grid>
      </Container>
    </Box>
  );
};

export default Dashboard;
