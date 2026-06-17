import { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import axios from 'axios';
import { User as UserIcon, ArrowLeft, ShieldAlert } from 'lucide-react';
import '../index.css';

const BASE_URL = 'http://127.0.0.1:8000/api/admin';

const getPhotoUrl = (path) => {
  if (!path) return null;
  if (path.startsWith('http')) return path;
  if (path.startsWith('/uploads/')) return `http://127.0.0.1:8000${path}`;
  return `http://127.0.0.1:8000/uploads/${path}`;
};

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

function RideRow({ ride }) {
  const date = ride.scheduled_for
    ? new Date(ride.scheduled_for).toLocaleString('fr-FR')
    : ride.requested_at
    ? new Date(ride.requested_at).toLocaleString('fr-FR')
    : '—';

  return (
    <tr>
      <td style={{ padding: '12px', color: 'var(--accent-color)', fontWeight: 600, whiteSpace: 'nowrap' }}>{ride.ref}</td>
      <td style={{ padding: '12px', fontSize: '0.85rem' }}>
        <div style={{ color: '#4ade80' }}>↑ {ride.pickup_location || '—'}</div>
        <div style={{ color: '#f87171', marginTop: 4 }}>↓ {ride.dropoff_location || '—'}</div>
      </td>
      <td style={{ padding: '12px', fontSize: '0.85rem', color: 'var(--text-secondary)' }}>{ride.driver_name || 'Unassigned'}</td>
      <td style={{ padding: '12px', fontSize: '0.8rem', color: 'var(--text-secondary)', whiteSpace: 'nowrap' }}>{date}</td>
      <td style={{ padding: '12px' }}><StatusBadge status={ride.status} /></td>
      <td style={{ padding: '12px', fontSize: '0.8rem', color: '#f87171' }}>{ride.cancellation_reason || ''}</td>
    </tr>
  );
}

function ReportRow({ report }) {
  const date = report.created_at ? new Date(report.created_at).toLocaleString('fr-FR') : '—';
  
  const getStatusColor = (status) => {
    switch(status) {
      case 'open': return '#f87171'; // red
      case 'in_progress': return '#fbbf24'; // yellow
      case 'resolved': return '#4ade80'; // green
      default: return '#a0a0a0';
    }
  };

  return (
    <tr>
      <td style={{ padding: '12px', color: 'var(--accent-color)', fontWeight: 600 }}>#{report.report_id}</td>
      <td style={{ padding: '12px', fontSize: '0.85rem' }}>{report.report_type}</td>
      <td style={{ padding: '12px', fontSize: '0.85rem' }}>{report.severity_level}</td>
      <td style={{ padding: '12px', fontSize: '0.8rem', color: 'var(--text-secondary)' }}>{date}</td>
      <td style={{ padding: '12px' }}>
        <span style={{
          display: 'inline-block', padding: '2px 8px', borderRadius: 12, fontSize: '0.75rem', fontWeight: 600,
          backgroundColor: getStatusColor(report.status) + '22',
          color: getStatusColor(report.status),
          border: `1px solid ${getStatusColor(report.status)}55`
        }}>
          {(report.status || '').toUpperCase()}
        </span>
      </td>
      <td style={{ padding: '12px', fontSize: '0.85rem', color: 'var(--text-secondary)' }}>{report.driver ? report.driver.name : '—'}</td>
    </tr>
  );
}

export default function UserDetails() {
  const { id } = useParams();
  const navigate = useNavigate();
  const [user, setUser] = useState(null);
  const [rides, setRides] = useState([]);
  const [reports, setReports] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [showEditModal, setShowEditModal] = useState(false);
  const [saving, setSaving] = useState(false);
  const [editData, setEditData] = useState({ full_name: '', email: '', phone: '', new_password: '', photoFile: null });

  useEffect(() => {
    fetchData();
  }, [id]);

  const fetchData = async () => {
    try {
      setLoading(true);
      // Fetch all users to find this one, as we are sure this endpoint exists
      const usersRes = await axios.get(`${BASE_URL}/users`);
      const foundUser = usersRes.data.find(u => String(u.user_id) === String(id));
      
      if (!foundUser) {
        setError('User non trouvé');
        setLoading(false);
        return;
      }
      setUser(foundUser);

      // Fetch rides
      const ridesRes = await axios.get(`${BASE_URL}/users/${id}/rides`);
      setRides(ridesRes.data);

      // Fetch reports
      const reportsRes = await axios.get(`${BASE_URL}/users/${id}/reports`);
      setReports(reportsRes.data);
    } catch (err) {
      console.error('Error fetching user details:', err);
      setError(`Erreur lors du chargement des données: ${err.response?.data?.detail || err.message}`);
    } finally {
      setLoading(false);
    }
  };

  const handleStatusChange = async (newStatus) => {
    try {
      await axios.put(`${BASE_URL}/users/${id}/status`, { is_active: newStatus });
      setUser(prev => ({ ...prev, is_active: newStatus }));
    } catch (error) {
      alert('Failed to update status: ' + (error.response?.data?.detail || error.message));
    }
  };

  const handleUpdateProfile = async (e) => {
    e.preventDefault();
    setSaving(true);
    try {
      // 1. Update info
      await axios.put(`${BASE_URL}/users/${id}`, {
        full_name: editData.full_name,
        email: editData.email,
        phone: editData.phone,
      });

      // 2. Update password if provided
      if (editData.new_password) {
        await axios.put(`${BASE_URL}/users/${id}/password`, {
          new_password: editData.new_password,
        });
      }

      // 3. Update photo if provided
      if (editData.photoFile) {
        const formData = new FormData();
        formData.append('file', editData.photoFile);
        await axios.post(`${BASE_URL}/users/${id}/photo`, formData, {
          headers: { 'Content-Type': 'multipart/form-data' },
        });
      }

      setShowEditModal(false);
      fetchData();
      alert('Profil mis à jour avec succès.');
    } catch (error) {
      alert('Erreur lors de la mise à jour: ' + (error.response?.data?.detail || error.message));
    } finally {
      setSaving(false);
    }
  };

  if (loading) {
    return (
      <div style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', height: '100vh', backgroundColor: '#0a0a0a' }}>
        <div className="spinner" />
      </div>
    );
  }

  if (error || !user) {
    return (
      <div style={{ padding: '40px', color: '#f87171', textAlign: 'center', backgroundColor: '#0a0a0a', minHeight: '100vh' }}>
        <ShieldAlert size={48} style={{ margin: '0 auto 16px', opacity: 0.8 }} />
        <h2>{error}</h2>
        <button className="btn" style={{ marginTop: '20px' }} onClick={() => navigate(-1)}>Back</button>
      </div>
    );
  }

  return (
    <div style={{ backgroundColor: '#0a0a0a', minHeight: '100vh', padding: '40px', color: '#ffffff' }}>
      {/* Header */}
      <div style={{ display: 'flex', alignItems: 'center', gap: '20px', marginBottom: '40px' }}>
        <div style={{ width: 72, height: 72, borderRadius: 18, overflow: 'hidden', border: '2px solid rgba(96,165,250,0.4)', boxShadow: '0 8px 24px rgba(37,99,235,0.2)', flexShrink: 0 }}>
          {user.image_url ? (
            <img
              src={getPhotoUrl(user.image_url)}
              alt={user.full_name}
              style={{ width: '100%', height: '100%', objectFit: 'cover' }}
            />
          ) : (
            <div style={{ width: '100%', height: '100%', background: 'linear-gradient(135deg, #60a5fa, #2563eb)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <UserIcon size={32} color="#fff" />
            </div>
          )}
        </div>
        <div style={{ flex: 1 }}>
          <h1 style={{ fontSize: '2.2rem', margin: '0 0 8px 0' }}>{user.full_name}</h1>
          <div style={{ display: 'flex', gap: '12px', alignItems: 'center' }}>
            <span style={{ color: 'var(--text-secondary)', fontSize: '1rem', textTransform: 'capitalize' }}>Passenger</span>
            <span style={{ color: 'var(--text-secondary)' }}>•</span>
            <span style={{ color: 'var(--text-secondary)', fontSize: '1rem' }}>{user.email}</span>
            <span style={{ color: 'var(--text-secondary)' }}>•</span>
            {user.is_active 
              ? <span className="badge badge-active">Active</span>
              : <span className="badge badge-pending">Suspendu</span>
            }
          </div>
        </div>
        <div style={{ display: 'flex', gap: '12px' }}>
          <button className="btn" style={{ backgroundColor: '#2563eb', color: '#fff' }} onClick={() => {
            setEditData({ full_name: user.full_name, email: user.email, phone: user.phone || '', new_password: '', photoFile: null });
            setShowEditModal(true);
          }}>
            Edit le Profil
          </button>
          {user.is_active ? (
            <button className="btn btn-danger" onClick={() => handleStatusChange(false)}>Suspend</button>
          ) : (
            <button className="btn btn-success" onClick={() => handleStatusChange(true)}>Activer</button>
          )}
        </div>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 2fr', gap: '32px' }}>
        {/* Left Column: Info */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: '24px' }}>
          <div className="glass-panel" style={{ padding: '24px' }}>
            <h2 style={{ fontSize: '1.2rem', marginBottom: '20px', color: 'var(--accent-color)', borderBottom: '1px solid rgba(255,255,255,0.1)', paddingBottom: '10px' }}>
              Informations Personnelles
            </h2>
            <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
              <div>
                <p style={{ color: 'var(--text-secondary)', fontSize: '0.85rem', marginBottom: '4px' }}>Name Complet</p>
                <p style={{ fontSize: '1.05rem', fontWeight: 500 }}>{user.full_name}</p>
              </div>
              <div>
                <p style={{ color: 'var(--text-secondary)', fontSize: '0.85rem', marginBottom: '4px' }}>Email</p>
                <p style={{ fontSize: '1.05rem', fontWeight: 500 }}>{user.email}</p>
              </div>
              <div>
                <p style={{ color: 'var(--text-secondary)', fontSize: '0.85rem', marginBottom: '4px' }}>Phone</p>
                <p style={{ fontSize: '1.05rem', fontWeight: 500 }}>{user.phone || 'No renseigné'}</p>
              </div>
              <div>
                <p style={{ color: 'var(--text-secondary)', fontSize: '0.85rem', marginBottom: '4px' }}>Date d'inscription</p>
                <p style={{ fontSize: '1.05rem', fontWeight: 500 }}>{user.created_at ? new Date(user.created_at).toLocaleDateString('fr-FR') : '—'}</p>
              </div>
            </div>
          </div>

          <div className="glass-panel" style={{ padding: '24px' }}>
            <h2 style={{ fontSize: '1.2rem', marginBottom: '20px', color: 'var(--accent-color)', borderBottom: '1px solid rgba(255,255,255,0.1)', paddingBottom: '10px' }}>
              Statistiques
            </h2>
            <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
              <div>
                <p style={{ color: 'var(--text-secondary)', fontSize: '0.85rem', marginBottom: '4px' }}>Total des demandes</p>
                <p style={{ fontSize: '1.5rem', fontWeight: 700 }}>{Array.isArray(rides) ? rides.length : 0}</p>
              </div>
              <div>
                <p style={{ color: 'var(--text-secondary)', fontSize: '0.85rem', marginBottom: '4px' }}>Rides complétées</p>
                <p style={{ fontSize: '1.5rem', fontWeight: 700, color: '#4ade80' }}>
                  {Array.isArray(rides) ? rides.filter(r => r.status === 'COMPLETED').length : 0}
                </p>
              </div>
            </div>
          </div>
        </div>

        {/* Right Column: Rides History & Reports */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: '24px' }}>
          <div className="glass-panel" style={{ padding: '24px' }}>
            <h2 style={{ fontSize: '1.4rem', marginBottom: '20px', display: 'flex', alignItems: 'center', gap: '12px' }}>
              📋 Historique des Demandes
            </h2>
            
            {Array.isArray(rides) && rides.length > 0 ? (
              <div style={{ overflowX: 'auto' }}>
                <table style={{ width: '100%', borderCollapse: 'collapse' }}>
                  <thead>
                    <tr style={{ borderBottom: '1px solid rgba(255,255,255,0.1)' }}>
                      {['Réf', 'Ride', 'Driver', 'Date', 'Status', 'Raison (Si annulé)'].map(h => (
                        <th key={h} style={{ padding: '12px', textAlign: 'left', fontSize: '0.85rem', color: 'var(--text-secondary)', textTransform: 'uppercase', letterSpacing: '0.05em' }}>{h}</th>
                      ))}
                    </tr>
                  </thead>
                  <tbody>
                    {rides.map(r => <RideRow key={r.request_id} ride={r} />)}
                  </tbody>
                </table>
              </div>
            ) : (
              <div style={{ textAlign: 'center', padding: '60px 20px', color: 'var(--text-secondary)' }}>
                <p style={{ fontSize: '1.1rem' }}>Aucun historique de demande disponible pour cet utilisateur.</p>
              </div>
            )}
          </div>

          <div className="glass-panel" style={{ padding: '24px' }}>
            <h2 style={{ fontSize: '1.4rem', marginBottom: '20px', display: 'flex', alignItems: 'center', gap: '12px', color: '#f87171' }}>
              ⚠️ Signalements & Réclamations
            </h2>
            
            {Array.isArray(reports) && reports.length > 0 ? (
              <div style={{ overflowX: 'auto' }}>
                <table style={{ width: '100%', borderCollapse: 'collapse' }}>
                  <thead>
                    <tr style={{ borderBottom: '1px solid rgba(255,255,255,0.1)' }}>
                      {['ID', 'Type', 'Sévérité', 'Date', 'Status', 'Driver'].map(h => (
                        <th key={h} style={{ padding: '12px', textAlign: 'left', fontSize: '0.85rem', color: 'var(--text-secondary)', textTransform: 'uppercase', letterSpacing: '0.05em' }}>{h}</th>
                      ))}
                    </tr>
                  </thead>
                  <tbody>
                    {reports.map(r => <ReportRow key={r.report_id} report={r} />)}
                  </tbody>
                </table>
              </div>
            ) : (
              <div style={{ textAlign: 'center', padding: '40px 20px', color: 'var(--text-secondary)' }}>
                <p style={{ fontSize: '1.1rem' }}>Aucun signalement soumis par cet utilisateur.</p>
              </div>
            )}
          </div>
        </div>
      </div>

      {showEditModal && (
        <div style={{ position: 'fixed', inset: 0, zIndex: 1000, background: 'rgba(0,0,0,0.8)', display: 'flex', alignItems: 'center', justifyContent: 'center' }} onClick={() => setShowEditModal(false)}>
          <div style={{ background: '#111', padding: '30px', borderRadius: '16px', width: '400px', border: '1px solid #333' }} onClick={e => e.stopPropagation()}>
            <h2 style={{ marginBottom: '20px' }}>Edit Profil</h2>
            <form onSubmit={handleUpdateProfile} style={{ display: 'flex', flexDirection: 'column', gap: '15px' }}>
              <div>
                <label style={{ fontSize: '0.8rem', color: '#888' }}>Name complet</label>
                <input type="text" className="form-control" value={editData.full_name} onChange={e => setEditData({...editData, full_name: e.target.value})} required style={{ background: '#222', border: '1px solid #444', color: '#fff', padding: '10px', borderRadius: '8px', width: '100%' }} />
              </div>
              <div>
                <label style={{ fontSize: '0.8rem', color: '#888' }}>Email</label>
                <input type="email" className="form-control" value={editData.email} onChange={e => setEditData({...editData, email: e.target.value})} required style={{ background: '#222', border: '1px solid #444', color: '#fff', padding: '10px', borderRadius: '8px', width: '100%' }} />
              </div>
              <div>
                <label style={{ fontSize: '0.8rem', color: '#888' }}>Phone</label>
                <input type="text" className="form-control" value={editData.phone} onChange={e => setEditData({...editData, phone: e.target.value})} style={{ background: '#222', border: '1px solid #444', color: '#fff', padding: '10px', borderRadius: '8px', width: '100%' }} />
              </div>
              <div>
                <label style={{ fontSize: '0.8rem', color: '#888' }}>Nouveau Password (Optionnel)</label>
                <input type="password" placeholder="Laisser vide pour ne pas changer" className="form-control" value={editData.new_password} onChange={e => setEditData({...editData, new_password: e.target.value})} style={{ background: '#222', border: '1px solid #444', color: '#fff', padding: '10px', borderRadius: '8px', width: '100%' }} />
              </div>
              <div>
                <label style={{ fontSize: '0.8rem', color: '#888' }}>Nouvelle Photo de profil (Optionnel)</label>
                <input type="file" accept="image/*" onChange={e => setEditData({...editData, photoFile: e.target.files[0]})} style={{ width: '100%', fontSize: '0.9rem' }} />
              </div>
              <div style={{ display: 'flex', gap: '10px', marginTop: '10px' }}>
                <button type="button" className="btn btn-secondary" style={{ flex: 1 }} onClick={() => setShowEditModal(false)}>Cancel</button>
                <button type="submit" className="btn btn-success" style={{ flex: 1 }} disabled={saving}>{saving ? 'Enregistrement...' : 'Save'}</button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
