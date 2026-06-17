import { useState, useEffect } from 'react';
import axios from 'axios';
import { Check, X, ShieldAlert, Trash2, Car, User as UserIcon, ChevronRight } from 'lucide-react';

const BASE_URL = 'http://127.0.0.1:8000/api/admin';

const STATUS_COLORS = {
  COMPLETED: '#4ade80',
  ACCEPTED:  '#FFCC00',
  PENDING:   '#60a5fa',
  CANCELLED: '#f87171',
  CANCELED:  '#f87171',
};

function StatusBadge({ status }) {
  const s = (status || '').toUpperCase();
  const color = STATUS_COLORS[s] || '#a0a0a0';
  return (
    <span style={{
      display: 'inline-block',
      padding: '2px 10px',
      borderRadius: 20,
      fontSize: '0.75rem',
      fontWeight: 600,
      backgroundColor: color + '22',
      color,
      border: `1px solid ${color}55`,
    }}>{s}</span>
  );
}

function RideRow({ ride, type }) {
  const date = ride.scheduled_for
    ? new Date(ride.scheduled_for).toLocaleString('fr-FR')
    : ride.requested_at
    ? new Date(ride.requested_at).toLocaleString('fr-FR')
    : '—';

  return (
    <tr>
      <td style={{ padding: '10px 12px', color: 'var(--accent-color)', fontWeight: 600, whiteSpace: 'nowrap' }}>{ride.ref}</td>
      <td style={{ padding: '10px 12px', fontSize: '0.85rem' }}>
        <div style={{ color: '#4ade80' }}>↑ {ride.pickup_location || '—'}</div>
        <div style={{ color: '#f87171', marginTop: 4 }}>↓ {ride.dropoff_location || '—'}</div>
      </td>
      {type === 'client' && <td style={{ padding: '10px 12px', fontSize: '0.85rem', color: 'var(--text-secondary)' }}>{ride.driver_name || 'Unassigned'}</td>}
      {type === 'driver' && <td style={{ padding: '10px 12px', fontSize: '0.85rem', color: 'var(--text-secondary)' }}>{ride.passenger_name || '—'}</td>}
      <td style={{ padding: '10px 12px', fontSize: '0.8rem', color: 'var(--text-secondary)', whiteSpace: 'nowrap' }}>{date}</td>
      <td style={{ padding: '10px 12px' }}><StatusBadge status={ride.status} /></td>
      {type === 'client' && ride.cancellation_reason && (
        <td style={{ padding: '10px 12px', fontSize: '0.8rem', color: '#f87171' }}>{ride.cancellation_reason}</td>
      )}
    </tr>
  );
}

export default function UsersList() {
  const [users, setUsers] = useState([]);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState('all');

  const [searchQuery, setSearchQuery] = useState('');
  const [statusFilter, setStatusFilter] = useState('all'); // 'all' | 'active' | 'inactive'

  // Create Driver state
  const [showCreateDriverModal, setShowCreateDriverModal] = useState(false);
  const [newDriver, setNewDriver] = useState({ full_name: '', email: '', phone: '', password: '', license_number: '', license_expiry: '' });
  const [files, setFiles] = useState({ profile_image: null, cin_image: null, driver_card_image: null });
  const [creatingDriver, setCreatingDriver] = useState(false);

  const handleCreateDriver = async (e) => {
    e.preventDefault();
    if (!files.cin_image || !files.driver_card_image) {
      alert("La CIN et la carte chauffeur sont obligatoires !");
      return;
    }
    
    setCreatingDriver(true);
    try {
      const formData = new FormData();
      formData.append('full_name', newDriver.full_name);
      formData.append('email', newDriver.email);
      formData.append('phone', newDriver.phone);
      formData.append('password', newDriver.password);
      formData.append('license_number', newDriver.license_number);
      formData.append('license_expiry', newDriver.license_expiry);
      if (files.profile_image) formData.append('profile_image', files.profile_image);
      formData.append('cin_image', files.cin_image);
      formData.append('driver_card_image', files.driver_card_image);

      await axios.post('http://127.0.0.1:8000/api/admin/drivers', formData, {
        headers: { 'Content-Type': 'multipart/form-data' }
      });
      alert('Driver created successfully!');
      setShowCreateDriverModal(false);
      setNewDriver({ full_name: '', email: '', phone: '', password: '', license_number: '', license_expiry: '' });
      setFiles({ profile_image: null, cin_image: null, driver_card_image: null });
      fetchUsers();
    } catch (error) {
      alert('Error creating driver: ' + (error.response?.data?.detail || error.message));
    } finally {
      setCreatingDriver(false);
    }
  };

  const getDocumentUrl = (path) => {
    if (!path) return '';
    if (path.startsWith('http')) return path;
    if (path.startsWith('/uploads/')) return `http://127.0.0.1:8000${path}`;
    return `http://127.0.0.1:8000/uploads/${path}`;
  };

  useEffect(() => { fetchUsers(); }, []);

  const fetchUsers = async () => {
    try {
      const response = await axios.get(`${BASE_URL}/users`);
      setUsers(response.data);
    } catch (error) {
      console.error('Error fetching users:', error);
    } finally {
      setLoading(false);
    }
  };

  const openDetails = (user) => {
    const url = user.role === 'driver' ? `/drivers/${user.user_id}` : `/users/${user.user_id}`;
    window.open(url, '_blank');
  };

  const handleStatusChange = async (userId, newStatus) => {
    try {
      await axios.put(`${BASE_URL}/users/${userId}/status`, { is_active: newStatus });
      fetchUsers();
    } catch (error) {
      alert('Failed to update status: ' + (error.response?.data?.detail || error.message));
    }
  };

  const handleDeleteUser = async (userId) => {
    if (!window.confirm("Delete définitivement cet utilisateur ?")) return;
    try {
      await axios.delete(`${BASE_URL}/users/${userId}`);
      fetchUsers();
    } catch (error) {
      alert('Failed to delete user: ' + (error.response?.data?.detail || error.message));
    }
  };



  const filteredUsers = users.filter(u => {
    // 1. Role Filter
    if (filter === 'drivers' && u.role !== 'driver') return false;
    if (filter === 'commuters' && u.role !== 'commuter') return false;

    // 2. Status Filter
    const isActive = u.role === 'commuter' || u.is_active;
    if (statusFilter === 'active' && !isActive) return false;
    if (statusFilter === 'inactive' && isActive) return false;

    // 3. Search query (name, email, phone)
    if (searchQuery.trim() !== '') {
      const q = searchQuery.toLowerCase();
      const name = (u.full_name || '').toLowerCase();
      const email = (u.email || '').toLowerCase();
      const phone = (u.phone || '').toLowerCase();
      if (!name.includes(q) && !email.includes(q) && !phone.includes(q)) {
        return false;
      }
    }
    return true;
  });

  const unvalidatedDrivers = users.filter(u => u.role === 'driver' && !u.is_active);

  const tableStyle = {
    width: '100%', borderCollapse: 'collapse',
  };
  const thStyle = {
    padding: '10px 12px', textAlign: 'left', fontSize: '0.8rem',
    color: 'var(--text-secondary)', borderBottom: '1px solid rgba(255,255,255,0.08)',
    fontWeight: 600, letterSpacing: '0.05em', textTransform: 'uppercase'
  };

  if (loading) return (
    <div style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', height: '100%' }}>
      <div className="spinner" />
    </div>
  );

  return (
    <div>
      {/* Header */}
     <div
  style={{
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: '32px',
    flexWrap: 'wrap',
    gap: '16px'
  }}
>
  
  {/* Left */}
  <div>
    <h1 style={{ fontSize: '2rem', marginBottom: '8px' }}>
      Accounts Management
    </h1>

    <p style={{ color: 'var(--text-secondary)' }}>
      Validate, suspend or delete accounts.
    </p>
  </div>

  {/* Right */}
  <div
    style={{
      display: 'flex',
      gap: '12px',
      alignItems: 'center',
      flexWrap: 'wrap'
    }}
  >

    {/* Filter buttons */}
    {[
      ['all', 'All'],
      ['drivers', 'Drivers'],
      ['commuters', 'Clients']
    ].map(([val, label]) => (
      <button
        key={val}
        className={`btn ${filter === val ? 'btn-primary' : ''}`}
        style={
          filter !== val
            ? {
                border: '1px solid rgba(255,255,255,0.1)',
                color: 'var(--text-secondary)'
              }
            : {}
        }
        onClick={() => setFilter(val)}
      >
        {label}
      </button>
    ))}

    {/* Create Driver Button */}
    <button
      onClick={() => setShowCreateDriverModal(true)}
      style={{
        display: 'flex',
        alignItems: 'center',
        gap: '8px',
        padding: '10px 16px',
        fontSize: '0.95rem',
        backgroundColor: '#ffd000',
        color: '#070606',
        border: 'none',
        borderRadius: '8px',
        cursor: 'pointer',
        whiteSpace: 'nowrap'
      }}
    >
      + Create Driver
    </button>

  </div>
</div>

{/* Create Driver Modal */}
{showCreateDriverModal && (
  <div style={{
    position: 'fixed', top: 0, left: 0, right: 0, bottom: 0,
    backgroundColor: 'rgba(0,0,0,0.7)', display: 'flex', justifyContent: 'center', alignItems: 'center', zIndex: 1000
  }}>
    <div className="glass-panel" style={{ padding: '24px', width: '100%', maxWidth: '500px', backgroundColor: '#1a1a1a', maxHeight: '90vh', overflowY: 'auto' }}>
      <h2 style={{ marginBottom: '16px', color: 'white' }}>Create New Driver</h2>
      <form onSubmit={handleCreateDriver} style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
        
        {/* Texts */}
        <input 
          required placeholder="Full Name" value={newDriver.full_name}
          onChange={(e) => setNewDriver({...newDriver, full_name: e.target.value})}
          style={{ padding: '10px', borderRadius: '8px', backgroundColor: '#2a2a2a', color: 'white', border: '1px solid #333' }}
        />
        <input 
          required type="email" placeholder="Email" value={newDriver.email}
          onChange={(e) => setNewDriver({...newDriver, email: e.target.value})}
          style={{ padding: '10px', borderRadius: '8px', backgroundColor: '#2a2a2a', color: 'white', border: '1px solid #333' }}
        />
        <input 
          required placeholder="Phone (8 digits)" value={newDriver.phone}
          onChange={(e) => setNewDriver({...newDriver, phone: e.target.value})}
          style={{ padding: '10px', borderRadius: '8px', backgroundColor: '#2a2a2a', color: 'white', border: '1px solid #333' }}
        />
        <input 
          required type="password" placeholder="Password" value={newDriver.password}
          onChange={(e) => setNewDriver({...newDriver, password: e.target.value})}
          style={{ padding: '10px', borderRadius: '8px', backgroundColor: '#2a2a2a', color: 'white', border: '1px solid #333' }}
        />
        <input 
          required placeholder="License Number" value={newDriver.license_number}
          onChange={(e) => setNewDriver({...newDriver, license_number: e.target.value})}
          style={{ padding: '10px', borderRadius: '8px', backgroundColor: '#2a2a2a', color: 'white', border: '1px solid #333' }}
        />
        <input 
          required type="date" placeholder="License Expiry" value={newDriver.license_expiry}
          onChange={(e) => setNewDriver({...newDriver, license_expiry: e.target.value})}
          style={{ padding: '10px', borderRadius: '8px', backgroundColor: '#2a2a2a', color: 'white', border: '1px solid #333' }}
        />

        {/* Files */}
        <div style={{ marginTop: '8px' }}>
          <label style={{ color: 'var(--text-secondary)', fontSize: '0.85rem' }}>Profile Image (Optional):</label>
          <input 
            type="file" accept="image/*"
            onChange={(e) => setFiles({...files, profile_image: e.target.files[0]})}
            style={{ width: '100%', marginTop: '4px', color: 'white' }}
          />
        </div>
        <div style={{ marginTop: '4px' }}>
          <label style={{ color: 'var(--text-secondary)', fontSize: '0.85rem' }}>CIN Image (Required):</label>
          <input 
            required type="file" accept="image/*"
            onChange={(e) => setFiles({...files, cin_image: e.target.files[0]})}
            style={{ width: '100%', marginTop: '4px', color: 'white' }}
          />
        </div>
        <div style={{ marginTop: '4px' }}>
          <label style={{ color: 'var(--text-secondary)', fontSize: '0.85rem' }}>Driver Card Image (Required):</label>
          <input 
            required type="file" accept="image/*"
            onChange={(e) => setFiles({...files, driver_card_image: e.target.files[0]})}
            style={{ width: '100%', marginTop: '4px', color: 'white' }}
          />
        </div>

        <div style={{ display: 'flex', gap: '12px', marginTop: '16px' }}>
          <button type="button" onClick={() => setShowCreateDriverModal(false)} style={{ flex: 1, padding: '10px', borderRadius: '8px', backgroundColor: '#333', color: 'white', border: 'none', cursor: 'pointer' }}>Cancel</button>
          <button type="submit" disabled={creatingDriver} style={{ flex: 1, padding: '10px', borderRadius: '8px', backgroundColor: '#ffd000', color: 'black', border: 'none', cursor: 'pointer', fontWeight: 'bold' }}>
            {creatingDriver ? 'Creating...' : 'Create Driver'}
          </button>
        </div>
      </form>
    </div>
  </div>
)}

      {/* Filter Bar (Search + Status) */}
      <div className="glass-panel" style={{ padding: '16px 24px', marginBottom: '32px', display: 'flex', gap: '16px', alignItems: 'center', flexWrap: 'wrap' }}>
        <div style={{ flex: 1, minWidth: '260px', position: 'relative' }}>
          <input
            type="text"
            placeholder="Search by name, email or phone..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            style={{
              width: '100%',
              padding: '12px 16px',
              paddingLeft: '40px',
              borderRadius: '12px',
              backgroundColor: 'rgba(255,255,255,0.03)',
              border: '1px solid rgba(255,255,255,0.08)',
              color: '#ffffff',
              fontSize: '0.9rem',
              outline: 'none',
              transition: 'all 0.2s'
            }}
            onFocus={(e) => e.target.style.borderColor = 'var(--accent-color)'}
            onBlur={(e) => e.target.style.borderColor = 'rgba(255,255,255,0.08)'}
          />
          <span style={{ position: 'absolute', left: '14px', top: '50%', transform: 'translateY(-50%)', color: 'var(--text-secondary)', fontSize: '0.9rem' }}>
            🔍
          </span>
        </div>
        <div style={{ minWidth: '220px' }}>
          <select
            value={statusFilter}
            onChange={(e) => setStatusFilter(e.target.value)}
            style={{
              width: '100%',
              padding: '12px 16px',
              borderRadius: '12px',
              backgroundColor: 'rgba(255,255,255,0.03)',
              border: '1px solid rgba(255,255,255,0.08)',
              color: '#ffffff',
              fontSize: '0.9rem',
              outline: 'none',
              cursor: 'pointer',
              transition: 'all 0.2s'
            }}
            onFocus={(e) => e.target.style.borderColor = 'var(--accent-color)'}
            onBlur={(e) => e.target.style.borderColor = 'rgba(255,255,255,0.08)'}
          >
            <option value="all" style={{ backgroundColor: '#0f0f0f' }}>Status : All</option>
            <option value="active" style={{ backgroundColor: '#0f0f0f' }}>Status : Active</option>
            <option value="inactive" style={{ backgroundColor: '#0f0f0f' }}>Status : Suspendus / Pending</option>
          </select>
        </div>
      </div>

      {/* Unvalidated drivers banner */}
      {(filter === 'all' || filter === 'drivers') && unvalidatedDrivers.length > 0 && (
        <div className="glass-panel" style={{ padding: '24px', marginBottom: '32px', border: '1px dashed var(--accent-color)' }}>
          <h2 style={{ fontSize: '1.4rem', marginBottom: '16px', display: 'flex', alignItems: 'center', gap: '8px', color: '#fbbf24' }}>
            <ShieldAlert size={24} /> Drivers en attente de validation ({unvalidatedDrivers.length})
          </h2>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(280px, 1fr))', gap: '16px' }}>
            {unvalidatedDrivers.map(drv => (
              <div key={drv.user_id} className="glass-panel" style={{ padding: '16px', backgroundColor: 'rgba(255,255,255,0.02)', display: 'flex', flexDirection: 'column', justifyContent: 'space-between' }}>
                <div>
                  <h3 style={{ fontSize: '1.1rem', marginBottom: '6px' }}>{drv.full_name}</h3>
                  <p style={{ fontSize: '0.85rem', color: 'var(--text-secondary)', marginBottom: '4px' }}>{drv.email}</p>
                  <p style={{ fontSize: '0.85rem', color: 'var(--text-secondary)', marginBottom: '12px' }}>Tel: {drv.phone}</p>
                  <p style={{ fontSize: '0.85rem' }}><strong>License:</strong> {drv.license_number || 'N/A'}</p>
                </div>
                <div style={{ display: 'flex', gap: '8px', marginTop: '16px' }}>
                  <button className="btn btn-primary" style={{ flex: 1, padding: '8px', fontSize: '0.8rem' }} onClick={() => openDetails(drv)}>Inspect</button>
                  <button className="btn btn-success" style={{ padding: '8px 12px' }} onClick={() => handleStatusChange(drv.user_id, true)} title="Validate"><Check size={16} /></button>
                  <button className="btn btn-danger" style={{ padding: '8px 12px' }} onClick={() => handleDeleteUser(drv.user_id)} title="Reject"><X size={16} /></button>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Users Table */}
      <div className="glass-panel table-container" style={{ padding: '24px' }}>
        <table>
          <thead>
            <tr>
              <th>User</th>
              <th>Role</th>
              <th>Status</th>
              <th>Performance</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            {filteredUsers.map(user => (
              <tr key={user.user_id}>
                <td>
                  <div style={{ fontWeight: '600' }}>{user.full_name}</div>
                  <div style={{ fontSize: '0.85rem', color: 'var(--text-secondary)' }}>{user.email} | {user.phone}</div>
                </td>
                <td>
                  <span style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                    {user.role === 'driver' ? <Car size={14} color="var(--accent-color)" /> : <UserIcon size={14} />}
                    <span style={{ textTransform: 'capitalize', color: user.role === 'driver' ? 'var(--accent-color)' : 'var(--text-primary)' }}>{user.role}</span>
                  </span>
                </td>
                <td>
                  {user.role === 'commuter' || user.is_active
                    ? <span className="badge badge-active">Active</span>
                    : <span className="badge badge-pending">Suspendu / Pending</span>
                  }
                </td>
                <td>
                  {user.role === 'driver' ? (
                    <div style={{ fontSize: '0.9rem' }}>
                      ★ <span style={{ color: '#fbbf24' }}>{user.average_rating || '0.0'}</span> · {user.total_trips || 0} courses
                    </div>
                  ) : <span style={{ color: 'var(--text-secondary)', fontSize: '0.9rem' }}>Standard passenger</span>}
                </td>
                <td>
                  <div style={{ display: 'flex', gap: '8px' }}>
                    <button
                      className="btn btn-primary"
                      style={{ padding: '8px 14px', fontSize: '0.85rem', display: 'flex', alignItems: 'center', gap: 6 }}
                      onClick={() => openDetails(user)}
                    >
                      Details <ChevronRight size={14} />
                    </button>
                    {user.role === 'driver' && (
                      !user.is_active
                        ? <button className="btn btn-success" style={{ padding: '8px 14px', fontSize: '0.85rem' }} onClick={() => handleStatusChange(user.user_id, true)}><Check size={16} /> Validate</button>
                        : <button className="btn btn-danger" style={{ padding: '8px 14px', fontSize: '0.85rem' }} onClick={() => handleStatusChange(user.user_id, false)}><X size={16} /> Suspend</button>
                    )}
                    <button className="btn" style={{ backgroundColor: 'rgba(255,255,255,0.05)', border: '1px solid rgba(255,255,255,0.1)', padding: '8px' }} onClick={() => handleDeleteUser(user.user_id)} title="Delete"><Trash2 size={16} color="var(--danger)" /></button>
                  </div>
                </td>
              </tr>
            ))}
            {filteredUsers.length === 0 && (
              <tr><td colSpan="5" style={{ textAlign: 'center', padding: '40px', color: 'var(--text-secondary)' }}>
                <ShieldAlert size={48} style={{ margin: '0 auto 16px', opacity: 0.5 }} /><br />No account found.
              </td></tr>
            )}
          </tbody>
        </table>
      </div>


    </div>
  );
}
