import { useState, useEffect } from 'react';
import axios from 'axios';
import { AlertTriangle, CheckCircle, Clock } from 'lucide-react';

const BASE_URL = 'http://127.0.0.1:8000/api/admin';

export default function Reports() {
  const [reports, setReports] = useState([]);
  const [loading, setLoading] = useState(true);
  const [resolutionText, setResolutionText] = useState({});

  useEffect(() => {
    fetchReports();
  }, []);

  const fetchReports = async () => {
    try {
      const response = await axios.get(`${BASE_URL}/reports`);
      setReports(response.data);
    } catch (error) {
      console.error('Error fetching reports:', error);
    } finally {
      setLoading(false);
    }
  };

  const handleUpdateStatus = async (reportId, status) => {
    try {
      await axios.put(`${BASE_URL}/reports/${reportId}/status`, {
        status: status,
        resolution_note: resolutionText[reportId] || null
      });
      alert('Report updated successfully');
      setResolutionText({ ...resolutionText, [reportId]: '' });
      fetchReports();
    } catch (error) {
      console.error('Error updating report:', error);
      alert('Failed to update report');
    }
  };

  const getStatusBadge = (status) => {
    switch(status) {
      case 'open': return <span className="badge badge-pending">Open</span>;
      case 'resolved': return <span className="badge badge-active">Resolved</span>;
      case 'rejected': return <span className="badge badge-inactive">Rejected</span>;
      default: return <span className="badge">{status}</span>;
    }
  };

  if (loading) {
    return <div style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', height: '100%' }}>Loading...</div>;
  }

  return (
    <div>
      <div style={{ marginBottom: '32px' }}>
        <h1 style={{ fontSize: '2rem', marginBottom: '8px' }}>Reports & Complaints</h1>
        <p style={{ color: 'var(--text-secondary)' }}>Manage user complaints and incident reports.</p>
      </div>

      <div style={{ display: 'flex', flexDirection: 'column', gap: '20px' }}>
        {reports.map(report => (
          <div key={report.report_id} className="glass-panel" style={{ padding: '24px' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: '16px' }}>
              <div>
                <h3 style={{ display: 'flex', alignItems: 'center', gap: '8px', fontSize: '1.2rem', marginBottom: '4px' }}>
                  <AlertTriangle color="var(--accent-color)" size={20} />
                  Report #{report.report_id} - {report.report_type}
                </h3>
                <p style={{ color: 'var(--text-secondary)', fontSize: '0.9rem' }}>
                  Reported by <strong style={{ color: 'var(--text-primary)' }}>{report.reporter_name}</strong> • Ride ID #{report.ride_id} • {new Date(report.created_at).toLocaleString()}
                </p>
              </div>
              <div>
                {getStatusBadge(report.status)}
              </div>
            </div>
            
            <div style={{ background: 'var(--input-bg)', padding: '16px', borderRadius: '12px', marginBottom: '20px', border: '1px solid var(--panel-border)' }}>
              <p>{report.description}</p>
            </div>

            {report.status === 'open' ? (
              <div style={{ borderTop: '1px solid var(--panel-border)', paddingTop: '16px' }}>
                <textarea 
                  placeholder="Resolution Note..."
                  className="form-select"
                  style={{ minHeight: '80px', resize: 'vertical', marginBottom: '12px' }}
                  value={resolutionText[report.report_id] || ''}
                  onChange={(e) => setResolutionText({...resolutionText, [report.report_id]: e.target.value})}
                ></textarea>
                <div style={{ display: 'flex', gap: '12px' }}>
                  <button className="btn btn-success" onClick={() => handleUpdateStatus(report.report_id, 'resolved')}>
                    <CheckCircle size={18} /> Mark Resolved
                  </button>
                  <button className="btn btn-danger" onClick={() => handleUpdateStatus(report.report_id, 'rejected')}>
                    Reject Report
                  </button>
                </div>
              </div>
            ) : (
              report.resolution_note && (
                <div style={{ borderTop: '1px solid var(--panel-border)', paddingTop: '16px' }}>
                  <h4 style={{ fontSize: '0.9rem', color: 'var(--text-secondary)', marginBottom: '8px' }}>Resolution Note</h4>
                  <p style={{ color: 'var(--success)' }}>{report.resolution_note}</p>
                </div>
              )
            )}
          </div>
        ))}
        
        {reports.length === 0 && (
          <div className="glass-panel" style={{ padding: '60px', textAlign: 'center', color: 'var(--text-secondary)' }}>
            <CheckCircle size={48} style={{ margin: '0 auto 16px', opacity: 0.5, color: 'var(--success)' }} />
            <p>No reports or complaints right now. Good job!</p>
          </div>
        )}
      </div>
    </div>
  );
}
