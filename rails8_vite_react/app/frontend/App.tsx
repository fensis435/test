import { BrowserRouter } from 'react-router-dom';
import { AppRoutes } from './AppRoutes';
import NotificationContainer from './components/NotificationContainer';

export default function App() {
  return (
    <BrowserRouter>
      <AppRoutes />
      <NotificationContainer />
    </BrowserRouter>
  );
}
