import { useState, useEffect } from 'react';
import axios from 'axios';
import { MapPin, Navigation, Send } from 'lucide-react';

const BASE_URL = 'http://127.0.0.1:8000/api/admin';

export default function Rides() {
  const [rides, setRides] = useState([]);
  const [taxis, setTaxis] = useState([]);
  const [loading, setLoading] = useState(true);
  const [selectedTaxiId, setSelectedTaxiId] = useState({});

  useEffect(() => {
    fetchData();
  }, []);

  const fetchData = async () => {
    try {
      const [ridesRes, taxisRes] = await Promise.all([
        axios.get(`${BASE_URL}/rides`),
        axios.get(`${BASE_URL}/taxis`)
      ]);
      setRides(ridesRes.data);
      setTaxis(taxisRes.data);
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

  const getStatusBadge = (status) => {
    switch(status) {
      case 'pending': return <span className="badge badge-pending">Pending</span>;
      case 'accepted': return <span className="badge badge-active">Accepted</span>;
      case 'completed': return <span className="badge badge-inactive">Completed</span>;
      default: return <span className="badge">{status}</span>;
    }
  };

  if (loading) {
    return <div style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', height: '100%' }}>Loading...</div>;
  }

  return (
    <div>
      <div style={{ marginBottom: '32px' }}>
        <h1 style={{ fontSize: '2rem', marginBottom: '8px' }}>Rides Management</h1>
        <p style={{ color: 'var(--text-secondary)' }}>View all rides and manually assign to available taxis.</p>
      </div>

      <div className="glass-panel table-container" style={{ padding: '24px' }}>
        <table>
          <thead>
            <tr>
              <th>ID & Info</th>
              <th>Locations</th>
              <th>Passenger</th>
              <th>Status</th>
              <th>Manual Assign</th>
            </tr>
          </thead>
          <tbody>
            {rides.map(ride => (
              <tr key={ride.request_id}>
                <td>
                  <div style={{ fontWeight: '600', color: 'var(--accent-color)' }}>#{ride.request_id}</div>
                  <div style={{ fontSize: '0.8rem', color: 'var(--text-secondary)' }}>
                    {new Date(ride.created_at).toLocaleString()}
                  </div>
                </td>
                <td>
                  <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '8px', fontSize: '0.9rem' }}>
                      <MapPin size={16} color="var(--success)" />
                      {ride.pickup_location}
                    </div>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '8px', fontSize: '0.9rem' }}>
                      <Navigation size={16} color="var(--danger)" />
                      {ride.dropoff_location}
                    </div>
                    {(ride.estimated_distance || ride.estimated_duration) && (
                      <div style={{ fontSize: '0.8rem', color: 'var(--text-secondary)' }}>
                        {ride.estimated_distance} km • {ride.estimated_duration} mins
                      </div>
                    )}
                  </div>
                </td>
                <td>
                  <div style={{ fontWeight: '500' }}>{ride.passenger_name}</div>
                  <div style={{ fontSize: '0.8rem', color: 'var(--text-secondary)' }}>ID: {ride.passenger_id}</div>
                </td>
                <td>{getStatusBadge(ride.status)}</td>
                <td>
                  {ride.status === 'pending' ? (
                    <div style={{ display: 'flex', gap: '8px' }}>
                      <select 
                        className="form-select" 
                        style={{ padding: '8px 12px', fontSize: '0.9rem', width: '200px' }}
                        value={selectedTaxiId[ride.request_id] || ''}
                        onChange={(e) => setSelectedTaxiId({
                          ...selectedTaxiId,
                          [ride.request_id]: e.target.value
                        })}
                      >
                        <option value="">Select Taxi...</option>
                        {taxis.map(taxi => (
                          <option key={taxi.taxi_id} value={taxi.taxi_id}>
                            Taxi #{taxi.taxi_id} ({taxi.plate_number})
                          </option>
                        ))}
                      </select>
                      <button 
                        className="btn btn-primary"
                        onClick={() => handleAssign(ride.request_id)}
                      >
                        <Send size={16} /> Assign
                      </button>
                    </div>
                  ) : (
                    <span style={{ color: 'var(--text-secondary)', fontSize: '0.9rem' }}>
                      Cannot assign
                    </span>
                  )}
                </td>
              </tr>
            ))}
            {rides.length === 0 && (
              <tr>
                <td colSpan="5" style={{ textAlign: 'center', padding: '40px', color: 'var(--text-secondary)' }}>
                  No rides found.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
