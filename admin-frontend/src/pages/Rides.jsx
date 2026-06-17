import { useState, useEffect, useMemo, useCallback } from 'react';
import axios from 'axios';
import { MapPin, Navigation, Send, RefreshCw, Calendar, DollarSign, Repeat, X, ChevronRight, User, Car } from 'lucide-react';

const BASE_URL = 'http://127.0.0.1:8000/api/admin';

export default function Rides() {
  const [rides, setRides] = useState([]);
  const [recurringRides, setRecurringRides] = useState([]);
  const [taxis, setTaxis] = useState([]);
  const [loading, setLoading] = useState(true);
  const [selectedTaxiId, setSelectedTaxiId] = useState({});
  const [activeTab, setActiveTab] = useState('single'); // 'single' | 'recurring'

  // Modal: détail des courses d'un planning récurrent
  const [selectedSchedule, setSelectedSchedule] = useState(null);
  const [scheduleRides, setScheduleRides] = useState([]);
  const [modalLoading, setModalLoading] = useState(false);
  const [modalTaxiId, setModalTaxiId] = useState({}); // taxi sélectionné par ride dans le modal
  const [newRideDate, setNewRideDate] = useState(''); // datetime for new ride
  const [newTaxiId, setNewTaxiId] = useState(''); // taxi for new ride


  useEffect(() => {
    fetchData();
  }, []);

  const fetchData = async () => {
    setLoading(true);
    try {
      const [ridesRes, taxisRes, recurringRes] = await Promise.all([
        axios.get(`${BASE_URL}/rides`),
        axios.get(`${BASE_URL}/taxis`),
        axios.get(`${BASE_URL}/recurring-rides`),
      ]);
      setRides(ridesRes.data);
      setTaxis(taxisRes.data);
      setRecurringRides(recurringRes.data);
    } catch (error) {
      console.error('Error fetching data:', error);
    } finally {
      setLoading(false);
    }
  };

  const handleAssign = async (requestId) => {
    const taxiId = selectedTaxiId[requestId];
    if (!taxiId) {
      alert('Please select a taxi first');
      return;
    }
    try {
      await axios.post(`${BASE_URL}/rides/${requestId}/assign`, { taxi_id: parseInt(taxiId) });
      alert('Ride assigned successfully');
      fetchData();
    } catch (error) {
      console.error('Error assigning ride:', error);
      alert('Failed to assign ride');
    }
  };

  // Assignation depuis le modal d'une course récurrente
  const handleAssignInModal = async (requestId) => {
    const taxiId = modalTaxiId[requestId];
    if (!taxiId) {
      alert('Veuillez sélectionner un chauffeur d\'abord');
      return;
    }
    try {
      await axios.post(`${BASE_URL}/rides/${requestId}/assign`, { taxi_id: parseInt(taxiId) });
      // Rafraîchir uniquement les courses du modal
      setModalTaxiId(prev => { const n = {...prev}; delete n[requestId]; return n; });
      if (selectedSchedule) {
        const ids = selectedSchedule.schedule_ids || [selectedSchedule.schedule_id];
        const allRides = [];
        await Promise.all(ids.map(async (sid) => {
          const res = await axios.get(`${BASE_URL}/recurring-rides/${sid}/rides`);
          allRides.push(...res.data);
        }));
        allRides.sort((a, b) => new Date(a.scheduled_for || 0) - new Date(b.scheduled_for || 0));
        setScheduleRides(allRides);
      }
      fetchData(); // met à jour les compteurs globaux
    } catch (error) {
      console.error('Error assigning ride in modal:', error);
      alert('Échec de l\'assignation');
    }
  };

  // Crée une ride individuelle depuis le planning et l'assigne immédiatement
  const handleCreateAndAssign = async () => {
    if (!newRideDate || !newTaxiId) {
      alert('Veuillez choisir une date et un chauffeur');
      return;
    }
    try {
      await axios.post(`${BASE_URL}/recurring-rides/${selectedSchedule.schedule_id}/create-ride`, {
        scheduled_for: newRideDate,
        taxi_id: parseInt(newTaxiId),
      });
      // Recharger les rides du modal
      const ids = selectedSchedule.schedule_ids || [selectedSchedule.schedule_id];
      const allRides = [];
      await Promise.all(ids.map(async (sid) => {
        const res = await axios.get(`${BASE_URL}/recurring-rides/${sid}/rides`);
        allRides.push(...res.data);
      }));
      allRides.sort((a, b) => new Date(a.scheduled_for || 0) - new Date(b.scheduled_for || 0));
      setScheduleRides(allRides);
      // Reset form fields
      setNewRideDate('');
      setNewTaxiId('');
      fetchData(); // mettre à jour les compteurs globaux
    } catch (error) {
      console.error('Error creating and assigning ride:', error);
      alert('Échec de la création/assignation');
    }
  };

  const getStatusBadge = (status) => {
    switch (status?.toLowerCase()) {
      case 'pending': return <span className="badge badge-pending">Pending</span>;
      case 'accepted': return <span className="badge badge-active">Accepted</span>;
      case 'completed': return <span className="badge badge-inactive">Completed</span>;
      case 'cancelled': return <span className="badge" style={{ background: 'rgba(239,68,68,0.15)', color: '#ef4444' }}>Cancelled</span>;
      default: return <span className="badge">{status}</span>;
    }
  };

  const openScheduleModal = useCallback(async (schedule) => {
    setSelectedSchedule(schedule);
    setScheduleRides([]);
    setModalLoading(true);
    try {
      // Fetch all schedule_ids grouped under this schedule row
      const ids = schedule.schedule_ids || [schedule.schedule_id];
      const allRides = [];
      await Promise.all(ids.map(async (sid) => {
        const res = await axios.get(`${BASE_URL}/recurring-rides/${sid}/rides`);
        allRides.push(...res.data);
      }));
      // Sort by scheduled_for ascending
      allRides.sort((a, b) => new Date(a.scheduled_for || 0) - new Date(b.scheduled_for || 0));
      setScheduleRides(allRides);
    } catch (err) {
      console.error('Error fetching schedule rides:', err);
    } finally {
      setModalLoading(false);
    }
  }, []);

  const closeModal = useCallback(() => {
    setSelectedSchedule(null);
    setScheduleRides([]);
  }, []);

  // Close modal on ESC
  useEffect(() => {
    const onKey = (e) => { if (e.key === 'Escape') closeModal(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [closeModal]);

  const tabStyle = (tab) => ({
    padding: '10px 24px',
    borderRadius: '8px',
    border: 'none',
    cursor: 'pointer',
    fontWeight: '600',
    fontSize: '0.95rem',
    transition: 'all 0.2s',
    background: activeTab === tab ? 'var(--accent-color)' : 'transparent',
    color: activeTab === tab ? '#000' : 'var(--text-secondary)',
    borderBottom: activeTab === tab ? '2px solid var(--accent-color)' : '2px solid transparent',
  });

  // Grouper les courses récurrentes par client, date et trajet
  const groupedRecurringRides = useMemo(() => {
    const groups = {};
    recurringRides.forEach(s => {
      const key = `${s.client_id}_${s.start_date}_${s.end_date}_${s.pickup_location}_${s.dropoff_location}_${s.pickup_time}`;
      if (!groups[key]) {
        groups[key] = {
          ...s,
          days_of_week: [s.day_of_week],
          schedule_ids: [s.schedule_id],
          total_nb_occurrences: s.nb_occurrences || 0,
          total_period_price_sum: s.total_period_price || 0,
        };
      } else {
        groups[key].days_of_week.push(s.day_of_week);
        groups[key].schedule_ids.push(s.schedule_id);
        groups[key].total_nb_occurrences += s.nb_occurrences || 0;
        groups[key].total_period_price_sum += s.total_period_price || 0;
      }
    });
    return Object.values(groups);
  }, [recurringRides]);

  if (loading) {
    return (
      <div style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', height: '100%' }}>
        <div style={{ textAlign: 'center' }}>
          <RefreshCw size={32} style={{ animation: 'spin 1s linear infinite', color: 'var(--accent-color)' }} />
          <p style={{ marginTop: '12px', color: 'var(--text-secondary)' }}>Loading rides...</p>
        </div>
      </div>
    );
  }

  return (
    <div>
      {/* HEADER */}
      <div style={{ marginBottom: '24px', display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
        <div>
          <h1 style={{ fontSize: '2rem', marginBottom: '8px' }}>Rides Management</h1>
          <p style={{ color: 'var(--text-secondary)' }}>
            {activeTab === 'single'
              ? 'View all single rides and manually assign to available taxis.'
              : 'View all recurring schedules with estimated prices and total period cost.'}
          </p>
        </div>
        <button className="btn btn-secondary" onClick={fetchData} style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
          <RefreshCw size={16} /> Refresh
        </button>
      </div>

      {/* SUMMARY CARDS */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: '16px', marginBottom: '24px' }}>
        <div className="glass-panel" style={{ padding: '20px', display: 'flex', alignItems: 'center', gap: '16px' }}>
          <div style={{ background: 'rgba(255,204,0,0.15)', borderRadius: '12px', padding: '12px' }}>
            <Send size={22} color="var(--accent-color)" />
          </div>
          <div>
            <div style={{ fontSize: '1.6rem', fontWeight: '700' }}>{rides.length}</div>
            <div style={{ color: 'var(--text-secondary)', fontSize: '0.85rem' }}>Single Rides</div>
          </div>
        </div>
        <div className="glass-panel" style={{ padding: '20px', display: 'flex', alignItems: 'center', gap: '16px' }}>
          <div style={{ background: 'rgba(99,102,241,0.15)', borderRadius: '12px', padding: '12px' }}>
            <Repeat size={22} color="#6366f1" />
          </div>
          <div>
            <div style={{ fontSize: '1.6rem', fontWeight: '700' }}>{recurringRides.length}</div>
            <div style={{ color: 'var(--text-secondary)', fontSize: '0.85rem' }}>Recurring Schedules</div>
          </div>
        </div>
        <div className="glass-panel" style={{ padding: '20px', display: 'flex', alignItems: 'center', gap: '16px' }}>
          <div style={{ background: 'rgba(34,197,94,0.15)', borderRadius: '12px', padding: '12px' }}>
            <DollarSign size={22} color="var(--success)" />
          </div>
          <div>
            <div style={{ fontSize: '1.6rem', fontWeight: '700' }}>
              {recurringRides.reduce((sum, r) => sum + (r.total_period_price || 0), 0).toFixed(1)} DT
            </div>
            <div style={{ color: 'var(--text-secondary)', fontSize: '0.85rem' }}>Total Recurring Revenue</div>
          </div>
        </div>
      </div>

      {/* TABS */}
      <div style={{ display: 'flex', gap: '4px', marginBottom: '20px', borderBottom: '1px solid var(--border-color)', paddingBottom: '0' }}>
        <button style={tabStyle('single')} onClick={() => setActiveTab('single')}>
          🚕 Single Rides ({rides.length})
        </button>
        <button style={tabStyle('recurring')} onClick={() => setActiveTab('recurring')}>
          🔁 Recurring Rides ({recurringRides.length})
        </button>
      </div>

      {/* SINGLE RIDES TABLE */}
      {activeTab === 'single' && (
        <div className="glass-panel table-container" style={{ padding: '24px' }}>
          <table>
            <thead>
              <tr>
                <th>ID & Info</th>
                <th>Locations & Price</th>
                <th>Passenger / Client</th>
                <th>Status</th>
                <th>Assign Driver</th>
              </tr>
            </thead>
            <tbody>
              {rides.map(ride => (
                <tr key={ride.request_id}>
                  <td>
                    <div style={{ fontWeight: '600', color: 'var(--accent-color)' }}>
                      REF-{String(ride.request_id).padStart(4, '0')}
                    </div>
                    <div style={{ fontSize: '0.8rem', color: 'var(--text-secondary)' }}>
                      {ride.created_at ? new Date(ride.created_at).toLocaleString() : '—'}
                    </div>
                  </td>
                  <td>
                    <div style={{ display: 'flex', flexDirection: 'column', gap: '6px' }}>
                      <div style={{ display: 'flex', alignItems: 'center', gap: '8px', fontSize: '0.9rem' }}>
                        <MapPin size={14} color="var(--success)" />
                        {ride.pickup_location}
                      </div>
                      <div style={{ display: 'flex', alignItems: 'center', gap: '8px', fontSize: '0.9rem' }}>
                        <Navigation size={14} color="var(--danger)" />
                        {ride.dropoff_location}
                      </div>
                      {(ride.estimated_distance || ride.estimated_price) && (
                        <div style={{ fontSize: '0.8rem', color: 'var(--text-secondary)' }}>
                          {ride.estimated_distance ? `${ride.estimated_distance} km` : ''}
                          {ride.estimated_price
                            ? ` · ${(ride.estimated_price / 1000).toFixed(2)} DT`
                            : ''}
                        </div>
                      )}
                      {ride.driver_name && (
                        <div style={{ fontSize: '0.82rem', color: '#6366f1', fontWeight: '600' }}>
                          🧑‍✈️ {ride.driver_name}
                        </div>
                      )}
                    </div>
                  </td>
                  <td>
                    <div style={{ fontWeight: '500' }}>{ride.passenger_name || ride.client_name || '—'}</div>
                    {ride.client_name && ride.passenger_name && ride.client_name !== ride.passenger_name && (
                      <div style={{ fontSize: '0.8rem', color: 'var(--text-secondary)' }}>
                        Réservé par : {ride.client_name}
                      </div>
                    )}
                  </td>
                  <td>{getStatusBadge(ride.status)}</td>
                  <td>
                    {ride.status?.toLowerCase() === 'pending' ? (
                      <div style={{ display: 'flex', gap: '8px', flexWrap: 'wrap' }}>
                        <select
                          className="form-select"
                          style={{ padding: '8px 12px', fontSize: '0.9rem', width: '200px' }}
                          value={selectedTaxiId[ride.request_id] || ''}
                          onChange={(e) => setSelectedTaxiId({ ...selectedTaxiId, [ride.request_id]: e.target.value })}
                        >
                          <option value="">Select Taxi...</option>
                          {[...taxis]
                            .sort((a, b) => (b.is_online ? 1 : 0) - (a.is_online ? 1 : 0))
                            .map(taxi => (
                              <option key={taxi.taxi_id} value={taxi.taxi_id} disabled={!taxi.is_online}>
                                {taxi.driver_name} ({taxi.is_online ? '🟢 Online' : '🔴 Offline'})
                              </option>
                            ))}
                        </select>
                        <button className="btn btn-primary" onClick={() => handleAssign(ride.request_id)}>
                          <Send size={14} /> Assign
                        </button>
                      </div>
                    ) : (
                      <span style={{ color: 'var(--text-secondary)', fontSize: '0.9rem' }}>—</span>
                    )}
                  </td>
                </tr>
              ))}
              {rides.length === 0 && (
                <tr>
                  <td colSpan="5" style={{ textAlign: 'center', padding: '40px', color: 'var(--text-secondary)' }}>
                    No single rides found.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      )}

      {/* RECURRING RIDES TABLE */}
      {activeTab === 'recurring' && (
        <div className="glass-panel table-container" style={{ padding: '24px' }}>
          <table>
            <thead>
              <tr>
                <th>ID</th>
                <th>Client</th>
                <th>Ride</th>
                <th>Planification</th>
                <th style={{ textAlign: 'right' }}>Price / Course</th>
                <th style={{ textAlign: 'right' }}>Nb Rides</th>
                <th style={{ textAlign: 'right', color: 'var(--accent-color)' }}>💰 Total Période</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>
              {groupedRecurringRides.map(s => (
                <tr
                  key={s.schedule_ids.join('_')}
                  onClick={() => openScheduleModal(s)}
                  style={{ cursor: 'pointer', transition: 'background 0.15s' }}
                  onMouseEnter={e => e.currentTarget.style.background = 'rgba(99,102,241,0.07)'}
                  onMouseLeave={e => e.currentTarget.style.background = ''}
                >
                  <td>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                      <div style={{ fontWeight: '600', color: '#6366f1' }}>
                        SCH-{String(s.schedule_ids[0]).padStart(4, '0')}
                        {s.schedule_ids.length > 1 && ` (+${s.schedule_ids.length - 1})`}
                      </div>
                      <ChevronRight size={14} color="#6366f1" />
                    </div>
                  </td>
                  <td>
                    <div style={{ fontWeight: '500' }}>{s.client_name}</div>
                  </td>
                  <td>
                    <div style={{ display: 'flex', flexDirection: 'column', gap: '4px' }}>
                      <div style={{ display: 'flex', alignItems: 'center', gap: '6px', fontSize: '0.85rem' }}>
                        <MapPin size={12} color="var(--success)" /> {s.pickup_location}
                      </div>
                      <div style={{ display: 'flex', alignItems: 'center', gap: '6px', fontSize: '0.85rem' }}>
                        <Navigation size={12} color="var(--danger)" /> {s.dropoff_location}
                      </div>
                      {s.distance_km && (
                        <div style={{ fontSize: '0.75rem', color: 'var(--text-secondary)' }}>
                          {s.distance_km} km
                        </div>
                      )}
                    </div>
                  </td>
                  <td>
                    <div style={{ display: 'flex', flexDirection: 'column', gap: '4px' }}>
                      <div style={{ display: 'flex', alignItems: 'center', gap: '6px', fontWeight: '600', color: 'var(--accent-color)' }}>
                        <Repeat size={13} /> {s.days_of_week.join(', ')}
                      </div>
                      {s.pickup_time && (
                        <div style={{ fontSize: '0.8rem', color: 'var(--text-secondary)' }}>
                          🕐 {s.pickup_time}
                        </div>
                      )}
                      {s.start_date && s.end_date && (
                        <div style={{ display: 'flex', alignItems: 'center', gap: '6px', fontSize: '0.78rem', color: 'var(--text-secondary)' }}>
                          <Calendar size={11} />
                          {s.start_date} → {s.end_date}
                        </div>
                      )}
                    </div>
                  </td>
                  <td style={{ textAlign: 'right' }}>
                    {s.estimated_price_per_ride != null
                      ? <span style={{ fontWeight: '600', color: 'var(--text-primary)' }}>{s.estimated_price_per_ride.toFixed(2)} DT</span>
                      : <span style={{ color: 'var(--text-secondary)' }}>—</span>
                    }
                  </td>
                  <td style={{ textAlign: 'right' }}>
                    {s.total_nb_occurrences != null && s.total_nb_occurrences > 0
                      ? <span style={{ fontWeight: '600' }}>{s.total_nb_occurrences}</span>
                      : <span style={{ color: 'var(--text-secondary)' }}>—</span>
                    }
                  </td>
                  <td style={{ textAlign: 'right' }}>
                    {s.total_period_price_sum != null && s.total_period_price_sum > 0
                      ? (
                        <span style={{
                          fontWeight: '700',
                          fontSize: '1rem',
                          color: 'var(--accent-color)',
                          background: 'rgba(255,204,0,0.12)',
                          padding: '4px 10px',
                          borderRadius: '8px',
                        }}>
                          {s.total_period_price_sum.toFixed(2)} DT
                        </span>
                      )
                      : <span style={{ color: 'var(--text-secondary)' }}>—</span>
                    }
                  </td>
                  <td>
                    {s.is_active
                      ? <span className="badge badge-active">Active</span>
                      : <span className="badge badge-inactive">Annulé</span>
                    }
                  </td>
                </tr>
              ))}
              {groupedRecurringRides.length === 0 && (
                <tr>
                  <td colSpan="8" style={{ textAlign: 'center', padding: '40px', color: 'var(--text-secondary)' }}>
                    Aucune course récurrente trouvée.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      )}

      {/* ── MODAL : Rides d'un planning récurrent ── */}
      {selectedSchedule && (
        <div
          onClick={closeModal}
          style={{
            position: 'fixed', inset: 0, zIndex: 1000,
            background: 'rgba(0,0,0,0.65)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            backdropFilter: 'blur(4px)',
            animation: 'fadeIn 0.2s ease',
          }}
        >
          <div
            onClick={e => e.stopPropagation()}
            style={{
              background: 'var(--card-bg)',
              border: '1px solid var(--border-color)',
              borderRadius: '16px',
              width: '90%', maxWidth: '900px',
              maxHeight: '85vh',
              display: 'flex', flexDirection: 'column',
              boxShadow: '0 24px 60px rgba(0,0,0,0.5)',
              animation: 'slideUp 0.25s ease',
            }}
          >
            {/* Header */}
            <div style={{
              padding: '20px 24px',
              borderBottom: '1px solid var(--border-color)',
              display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start',
              flexShrink: 0,
            }}>
              <div>
                <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginBottom: '6px' }}>
                  <Repeat size={18} color="#6366f1" />
                  <h2 style={{ margin: 0, fontSize: '1.2rem' }}>
                    Rides — SCH-{String(selectedSchedule.schedule_ids[0]).padStart(4, '0')}
                    {selectedSchedule.schedule_ids.length > 1 && ` (+${selectedSchedule.schedule_ids.length - 1})`}
                  </h2>
                </div>
                <div style={{ display: 'flex', gap: '16px', flexWrap: 'wrap', fontSize: '0.85rem', color: 'var(--text-secondary)' }}>
                  <span style={{ display: 'flex', alignItems: 'center', gap: '5px' }}>
                    <User size={13} /> {selectedSchedule.client_name}
                  </span>
                  <span style={{ display: 'flex', alignItems: 'center', gap: '5px' }}>
                    <MapPin size={13} color="var(--success)" /> {selectedSchedule.pickup_location}
                  </span>
                  <span style={{ display: 'flex', alignItems: 'center', gap: '5px' }}>
                    <Navigation size={13} color="var(--danger)" /> {selectedSchedule.dropoff_location}
                  </span>
                  <span style={{ display: 'flex', alignItems: 'center', gap: '5px' }}>
                    <Repeat size={13} color="var(--accent-color)" /> {selectedSchedule.days_of_week?.join(', ')}
                  </span>
                </div>
              </div>
              <button
                onClick={closeModal}
                style={{
                  background: 'rgba(255,255,255,0.07)', border: '1px solid var(--border-color)',
                  borderRadius: '8px', padding: '6px 10px', cursor: 'pointer',
                  color: 'var(--text-primary)', display: 'flex', alignItems: 'center',
                }}
              >
                <X size={18} />
              </button>
            </div>

            {/* Body */}
            <div style={{ overflowY: 'auto', flex: 1, padding: '16px 24px 24px' }}>
              {modalLoading ? (
                <div style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', height: '200px' }}>
                  <div style={{ textAlign: 'center' }}>
                    <RefreshCw size={28} style={{ animation: 'spin 1s linear infinite', color: 'var(--accent-color)' }} />
                    <p style={{ marginTop: '10px', color: 'var(--text-secondary)' }}>Loading rides...</p>
                  </div>
                </div>
                ) : scheduleRides.length === 0 ? (
                  <div style={{ textAlign: 'center', padding: '60px 20px', color: 'var(--text-secondary)' }}>
                    <Repeat size={40} style={{ opacity: 0.3, marginBottom: '12px' }} />
                    <p style={{ fontSize: '1rem' }}>No individual rides generated for this schedule.</p>
                  </div>
                ) : (
                <table style={{ width: '100%', borderCollapse: 'collapse', marginBottom: '20px' }}>
                  <thead>
                    <tr style={{ borderBottom: '1px solid var(--border-color)' }}>
                      <th style={{ textAlign: 'left', padding: '10px 12px', color: 'var(--text-secondary)', fontSize: '0.8rem', fontWeight: '600' }}>Ref</th>
                      <th style={{ textAlign: 'left', padding: '10px 12px', color: 'var(--text-secondary)', fontSize: '0.8rem', fontWeight: '600' }}>Date & Time</th>
                      <th style={{ textAlign: 'left', padding: '10px 12px', color: 'var(--text-secondary)', fontSize: '0.8rem', fontWeight: '600' }}>Passenger</th>
                      <th style={{ textAlign: 'left', padding: '10px 12px', color: 'var(--text-secondary)', fontSize: '0.8rem', fontWeight: '600' }}>Driver</th>
                      <th style={{ textAlign: 'left', padding: '10px 12px', color: 'var(--text-secondary)', fontSize: '0.8rem', fontWeight: '600' }}>Status</th>
                      <th style={{ textAlign: 'right', padding: '10px 12px', color: 'var(--text-secondary)', fontSize: '0.8rem', fontWeight: '600' }}>Price</th>
                      <th style={{ textAlign: 'left', padding: '10px 12px', color: 'var(--text-secondary)', fontSize: '0.8rem', fontWeight: '600' }}>Assign</th>
                    </tr>
                  </thead>
                  <tbody>
                    {scheduleRides.map((ride, idx) => (
                      <tr
                        key={ride.request_id}
                        style={{
                          borderBottom: '1px solid var(--border-color)',
                          background: idx % 2 === 0 ? 'transparent' : 'rgba(255,255,255,0.02)',
                        }}
                      >
                        <td style={{ padding: '12px' }}>
                          <span style={{ fontWeight: '600', color: 'var(--accent-color)', fontSize: '0.85rem' }}>
                            REF-{String(ride.request_id).padStart(4, '0')}
                          </span>
                        </td>
                        <td style={{ padding: '12px' }}>
                          <div style={{ fontSize: '0.85rem' }}>
                            {ride.scheduled_for
                              ? new Date(ride.scheduled_for).toLocaleDateString('fr-FR', { weekday: 'short', day: '2-digit', month: '2-digit', year: 'numeric' })
                              : '—'}
                          </div>
                          <div style={{ fontSize: '0.75rem', color: 'var(--text-secondary)' }}>
                            {ride.scheduled_for
                              ? new Date(ride.scheduled_for).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' })
                              : ''}
                          </div>
                        </td>
                        <td style={{ padding: '12px' }}>
                          <div style={{ display: 'flex', alignItems: 'center', gap: '6px', fontSize: '0.85rem' }}>
                            <User size={13} color="var(--text-secondary)" />
                            {ride.passenger_name || ride.client_name || '—'}
                          </div>
                        </td>
                        <td style={{ padding: '12px' }}>
                          {ride.driver_name ? (
                            <div>
                              <div style={{ display: 'flex', alignItems: 'center', gap: '6px', fontSize: '0.85rem', fontWeight: '600', color: '#6366f1' }}>
                                🧑‍✈️ {ride.driver_name}
                              </div>
                              {ride.plate_number && (
                                <div style={{ display: 'flex', alignItems: 'center', gap: '5px', fontSize: '0.75rem', color: 'var(--text-secondary)', marginTop: '2px' }}>
                                  <Car size={11} /> {ride.plate_number}
                                </div>
                              )}
                            </div>
                          ) : (
                            <span style={{ color: 'var(--text-secondary)', fontSize: '0.85rem' }}>Unassigned</span>
                          )}
                        </td>
                        <td style={{ padding: '12px' }}>
                          {getStatusBadge(ride.status)}
                        </td>
                        <td style={{ padding: '12px', textAlign: 'right' }}>
                          {ride.estimated_price != null
                            ? <span style={{ fontWeight: '600', fontSize: '0.85rem' }}>
                                {(ride.estimated_price / 1000).toFixed(2)} DT
                              </span>
                            : <span style={{ color: 'var(--text-secondary)' }}>—</span>
                          }
                        </td>
                        <td style={{ padding: '10px 12px' }}>
                          {ride.status?.toLowerCase() === 'pending' ? (
                            <div style={{ display: 'flex', gap: '6px', alignItems: 'center', flexWrap: 'wrap' }}>
                              <select
                                className="form-select"
                                style={{ padding: '6px 10px', fontSize: '0.82rem', minWidth: '160px', maxWidth: '200px' }}
                                value={modalTaxiId[ride.request_id] || ''}
                                onChange={e => setModalTaxiId(prev => ({ ...prev, [ride.request_id]: e.target.value }))}
                              >
                                <option value="">Choose driver...</option>
                                {[...taxis]
                                  .sort((a, b) => (b.is_online ? 1 : 0) - (a.is_online ? 1 : 0))
                                  .map(taxi => (
                                    <option key={taxi.taxi_id} value={taxi.taxi_id} disabled={!taxi.is_online}>
                                      {taxi.driver_name} ({taxi.is_online ? '🟢' : '🔴'})
                                    </option>
                                  ))}
                              </select>
                              <button
                                className="btn btn-primary"
                                style={{ padding: '6px 12px', fontSize: '0.82rem', whiteSpace: 'nowrap' }}
                                onClick={() => handleAssignInModal(ride.request_id)}
                              >
                                <Send size={12} style={{ marginRight: '4px' }} /> Assign
                              </button>
                            </div>
                          ) : (
                            <span style={{ color: 'var(--text-secondary)', fontSize: '0.82rem' }}>—</span>
                          )}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              )}
            </div>

            {/* Footer */}
            {!modalLoading && scheduleRides.length > 0 && (
              <div style={{
                padding: '14px 24px',
                borderTop: '1px solid var(--border-color)',
                display: 'flex', justifyContent: 'space-between', alignItems: 'center',
                flexShrink: 0,
                fontSize: '0.85rem', color: 'var(--text-secondary)',
              }}>
                <span>{scheduleRides.length} total ride{scheduleRides.length > 1 ? 's' : ''}</span>
                <span>
                  {scheduleRides.filter(r => r.driver_name).length} assigned · {scheduleRides.filter(r => !r.driver_name).length} unassigned
                </span>
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
