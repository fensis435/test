import { useEffect, useState } from 'react';
import dynamic from 'next/dynamic';
import { ThemeProvider, createTheme } from '@mui/material/styles';
import CssBaseline from '@mui/material/CssBaseline';

// MUIのテーマ設定
const theme = createTheme({
  palette: {
    primary: { main: '#1976d2' },
    secondary: { main: '#dc004e' },
    background: { default: '#f5f5f5' },
  },
});

function MyApp({ Component, pageProps }) {
  const [mounted, setMounted] = useState(false);

  // クライアントサイドでのみ実行
  useEffect(() => {
      try {
          if (typeof window !== 'undefined' && typeof WebGL2RenderingContext !== 'undefined') {
              console.log('WebGL2 is available in the browser environment.');
          } else {
              console.error('WebGL2RenderingContext is not supported in the current runtime.');
          }
          setMounted(true);
      } catch (error) {
          console.error('Error loading WebGL2RenderingContext:', error);
      }
  }, []);

  if (!mounted) {
    return null; // サーバーサイドでは何もレンダリングしない
  }

  return (
    <ThemeProvider theme={theme}>
      <CssBaseline />
      <Component {...pageProps} />
    </ThemeProvider>
  );
}

export default MyApp;
