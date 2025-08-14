import React from 'react';
import { Snackbar, Alert, Stack } from '@mui/material';
import { useNotification } from '../context/NotificationContext';

const NotificationContainer = () => {
  const { notifications, removeNotification } = useNotification();

  return (
    <Stack spacing={2} sx={{ position: 'fixed', top: 16, right: 16, zIndex: 9999 }}>
      {notifications.map((notification) => (
        <Snackbar
          key={notification.id}
          open={true}
          autoHideDuration={5000}
          onClose={() => removeNotification(notification.id)}
        >
          <Alert
            onClose={() => removeNotification(notification.id)}
            severity={notification.type === 'success' ? 'success' : 
                     notification.type === 'error' ? 'error' :
                     notification.type === 'warning' ? 'warning' : 'info'}
            sx={{ width: '100%' }}
          >
            {notification.message}
          </Alert>
        </Snackbar>
      ))}
    </Stack>
  );
};

export default NotificationContainer;
