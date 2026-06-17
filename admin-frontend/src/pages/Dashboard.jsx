import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  Users, Car, CheckCircle, Clock, TrendingUp,
  AlertTriangle, XCircle, Activity, UserPlus
} from 'lucide-react';
import axios from 'axios';
import {
  Chart as ChartJS,
  CategoryScale, LinearScale, PointElement, LineElement,
  BarElement, ArcElement, Title, Tooltip, Legend, Filler,
} from 'chart.js';
import { Line, Bar, Doughnut } from 'react-chartjs-2';

ChartJS.register(
  CategoryScale, LinearScale, PointElement, LineElement,
  BarElement, ArcElement, Title, Tooltip, Legend, Filler
);

const BASE_URL = 'http://127.0.0.1:8000/api/admin';

// ── Shared chart style helpers ────────────────────────────────────────────────
const tooltip = {
  backgroundColor: '#111', titleColor: '#fff',
  bodyColor: '#a0a0a0', borderColor: '#333', borderWidth: 1,
};
const gridX = { grid: { color: 'rgba(255,255,255,0.04)' }, ticks: { color: '#a0a0a0', font: { size: 11 } } };
const gridY = { grid: { color: 'rgba(255,255,255,0.04)' }, ticks: { color: '#a0a0a0', font: { size: 11 } } };

const lineOpts = {
  responsive: true, maintainAspectRatio: false,
  plugins: { legend: { display: false }, tooltip },
  scales: { x: gridX, y: gridY },
};

const barOpts = {
  responsive: true, maintainAspectRatio: false,
  plugins: { legend: { display: false }, tooltip },
  scales: { x: { ...gridX, grid: { display: false } }, y: gridY },
};

const donutOpts = (showLegend = true) => ({
  responsive: true, maintainAspectRatio: false, cutout: '70%',
  plugins: {
    legend: showLegend
      ? { position: 'bottom', labels: { color: '#a0a0a0', boxWidth: 11, padding: 14, font: { size: 11 } } }
      : { display: false },
    tooltip: { ...tooltip, callbacks: { label: ctx => ` ${ctx.label}: ${ctx.parsed}` } },
  },
});

export default function Dashboard() {
  const navigate = useNavigate();
  const [stats, setStats]       = useState(null);
  const [analytics, setAnalytics] = useState(null);
  const [loading, setLoading]   = useState(true);

  useEffect(() => {
    Promise.all([
      axios.get(`${BASE_URL}/stats`),
      axios.get(`${BASE_URL}/analytics`),
    ]).then(([s, a]) => {
      setStats(s.data);
      setAnalytics(a.data);
    }).catch(e => console.error(e))
      .finally(() => setLoading(false));
  }, []);

  if (loading) {
    return (
      <div style={{ display: 'flex', justifyContent: 'center', alignItems: 'center', height: '60vh', flexDirection: 'column', gap: 16 }}>
        <div className="spinner" />
        <p style={{ color: 'var(--text-secondary)' }}>Loading...</p>
      </div>
    );
  }

  // ── Shortcuts ─────────────────────────────────────────────────────────────
  const labels      = analytics?.labels        ?? [];
  const ridesDay    = analytics?.rides_per_day ?? [];
  const revDay      = analytics?.revenue_per_day ?? [];
  const rStatus     = analytics?.ride_status   ?? { completed: 0, cancelled: 0, pending: 0, accepted: 0 };
  const drivers     = analytics?.drivers       ?? { active: 0, inactive: 0 };
  const incidents   = analytics?.incidents     ?? { total: 0, open: 0, closed: 0 };
  const compRate    = analytics?.completion_rate   ?? 0;
  const cancelRate  = analytics?.cancellation_rate ?? 0;

  // ── Chart datasets ────────────────────────────────────────────────────────
  const revenueData = {
    labels,
    datasets: [{
      label: 'Revenue (DT)',
      data: revDay,
      fill: true, tension: 0.45,
      borderColor: '#FFCC00', borderWidth: 2,
      backgroundColor: 'rgba(255,204,0,0.07)',
      pointBackgroundColor: '#FFCC00', pointRadius: 4, pointHoverRadius: 6,
    }],
  };

  const ridesData = {
    labels,
    datasets: [{
      label: 'Rides',
      data: ridesDay,
      backgroundColor: 'rgba(255,204,0,0.75)',
      borderRadius: 8, borderSkipped: false,
      hoverBackgroundColor: '#FFCC00',
    }],
  };

  const rideStatusData = {
    labels: ['Completed', 'Cancelled', 'Pending', 'Accepted'],
    datasets: [{
      data: [rStatus.completed, rStatus.cancelled, rStatus.pending, rStatus.accepted],
      backgroundColor: [
        'rgba(74,222,128,0.8)',
        'rgba(248,113,113,0.8)',
        'rgba(255,204,0,0.8)',
        'rgba(99,179,237,0.8)',
      ],
      borderColor: ['#4ade80', '#f87171', '#FFCC00', '#63b3ed'],
      borderWidth: 2, hoverOffset: 5,
    }],
  };

  const driverStatusData = {
    labels: ['Active', 'Inactifs/Pending'],
    datasets: [{
      data: [drivers.active, drivers.inactive],
      backgroundColor: ['rgba(74,222,128,0.8)', 'rgba(248,113,113,0.8)'],
      borderColor: ['#4ade80', '#f87171'],
      borderWidth: 2, hoverOffset: 5,
    }],
  };

  // ── Sub-components ────────────────────────────────────────────────────────
  const StatCard = ({ title, value, icon, color, suffix = '' }) => (
    <div className="glass-panel" style={{ padding: '20px', display: 'flex', alignItems: 'center', gap: '16px' }}>
      <div style={{
        width: 50, height: 50, borderRadius: '13px',
        background: `rgba(${color}, 0.12)`,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        color: `rgb(${color})`, flexShrink: 0,
      }}>
        {icon}
      </div>
      <div>
        <p style={{ color: 'var(--text-secondary)', fontSize: '0.75rem', textTransform: 'uppercase', letterSpacing: '0.06em', marginBottom: '3px' }}>{title}</p>
        <p style={{ fontSize: '1.75rem', fontWeight: '700', lineHeight: 1 }}>{value}{suffix}</p>
      </div>
    </div>
  );

  const ChartPanel = ({ title, subtitle, children, height = 220 }) => (
    <div className="glass-panel" style={{ padding: '22px', display: 'flex', flexDirection: 'column' }}>
      <div style={{ marginBottom: '16px' }}>
        <h2 style={{ fontSize: '0.95rem', fontWeight: '600', marginBottom: '3px' }}>{title}</h2>
        {subtitle && <p style={{ color: 'var(--text-secondary)', fontSize: '0.78rem' }}>{subtitle}</p>}
      </div>
      <div style={{ height, position: 'relative' }}>{children}</div>
    </div>
  );

  const DonutCenter = ({ value, label, color = '#FFCC00' }) => (
    <div style={{
      position: 'absolute', top: 0, left: 0, right: 0, bottom: 40,
      display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center',
      pointerEvents: 'none',
    }}>
      <span style={{ fontSize: '1.7rem', fontWeight: '700', color }}>{value}</span>
      <span style={{ fontSize: '0.7rem', color: 'var(--text-secondary)', marginTop: 2 }}>{label}</span>
    </div>
  );

  const totalRides = rStatus.completed + rStatus.cancelled + rStatus.pending + rStatus.accepted;

  return (
    <div>
      {/* ── Header ─────────────────────────────────────────────────────────── */}
      <div style={{ marginBottom: '28px', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <div>
          <h1 style={{ fontSize: '2rem', marginBottom: '6px' }}>Dashboard</h1>
          <p style={{ color: 'var(--text-secondary)' }}>Statistics (system overview) </p>
        </div>
        
      </div>

      {/* ── KPI Cards ──────────────────────────────────────────────────────── */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))', gap: '16px', marginBottom: '20px' }}>
        <StatCard title="Total Revenue"      value={(stats?.total_revenue ?? 0).toFixed(2)} suffix=" DT" icon={<TrendingUp size={22} />} color="255, 204, 0"   />
        <StatCard title="Passengers"         value={stats?.total_users    ?? 0}                          icon={<Users size={22}       />} color="255, 255, 255" />
        <StatCard title="Active Drivers" value={drivers.active}                                      icon={<Car size={22}         />} color="74, 222, 128"  />
        <StatCard title="Pending Approval" value={stats?.pending_drivers ?? 0}                         icon={<Clock size={22}       />} color="255, 204, 0"   />
        <StatCard title="Total Rides"     value={totalRides}                                          icon={<Activity size={22}    />} color="160, 160, 160" />
        <StatCard title="Completion Rate"   value={`${compRate}%`}                                      icon={<CheckCircle size={22} />} color="74, 222, 128"  />
        <StatCard title="Cancellation Rate"   value={`${cancelRate}%`}                                    icon={<XCircle size={22}     />} color="248, 113, 113" />
        <StatCard title="Open Incidents" value={incidents.open}                                      icon={<AlertTriangle size={22}/>} color="248, 113, 113"/>
      </div>

      {/* ── Charts row 1: Revenu + Rides 7j ──────────────────────────────── */}
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '18px', marginBottom: '18px' }}>
        <ChartPanel
          title="💰 Revenue — Last 7 Days"
          subtitle="Collected amounts "
          height={220}
        >
          <Line data={revenueData} options={lineOpts} />
        </ChartPanel>
        <ChartPanel
          title="🚕 Rides — Last 7 Days"
          subtitle="Number of requests (ride_requests)"
          height={220}
        >
          <Bar data={ridesData} options={barOpts} />
        </ChartPanel>
      </div>

      {/* ── Charts row 2: Statuss courses + Statuss chauffeurs ─────────────── */}
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '18px' }}>
        <ChartPanel
          title="📊 Rides Distribution"
          subtitle="By status — all rides in the DB"
          height={230}
        >
          <DonutCenter value={totalRides} label="rides" color="#FFCC00" />
          <Doughnut data={rideStatusData} options={donutOpts(true)} />
        </ChartPanel>

        <ChartPanel
          title="👨‍✈️ Drivers Status"
          subtitle="Active drivers vs pending approval"
          height={230}
        >
          <DonutCenter
            value={drivers.active + drivers.inactive}
            label="drivers"
            color="#4ade80"
          />
          <Doughnut data={driverStatusData} options={donutOpts(true)} />
        </ChartPanel>
      </div>
    </div>
  );
}
