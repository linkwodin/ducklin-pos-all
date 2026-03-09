import { useState, useEffect, useRef, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  TextField,
  Button,
  Typography,
  Box,
  Alert,
  InputAdornment,
  IconButton,
  CircularProgress,
} from '@mui/material';
import {
  Visibility,
  VisibilityOff,
  PersonOutline,
  LockOutlined,
} from '@mui/icons-material';
import { keyframes } from '@emotion/react';
import { useAuth } from '../context/AuthContext';
import { useSnackbar } from 'notistack';
import { useTranslation } from 'react-i18next';
import LanguageSelector from '../components/LanguageSelector';

const envLabel =
  import.meta.env.MODE === 'uat' ? 'UAT' :
  import.meta.env.MODE === 'development' ? 'DEV' :
  null;

const shake = keyframes`
  0%, 100% { transform: translateX(0); }
  15% { transform: translateX(-6px); }
  30% { transform: translateX(5px); }
  45% { transform: translateX(-4px); }
  60% { transform: translateX(3px); }
  75% { transform: translateX(-1px); }
`;

const drift1 = keyframes`
  0%, 100% { transform: translate(0, 0) scale(1); }
  25% { transform: translate(80px, -50px) scale(1.15); }
  50% { transform: translate(-40px, 60px) scale(0.9); }
  75% { transform: translate(50px, 25px) scale(1.08); }
`;

const drift2 = keyframes`
  0%, 100% { transform: translate(0, 0) scale(1); }
  25% { transform: translate(-60px, 40px) scale(1.12); }
  50% { transform: translate(50px, -60px) scale(0.88); }
  75% { transform: translate(-35px, -25px) scale(1.05); }
`;

const drift3 = keyframes`
  0%, 100% { transform: translate(0, 0) scale(1); }
  33% { transform: translate(45px, 50px) scale(1.1); }
  66% { transform: translate(-55px, -35px) scale(0.92); }
`;

const shimmer = keyframes`
  0%, 100% { filter: drop-shadow(0 2px 8px rgba(0,0,0,0.06)); }
  50% { filter: drop-shadow(0 4px 20px rgba(59,130,246,0.18)); }
`;

interface Particle {
  x: number; y: number; vx: number; vy: number;
  radius: number; opacity: number; hue: number;
}

function useParticleCanvas() {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const mouseRef = useRef({ x: -1000, y: -1000 });
  const rafRef = useRef(0);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const resize = () => { canvas.width = window.innerWidth; canvas.height = window.innerHeight; };
    resize();
    window.addEventListener('resize', resize);

    const particles: Particle[] = [];
    for (let i = 0; i < 45; i++) {
      particles.push({
        x: Math.random() * canvas.width,
        y: Math.random() * canvas.height,
        vx: (Math.random() - 0.5) * 0.25,
        vy: (Math.random() - 0.5) * 0.25,
        radius: Math.random() * 1.5 + 0.5,
        opacity: Math.random() * 0.18 + 0.04,
        hue: 200 + Math.random() * 80,
      });
    }

    const draw = () => {
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      const mx = mouseRef.current.x;
      const my = mouseRef.current.y;

      for (const p of particles) {
        const dx = mx - p.x;
        const dy = my - p.y;
        const dist = Math.sqrt(dx * dx + dy * dy);
        if (dist < 130) {
          const force = (130 - dist) / 130;
          p.vx -= (dx / dist) * force * 0.08;
          p.vy -= (dy / dist) * force * 0.08;
        }
        p.vx *= 0.993;
        p.vy *= 0.993;
        p.x += p.vx;
        p.y += p.vy;
        if (p.x < 0) p.x = canvas.width;
        if (p.x > canvas.width) p.x = 0;
        if (p.y < 0) p.y = canvas.height;
        if (p.y > canvas.height) p.y = 0;

        ctx.beginPath();
        ctx.arc(p.x, p.y, p.radius, 0, Math.PI * 2);
        const boost = dist < 160 ? 0.15 : 0;
        ctx.fillStyle = `hsla(${p.hue}, 40%, 60%, ${p.opacity + boost})`;
        ctx.fill();
      }

      for (let i = 0; i < particles.length; i++) {
        for (let j = i + 1; j < particles.length; j++) {
          const dx = particles[i].x - particles[j].x;
          const dy = particles[i].y - particles[j].y;
          const dist = Math.sqrt(dx * dx + dy * dy);
          if (dist < 90) {
            ctx.beginPath();
            ctx.moveTo(particles[i].x, particles[i].y);
            ctx.lineTo(particles[j].x, particles[j].y);
            ctx.strokeStyle = `rgba(150, 170, 220, ${0.035 * (1 - dist / 90)})`;
            ctx.lineWidth = 0.5;
            ctx.stroke();
          }
        }
      }

      rafRef.current = requestAnimationFrame(draw);
    };
    rafRef.current = requestAnimationFrame(draw);

    return () => { cancelAnimationFrame(rafRef.current); window.removeEventListener('resize', resize); };
  }, []);

  const handleMouseMove = useCallback((e: React.MouseEvent) => {
    mouseRef.current = { x: e.clientX, y: e.clientY };
  }, []);

  return { canvasRef, handleMouseMove };
}

// Liquid glass input fields
const liquidInputSx = {
  '& .MuiOutlinedInput-root': {
    borderRadius: '14px',
    backgroundColor: 'rgba(255,255,255,0.7)',
    transition: 'all 0.3s cubic-bezier(0.16,1,0.3,1)',
    '& fieldset': {
      borderColor: 'rgba(255,255,255,0.18)',
      borderWidth: '1px',
      transition: 'border-color 0.3s ease',
    },
    '&:hover': {
      backgroundColor: 'rgba(255,255,255,0.18)',
    },
    '&:hover fieldset': {
      borderColor: 'rgba(255,255,255,0.3)',
    },
    '&.Mui-focused': {
      backgroundColor: 'rgba(255,255,255,0.22)',
      boxShadow: '0 0 0 3px rgba(0,122,255,0.12), inset 0 1px 0 rgba(255,255,255,0.15)',
    },
    '&.Mui-focused fieldset': {
      borderColor: 'rgba(0,122,255,0.35)',
      borderWidth: '1.5px',
    },
  },
  '& .MuiOutlinedInput-input': {
    // Safari: ensure input is interactive and doesn't get blocked
    pointerEvents: 'auto',
    WebkitAppearance: 'none',
    fontSize: '16px', // avoids iOS zoom and helps Safari focus
  },
  '& input::-ms-reveal, & input::-ms-clear': { display: 'none' },
  '& input::-webkit-credentials-auto-fill-button': { display: 'none' },
  '& input::-webkit-textfield-decoration-container': { display: 'none' },
};

export default function LoginPage() {
  const { t } = useTranslation();
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const [shakeKey, setShakeKey] = useState(0);
  const [mounted, setMounted] = useState(false);
  // Safari: start inputs readOnly and unlock on first focus so keyboard opens
  const [inputsUnlocked, setInputsUnlocked] = useState(false);
  const { login } = useAuth();
  const navigate = useNavigate();
  const { enqueueSnackbar } = useSnackbar();
  const { canvasRef, handleMouseMove } = useParticleCanvas();

  useEffect(() => {
    const id = requestAnimationFrame(() => setMounted(true));
    return () => cancelAnimationFrame(id);
  }, []);

  const handleSubmit = async (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    setError('');
    setLoading(true);
    try {
      await login(username, password);
      enqueueSnackbar('Login successful', { variant: 'success' });
      navigate('/');
    } catch (err: any) {
      setError(err.response?.data?.error || 'Login failed');
      setShakeKey((k) => k + 1);
      enqueueSnackbar('Login failed', { variant: 'error' });
    } finally {
      setLoading(false);
    }
  };

  const stagger = (delayMs: number) => ({
    opacity: mounted ? 1 : 0,
    transform: mounted ? 'translateY(0) scale(1)' : 'translateY(24px) scale(0.97)',
    transition: `opacity 0.8s cubic-bezier(0.16,1,0.3,1) ${delayMs}ms, transform 0.8s cubic-bezier(0.16,1,0.3,1) ${delayMs}ms`,
  });

  return (
    <Box
      onMouseMove={handleMouseMove}
      sx={{
        minHeight: '100vh',
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        justifyContent: 'center',
        // Rich colorful background so the glass refraction is visible
        background: 'linear-gradient(160deg, #c2d7f5 0%, #d4c5f0 25%, #e8d0d0 50%, #c8dce8 75%, #d0d5ef 100%)',
        position: 'relative',
        overflow: 'hidden',
      }}
    >
      {/* Large vivid gradient blobs — the color source for glass refraction */}
      <Box sx={{
        position: 'absolute', top: '-12%', right: '-8%',
        width: 550, height: 550, borderRadius: '50%',
        background: 'radial-gradient(circle, rgba(80,140,255,0.5) 0%, transparent 65%)',
        animation: `${drift1} 20s ease-in-out infinite`,
        pointerEvents: 'none', filter: 'blur(30px)',
      }} />
      <Box sx={{
        position: 'absolute', bottom: '-10%', left: '-10%',
        width: 500, height: 500, borderRadius: '50%',
        background: 'radial-gradient(circle, rgba(180,100,255,0.45) 0%, transparent 65%)',
        animation: `${drift2} 24s ease-in-out infinite`,
        pointerEvents: 'none', filter: 'blur(30px)',
      }} />
      <Box sx={{
        position: 'absolute', top: '25%', left: '50%',
        width: 420, height: 420, borderRadius: '50%',
        background: 'radial-gradient(circle, rgba(60,200,255,0.35) 0%, transparent 65%)',
        animation: `${drift3} 28s ease-in-out infinite`,
        pointerEvents: 'none', filter: 'blur(25px)',
      }} />
      <Box sx={{
        position: 'absolute', top: '55%', right: '35%',
        width: 380, height: 380, borderRadius: '50%',
        background: 'radial-gradient(circle, rgba(255,140,180,0.35) 0%, transparent 65%)',
        animation: `${drift1} 26s ease-in-out infinite reverse`,
        pointerEvents: 'none', filter: 'blur(25px)',
      }} />
      <Box sx={{
        position: 'absolute', top: '10%', left: '15%',
        width: 300, height: 300, borderRadius: '50%',
        background: 'radial-gradient(circle, rgba(100,255,200,0.25) 0%, transparent 65%)',
        animation: `${drift2} 32s ease-in-out infinite reverse`,
        pointerEvents: 'none', filter: 'blur(30px)',
      }} />

      {/* Particle canvas */}
      <canvas
        ref={canvasRef}
        style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', pointerEvents: 'none', zIndex: 0 }}
      />

      {/* Environment badge — liquid glass style */}
      {envLabel && (
        <Box sx={{
          position: 'absolute', top: 16, left: 16, zIndex: 3,
          px: 1.5, py: 0.5, borderRadius: '10px',
          fontSize: '0.7rem', fontWeight: 700, letterSpacing: '0.06em',
          color: '#fff',
          background: envLabel === 'DEV'
            ? 'linear-gradient(135deg, rgba(245,158,11,0.7), rgba(245,158,11,0.5))'
            : 'linear-gradient(135deg, rgba(139,92,246,0.7), rgba(139,92,246,0.5))',
          backdropFilter: 'blur(20px)', WebkitBackdropFilter: 'blur(20px)',
          border: '1px solid rgba(255,255,255,0.2)',
          boxShadow: '0 4px 12px rgba(0,0,0,0.1), inset 0 1px 0 rgba(255,255,255,0.2)',
        }}>
          {envLabel}
        </Box>
      )}

      {/* Language selector */}
      <Box sx={{ position: 'absolute', top: 16, right: 16, zIndex: 3 }}>
        <LanguageSelector />
      </Box>

      {/* Main content */}
      <Box sx={{ width: '100%', maxWidth: 400, mx: 2, zIndex: 1 }}>
        {/* Logo & Company Name */}
        <Box sx={{ display: 'flex', flexDirection: 'column', alignItems: 'center', mb: 3.5, ...stagger(0) }}>
          <Box
            component="img"
            src="/logo.png"
            alt="Company Logo"
            sx={{
              height: 64, width: 'auto', objectFit: 'contain', mb: 1.5,
              animation: `${shimmer} 4s ease-in-out infinite`,
            }}
          />
          <Typography sx={{ fontSize: '1.05rem', fontWeight: 600, color: 'rgba(0,0,0,0.8)', letterSpacing: '0.02em' }}>
            Ducklin Company UK
          </Typography>
          <Typography sx={{
            fontSize: '0.72rem', fontWeight: 500, color: 'rgba(0,0,0,0.4)',
            letterSpacing: '0.1em', textTransform: 'uppercase', mt: 0.25,
          }}>
            Management Portal
          </Typography>
        </Box>

        {/* ── Liquid Glass Card ── */}
        <Box
          key={shakeKey}
          sx={{
            ...stagger(100),
            ...(error ? { animation: `${shake} 0.5s ease-out` } : {}),
          }}
        >
          <Box
            sx={{
              position: 'relative',
              borderRadius: '24px',
              p: { xs: 3, sm: 4 },
              overflow: 'hidden',
              // Solid background (no backdrop-filter) so Safari can focus/type in inputs
              background: 'linear-gradient(135deg, rgba(255,255,255,0.96) 0%, rgba(255,255,255,0.92) 100%)',
              border: '1px solid rgba(255,255,255,0.4)',
              boxShadow: `
                0 8px 32px rgba(0,0,0,0.12),
                inset 0 1px 0 rgba(255,255,255,0.5),
                inset 0 -0.5px 0 rgba(0,0,0,0.05)
              `,
              '&::before': {
                content: '""',
                position: 'absolute',
                inset: 0,
                borderRadius: '24px',
                background: 'linear-gradient(135deg, rgba(255,255,255,0.2) 0%, rgba(255,255,255,0.05) 50%, transparent 100%)',
                mixBlendMode: 'overlay',
                pointerEvents: 'none',
              },
              '&::after': {
                content: '""',
                position: 'absolute',
                inset: '-1px',
                borderRadius: '24px',
                background: `
                  radial-gradient(ellipse at 25% 0%, rgba(255,255,255,0.3) 0%, transparent 50%),
                  radial-gradient(ellipse at 75% 100%, rgba(255,255,255,0.1) 0%, transparent 50%)
                `,
                pointerEvents: 'none',
              },
            }}
          >
            <Box sx={{ position: 'relative', zIndex: 2, pointerEvents: 'auto', isolation: 'isolate' }}>
              <Typography
                variant="h5" align="center"
                sx={{ fontWeight: 700, color: 'rgba(0,0,0,0.8)', mb: 0.5, fontSize: '1.35rem' }}
              >
                {t('login.title')}
              </Typography>
              <Typography
                variant="body2" align="center"
                sx={{ color: 'rgba(0,0,0,0.4)', mb: 3, fontSize: '0.85rem' }}
              >
                {t('login.subtitle')}
              </Typography>

              {error && (
                <Alert
                  severity="error"
                  sx={{
                    mb: 2.5, borderRadius: '14px',
                    backgroundColor: 'rgba(255,59,48,0.1)',
                    backdropFilter: 'blur(8px)',
                    border: '1px solid rgba(255,59,48,0.15)',
                    '& .MuiAlert-icon': { color: '#ff3b30' },
                    '& .MuiAlert-message': { fontSize: '0.85rem', color: 'rgba(0,0,0,0.75)' },
                  }}
                >
                  {error}
                </Alert>
              )}

              <Box component="form" onSubmit={handleSubmit} sx={{ position: 'relative', zIndex: 1 }}>
                <TextField
                  fullWidth required
                  id="username"
                  name="username"
                  placeholder={t('login.username')}
                  autoComplete="username"
                  autoFocus={!inputsUnlocked}
                  value={username}
                  onChange={(e: React.ChangeEvent<HTMLInputElement>) => setUsername(e.target.value)}
                  onFocus={() => setInputsUnlocked(true)}
                  onTouchStart={() => setInputsUnlocked(true)}
                  inputProps={{
                    'aria-label': t('login.username'),
                    style: { fontSize: 16 },
                    readOnly: !inputsUnlocked,
                  }}
                  InputProps={{
                    startAdornment: (
                      <InputAdornment position="start">
                        <PersonOutline sx={{ color: 'rgba(0,0,0,0.35)', fontSize: 20 }} />
                      </InputAdornment>
                    ),
                  }}
                  sx={{ mb: 1.5, ...liquidInputSx }}
                />

                <TextField
                  fullWidth required
                  name="password"
                  placeholder={t('login.password')}
                  type={showPassword ? 'text' : 'password'}
                  id="password"
                  autoComplete="current-password"
                  value={password}
                  onChange={(e: React.ChangeEvent<HTMLInputElement>) => setPassword(e.target.value)}
                  onFocus={() => setInputsUnlocked(true)}
                  onTouchStart={() => setInputsUnlocked(true)}
                  inputProps={{
                    'data-lpignore': 'true',
                    'aria-label': t('login.password'),
                    style: { fontSize: 16 },
                    readOnly: !inputsUnlocked,
                  }}
                  InputProps={{
                    startAdornment: (
                      <InputAdornment position="start">
                        <LockOutlined sx={{ color: 'rgba(0,0,0,0.35)', fontSize: 20 }} />
                      </InputAdornment>
                    ),
                    endAdornment: (
                      <InputAdornment position="end">
                        <IconButton
                          onClick={() => setShowPassword(!showPassword)}
                          edge="end" size="small"
                          sx={{ color: 'rgba(0,0,0,0.35)' }}
                        >
                          {showPassword ? <VisibilityOff fontSize="small" /> : <Visibility fontSize="small" />}
                        </IconButton>
                      </InputAdornment>
                    ),
                  }}
                  sx={{ mb: 3, ...liquidInputSx }}
                />

                {/* Liquid glass button */}
                <Button
                  type="submit" fullWidth variant="contained" disabled={loading}
                  sx={{
                    py: 1.4,
                    borderRadius: '14px',
                    fontSize: '0.95rem',
                    fontWeight: 600,
                    textTransform: 'none',
                    color: '#fff',
                    background: 'linear-gradient(135deg, rgba(0,122,255,0.75) 0%, rgba(80,60,230,0.65) 100%)',
                    backdropFilter: 'blur(16px)',
                    WebkitBackdropFilter: 'blur(16px)',
                    border: '1px solid rgba(255,255,255,0.2)',
                    boxShadow: `
                      0 6px 20px rgba(0,80,200,0.2),
                      inset 0 1px 0 rgba(255,255,255,0.25),
                      inset 0 -1px 0 rgba(0,0,0,0.05)
                    `,
                    transition: 'all 0.25s cubic-bezier(0.16,1,0.3,1)',
                    '&:hover': {
                      background: 'linear-gradient(135deg, rgba(0,110,240,0.85) 0%, rgba(70,50,220,0.75) 100%)',
                      boxShadow: `
                        0 8px 28px rgba(0,80,200,0.3),
                        inset 0 1px 0 rgba(255,255,255,0.3),
                        inset 0 -1px 0 rgba(0,0,0,0.06)
                      `,
                      transform: 'translateY(-1px)',
                    },
                    '&:active': {
                      transform: 'translateY(0)',
                      boxShadow: '0 2px 10px rgba(0,80,200,0.15), inset 0 1px 0 rgba(255,255,255,0.15)',
                    },
                    '&.Mui-disabled': {
                      background: 'rgba(255,255,255,0.12)',
                      backdropFilter: 'blur(12px)',
                      color: 'rgba(0,0,0,0.3)',
                      border: '1px solid rgba(255,255,255,0.15)',
                      boxShadow: 'none',
                    },
                  }}
                >
                  {loading ? (
                    <CircularProgress size={22} sx={{ color: '#fff' }} />
                  ) : (
                    t('login.signIn')
                  )}
                </Button>
              </Box>
            </Box>
          </Box>
        </Box>
      </Box>

      {/* Footer pinned to bottom */}
      <Typography
        variant="caption" align="center"
        sx={{
          position: 'absolute', bottom: 16, left: 0, right: 0,
          color: 'rgba(0,0,0,0.35)', fontSize: '0.7rem', zIndex: 1,
          ...stagger(200),
        }}
      >
        &copy; {new Date().getFullYear()} Ducklin Company UK. All rights reserved.
      </Typography>
    </Box>
  );
}
