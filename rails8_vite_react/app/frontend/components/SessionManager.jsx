import React, { useState, useEffect } from 'react';
import {
  Card,
  CardContent,
  Typography,
  List,
  ListItem,
  ListItemAvatar,
  ListItemText,
  Avatar,
  Chip,
  Box,
  CircularProgress,
  Alert,
  IconButton,
  Tooltip,
  Button,
} from '@mui/material';
import {
  Computer,
  Smartphone,
  Refresh,
  FiberManualRecord
} from '@mui/icons-material';
import { useAuthHeader } from 'react-auth-kit';
import AuthService from '../auth/authService';

const SessionManager = () => {
  const [sessions, setSessions] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const getAuthHeader = useAuthHeader();

  useEffect(() => {
    fetchSessions();
  }, []);

  const fetchSessions = async () => {
    try {
      const authHeader = getAuthHeader();
      setError('');
      setLoading(true);
      const accessToken = authHeader?.replace('Bearer ', '');
      if (!accessToken) {
        throw new Error('No access token available');
      }

      const data = await AuthService.getSessions(accessToken);
      setSessions(data.sessions || []);
    } catch (error) {
      console.error('Failed to fetch sessions:', error);
      setError('Failed to load sessions');
      setSessions([]);
    } finally {
      setLoading(false);
    }
  };

  const formatDeviceInfo = (deviceInfo) => {
    if (!deviceInfo) {
      return {
        browser: 'Unknown',
        ip: 'Unknown',
        lastUsed: 'Unknown',
        deviceType: 'desktop'
      };
    }

    try {
      const info = JSON.parse(deviceInfo);
      const userAgent = info.user_agent || 'Unknown';
      const browser = userAgent.includes('Chrome')
        ? 'Chrome'
        : userAgent.includes('Firefox')
          ? 'Firefox'
          : userAgent.includes('Safari')
            ? 'Safari'
            : userAgent.includes('Edge')
              ? 'Edge'
              : 'Unknown Browser';

      const deviceType = userAgent.includes('Mobile') ? 'mobile' : 'desktop';

      return {
        browser,
        ip: info.ip_address || 'Unknown',
        lastUsed: new Date(info.created_at).toLocaleDateString(),
        deviceType,
        userAgent: userAgent.substring(0, 50) + '...'
      };
    } catch {
      return {
        browser: 'Unknown',
        ip: 'Unknown',
        lastUsed: 'Unknown',
        deviceType: 'desktop'
      };
    }
  };

  if (loading) {
    return (
      <Card>
        <CardContent>
          <Box
            display='flex'
            justifyContent='space-between'
            alignItems='center'
            mb={2}
          >
            <Typography variant='h6' component='h2'>
              Active Sessions
            </Typography>
          </Box>
          <Box display='flex' justifyContent='center' py={4}>
            <CircularProgress />
          </Box>
        </CardContent>
      </Card>
    );
  }

  if (error) {
    return (
      <Card>
        <CardContent>
          <Box
            display='flex'
            justifyContent='space-between'
            alignItems='center'
            mb={2}
          >
            <Typography variant='h6' component='h2'>
              Active Sessions
            </Typography>
            <Tooltip title='Refresh sessions'>
              <IconButton onClick={fetchSessions} size='small'>
                <Refresh />
              </IconButton>
            </Tooltip>
          </Box>
          <Alert
            severity='error'
            action={
              <Button color='inherit' size='small' onClick={fetchSessions}>
                Retry
              </Button>
            }
          >
            {error}
          </Alert>
        </CardContent>
      </Card>
    );
  }

  return (
    <Card>
      <CardContent>
        <Box
          display='flex'
          justifyContent='space-between'
          alignItems='center'
          mb={2}
        >
          <Typography variant='h6' component='h2'>
            Active Sessions
          </Typography>
          <Tooltip title='Refresh sessions'>
            <IconButton onClick={fetchSessions} size='small'>
              <Refresh />
            </IconButton>
          </Tooltip>
        </Box>

        {sessions.length === 0 ? (
          <Alert severity='info'>No active sessions found</Alert>
        ) : (
          <>
            <List>
              {sessions.map((session) => {
                const deviceInfo = formatDeviceInfo(session.device_info);
                const createdDate = new Date(session.created_at);

                return (
                  <ListItem key={session.id} divider>
                    <ListItemAvatar>
                      <Avatar sx={{ bgcolor: 'primary.main' }}>
                        {deviceInfo.deviceType === 'mobile' ? (
                          <Smartphone />
                        ) : (
                          <Computer />
                        )}
                      </Avatar>
                    </ListItemAvatar>
                    <ListItemText
                      primary={
                        <Box display='flex' alignItems='center' gap={1}>
                          <Typography variant='subtitle1'>
                            {deviceInfo.browser}
                          </Typography>
                          <Chip
                            icon={<FiberManualRecord />}
                            label='Active'
                            size='small'
                            color='success'
                            variant='outlined'
                          />
                        </Box>
                      }
                      secondary={
                        <Box>
                          <Typography variant='body2' color='text.secondary'>
                            IP: {deviceInfo.ip}
                          </Typography>
                          <Typography variant='caption' color='text.secondary'>
                            Created: {createdDate.toLocaleDateString()} at{' '}
                            {createdDate.toLocaleTimeString()}
                          </Typography>
                        </Box>
                      }
                    />
                  </ListItem>
                );
              })}
            </List>

            <Box
              mt={2}
              display='flex'
              justifyContent='space-between'
              alignItems='center'
            >
              <Typography variant='body2' color='text.secondary'>
                Total active sessions: {sessions.length}
              </Typography>
              <Typography variant='caption' color='text.secondary'>
                Sessions are automatically cleaned up when expired
              </Typography>
            </Box>
          </>
        )}
      </CardContent>
    </Card>
  );
};

export default SessionManager;
