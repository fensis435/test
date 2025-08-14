import ApiClient from '../utils/apiClient';

class UserService {
  static async getCurrentUser(accessToken) {
    try {
      const response = await ApiClient.get('/users/me', {
        'Authorization': `Bearer ${accessToken}`,
      });
      return response;
    } catch (error) {
      throw new Error(error.message || 'Failed to get current user');
    }
  }

  static async getUser(id, accessToken) {
    try {
      const response = await ApiClient.get(`/users/${id}`, {
        'Authorization': `Bearer ${accessToken}`,
      });
      return response;
    } catch (error) {
      throw new Error(error.message || 'Failed to get user');
    }
  }

  static async getAllUsers(accessToken, page = 1, perPage = 20) {
    try {
      const response = await ApiClient.get(
        `/users?page=${page}&per_page=${perPage}`, 
        {
          'Authorization': `Bearer ${accessToken}`,
        }
      );
      return response;
    } catch (error) {
      throw new Error(error.message || 'Failed to get users');
    }
  }

  static async createUser(userData, accessToken = null) {
    try {
      const headers = accessToken ? { 'Authorization': `Bearer ${accessToken}` } : {};
      const response = await ApiClient.post('/users', userData, headers);
      return response;
    } catch (error) {
      throw new Error(error.message || 'Failed to create user');
    }
  }

  static async updateUser(id, userData, accessToken) {
    try {
      const response = await ApiClient.request(`/users/${id}`, {
        method: 'PUT',
        headers: { 'Authorization': `Bearer ${accessToken}` },
        body: JSON.stringify(userData),
      });
      return response;
    } catch (error) {
      throw new Error(error.message || 'Failed to update user');
    }
  }

  static async deleteUser(id, accessToken) {
    try {
      const response = await ApiClient.delete(`/users/${id}`, {}, {
        'Authorization': `Bearer ${accessToken}`,
      });
      return response;
    } catch (error) {
      throw new Error(error.message || 'Failed to delete user');
    }
  }

  static async changePassword(id, passwordData, accessToken) {
    try {
      const response = await ApiClient.request(`/users/${id}/change_password`, {
        method: 'PUT',
        headers: { 'Authorization': `Bearer ${accessToken}` },
        body: JSON.stringify(passwordData),
      });
      return response;
    } catch (error) {
      throw new Error(error.message || 'Failed to change password');
    }
  }

  static async searchUsers(query, accessToken) {
    try {
      const response = await ApiClient.get(`/users/search?q=${encodeURIComponent(query)}`, {
        'Authorization': `Bearer ${accessToken}`,
      });
      return response;
    } catch (error) {
      throw new Error(error.message || 'Failed to search users');
    }
  }

  static async getUserSessions(id, accessToken) {
    try {
      const response = await ApiClient.get(`/users/${id}/sessions`, {
        'Authorization': `Bearer ${accessToken}`,
      });
      return response;
    } catch (error) {
      throw new Error(error.message || 'Failed to get user sessions');
    }
  }
}

export default UserService;
