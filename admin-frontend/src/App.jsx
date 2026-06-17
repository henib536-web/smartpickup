import { useState, useEffect } from 'react';
import { BrowserRouter, Routes, Route, Navigate, NavLink } from 'react-router-dom';
import { LayoutDashboard, Users, Car, Map, Settings, LogOut } from 'lucide-react';
import axios from 'axios';
import Dashboard from './pages/Dashboard';
import Rides from './pages/Rides';
import UsersList from './pages/Users';
import UserDetails from './pages/UserDetails';
import DriverDetails from './pages/DriverDetails';
import CreateDriver from './pages/CreateDriver';
import Reports from './pages/Reports';
import LiveTracking from './pages/LiveTracking';
import Login from './pages/Login';
import './index.css';

function Sidebar({ onLogout }) {
  return (
    <div className="sidebar">
      <div style={{ marginBottom: '40px', padding: '0 16px' }}>
        <h2 style={{ color: 'white', display: 'flex', alignItems: 'center', gap: '10px', fontSize: '1.4rem' }}>
          <div style={{ width: 32, height: 32, borderRadius: 8, background: 'linear-gradient(135deg, #FFCC00, #B38F00)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <Car size={20} color="black" />
          </div>
          SmartPickup
        </h2>
      </div>
      
      <nav style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: '4px' }}>
        <NavLink to="/dashboard" className={({isActive}) => isActive ? "nav-link active" : "nav-link"}>
          <LayoutDashboard size={20} /> Dashboard
        </NavLink>
        <NavLink to="/users" className={({isActive}) => isActive ? "nav-link active" : "nav-link"}>
          <Users size={20} /> Accounts & Validation
        </NavLink>
        <NavLink to="/rides" className={({isActive}) => isActive ? "nav-link active" : "nav-link"}>
          <Map size={20} /> Rides Management
        </NavLink>
        <NavLink to="/reports" className={({isActive}) => isActive ? "nav-link active" : "nav-link"}>
          <Settings size={20} /> Reports & Complaints
        </NavLink>
        <NavLink to="/live-tracking" className={({isActive}) => isActive ? "nav-link active" : "nav-link"}>
          <Map size={20} /> Live Tracking
        </NavLink>
      </nav>

      <div style={{ marginTop: 'auto', paddingTop: '20px', borderTop: '1px solid rgba(255,255,255,0.08)' }}>
        <button onClick={onLogout} className="nav-link" style={{ width: '100%', border: 'none', background: 'none', color: '#ef4444', textAlign: 'left' }}>
          <LogOut size={20} /> Logout
        </button>
      </div>
    </div>
  );
}

function App() {
  const [user, setUser] = useState(() => {
    // Check if there are query parameters in URL (from Flutter login.dart redirection)
    const params = new URLSearchParams(window.location.search);
    const token = params.get('token');
    const userId = params.get('user_id');
    const email = params.get('email');
    const fullName = params.get('full_name');
    const role = params.get('role');

    if (token && role === 'admin') {
      const userData = {
        access_token: token,
        user_id: userId,
        email: email,
        full_name: fullName,
        role: role
      };
      localStorage.setItem('admin_user', JSON.stringify(userData));
      
      // Clean up URL parameters
      window.history.replaceState({}, document.title, window.location.pathname);
      if (userData.access_token) {
        axios.defaults.headers.common['Authorization'] = `Bearer ${userData.access_token}`;
      }
      return userData;
    }

    const saved = localStorage.getItem('admin_user');
    const parsedUser = saved ? JSON.parse(saved) : null;
    
    if (parsedUser && parsedUser.access_token) {
      axios.defaults.headers.common['Authorization'] = `Bearer ${parsedUser.access_token}`;
    }
    
    return parsedUser;
  });

  // Keep this to update headers if user state changes during app lifecycle
  useEffect(() => {
    if (user && user.access_token) {
      axios.defaults.headers.common['Authorization'] = `Bearer ${user.access_token}`;
    } else {
      delete axios.defaults.headers.common['Authorization'];
    }
  }, [user]);

  const handleLoginSuccess = (userData) => {
    localStorage.setItem('admin_user', JSON.stringify(userData));
    setUser(userData);
  };

  const handleLogout = () => {
    localStorage.removeItem('admin_user');
    setUser(null);
  };

  if (!user || user.role !== 'admin') {
    return <Login onLoginSuccess={handleLoginSuccess} />;
  }

  return (
    <BrowserRouter>
      <div className="app-container">
        <Sidebar onLogout={handleLogout} />
        <div className="main-content">
          <Routes>
            <Route path="/" element={<Navigate to="/dashboard" replace />} />
            <Route path="/dashboard" element={<Dashboard />} />
            <Route path="/users" element={<UsersList />} />
            <Route path="/users/:id" element={<UserDetails />} />
            <Route path="/drivers/:id" element={<DriverDetails />} />
            <Route path="/create-driver" element={<CreateDriver />} />
            <Route path="/rides" element={<Rides />} />
            <Route path="/reports" element={<Reports />} />
            <Route path="/live-tracking" element={<LiveTracking />} />
            <Route path="*" element={<Navigate to="/dashboard" replace />} />
          </Routes>
        </div>
      </div>
    </BrowserRouter>
  );
}

export default App;
