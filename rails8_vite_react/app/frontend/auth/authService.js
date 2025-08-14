import ApiClient from '../utils/apiClient';

class AuthService {
  static async login(email, password) {
    try {
      const response = await ApiClient.post('/auth/login', {
        email,
        password
      });
      return response;
    } catch (error) {
      console.error(error);
      throw new Error(error.message || 'Login failed');
    }
  }

  static async refresh(refreshToken) {
    try {
      const response = await ApiClient.post('/auth/refresh', {
        refresh_token: refreshToken
      });
      return response;
    } catch (error) {
      throw new Error(error.message || 'Token refresh failed');
    }
  }

  static async logout(accessToken, refreshToken) {
    try {
      await ApiClient.delete(
        '/auth/logout',
        { refresh_token: refreshToken },
        { Authorization: `Bearer ${accessToken}` }
      );
      return true;
    } catch (error) {
      console.error('Logout error:', error);
      return false;
    }
  }

  static async logoutAll(accessToken) {
    try {
      await ApiClient.delete(
        '/auth/logout_all',
        {},
        {
          Authorization: `Bearer ${accessToken}`
        }
      );
      return true;
    } catch (error) {
      console.error('Logout all error:', error);
      return false;
    }
  }

  static async getSessions(accessToken) {
    try {
      const response = await ApiClient.get('/auth/sessions', {
        Authorization: `Bearer ${accessToken}`
      });
      return response;
    } catch (error) {
      throw new Error(error.message || 'Failed to fetch sessions');
    }
  }
}

export default AuthService;
