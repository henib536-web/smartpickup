import React, { useState, useEffect, useMemo } from 'react';
import { MapContainer, TileLayer, Marker, Popup, useMap } from 'react-leaflet';
import L from 'leaflet';
import { Search, Filter, ChevronRight, Phone } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import 'leaflet/dist/leaflet.css';

// Fix for default Leaflet icon (though we use custom icons, it's good practice)
import icon from 'leaflet/dist/images/marker-icon.png';
import iconShadow from 'leaflet/dist/images/marker-shadow.png';

let DefaultIcon = L.icon({
    iconUrl: icon,
    shadowUrl: iconShadow,
    iconSize: [25, 41],
    iconAnchor: [12, 41]
});
L.Marker.prototype.options.icon = DefaultIcon;

const WS_URL = 'ws://127.0.0.1:8000/api/admin/locations/ws';

function MapUpdater({ selectedDriver }) {
  const map = useMap();
  
  useEffect(() => {
    if (selectedDriver && selectedDriver.latitude && selectedDriver.longitude) {
      map.flyTo([selectedDriver.latitude, selectedDriver.longitude], 15, {
        animate: true,
        duration: 1.5
      });
    }
  }, [selectedDriver, map]);
  
  return null;
}

export default function LiveTracking() {
  const navigate = useNavigate();
  const [drivers, setDrivers] = useState({});
  const [searchTerm, setSearchTerm] = useState('');
  const [statusFilter, setStatusFilter] = useState('all');
  const [selectedDriver, setSelectedDriver] = useState(null);

  useEffect(() => {
    const ws = new WebSocket(WS_URL);

    ws.onopen = () => {
      console.log('Connected to admin live tracking WebSocket');
    };

    ws.onmessage = (event) => {
      const data = JSON.parse(event.data);
      console.log('Received driver update:', data);
      
      setDrivers(prevDrivers => ({
        ...prevDrivers,
        [data.driver_id]: {
          ...data,
          last_updated: new Date()
        }
      }));
    };

    ws.onclose = () => {
      console.log('Disconnected from admin live tracking WebSocket');
    };

    ws.onerror = (error) => {
      console.error('WebSocket error:', error);
    };

    return () => {
      ws.close();
    };
  }, []);

  // Filter drivers based on search and filter status
  const filteredDrivers = useMemo(() => {
    return Object.values(drivers).filter(driver => {
      const matchesSearch = driver.driver_name.toLowerCase().includes(searchTerm.toLowerCase()) || 
                            driver.driver_id.toString().includes(searchTerm);
      const matchesStatus = statusFilter === 'all' || driver.status === statusFilter;
      return matchesSearch && matchesStatus;
    });
  }, [drivers, searchTerm, statusFilter]);

  // Counters
  const totalActive = Object.values(drivers).length;
  const availableCount = Object.values(drivers).filter(d => d.status === 'available').length;
  const occupiedCount = Object.values(drivers).filter(d => d.status === 'occupied').length;
  const offlineCount = Object.values(drivers).filter(d => d.status === 'offline').length;

  // Custom Marker Icon generator
  const createCustomIcon = (status, heading = 0) => {
    let borderColor = '#a0a0a0'; // offline/gray
    if (status === 'available') borderColor = '#4ade80'; // green
    if (status === 'occupied') borderColor = '#f87171'; // red

    return L.divIcon({
      className: 'custom-div-icon',
      html: `
        <div style="
          background-color: #ffffff;
          width: 36px;
          height: 36px;
          border-radius: 50%;
          display: flex;
          justify-content: center;
          align-items: center;
          border: 3px solid ${borderColor};
          box-shadow: 0 4px 6px rgba(0,0,0,0.3);
          transform: rotate(${heading}deg);
          transition: transform 0.3s ease;
        ">
          <span style="font-size: 20px; line-height: 1; transform: rotate(-90deg); display: inline-block;">🚕</span>
        </div>
      `,
      iconSize: [36, 36],
      iconAnchor: [18, 18],
      popupAnchor: [0, -18]
    });
  };

  return (
    <div style={{ height: 'calc(100vh - 80px)', display: 'flex', flexDirection: 'column', gap: '20px' }}>
      
      {/* Header & Stats */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <div>
          <h1 style={{ fontSize: '2rem', marginBottom: '8px' }}>Live Taxi Tracking</h1>
          <p style={{ color: 'var(--text-secondary)' }}>Monitor all active drivers in real-time.</p>
        </div>
        
        <div style={{ display: 'flex', gap: '15px' }}>
          <div className="glass-panel" style={{ padding: '12px 20px', display: 'flex', alignItems: 'center', gap: '10px' }}>
            <div style={{ width: 12, height: 12, borderRadius: '50%', backgroundColor: '#4ade80' }}></div>
            <div>
              <p style={{ fontSize: '0.8rem', color: 'var(--text-secondary)' }}>Available</p>
              <p style={{ fontSize: '1.2rem', fontWeight: '700' }}>{availableCount}</p>
            </div>
          </div>
          <div className="glass-panel" style={{ padding: '12px 20px', display: 'flex', alignItems: 'center', gap: '10px' }}>
            <div style={{ width: 12, height: 12, borderRadius: '50%', backgroundColor: '#f87171' }}></div>
            <div>
              <p style={{ fontSize: '0.8rem', color: 'var(--text-secondary)' }}>Occupied</p>
              <p style={{ fontSize: '1.2rem', fontWeight: '700' }}>{occupiedCount}</p>
            </div>
          </div>
          <div className="glass-panel" style={{ padding: '12px 20px', display: 'flex', alignItems: 'center', gap: '10px' }}>
            <div style={{ width: 12, height: 12, borderRadius: '50%', backgroundColor: '#a0a0a0' }}></div>
            <div>
              <p style={{ fontSize: '0.8rem', color: 'var(--text-secondary)' }}>Offline</p>
              <p style={{ fontSize: '1.2rem', fontWeight: '700' }}>{offlineCount}</p>
            </div>
          </div>
        </div>
      </div>

      {/* Controls & Map Container */}
      <div style={{ flex: 1, display: 'flex', gap: '20px', minHeight: 0 }}>
        
        {/* Sidebar Controls */}
        <div className="glass-panel" style={{ width: '320px', padding: '20px', display: 'flex', flexDirection: 'column', gap: '15px', overflowY: 'auto' }}>
          
          {/* Search */}
          <div style={{ position: 'relative' }}>
            <Search size={18} style={{ position: 'absolute', left: '12px', top: '50%', transform: 'translateY(-50%)', color: 'var(--text-secondary)' }} />
            <input 
              type="text" 
              placeholder="Search driver or ID..." 
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              style={{
                width: '100%',
                padding: '12px 12px 12px 40px',
                background: 'var(--input-bg)',
                border: '1px solid var(--panel-border)',
                borderRadius: '12px',
                color: 'white',
                outline: 'none'
              }}
            />
          </div>

          {/* Filter */}
          <div style={{ position: 'relative' }}>
            <Filter size={18} style={{ position: 'absolute', left: '12px', top: '50%', transform: 'translateY(-50%)', color: 'var(--text-secondary)' }} />
            <select 
              value={statusFilter}
              onChange={(e) => setStatusFilter(e.target.value)}
              style={{
                width: '100%',
                padding: '12px 12px 12px 40px',
                background: 'var(--input-bg)',
                border: '1px solid var(--panel-border)',
                borderRadius: '12px',
                color: 'white',
                outline: 'none',
                appearance: 'none'
              }}
            >
              <option value="all">All Status</option>
              <option value="available">Available</option>
              <option value="occupied">Occupied</option>
              <option value="offline">Offline</option>
            </select>
          </div>

          <div style={{ borderTop: '1px solid var(--panel-border)', paddingTop: '15px' }}>
            <h3 style={{ fontSize: '1rem', marginBottom: '10px' }}>Drivers List ({filteredDrivers.length})</h3>
            <div style={{ display: 'flex', flexDirection: 'column', gap: '10px' }}>
              {filteredDrivers.map(driver => (
                <div 
                  key={driver.driver_id}
                  onClick={() => setSelectedDriver(driver)}
                  style={{
                    padding: '12px',
                    borderRadius: '8px',
                    background: selectedDriver?.driver_id === driver.driver_id ? 'rgba(255, 204, 0, 0.1)' : 'rgba(255,255,255,0.02)',
                    border: selectedDriver?.driver_id === driver.driver_id ? '1px solid var(--accent-color)' : '1px solid transparent',
                    cursor: 'pointer',
                    transition: 'all 0.2s',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'space-between'
                  }}
                >
                  <div style={{ flex: 1 }}>
                    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                      <p style={{ fontWeight: '600' }}>{driver.driver_name}</p>
                      <span style={{ 
                        fontSize: '0.7rem', 
                        padding: '4px 8px', 
                        borderRadius: '10px',
                        backgroundColor: driver.status === 'available' ? 'rgba(74, 222, 128, 0.2)' : driver.status === 'occupied' ? 'rgba(248, 113, 113, 0.2)' : 'rgba(160, 160, 160, 0.2)',
                        color: driver.status === 'available' ? '#4ade80' : driver.status === 'occupied' ? '#f87171' : '#a0a0a0'
                      }}>
                        {driver.status}
                      </span>
                    </div>
                    
                    <div style={{ display: 'flex', alignItems: 'center', gap: '5px', marginTop: '6px' }}>
                      <Phone size={12} color="var(--text-secondary)" />
                      <p style={{ fontSize: '0.8rem', color: 'var(--text-secondary)' }}>
                        {driver.driver_phone || 'No spécifié'}
                      </p>
                    </div>
                  </div>
                  
                  <button 
                    onClick={(e) => {
                      e.stopPropagation();
                      navigate(`/drivers/${driver.driver_id}`);
                    }}
                    style={{
                      marginLeft: '10px',
                      background: 'rgba(255,255,255,0.05)',
                      border: 'none',
                      borderRadius: '50%',
                      width: '32px',
                      height: '32px',
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'center',
                      cursor: 'pointer',
                      color: 'var(--accent-color)'
                    }}
                    title="Voir les détails"
                  >
                    <ChevronRight size={18} />
                  </button>
                </div>
              ))}
              {filteredDrivers.length === 0 && (
                <p style={{ color: 'var(--text-secondary)', textAlign: 'center', marginTop: '20px' }}>No drivers found</p>
              )}
            </div>
          </div>
        </div>
        <p>test</p>

        {/* Map */}
        <div className="glass-panel" style={{ flex: 1, borderRadius: '20px', overflow: 'hidden', position: 'relative' }}>
          <MapContainer 
            center={[36.8065, 10.1815]} // Default center (Tunis, example)
            zoom={13} 
            style={{ height: '100%', width: '100%' }}
          >
            <TileLayer
              attribution='&copy; <a href="https://www.mapbox.com/about/maps/">Mapbox</a>'
              url="https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/256/{z}/{x}/{y}@2x?access_token=pk.eyJ1IjoiaGVuaTg4MyIsImEiOiJjbW5pdHh0aGIwYTR0MnFyNjI4YTY5M3gxIn0.pcHfhkMrWoad2IWty-ZdyQ"
              className="map-tiles"
            />
            
            <MapUpdater selectedDriver={selectedDriver} />
            
            {filteredDrivers.filter(d => d.latitude != null && d.longitude != null).map(driver => (
              <Marker 
                key={driver.driver_id} 
                position={[driver.latitude, driver.longitude]}
                icon={createCustomIcon(driver.status, driver.heading)}
              >
                <Popup>
                  <div style={{ color: '#000000', padding: '5px' }}>
                    <h3 style={{ margin: '0 0 5px 0', color: '#000' }}>{driver.driver_name}</h3>
                    <p style={{ margin: '3px 0' }}><strong>ID:</strong> {driver.driver_id}</p>
                    <p style={{ margin: '3px 0' }}><strong>Status:</strong> <span style={{ color: driver.status === 'available' ? '#4ade80' : driver.status === 'occupied' ? '#f87171' : '#a0a0a0', fontWeight: 'bold' }}>{driver.status}</span></p>
                    <p style={{ margin: '3px 0' }}><strong>Speed:</strong> {driver.speed} km/h</p>
                    <p style={{ margin: '3px 0' }}><strong>Position:</strong> {driver.latitude.toFixed(4)}, {driver.longitude.toFixed(4)}</p>
                    <p style={{ margin: '3px 0', fontSize: '0.75rem', color: '#666' }}>Last update: {driver.last_updated?.toLocaleTimeString()}</p>
                  </div>
                </Popup>
              </Marker>
            ))}
          </MapContainer>
        </div>
      </div>
    </div>
  );
}
