import { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import axios from 'axios';
import { Car, ShieldAlert, Check, X, FileText } from 'lucide-react';
import '../index.css';

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
      padding: '4px 12px',
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
      <td style={{ padding: '12px', fontSize: '0.85rem', color: 'var(--text-secondary)' }}>{ride.passenger_name || '—'}</td>
      <td style={{ padding: '12px', fontSize: '0.8rem', color: 'var(--text-secondary)', whiteSpace: 'nowrap' }}>{date}</td>
      <td style={{ padding: '12px' }}><StatusBadge status={ride.status} /></td>
    </tr>
  );
}

export default function DriverDetails() {
  const { id } = useParams();
  const navigate = useNavigate();
  const [driver, setDriver] = useState(null);
  const [taxi, setTaxi] = useState(null);
  const [rides, setRides] = useState({ active: [], completed: [] });
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [showEditModal, setShowEditModal] = useState(false);
  const [saving, setSaving] = useState(false);
  const [editData, setEditData] = useState({ full_name: '', email: '', phone: '', new_password: '', photoFile: null, license_number: '', plate_number: '', vehicle_model: '' });

  const getDocumentUrl = (path) => {
    if (!path) return '';
    if (path.startsWith('http')) return path;
    if (path.startsWith('/uploads/')) return `http://127.0.0.1:8000${path}`;
    return `http://127.0.0.1:8000/uploads/${path}`;
  };

  useEffect(() => {
    fetchData();
  }, [id]);

  const fetchData = async () => {
    try {
      setLoading(true);
      const usersRes = await axios.get(`${BASE_URL}/users`);
      const foundDriver = usersRes.data.find(u => String(u.user_id) === String(id) && u.role === 'driver');
      
      if (!foundDriver) {
        setError('Driver non trouvé');
        setLoading(false);
        return;
      }
      setDriver(foundDriver);

      // Fetch taxi info
      try {
        const taxisRes = await axios.get(`${BASE_URL}/taxis`);
        const foundTaxi = taxisRes.data.find(t => String(t.driver_id) === String(id));
        setTaxi(foundTaxi || null);
      } catch (_) {}

      const ridesRes = await axios.get(`${BASE_URL}/users/${id}/driver-rides`);
      setRides(ridesRes.data || { active: [], completed: [] });
    } catch (err) {
      console.error('Error fetching driver details:', err);
      setError(`Erreur lors du chargement des données: ${err.response?.data?.detail || err.message}`);
    } finally {
      setLoading(false);
    }
  };

  const handleStatusChange = async (newStatus) => {
    try {
      await axios.put(`${BASE_URL}/users/${id}/status`, { is_active: newStatus });
      setDriver(prev => ({ ...prev, is_active: newStatus }));
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
        license_number: editData.license_number,
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

      // 4. Update taxi info if provided
      if (editData.plate_number || editData.vehicle_model) {
        await axios.put(`${BASE_URL}/drivers/${id}/taxi`, {
          plate_number: editData.plate_number || undefined,
          vehicle_model: editData.vehicle_model || undefined,
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

  if (error || !driver) {
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
      <div style={{ display: 'flex', alignItems: 'center', gap: '24px', marginBottom: '40px' }}>
        <div style={{ width: 80, height: 80, borderRadius: 20, overflow: 'hidden', boxShadow: '0 8px 32px rgba(255, 204, 0, 0.2)', border: '2px solid rgba(255,204,0,0.4)', flexShrink: 0 }}>
          {driver.image_url ? (
            <img
              src={getDocumentUrl(driver.image_url)}
              alt={driver.full_name}
              style={{ width: '100%', height: '100%', objectFit: 'cover' }}
            />
          ) : (
            <div style={{ width: '100%', height: '100%', background: 'linear-gradient(135deg, #FFCC00, #b38f00)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <Car size={40} color="#000" />
            </div>
          )}
        </div>
        <div style={{ flex: 1 }}>
          <h1 style={{ fontSize: '2.5rem', margin: '0 0 8px 0', letterSpacing: '-0.5px' }}>{driver.full_name}</h1>
          <div style={{ display: 'flex', gap: '16px', alignItems: 'center' }}>
            <span style={{ color: 'var(--accent-color)', fontSize: '1.1rem', fontWeight: 600 }}>Driver</span>
            <span style={{ color: 'rgba(255,255,255,0.3)' }}>|</span>
            <span style={{ color: 'var(--text-secondary)', fontSize: '1.1rem' }}>{driver.email}</span>
            <span style={{ color: 'rgba(255,255,255,0.3)' }}>|</span>
            {driver.is_active 
              ? <span className="badge badge-active" style={{ fontSize: '0.9rem', padding: '6px 14px' }}>Compte Validé</span>
              : <span className="badge badge-pending" style={{ fontSize: '0.9rem', padding: '6px 14px' }}>Pending d'approbation</span>
            }
          </div>
        </div>
        <div style={{ display: 'flex', gap: '16px' }}>
          <button className="btn" style={{ backgroundColor: '#2563eb', color: '#fff', padding: '12px 24px', fontSize: '1rem', display: 'flex', alignItems: 'center', gap: '8px' }} onClick={() => {
            setEditData({
              full_name: driver.full_name,
              email: driver.email,
              phone: driver.phone || '',
              license_number: driver.license_number || '',
              new_password: '',
              photoFile: null,
              plate_number: taxi?.plate_number || '',
              vehicle_model: taxi?.vehicle_model || '',
            });
            setShowEditModal(true);
          }}>
            Edit Profil
          </button>
          {!driver.is_active ? (
            <button className="btn btn-success" style={{ padding: '12px 24px', fontSize: '1rem', display: 'flex', alignItems: 'center', gap: '8px' }} onClick={() => handleStatusChange(true)}>
              <Check size={20} /> Validate le chauffeur
            </button>
          ) : (
            <button className="btn btn-danger" style={{ padding: '12px 24px', fontSize: '1rem', display: 'flex', alignItems: 'center', gap: '8px' }} onClick={() => handleStatusChange(false)}>
              <X size={20} /> Suspend
            </button>
          )}
        </div>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '32px', marginBottom: '32px' }}>
        {/* Info Box */}
        <div className="glass-panel" style={{ padding: '32px' }}>
          <h2 style={{ fontSize: '1.3rem', marginBottom: '24px', color: 'var(--accent-color)', borderBottom: '1px solid rgba(255,255,255,0.1)', paddingBottom: '12px' }}>
            Informations Professionnelles
          </h2>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '24px' }}>
            <div>
              <p style={{ color: 'var(--text-secondary)', fontSize: '0.9rem', marginBottom: '6px' }}>Phone</p>
              <p style={{ fontSize: '1.1rem', fontWeight: 500 }}>{driver.phone || 'N/A'}</p>
            </div>
            <div>
              <p style={{ color: 'var(--text-secondary)', fontSize: '0.9rem', marginBottom: '6px' }}>Numéro de Permis</p>
              <p style={{ fontSize: '1.1rem', fontWeight: 500 }}>{driver.license_number || 'N/A'}</p>
            </div>
            <div>
              <p style={{ color: 'var(--text-secondary)', fontSize: '0.9rem', marginBottom: '6px' }}>Note Moyenne</p>
              <p style={{ fontSize: '1.3rem', fontWeight: 700, color: '#fbbf24' }}>★ {driver.average_rating || 'N/A'}</p>
            </div>
            <div>
              <p style={{ color: 'var(--text-secondary)', fontSize: '0.9rem', marginBottom: '6px' }}>Total Rideses</p>
              <p style={{ fontSize: '1.3rem', fontWeight: 700 }}>{driver.total_trips || 0}</p>
            </div>
          </div>
        </div>

        {/* Documents Box */}
        <div className="glass-panel" style={{ padding: '32px' }}>
          <h2 style={{ fontSize: '1.3rem', marginBottom: '24px', color: 'var(--accent-color)', borderBottom: '1px solid rgba(255,255,255,0.1)', paddingBottom: '12px', display: 'flex', alignItems: 'center', gap: '8px' }}>
            <FileText size={20} /> Documents Téléchargés
          </h2>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '24px' }}>
            <div>
              <p style={{ marginBottom: '12px', fontWeight: 600, color: 'var(--text-secondary)' }}>Carte d'identité (CIN)</p>
              {driver.cin_card_photo ? (
                <a href={getDocumentUrl(driver.cin_card_photo)} target="_blank" rel="noreferrer">
                  <img src={getDocumentUrl(driver.cin_card_photo)} alt="CIN" style={{ width: '100%', height: '140px', objectFit: 'cover', borderRadius: '12px', border: '2px solid rgba(255,255,255,0.1)', transition: 'transform 0.2s', cursor: 'pointer' }} onMouseOver={e => e.currentTarget.style.transform = 'scale(1.02)'} onMouseOut={e => e.currentTarget.style.transform = 'scale(1)'} />
                </a>
              ) : (
                <div style={{ height: '140px', background: 'rgba(255,255,255,0.02)', borderRadius: '12px', border: '2px dashed rgba(255,255,255,0.1)', display: 'flex', justifyContent: 'center', alignItems: 'center', color: 'var(--text-secondary)' }}>No fournie</div>
              )}
            </div>
            <div>
              <p style={{ marginBottom: '12px', fontWeight: 600, color: 'var(--text-secondary)' }}>Carte Professionnelle</p>
              {driver.driver_card_photo ? (
                <a href={getDocumentUrl(driver.driver_card_photo)} target="_blank" rel="noreferrer">
                  <img src={getDocumentUrl(driver.driver_card_photo)} alt="Carte Pro" style={{ width: '100%', height: '140px', objectFit: 'cover', borderRadius: '12px', border: '2px solid rgba(255,255,255,0.1)', transition: 'transform 0.2s', cursor: 'pointer' }} onMouseOver={e => e.currentTarget.style.transform = 'scale(1.02)'} onMouseOut={e => e.currentTarget.style.transform = 'scale(1)'} />
                </a>
              ) : (
                <div style={{ height: '140px', background: 'rgba(255,255,255,0.02)', borderRadius: '12px', border: '2px dashed rgba(255,255,255,0.1)', display: 'flex', justifyContent: 'center', alignItems: 'center', color: 'var(--text-secondary)' }}>No fournie</div>
              )}
            </div>
          </div>
        </div>
      </div>

      {/* Rides History */}
      <div className="glass-panel" style={{ padding: '32px' }}>
        <h2 style={{ fontSize: '1.5rem', marginBottom: '32px', display: 'flex', alignItems: 'center', gap: '12px' }}>
          🚕 Historique des Rides
        </h2>

        {/* Active Rides */}
        <div style={{ marginBottom: '40px' }}>
          <h3 style={{ fontSize: '1.1rem', marginBottom: '16px', color: '#FFCC00', display: 'flex', alignItems: 'center', gap: '8px' }}>
            🟡 Rides Accepted / En cours ({rides.active?.length || 0})
          </h3>
          {rides.active?.length > 0 ? (
            <div style={{ overflowX: 'auto' }}>
              <table style={{ width: '100%', borderCollapse: 'collapse' }}>
                <thead>
                  <tr style={{ borderBottom: '1px solid rgba(255,255,255,0.1)' }}>
                    {['Réf', 'Ride', 'Passenger', 'Date', 'Status'].map(h => <th key={h} style={{ padding: '12px', textAlign: 'left', fontSize: '0.85rem', color: 'var(--text-secondary)', textTransform: 'uppercase' }}>{h}</th>)}
                  </tr>
                </thead>
                <tbody>
                  {rides.active.map(r => <RideRow key={r.request_id} ride={r} />)}
                </tbody>
              </table>
            </div>
          ) : <p style={{ color: 'var(--text-secondary)', padding: '16px 0' }}>Aucune course active actuellement.</p>}
        </div>

        {/* Completed Rides */}
        <div>
          <h3 style={{ fontSize: '1.1rem', marginBottom: '16px', color: '#4ade80', display: 'flex', alignItems: 'center', gap: '8px' }}>
            ✅ Rides Finalisées ({rides.completed?.length || 0})
          </h3>
          {rides.completed?.length > 0 ? (
            <div style={{ overflowX: 'auto' }}>
              <table style={{ width: '100%', borderCollapse: 'collapse' }}>
                <thead>
                  <tr style={{ borderBottom: '1px solid rgba(255,255,255,0.1)' }}>
                    {['Réf', 'Ride', 'Passenger', 'Date', 'Status'].map(h => <th key={h} style={{ padding: '12px', textAlign: 'left', fontSize: '0.85rem', color: 'var(--text-secondary)', textTransform: 'uppercase' }}>{h}</th>)}
                  </tr>
                </thead>
                <tbody>
                  {rides.completed.map(r => <RideRow key={r.request_id} ride={r} />)}
                </tbody>
              </table>
            </div>
          ) : <p style={{ color: 'var(--text-secondary)', padding: '16px 0' }}>Aucune course complétée trouvée.</p>}
        </div>
      </div>

      {showEditModal && (
        <div style={{ position: 'fixed', inset: 0, zIndex: 1000, background: 'rgba(0,0,0,0.8)', display: 'flex', alignItems: 'center', justifyContent: 'center' }} onClick={() => setShowEditModal(false)}>
          <div style={{ background: '#111', padding: '30px', borderRadius: '16px', width: '400px', border: '1px solid #333' }} onClick={e => e.stopPropagation()}>
            <h2 style={{ marginBottom: '20px' }}>Edit Profil Driver</h2>
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
                <label style={{ fontSize: '0.8rem', color: '#888' }}>Numéro de Permis</label>
                <input type="text" className="form-control" value={editData.license_number} onChange={e => setEditData({...editData, license_number: e.target.value})} style={{ background: '#222', border: '1px solid #444', color: '#fff', padding: '10px', borderRadius: '8px', width: '100%' }} />
              </div>
              <div>
                <label style={{ fontSize: '0.8rem', color: '#888' }}>Nouveau Password (Optionnel)</label>
                <input type="password" placeholder="Laisser vide pour ne pas changer" className="form-control" value={editData.new_password} onChange={e => setEditData({...editData, new_password: e.target.value})} style={{ background: '#222', border: '1px solid #444', color: '#fff', padding: '10px', borderRadius: '8px', width: '100%' }} />
              </div>
              <div>
                <label style={{ fontSize: '0.8rem', color: '#888' }}>Nouvelle Photo de profil (Optionnel)</label>
                <input type="file" accept="image/*" onChange={e => setEditData({...editData, photoFile: e.target.files[0]})} style={{ width: '100%', fontSize: '0.9rem' }} />
              </div>

              {/* Vehicle Section */}
              <div style={{ borderTop: '1px solid #333', paddingTop: '15px' }}>
                <p style={{ fontSize: '0.85rem', color: 'var(--accent-color)', fontWeight: '600', marginBottom: '12px' }}>🚕 Informations Véhicule</p>
                <div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
                  <div>
                    <label style={{ fontSize: '0.8rem', color: '#888' }}>Plaque d'immatriculation</label>
                    <input type="text" className="form-control" value={editData.plate_number} onChange={e => setEditData({...editData, plate_number: e.target.value})} style={{ background: '#222', border: '1px solid #444', color: '#fff', padding: '10px', borderRadius: '8px', width: '100%' }} />
                  </div>
                  <div>
                    <label style={{ fontSize: '0.8rem', color: '#888' }}>Modèle du véhicule</label>
                    <input type="text" className="form-control" value={editData.vehicle_model} onChange={e => setEditData({...editData, vehicle_model: e.target.value})} style={{ background: '#222', border: '1px solid #444', color: '#fff', padding: '10px', borderRadius: '8px', width: '100%' }} />
                  </div>
                </div>
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
