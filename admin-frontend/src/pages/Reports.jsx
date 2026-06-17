import { useState, useEffect } from 'react';
import axios from 'axios';
import { AlertTriangle, CheckCircle, XCircle, Eye, MapPin, Navigation, User, Car, Star, Phone, Mail, FileText, X } from 'lucide-react';

const BASE_URL = 'http://127.0.0.1:8000/api/admin';

const SEVERITY_COLORS = {
  low:      { bg: 'rgba(74,222,128,0.12)',  color: '#4ade80' },
  medium:   { bg: 'rgba(255,204,0,0.12)',   color: '#FFCC00' },
  high:     { bg: 'rgba(248,113,113,0.12)', color: '#f87171' },
  critical: { bg: 'rgba(239,68,68,0.18)',   color: '#ef4444' },
};

function SeverityBadge({ level }) {
  const s = SEVERITY_COLORS[String(level || '').toLowerCase()] || SEVERITY_COLORS.medium;
  return <span style={{ padding: '4px 10px', borderRadius: '20px', fontSize: '0.75rem', fontWeight: 600, background: s.bg, color: s.color, textTransform: 'capitalize' }}>{level || 'N/A'}</span>;
}

function StatusBadge({ status }) {
  const map = {
    open:     { bg: 'rgba(255,204,0,0.12)',   color: '#FFCC00', label: 'Open'  },
    resolved: { bg: 'rgba(74,222,128,0.12)',  color: '#4ade80', label: 'Resolved'  },
    rejected: { bg: 'rgba(160,160,160,0.12)', color: '#a0a0a0', label: 'Rejected'  },
  };
  const s = map[String(status || '').toLowerCase()] || map.open;
  return <span style={{ padding: '5px 12px', borderRadius: '20px', fontSize: '0.75rem', fontWeight: 600, background: s.bg, color: s.color }}>{s.label}</span>;
}

// InfoRow defined OUTSIDE modals to avoid re-creation on each render
function InfoRow({ icon: Icon, label, value }) {
  return (
    <div style={{ display: 'flex', alignItems: 'flex-start', gap: '10px', marginBottom: '10px' }}>
      <Icon size={15} color="#666" style={{ marginTop: 2, flexShrink: 0 }} />
      <div>
        <span style={{ fontSize: '0.78rem', color: '#888', display: 'block' }}>{label}</span>
        <span style={{ fontSize: '0.92rem', color: '#fff' }}>{value || '—'}</span>
      </div>
    </div>
  );
}

function DecisionModal({ report, onClose, onSaved }) {
  const [note, setNote]     = useState('');
  const [rating, setRating] = useState(String(report?.driver?.average_rating ?? 5.0));
  const [saving, setSaving] = useState(false);

  const submit = async (status) => {
    setSaving(true);
    try {
      await axios.put(`${BASE_URL}/reports/${report.report_id}/status`, {
        status,
        resolution_note: note || null,
      });
      if (report.driver) {
        const parsed = parseFloat(rating);
        if (!isNaN(parsed) && parsed >= 0 && parsed <= 5) {
          await axios.put(`${BASE_URL}/drivers/${report.driver.driver_id}/rating`, { average_rating: parsed });
        }
      }
      onSaved();
      onClose();
    } catch (e) {
      alert('Error during update.');
    } finally {
      setSaving(false);
    }
  };

  return (
    <div style={{ position: 'fixed', inset: 0, zIndex: 1000, background: 'rgba(0,0,0,0.78)', backdropFilter: 'blur(6px)', display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '20px' }} onClick={onClose}>
      <div onClick={e => e.stopPropagation()} style={{ background: '#111', border: '1px solid #2a2a2a', borderRadius: '20px', width: '100%', maxWidth: '500px', boxShadow: '0 30px 80px rgba(0,0,0,0.9)', overflow: 'hidden' }}>
        {/* Header */}
        <div style={{ padding: '18px 24px', borderBottom: '1px solid #222', display: 'flex', justifyContent: 'space-between', alignItems: 'center', background: 'rgba(255,204,0,0.04)' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '10px', color: '#fff', fontWeight: 700 }}>
            <AlertTriangle size={18} color="#FFCC00" />
            Decision — Report #{report.report_id}
          </div>
          <button onClick={onClose} style={{ color: '#555', cursor: 'pointer', padding: '4px' }}><X size={18} /></button>
        </div>

        <div style={{ padding: '22px', display: 'flex', flexDirection: 'column', gap: '16px' }}>
          {/* Description */}
          <div style={{ background: '#1a1a1a', border: '1px solid #222', borderRadius: '12px', padding: '14px' }}>
            <p style={{ fontSize: '0.8rem', color: '#666', marginBottom: '6px' }}>Description</p>
            <p style={{ fontSize: '0.9rem', color: '#ddd', lineHeight: 1.6 }}>{report.description}</p>
          </div>

          {/* Rating */}
          {report.driver && (
            <div style={{ background: '#1a1a1a', border: '1px solid #222', borderRadius: '12px', padding: '14px', display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: '12px' }}>
              <div>
                <p style={{ fontSize: '0.8rem', color: '#666', marginBottom: '4px' }}>Rating for {report.driver.name}</p>
                <p style={{ fontSize: '0.8rem', color: '#555' }}>Current: ★ {Number(report.driver.average_rating || 5).toFixed(1)}</p>
              </div>
              <input
                type="number"
                step="0.1"
                min="0"
                max="5"
                value={rating}
                onChange={e => setRating(e.target.value)}
                onClick={e => e.stopPropagation()}
                style={{ width: '80px', padding: '8px', textAlign: 'center', background: '#222', border: '1px solid #3a3a3a', borderRadius: '8px', color: '#fff', fontSize: '1rem', outline: 'none' }}
              />
            </div>
          )}

          {/* Resolution note */}
          <textarea
            placeholder="Resolution note (optional)..."
            value={note}
            onChange={e => setNote(e.target.value)}
            rows={3}
            style={{ width: '100%', padding: '12px', resize: 'vertical', background: '#1a1a1a', border: '1px solid #2a2a2a', borderRadius: '12px', color: '#fff', fontFamily: 'inherit', fontSize: '0.9rem', outline: 'none' }}
          />

          {/* Actions */}
          <div style={{ display: 'flex', gap: '12px' }}>
            <button className="btn btn-success" style={{ flex: 1 }} disabled={saving} onClick={() => submit('resolved')}>
              <CheckCircle size={15} /> Resolve
            </button>
            <button className="btn btn-danger" style={{ flex: 1 }} disabled={saving} onClick={() => submit('rejected')}>
              <XCircle size={15} /> Reject
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

function DetailModal({ report, onClose }) {
  const ride   = report.ride   || null;
  const driver = report.driver || null;

  return (
    <div style={{ position: 'fixed', inset: 0, zIndex: 1000, background: 'rgba(0,0,0,0.78)', backdropFilter: 'blur(6px)', display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '20px' }} onClick={onClose}>
      <div onClick={e => e.stopPropagation()} style={{ background: '#111', border: '1px solid #2a2a2a', borderRadius: '20px', width: '100%', maxWidth: '620px', maxHeight: '85vh', overflowY: 'auto', boxShadow: '0 30px 80px rgba(0,0,0,0.9)' }}>
        {/* Header */}
        <div style={{ padding: '18px 24px', borderBottom: '1px solid #222', display: 'flex', justifyContent: 'space-between', alignItems: 'center', background: 'rgba(255,204,0,0.04)', position: 'sticky', top: 0, zIndex: 2, backdropFilter: 'blur(10px)' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: '10px', color: '#fff', fontWeight: 700 }}>
            <Eye size={18} color="#FFCC00" />
            Details — Report #{report.report_id}
          </div>
          <button onClick={onClose} style={{ color: '#555', cursor: 'pointer', padding: '4px' }}><X size={18} /></button>
        </div>

        <div style={{ padding: '22px', display: 'flex', flexDirection: 'column', gap: '20px' }}>
          {/* Report info */}
          <section>
            <p style={{ fontSize: '0.75rem', color: '#555', textTransform: 'uppercase', letterSpacing: '0.08em', marginBottom: '10px' }}>Report information</p>
            <div style={{ background: '#1a1a1a', border: '1px solid #222', borderRadius: '12px', padding: '16px' }}>
              <InfoRow icon={AlertTriangle} label="Type" value={report.report_type} />
              <InfoRow icon={FileText}      label="Description" value={report.description} />
              <InfoRow icon={User}          label="Reported by" value={report.reporter_name} />
              <InfoRow icon={AlertTriangle} label="Severity" value={report.severity_level} />
              <InfoRow icon={CheckCircle}   label="Date" value={new Date(report.created_at).toLocaleString('fr-FR')} />
              {report.resolution_note && <InfoRow icon={FileText} label="Resolution note" value={report.resolution_note} />}
            </div>
          </section>

          {/* Ride info */}
          {ride && (
            <section>
              <p style={{ fontSize: '0.75rem', color: '#555', textTransform: 'uppercase', letterSpacing: '0.08em', marginBottom: '10px' }}>Ride details</p>
              <div style={{ background: '#1a1a1a', border: '1px solid #222', borderRadius: '12px', padding: '16px' }}>
                <InfoRow icon={MapPin}     label="Pickup"      value={ride.pickup_location} />
                <InfoRow icon={Navigation} label="Destination" value={ride.dropoff_location} />
                <InfoRow icon={User}       label="Client"      value={ride.client_name} />
                <InfoRow icon={Phone}      label="Phone"   value={ride.client_phone} />
                <div style={{ display: 'flex', gap: '10px', marginTop: '10px', flexWrap: 'wrap' }}>
                  <span style={{ background: 'rgba(255,204,0,0.08)', borderRadius: '8px', padding: '6px 12px', fontSize: '0.82rem', color: '#fff' }}>
                    💰 {ride.estimated_price ? `${Number(ride.estimated_price).toLocaleString()} DZD` : '—'}
                  </span>
                  <span style={{ background: 'rgba(255,255,255,0.05)', borderRadius: '8px', padding: '6px 12px', fontSize: '0.82rem', color: '#fff' }}>
                    📍 {ride.distance_km ? `${ride.distance_km} km` : '—'}
                  </span>
                  <StatusBadge status={ride.status} />
                </div>
              </div>
            </section>
          )}

          {/* Driver info */}
          {driver && (
            <section>
              <p style={{ fontSize: '0.75rem', color: '#555', textTransform: 'uppercase', letterSpacing: '0.08em', marginBottom: '10px' }}>Involved Driver</p>
              <div style={{ background: '#1a1a1a', border: '1px solid #222', borderRadius: '12px', padding: '16px' }}>
                <InfoRow icon={User}     label="Name"       value={driver.name} />
                <InfoRow icon={Phone}    label="Phone" value={driver.phone} />
                <InfoRow icon={Mail}     label="Email"     value={driver.email} />
                <InfoRow icon={Car}      label="Vehicle"  value={`${driver.vehicle_model || ''} — ${driver.plate_number || ''}`} />
                <InfoRow icon={FileText} label="License"    value={driver.license_number} />
                <InfoRow icon={Star}     label="Rating"      value={`★ ${Number(driver.average_rating || 5).toFixed(1)} / 5`} />
              </div>
            </section>
          )}
        </div>
      </div>
    </div>
  );
}

export default function Reports() {
  const [reports, setReports]           = useState([]);
  const [loading, setLoading]           = useState(true);
  const [filterStatus, setFilterStatus] = useState('all');
  const [detailReport, setDetailReport] = useState(null);
  const [decisionReport, setDecisionReport] = useState(null);

  useEffect(() => { fetchReports(); }, []);

  const fetchReports = async () => {
    try {
      const r = await axios.get(`${BASE_URL}/reports`);
      setReports(Array.isArray(r.data) ? r.data : []);
    } catch (e) {
      console.error('Fetch reports error:', e);
    } finally {
      setLoading(false);
    }
  };

  const filtered = filterStatus === 'all' ? reports : reports.filter(r => String(r.status || '').toLowerCase() === filterStatus);

  if (loading) return (
    <div style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', height: '300px' }}>
      <div className="spinner" />
    </div>
  );

  return (
    <div>
      {/* Page header */}
      <div style={{ marginBottom: '28px', display: 'flex', justifyContent: 'space-between', alignItems: 'flex-end', flexWrap: 'wrap', gap: '16px' }}>
        <div>
          <h1 style={{ fontSize: '2rem', marginBottom: '6px', color: '#fff' }}>Reports & Incidents</h1>
          <p style={{ color: '#888' }}>Manage reports and make decisions.</p>
        </div>
        <select className="form-select" style={{ width: 'auto', padding: '8px 16px' }} value={filterStatus} onChange={e => setFilterStatus(e.target.value)}>
          <option value="all">All ({reports.length})</option>
          <option value="open">Open ({reports.filter(r => String(r.status || '').toLowerCase() === 'open').length})</option>
          <option value="resolved">Resolved ({reports.filter(r => String(r.status || '').toLowerCase() === 'resolved').length})</option>
          <option value="rejected">Rejected ({reports.filter(r => String(r.status || '').toLowerCase() === 'rejected').length})</option>
        </select>
      </div>

      {/* Table */}
      <div className="glass-panel table-container">
        <table>
          <thead>
            <tr>
              <th style={{ paddingLeft: '24px' }}>Report</th>
              <th>Reported by</th>
              <th>Ride</th>
              <th>Driver</th>
              <th>Severity</th>
              <th>Status</th>
              <th style={{ textAlign: 'right', paddingRight: '24px' }}>Actions</th>
            </tr>
          </thead>
          <tbody>
            {filtered.map(report => (
              <tr key={report.report_id}>
                <td style={{ paddingLeft: '24px' }}>
                  <div style={{ fontWeight: 600, color: '#FFCC00', fontSize: '0.85rem' }}>#{report.report_id}</div>
                  <div style={{ fontSize: '0.88rem', color: '#ddd', marginTop: '2px' }}>{report.report_type}</div>
                  <div style={{ fontSize: '0.75rem', color: '#666', marginTop: '2px' }}>{new Date(report.created_at).toLocaleDateString('fr-FR')}</div>
                </td>

                <td>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                    <div style={{ width: 30, height: 30, borderRadius: '50%', background: 'rgba(255,204,0,0.1)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
                      <User size={13} color="#FFCC00" />
                    </div>
                    <span style={{ fontSize: '0.88rem', color: '#ddd' }}>{report.reporter_name}</span>
                  </div>
                </td>

                <td>
                  {report.ride ? (
                    <div style={{ fontSize: '0.8rem' }}>
                      <div style={{ color: '#4ade80', marginBottom: '3px', display: 'flex', alignItems: 'center', gap: '4px' }}>
                        <MapPin size={10} />
                        <span style={{ maxWidth: '140px', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', display: 'inline-block' }}>{report.ride.pickup_location}</span>
                      </div>
                      <div style={{ color: '#f87171', display: 'flex', alignItems: 'center', gap: '4px' }}>
                        <Navigation size={10} />
                        <span style={{ maxWidth: '140px', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', display: 'inline-block' }}>{report.ride.dropoff_location}</span>
                      </div>
                      <div style={{ color: '#555', marginTop: '3px' }}>Ride #{report.ride_id}</div>
                    </div>
                  ) : <span style={{ color: '#555', fontSize: '0.85rem' }}>—</span>}
                </td>

                <td>
                  {report.driver ? (
                    <div style={{ fontSize: '0.85rem' }}>
                      <div style={{ color: '#ddd', fontWeight: 500 }}>{report.driver.name}</div>
                      <div style={{ color: '#fbbf24', fontSize: '0.78rem', marginTop: '2px' }}>★ {Number(report.driver.average_rating || 5).toFixed(1)}</div>
                      <div style={{ color: '#555', fontSize: '0.78rem' }}>{report.driver.vehicle_model}</div>
                    </div>
                  ) : <span style={{ color: '#555', fontSize: '0.85rem' }}>—</span>}
                </td>

                <td><SeverityBadge level={report.severity_level} /></td>
                <td><StatusBadge status={report.status} /></td>

                <td style={{ textAlign: 'right', paddingRight: '24px' }}>
                  <div style={{ display: 'flex', gap: '8px', justifyContent: 'flex-end' }}>
                    <button
                      onClick={() => setDetailReport(report)}
                      style={{ padding: '6px 11px', borderRadius: '8px', fontSize: '0.78rem', background: 'rgba(255,255,255,0.05)', border: '1px solid #2a2a2a', color: '#bbb', display: 'flex', alignItems: 'center', gap: '5px', cursor: 'pointer' }}
                    >
                      <Eye size={13} /> Details
                    </button>
                    {String(report.status || '').toLowerCase() === 'open' && (
                      <button
                        onClick={() => setDecisionReport(report)}
                        style={{ padding: '6px 11px', borderRadius: '8px', fontSize: '0.78rem', background: 'rgba(255,204,0,0.1)', border: '1px solid rgba(255,204,0,0.25)', color: '#FFCC00', display: 'flex', alignItems: 'center', gap: '5px', cursor: 'pointer' }}
                      >
                        <CheckCircle size={13} /> Decision
                      </button>
                    )}
                  </div>
                </td>
              </tr>
            ))}

            {filtered.length === 0 && (
              <tr>
                <td colSpan="7" style={{ textAlign: 'center', padding: '60px', color: '#555' }}>
                  <CheckCircle size={36} style={{ margin: '0 auto 10px', display: 'block', opacity: 0.25 }} />
                  No report found.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      {detailReport   && <DetailModal   report={detailReport}   onClose={() => setDetailReport(null)} />}
      {decisionReport && <DecisionModal report={decisionReport} onClose={() => setDecisionReport(null)} onSaved={fetchReports} />}
    </div>
  );
}
