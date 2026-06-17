import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import axios from 'axios';
import { UserPlus, Upload, ShieldCheck, ArrowLeft } from 'lucide-react';
import '../index.css';

const BASE_URL = 'http://127.0.0.1:8000/api/admin';

export default function CreateDriver() {
  const navigate = useNavigate();
  const [formData, setFormData] = useState({
    full_name: '',
    email: '',
    phone: '',
    password: '',
    license_number: ''
  });
  
  const [files, setFiles] = useState({
    cin_card_photo: null,
    driver_card_photo: null
  });

  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);
  const [success, setSuccess] = useState(false);

  const handleInputChange = (e) => {
    setFormData({ ...formData, [e.target.name]: e.target.value });
  };

  const handleFileChange = (e) => {
    setFiles({ ...files, [e.target.name]: e.target.files[0] });
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    setLoading(true);
    setError(null);
    setSuccess(false);

    try {
      // Create FormData payload
      const data = new FormData();
      Object.keys(formData).forEach(key => {
        data.append(key, formData[key]);
      });
      if (files.cin_card_photo) data.append('cin_card_photo', files.cin_card_photo);
      if (files.driver_card_photo) data.append('driver_card_photo', files.driver_card_photo);
      
      // We assume this endpoint handles driver creation with multipart/form-data
      // Alternatively, it might just need JSON, but the user requested document upload support
      await axios.post(`${BASE_URL}/users/driver`, data, {
        headers: { 'Content-Type': 'multipart/form-data' }
      });
      
      setSuccess(true);
      setTimeout(() => navigate('/users'), 2000);
    } catch (err) {
      console.error('Error creating driver:', err);
      setError(err.response?.data?.detail || err.message || 'Une erreur est survenue lors de la création du chauffeur.');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div style={{ padding: '24px', maxWidth: '800px', margin: '0 auto' }}>
      <button 
        onClick={() => navigate(-1)}
        className="btn" 
        style={{ display: 'flex', alignItems: 'center', gap: '8px', marginBottom: '24px', backgroundColor: 'rgba(255,255,255,0.05)' }}
      >
        <ArrowLeft size={16} /> Back
      </button>

      <div className="glass-panel" style={{ padding: '40px' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '16px', marginBottom: '32px' }}>
          <div style={{ width: 56, height: 56, borderRadius: 16, background: 'linear-gradient(135deg, #FFCC00, #b38f00)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <UserPlus size={28} color="#000" />
          </div>
          <div>
            <h1 style={{ fontSize: '2rem', margin: '0 0 4px 0' }}>Create un Driver</h1>
            <p style={{ color: 'var(--text-secondary)', margin: 0 }}>Ajouter manuellement un nouveau chauffeur dans le système.</p>
          </div>
        </div>

        {error && (
          <div style={{ backgroundColor: 'rgba(248, 113, 113, 0.1)', border: '1px solid #f87171', color: '#f87171', padding: '16px', borderRadius: '12px', marginBottom: '24px' }}>
            {error}
          </div>
        )}

        {success && (
          <div style={{ backgroundColor: 'rgba(74, 222, 128, 0.1)', border: '1px solid #4ade80', color: '#4ade80', padding: '16px', borderRadius: '12px', marginBottom: '24px', display: 'flex', alignItems: 'center', gap: '12px' }}>
            <ShieldCheck size={24} /> Driver créé avec succès ! Redirection...
          </div>
        )}

        <form onSubmit={handleSubmit}>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '24px', marginBottom: '32px' }}>
            {/* Informations Personnelles */}
            <div style={{ gridColumn: '1 / -1' }}>
              <h2 style={{ fontSize: '1.1rem', color: 'var(--accent-color)', borderBottom: '1px solid rgba(255,255,255,0.1)', paddingBottom: '8px', marginBottom: '16px' }}>Informations Personnelles</h2>
            </div>
            
            <div>
              <label style={{ display: 'block', marginBottom: '8px', color: 'var(--text-secondary)', fontSize: '0.9rem' }}>Name Complet *</label>
              <input type="text" name="full_name" value={formData.full_name} onChange={handleInputChange} required
                className="input" style={{ width: '100%', padding: '12px', borderRadius: '12px', backgroundColor: 'rgba(255,255,255,0.03)', border: '1px solid rgba(255,255,255,0.1)', color: 'white', outline: 'none' }} />
            </div>

            <div>
              <label style={{ display: 'block', marginBottom: '8px', color: 'var(--text-secondary)', fontSize: '0.9rem' }}>Email *</label>
              <input type="email" name="email" value={formData.email} onChange={handleInputChange} required
                className="input" style={{ width: '100%', padding: '12px', borderRadius: '12px', backgroundColor: 'rgba(255,255,255,0.03)', border: '1px solid rgba(255,255,255,0.1)', color: 'white', outline: 'none' }} />
            </div>

            <div>
              <label style={{ display: 'block', marginBottom: '8px', color: 'var(--text-secondary)', fontSize: '0.9rem' }}>Phone *</label>
              <input type="text" name="phone" value={formData.phone} onChange={handleInputChange} required
                className="input" style={{ width: '100%', padding: '12px', borderRadius: '12px', backgroundColor: 'rgba(255,255,255,0.03)', border: '1px solid rgba(255,255,255,0.1)', color: 'white', outline: 'none' }} />
            </div>

            <div>
              <label style={{ display: 'block', marginBottom: '8px', color: 'var(--text-secondary)', fontSize: '0.9rem' }}>Password *</label>
              <input type="password" name="password" value={formData.password} onChange={handleInputChange} required minLength="6"
                className="input" style={{ width: '100%', padding: '12px', borderRadius: '12px', backgroundColor: 'rgba(255,255,255,0.03)', border: '1px solid rgba(255,255,255,0.1)', color: 'white', outline: 'none' }} />
            </div>

            {/* Informations Professionnelles */}
            <div style={{ gridColumn: '1 / -1', marginTop: '16px' }}>
              <h2 style={{ fontSize: '1.1rem', color: 'var(--accent-color)', borderBottom: '1px solid rgba(255,255,255,0.1)', paddingBottom: '8px', marginBottom: '16px' }}>Informations Professionnelles</h2>
            </div>

            <div style={{ gridColumn: '1 / -1' }}>
              <label style={{ display: 'block', marginBottom: '8px', color: 'var(--text-secondary)', fontSize: '0.9rem' }}>Numéro de Permis de Conduire *</label>
              <input type="text" name="license_number" value={formData.license_number} onChange={handleInputChange} required
                className="input" style={{ width: '100%', padding: '12px', borderRadius: '12px', backgroundColor: 'rgba(255,255,255,0.03)', border: '1px solid rgba(255,255,255,0.1)', color: 'white', outline: 'none' }} />
            </div>

            {/* Documents */}
            <div style={{ gridColumn: '1 / -1', marginTop: '16px' }}>
              <h2 style={{ fontSize: '1.1rem', color: 'var(--accent-color)', borderBottom: '1px solid rgba(255,255,255,0.1)', paddingBottom: '8px', marginBottom: '16px' }}>Documents Justificatifs</h2>
            </div>

            <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
              <label style={{ color: 'var(--text-secondary)', fontSize: '0.9rem' }}>Carte d'identité (CIN)</label>
              <div style={{ position: 'relative', overflow: 'hidden', display: 'inline-block' }}>
                <button type="button" className="btn" style={{ width: '100%', padding: '16px', backgroundColor: 'rgba(255,255,255,0.03)', border: '1px dashed rgba(255,255,255,0.2)', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '8px' }}>
                  <Upload size={24} color="var(--accent-color)" />
                  <span style={{ color: files.cin_card_photo ? '#4ade80' : 'white' }}>
                    {files.cin_card_photo ? files.cin_card_photo.name : 'Sélectionner un fichier...'}
                  </span>
                </button>
                <input type="file" name="cin_card_photo" onChange={handleFileChange} accept="image/*"
                  style={{ position: 'absolute', left: 0, top: 0, opacity: 0, width: '100%', height: '100%', cursor: 'pointer' }} />
              </div>
            </div>

            <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
              <label style={{ color: 'var(--text-secondary)', fontSize: '0.9rem' }}>Carte Professionnelle VTC</label>
              <div style={{ position: 'relative', overflow: 'hidden', display: 'inline-block' }}>
                <button type="button" className="btn" style={{ width: '100%', padding: '16px', backgroundColor: 'rgba(255,255,255,0.03)', border: '1px dashed rgba(255,255,255,0.2)', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: '8px' }}>
                  <Upload size={24} color="var(--accent-color)" />
                  <span style={{ color: files.driver_card_photo ? '#4ade80' : 'white' }}>
                    {files.driver_card_photo ? files.driver_card_photo.name : 'Sélectionner un fichier...'}
                  </span>
                </button>
                <input type="file" name="driver_card_photo" onChange={handleFileChange} accept="image/*"
                  style={{ position: 'absolute', left: 0, top: 0, opacity: 0, width: '100%', height: '100%', cursor: 'pointer' }} />
              </div>
            </div>
          </div>

          <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '16px', marginTop: '40px' }}>
            <button type="button" className="btn" style={{ backgroundColor: 'rgba(255,255,255,0.05)', padding: '12px 24px' }} onClick={() => navigate(-1)}>Cancel</button>
            <button type="submit" className="btn btn-primary" style={{ padding: '12px 32px', fontSize: '1.05rem', fontWeight: 600 }} disabled={loading}>
              {loading ? 'Création en cours...' : 'Create le chauffeur'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
