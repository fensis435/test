import { useAuthHeader, useSignOut, useSignIn } from 'react-auth-kit';
import AuthService from '../auth/authService';

export const setupTokenRefresh = () => {
  // Axiosのインターセプターでトークンリフレッシュを自動化
  const refreshToken = async () => {
    try {
      const storedRefreshToken = localStorage.getItem('refreshToken');
      if (!storedRefreshToken) {
        throw new Error('No refresh token available');
      }

      const response = await AuthService.refresh(storedRefreshToken);
      
      // 新しいリフレッシュトークンを保存
      localStorage.setItem('refreshToken', response.refresh_token);
      
      return response.access_token;
    } catch (error) {
      // リフレッシュに失敗した場合はログアウト
      localStorage.removeItem('refreshToken');
      throw error;
    }
  };

  return refreshToken;
};
