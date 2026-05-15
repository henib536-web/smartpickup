import { BrowserRouter, Routes, Route, Navigate, NavLink } from 'react-router-dom';
import { LayoutDashboard, Users, Car, Map, Settings, LogOut } from 'lucide-react';
import Dashboard from './pages/Dashboard';
import Rides from './pages/Rides';
import './index.css';

function Sidebar() {
  return (
    <div className="sidebar">
      <div style={{ marginBottom: '40px', padding: '0 16px' }}>
        <h2 style={{ color: 'white', display: 'flex', alignItems: 'center', gap: '10px', fontSize: '1.4rem' }}>
          <div style={{ width: 32, height: 32, borderRadius: 8, background: 'linear-gradient(135deg, #FFCC00, #B38F00)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <Car size={20} color="black" />
          </div>
          SmartAdmin
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
        <button className="nav-link" style={{ width: '100%', border: 'none', background: 'none', color: '#ef4444', textAlign: 'left' }}>
          <LogOut size={20} /> Logout
        </button>
      </div>
    </div>
  );
}

import UsersList from './pages/Users';
import Reports from './pages/Reports';
import LiveTracking from './pages/LiveTracking';

function App() {
  return (
    <BrowserRouter>
      <div className="app-container">
        <Sidebar />
        <div className="main-content">
          <Routes>
            <Route path="/" element={<Navigate to="/dashboard" replace />} />
            <Route path="/dashboard" element={<Dashboard />} />
            <Route path="/users" element={<UsersList />} />
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
