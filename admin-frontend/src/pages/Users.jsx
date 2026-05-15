import { useState, useEffect } from 'react';
import axios from 'axios';
import { Check, X, ShieldAlert, Trash2 } from 'lucide-react';

const BASE_URL = 'http://127.0.0.1:8000/api/admin';

export default function UsersList() {
  const [users, setUsers] = useState([]);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState('all');
  const [selectedDriver, setSelectedDriver] = useState(null);

  useEffect(() => {
    fetchUsers();
  }, []);

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

  const handleStatusChange = async (userId, newStatus) => {
    console.log(`Sending PUT request to ${BASE_URL}/users/${userId}/status with`, { is_active: newStatus });
    try {
      const res = await axios.put(`${BASE_URL}/users/${userId}/status`, { is_active: newStatus });
      console.log('PUT response:', res.data);
      fetchUsers();
    } catch (error) {
      console.error('Error updating status:', error);
      alert('Failed to update status: ' + (error.response?.data?.detail || error.message));
    }
  };

  const handleDeleteUser = async (userId) => {
    console.log(`Sending DELETE request to ${BASE_URL}/users/${userId}`);
    try {
      const res = await axios.delete(`${BASE_URL}/users/${userId}`);
      console.log('DELETE response:', res.data);
      fetchUsers();
    } catch (error) {
      console.error('Error deleting user:', error);
      alert('Failed to delete user: ' + (error.response?.data?.detail || error.message));
    }
  };

  const filteredUsers = users.filter(u => {
    if (filter === 'drivers') return u.role === 'driver';
    if (filter === 'commuters') return u.role === 'commuter';
    return true;
  });

  if (loading) {
    return <div style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', height: '100%' }}>Loading...</div>;
  }

  return (
    <div>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '32px' }}>
        <div>
          <h1 style={{ fontSize: '2rem', marginBottom: '8px' }}>Accounts Management</h1>
          <p style={{ color: 'var(--text-secondary)' }}>Validate drivers, suspend or delete users.</p>
        </div>
        <div style={{ display: 'flex', gap: '12px' }}>
          <button 
            className={`btn ${filter === 'drivers' ? 'btn-primary' : ''}`} 
            style={filter !== 'drivers' ? { border: '1px solid rgba(255,255,255,0.1)', color: 'var(--text-secondary)' } : {}}
            onClick={() => setFilter('drivers')}
          >
            Chauffeurs
          </button>
          <button 
            className={`btn ${filter === 'commuters' ? 'btn-primary' : ''}`} 
            style={filter !== 'commuters' ? { border: '1px solid rgba(255,255,255,0.1)', color: 'var(--text-secondary)' } : {}}
            onClick={() => setFilter('commuters')}
          >
            Clients
          </button>
          <button 
            className={`btn ${filter === 'all' ? 'btn-primary' : ''}`} 
            style={filter !== 'all' ? { border: '1px solid rgba(255,255,255,0.1)', color: 'var(--text-secondary)' } : {}}
            onClick={() => setFilter('all')}
          >
            Tous
          </button>
        </div>
      </div>

      <div className="glass-panel table-container" style={{ padding: '24px' }}>
        <table>
          <thead>
            <tr>
              <th>User Info</th>
              <th>Role</th>
              <th>Status</th>
              <th>Performance / Info</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            {filteredUsers.map(user => (
              <tr key={user.user_id}>
                <td>
                  <div>
                    <div style={{ fontWeight: '600' }}>{user.full_name}</div>
                    <div style={{ fontSize: '0.85rem', color: 'var(--text-secondary)' }}>{user.email} | {user.phone}</div>
                  </div>
                </td>
                <td>
                  <span style={{ textTransform: 'capitalize', color: user.role === 'driver' ? 'var(--accent-color)' : 'var(--text-primary)' }}>
                    {user.role}
                  </span>
                </td>
                <td>
                  {user.role === 'commuter' || user.is_active ? (
                    <span className="badge badge-active">Active</span>
                  ) : (
                    <span className="badge badge-pending">Suspended / Pending</span>
                  )}
                </td>
                <td>
                  {user.role === 'driver' ? (
                    <div style={{ fontSize: '0.9rem' }}>
                      Licence: {user.license_number || 'N/A'}<br/>
                      <span style={{ color: '#fbbf24' }}>★ {user.average_rating || '0.0'}</span> ({user.total_trips} trips)
                    </div>
                  ) : (
                    <span style={{ color: 'var(--text-secondary)' }}>Standard User</span>
                  )}
                </td>
                <td>
                  <div style={{ display: 'flex', gap: '8px' }}>
                    {user.role === 'driver' && (
                      <>
                        <button 
                          className="btn btn-primary" 
                          style={{ padding: '8px 16px', fontSize: '0.85rem' }}
                          onClick={() => setSelectedDriver(user)}
                        >
                          Détails
                        </button>
                        {!user.is_active ? (
                          <button 
                            className="btn btn-success" 
                            style={{ padding: '8px 16px', fontSize: '0.85rem' }}
                            onClick={() => handleStatusChange(user.user_id, true)}
                          >
                            <Check size={16} /> Validate
                          </button>
                        ) : (
                          <button 
                            className="btn btn-danger" 
                            style={{ padding: '8px 16px', fontSize: '0.85rem' }}
                            onClick={() => handleStatusChange(user.user_id, false)}
                          >
                            <X size={16} /> Suspend
                          </button>
                        )}
                      </>
                    )}
                    <button 
                      className="btn" 
                      style={{ backgroundColor: 'rgba(255,255,255,0.05)', border: '1px solid rgba(255,255,255,0.1)', padding: '8px' }}
                      onClick={() => handleDeleteUser(user.user_id)}
                      title="Delete Permanently"
                    >
                      <Trash2 size={16} color="var(--danger)" />
                    </button>
                  </div>
                </td>
              </tr>
            ))}
            {filteredUsers.length === 0 && (
              <tr>
                <td colSpan="5" style={{ textAlign: 'center', padding: '40px', color: 'var(--text-secondary)' }}>
                  <ShieldAlert size={48} style={{ margin: '0 auto 16px', opacity: 0.5 }} />
                  No accounts found.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      {/* Modal pour les détails du chauffeur */}
      {selectedDriver && (
        <div style={{
          position: 'fixed',
          top: 0,
          left: 0,
          width: '100%',
          height: '100%',
          backgroundColor: 'rgba(0,0,0,0.8)',
          display: 'flex',
          justifyContent: 'center',
          alignItems: 'center',
          zIndex: 1000,
          padding: '20px'
        }}>
          <div className="glass-panel" style={{
            maxWidth: '800px',
            width: '100%',
            maxHeight: '90vh',
            overflowY: 'auto',
            padding: '32px',
            backgroundColor: '#0F0F0F',
            border: '1px solid var(--accent-color)'
          }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '24px' }}>
              <h2 style={{ fontSize: '1.8rem' }}>Détails du Chauffeur</h2>
              <button 
                className="btn" 
                style={{ backgroundColor: 'rgba(255,255,255,0.1)', padding: '8px' }}
                onClick={() => setSelectedDriver(null)}
              >
                <X size={24} />
              </button>
            </div>

            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '24px' }}>
              <div>
                <h3 style={{ fontSize: '1.2rem', marginBottom: '16px', color: 'var(--accent-color)' }}>Informations Personnelles</h3>
                <p><strong>Nom:</strong> {selectedDriver.full_name}</p>
                <p><strong>Email:</strong> {selectedDriver.email}</p>
                <p><strong>Téléphone:</strong> {selectedDriver.phone}</p>
                <p><strong>Statut:</strong> {selectedDriver.is_active ? 'Actif' : 'En attente/Suspendu'}</p>
              </div>
              <div>
                <h3 style={{ fontSize: '1.2rem', marginBottom: '16px', color: 'var(--accent-color)' }}>Informations Professionnelles</h3>
                <p><strong>N° Permis:</strong> {selectedDriver.license_number || 'N/A'}</p>
                <p><strong>Date d'expiration:</strong> {selectedDriver.license_expiry_date || 'N/A'}</p>
                <p><strong>Note moyenne:</strong> ★ {selectedDriver.average_rating || '5.0'}</p>
              </div>
            </div>

            <div style={{ marginTop: '24px' }}>
              <h3 style={{ fontSize: '1.2rem', marginBottom: '16px', color: 'var(--accent-color)' }}>Documents fournis</h3>
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '16px' }}>
                <div>
                  <p style={{ marginBottom: '8px' }}><strong>Photo CIN:</strong></p>
                  {selectedDriver.cin_card_photo ? (
                    <img 
                      src={selectedDriver.cin_card_photo.startsWith('http') ? selectedDriver.cin_card_photo : `http://127.0.0.1:8000/uploads/${selectedDriver.cin_card_photo}`} 
                      alt="CIN" 
                      style={{ width: '100%', borderRadius: '12px', border: '1px solid rgba(255,255,255,0.1)' }} 
                    />
                  ) : (
                    <div style={{ height: '150px', background: 'rgba(255,255,255,0.05)', borderRadius: '12px', display: 'flex', justifyContent: 'center', alignItems: 'center' }}>
                      Non fournie
                    </div>
                  )}
                </div>
                <div>
                  <p style={{ marginBottom: '8px' }}><strong>Photo Carte Pro:</strong></p>
                  {selectedDriver.driver_card_photo ? (
                    <img 
                      src={selectedDriver.driver_card_photo.startsWith('http') ? selectedDriver.driver_card_photo : `http://127.0.0.1:8000/uploads/${selectedDriver.driver_card_photo}`} 
                      alt="Carte Pro" 
                      style={{ width: '100%', borderRadius: '12px', border: '1px solid rgba(255,255,255,0.1)' }} 
                    />
                  ) : (
                    <div style={{ height: '150px', background: 'rgba(255,255,255,0.05)', borderRadius: '12px', display: 'flex', justifyContent: 'center', alignItems: 'center' }}>
                      Non fournie
                    </div>
                  )}
                </div>
              </div>
            </div>

            <div style={{ marginTop: '32px', display: 'flex', justifyContent: 'flex-end', gap: '12px' }}>
              {!selectedDriver.is_active ? (
                <button 
                  className="btn btn-success" 
                  onClick={() => {
                    handleStatusChange(selectedDriver.user_id, true);
                    setSelectedDriver(null);
                  }}
                >
                  <Check size={16} /> Valider le compte
                </button>
              ) : (
                <button 
                  className="btn btn-danger" 
                  onClick={() => {
                    handleStatusChange(selectedDriver.user_id, false);
                    setSelectedDriver(null);
                  }}
                >
                  <X size={16} /> Suspendre le compte
                </button>
              )}
              <button 
                className="btn" 
                style={{ backgroundColor: 'rgba(255,255,255,0.1)' }}
                onClick={() => setSelectedDriver(null)}
              >
                Fermer
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
