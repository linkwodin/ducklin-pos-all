import { useEffect, useState } from 'react';
import {
  Box,
  Button,
  Paper,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Typography,
  IconButton,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  TextField,
} from '@mui/material';
import {
  Add as AddIcon,
  Edit as EditIcon,
  Delete as DeleteIcon,
} from '@mui/icons-material';
import { useTranslation } from 'react-i18next';
import { sectorsAPI } from '../services/api';
import { useSnackbar } from 'notistack';
import type { Sector } from '../types';

export default function SectorsPage() {
  const { t } = useTranslation('sectors');
  const [sectors, setSectors] = useState<Sector[]>([]);
  const [loading, setLoading] = useState(true);
  const [open, setOpen] = useState(false);
  const [editingSector, setEditingSector] = useState<Sector | null>(null);
  const { enqueueSnackbar } = useSnackbar();

  useEffect(() => {
    fetchSectors();
  }, []);

  const fetchSectors = async () => {
    try {
      setLoading(true);
      const data = await sectorsAPI.list();
      setSectors(data);
    } catch (error) {
      enqueueSnackbar('Failed to fetch sectors', { variant: 'error' });
    } finally {
      setLoading(false);
    }
  };

  const handleDelete = async (id: number) => {
    if (!window.confirm(t('confirmDeactivate'))) {
      return;
    }
    try {
      await sectorsAPI.delete(id);
      enqueueSnackbar('Sector deactivated', { variant: 'success' });
      fetchSectors();
    } catch (error) {
      enqueueSnackbar('Failed to deactivate sector', { variant: 'error' });
    }
  };

  const handleSave = async (sectorData: Partial<Sector>) => {
    try {
      if (editingSector) {
        await sectorsAPI.update(editingSector.id, sectorData);
        enqueueSnackbar('Sector updated', { variant: 'success' });
      } else {
        await sectorsAPI.create(sectorData);
        enqueueSnackbar('Sector created', { variant: 'success' });
      }
      setOpen(false);
      setEditingSector(null);
      fetchSectors();
    } catch (error: any) {
      enqueueSnackbar(error.response?.data?.error || 'Failed to save sector', {
        variant: 'error',
      });
    }
  };

  return (
    <Box>
      <Box sx={{ display: 'flex', justifyContent: 'space-between', mb: 3 }}>
        <Typography variant="h4">{t('title')}</Typography>
        <Button
          variant="contained"
          startIcon={<AddIcon />}
          onClick={() => {
            setEditingSector(null);
            setOpen(true);
          }}
        >
          {t('addSector')}
        </Button>
      </Box>

      <TableContainer component={Paper}>
        <Table>
          <TableHead>
            <TableRow>
              <TableCell>{t('sectorName')}</TableCell>
              <TableCell>{t('description')}</TableCell>
              <TableCell>{t('status')}</TableCell>
              <TableCell>{t('actions')}</TableCell>
            </TableRow>
          </TableHead>
          <TableBody>
            {loading ? (
              <TableRow>
                <TableCell colSpan={4} align="center">
                  {t('loading')}
                </TableCell>
              </TableRow>
            ) : sectors.length === 0 ? (
              <TableRow>
                <TableCell colSpan={4} align="center">
                  {t('noSectors')}
                </TableCell>
              </TableRow>
            ) : (
              sectors.map((sector: Sector) => (
                <TableRow key={sector.id}>
                  <TableCell>{sector.name}</TableCell>
                  <TableCell>{sector.description || '-'}</TableCell>
                  <TableCell>{sector.is_active ? t('active') : t('inactive')}</TableCell>
                  <TableCell>
                    <IconButton
                      size="small"
                      onClick={() => {
                        setEditingSector(sector);
                        setOpen(true);
                      }}
                    >
                      <EditIcon />
                    </IconButton>
                    <IconButton
                      size="small"
                      onClick={() => handleDelete(sector.id)}
                      color="error"
                    >
                      <DeleteIcon />
                    </IconButton>
                  </TableCell>
                </TableRow>
              ))
            )}
          </TableBody>
        </Table>
      </TableContainer>

      <SectorDialog
        open={open}
        onClose={() => {
          setOpen(false);
          setEditingSector(null);
        }}
        onSave={handleSave}
        sector={editingSector}
        t={t}
      />
    </Box>
  );
}

function SectorDialog({
  open,
  onClose,
  onSave,
  sector,
  t,
}: {
  open: boolean;
  onClose: () => void;
  onSave: (data: Partial<Sector>) => void;
  sector: Sector | null;
  t: (key: string) => string;
}) {
  const [formData, setFormData] = useState({
    name: '',
    description: '',
  });

  useEffect(() => {
    if (sector) {
      setFormData({
        name: sector.name || '',
        description: sector.description || '',
      });
    } else {
      setFormData({
        name: '',
        description: '',
      });
    }
  }, [sector, open]);

  const handleSubmit = () => {
    onSave(formData);
  };

  return (
    <Dialog open={open} onClose={onClose} maxWidth="sm" fullWidth>
      <DialogTitle>{sector ? t('editSectorTitle') : t('addSectorTitle')}</DialogTitle>
      <DialogContent>
        <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2, mt: 1 }}>
          <TextField
            label={t('sectorName')}
            required
            fullWidth
            value={formData.name}
            onChange={(e: React.ChangeEvent<HTMLInputElement>) => setFormData({ ...formData, name: e.target.value })}
          />
          <TextField
            label={t('description')}
            fullWidth
            multiline
            rows={3}
            value={formData.description}
            onChange={(e: React.ChangeEvent<HTMLInputElement>) =>
              setFormData({ ...formData, description: e.target.value })
            }
          />
        </Box>
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose}>{t('cancel')}</Button>
        <Button onClick={handleSubmit} variant="contained">
          {t('save')}
        </Button>
      </DialogActions>
    </Dialog>
  );
}

