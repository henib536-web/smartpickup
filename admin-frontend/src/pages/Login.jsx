import { useState } from 'react';
import { Mail, Lock, Car, AlertCircle, ArrowRight } from 'lucide-react';
import axios from 'axios';

export default function Login({ onLoginSuccess }) {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [rememberMe, setRememberMe] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState('');

  const handleSubmit = async (e) => {
    e.preventDefault();
    if (!email || !password) {
      setError('Please fill in all fields.');
      return;
    }

    setIsLoading(true);
    setError('');

    try {
      const response = await axios.post('http://127.0.0.1:8000/auth/login', {
        email: email.trim(),
        password,
        remember_me: rememberMe,
      });

      const data = response.data;

      // Vérifier si l'utilisateur connecté est bien un admin
      if (data.role !== 'admin') {
        setError('Access denied. This console is reserved for administrators.');
        setIsLoading(false);
        return;
      }

      // Passer les données à l'application principale
      onLoginSuccess({
        access_token: data.access_token,
        user_id: data.user_id,
        email: data.email,
        full_name: data.full_name,
        role: data.role,
      });
    } catch (err) {
      console.error(err);
      if (err.response && err.response.data && err.response.data.detail) {
        setError(err.response.data.detail);
      } else {
        setError('Cannot connect to backend server.');
      }
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div className="login-page-container">
      {/* Decorative background effects */}
      <div className="login-bg-glow" />
      <div className="login-bg-glow-bottom" />

      <div className="login-card">
        <div className="login-header">
          <div className="login-logo-container">
            <Car size={32} color="black" />
          </div>
          <h1 className="login-title">SmartPickup</h1>
          <p className="login-subtitle">Sign in to access the dashboard</p>
        </div>

        {error && (
          <div className="login-error-alert">
            <AlertCircle size={18} style={{ flexShrink: 0 }} />
            <span>{error}</span>
          </div>
        )}

        <form onSubmit={handleSubmit}>
          <div className="login-form-group">
            <label className="login-form-label">Email Address</label>
            <div className="login-input-wrapper">
              <Mail className="login-input-icon" size={18} />
              <input
                type="email"
                className="login-input"
                placeholder="name@example.com"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                required
                disabled={isLoading}
              />
            </div>
          </div>

          <div className="login-form-group">
            <label className="login-form-label">Password</label>
            <div className="login-input-wrapper">
              <Lock className="login-input-icon" size={18} />
              <input
                type="password"
                className="login-input"
                placeholder="••••••••"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                required
                disabled={isLoading}
              />
            </div>
          </div>

          <div className="login-options">
            <label className="login-remember">
              <input
                type="checkbox"
                checked={rememberMe}
                onChange={(e) => setRememberMe(e.target.checked)}
                disabled={isLoading}
              />
              <span>Remember me</span>
            </label>
          </div>

          <button type="submit" className="login-btn" disabled={isLoading}>
            {isLoading ? (
              <div className="spinner" style={{ width: 20, height: 20, margin: 0, borderWidth: 2 }} />
            ) : (
              <>
                <span>Sign in</span>
                <ArrowRight size={18} />
              </>
            )}
          </button>
        </form>
      </div>
    </div>
  );
}
