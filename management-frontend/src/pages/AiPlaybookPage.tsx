import { useEffect, useState } from 'react';
import { Box, Paper, Typography, CircularProgress, Alert } from '@mui/material';
import { useTranslation } from 'react-i18next';

const PLAYBOOK_URL = import.meta.env.VITE_AI_PLAYBOOK_URL as string | undefined;

export default function AiPlaybookPage() {
  const { t } = useTranslation();
  const [body, setBody] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const hasRemoteUrl = Boolean(PLAYBOOK_URL?.trim());
  const useDevBundle = import.meta.env.DEV && !hasRemoteUrl;
  const [loading, setLoading] = useState(hasRemoteUrl || useDevBundle);

  useEffect(() => {
    let cancelled = false;

    const loadFromUrl = async () => {
      const url = PLAYBOOK_URL?.trim();
      if (!url) return;
      setLoading(true);
      const token = localStorage.getItem('token');
      if (!token) {
        setError(t('aiPlaybookPage.notLoggedIn'));
        setLoading(false);
        return;
      }
      try {
        const res = await fetch(url, {
          headers: { Authorization: `Bearer ${token}` },
        });
        const text = await res.text();
        if (cancelled) return;
        if (!res.ok) {
          setError(text || res.statusText || t('aiPlaybookPage.loadError'));
          return;
        }
        setBody(text);
      } catch (e) {
        if (!cancelled) {
          setError(e instanceof Error ? e.message : t('aiPlaybookPage.loadError'));
        }
      } finally {
        if (!cancelled) setLoading(false);
      }
    };

    const loadDevMd = async () => {
      if (!import.meta.env.DEV || hasRemoteUrl) return;
      setLoading(true);
      try {
        const mod = await import('@repoDocs/ai-playbook-wholesale-po-to-order.md?raw');
        if (!cancelled) setBody(mod.default);
      } catch (e) {
        if (!cancelled) {
          setError(e instanceof Error ? e.message : t('aiPlaybookPage.loadError'));
        }
      } finally {
        if (!cancelled) setLoading(false);
      }
    };

    if (hasRemoteUrl) {
      loadFromUrl();
    } else if (import.meta.env.DEV) {
      loadDevMd();
    } else {
      setLoading(false);
    }

    return () => {
      cancelled = true;
    };
  }, [t, hasRemoteUrl]);

  if (!hasRemoteUrl && !import.meta.env.DEV) {
    return (
      <Box sx={{ p: 2, maxWidth: 900 }}>
        <Typography variant="h5" gutterBottom>
          {t('aiPlaybookPage.title')}
        </Typography>
        <Alert severity="info">{t('aiPlaybookPage.notConfigured')}</Alert>
      </Box>
    );
  }

  return (
    <Box sx={{ p: 2, maxWidth: 1000 }}>
      <Typography variant="h5" gutterBottom>
        {t('aiPlaybookPage.title')}
      </Typography>
      {hasRemoteUrl ? (
        <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
          {t('aiPlaybookPage.subtitle')}
        </Typography>
      ) : (
        <Alert severity="warning" sx={{ mb: 2 }}>
          {t('aiPlaybookPage.devOnlyBundled')}
        </Alert>
      )}
      {loading && (
        <Box sx={{ display: 'flex', justifyContent: 'center', py: 4 }}>
          <CircularProgress />
        </Box>
      )}
      {error && !loading && (
        <Alert severity="error" sx={{ mb: 2 }}>
          <Typography variant="body2" component="span" sx={{ display: 'block' }}>
            {error}
          </Typography>
          {error === 'Failed to fetch' || error === 'Load failed' ? (
            <Typography variant="body2" sx={{ mt: 1, opacity: 0.95 }}>
              {t('aiPlaybookPage.fetchFailedHint')}
            </Typography>
          ) : null}
        </Alert>
      )}
      {body && !loading && (
        <Paper variant="outlined" sx={{ p: 2, overflow: 'auto' }}>
          <Box
            component="pre"
            sx={{
              m: 0,
              whiteSpace: 'pre-wrap',
              wordBreak: 'break-word',
              fontFamily: 'ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace',
              fontSize: '0.875rem',
            }}
          >
            {body}
          </Box>
        </Paper>
      )}
      <Typography variant="caption" color="text.secondary" display="block" sx={{ mt: 2 }}>
        {hasRemoteUrl ? t('aiPlaybookPage.footer') : t('aiPlaybookPage.footerDev')}
      </Typography>
    </Box>
  );
}
