// src/pages/ProfilePage.tsx
import React from 'react';
import { Container } from '@mui/material';
import ProfileCard, { ProfileData } from '../components/ProfileCard';

const initialProfile: ProfileData = {
  id: 1,
  name: '太郎',
  email: 'taro@example.com',
  organization: 'ABC Corp',
  position: 'Manager',
};

const ProfilePage: React.FC = () => {
  const [profile, setProfile] = React.useState<ProfileData>(
    initialProfile
  );

  return (
    <Container maxWidth="sm" sx={{ mt: 4 }}>
      <ProfileCard
        data={profile}
        onSave={(updated) => setProfile(updated)}
        editable
      />
    </Container>
  );
};

export default ProfilePage;
