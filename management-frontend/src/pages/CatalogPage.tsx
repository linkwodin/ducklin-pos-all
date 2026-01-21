import { useEffect, useState } from 'react';
import {
  Box,
  Button,
  Paper,
  Typography,
  TextField,
  MenuItem,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
} from '@mui/material';
import { Download as DownloadIcon } from '@mui/icons-material';
import { catalogAPI, sectorsAPI } from '../services/api';
import { useSnackbar } from 'notistack';
import type { Sector } from '../types';

export default function CatalogPage() {
  const [sectors, setSectors] = useState<Sector[]>([]);
  const [selectedSector, setSelectedSector] = useState<number | ''>('');
  const [catalogData, setCatalogData] = useState<any>(null);
  const [loading, setLoading] = useState(false);
  const { enqueueSnackbar } = useSnackbar();

  useEffect(() => {
    fetchSectors();
  }, []);

  const fetchSectors = async () => {
    try {
      const data = await sectorsAPI.list();
      setSectors(data);
    } catch (error) {
      enqueueSnackbar('Failed to fetch sectors', { variant: 'error' });
    }
  };

  const handleGenerate = async () => {
    if (!selectedSector) {
      enqueueSnackbar('Please select a sector', { variant: 'warning' });
      return;
    }
    try {
      setLoading(true);
      const data = await catalogAPI.generate(Number(selectedSector));
      setCatalogData(data);
      enqueueSnackbar('Catalog generated successfully', { variant: 'success' });
    } catch (error) {
      enqueueSnackbar('Failed to generate catalog', { variant: 'error' });
    } finally {
      setLoading(false);
    }
  };

  const handleDownload = async () => {
    if (!selectedSector) {
      return;
    }
    try {
      const blob = await catalogAPI.download(Number(selectedSector));
      const url = window.URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `catalog-${selectedSector}-${new Date().getTime()}.pdf`;
      document.body.appendChild(a);
      a.click();
      window.URL.revokeObjectURL(url);
      document.body.removeChild(a);
      enqueueSnackbar('Catalog downloaded', { variant: 'success' });
    } catch (error) {
      enqueueSnackbar('Failed to download catalog', { variant: 'error' });
    }
  };

  return (
    <Box>
      <Typography variant="h4" gutterBottom>
        E-Catalog Generation
      </Typography>

      <Paper sx={{ p: 3, mb: 3 }}>
        <Box sx={{ display: 'flex', gap: 2, alignItems: 'flex-end' }}>
          <TextField
            select
            label="Select Sector"
            value={selectedSector}
            onChange={(e) => setSelectedSector(e.target.value ? Number(e.target.value) : '')}
            sx={{ minWidth: 300 }}
          >
            {sectors.map((sector) => (
              <MenuItem key={sector.id} value={sector.id}>
                {sector.name}
              </MenuItem>
            ))}
          </TextField>
          <Button
            variant="contained"
            onClick={handleGenerate}
            disabled={loading || !selectedSector}
          >
            Generate Catalog
          </Button>
          {catalogData && (
            <Button
              variant="outlined"
              startIcon={<DownloadIcon />}
              onClick={handleDownload}
            >
              Download PDF
            </Button>
          )}
        </Box>
      </Paper>

      {catalogData && (
        <Paper sx={{ p: 3 }}>
          <Typography variant="h6" gutterBottom>
            Catalog Preview - {catalogData.sector?.name} ({catalogData.quarter})
          </Typography>
          <Typography variant="body2" color="text.secondary" gutterBottom>
            Generated at: {new Date(catalogData.generated_at).toLocaleString()}
          </Typography>
          <TableContainer sx={{ mt: 2 }}>
            <Table size="small">
              <TableHead>
                <TableRow>
                  <TableCell>Product</TableCell>
                  <TableCell>SKU</TableCell>
                  <TableCell>Barcode</TableCell>
                  <TableCell>Wholesale Cost</TableCell>
                  <TableCell>Discount</TableCell>
                  <TableCell>Final Price</TableCell>
                </TableRow>
              </TableHead>
              <TableBody>
                {catalogData.items?.map((item: any, index: number) => (
                  <TableRow key={index}>
                    <TableCell>{item.product?.name || '-'}</TableCell>
                    <TableCell>{item.product?.sku || '-'}</TableCell>
                    <TableCell>{item.product?.barcode || '-'}</TableCell>
                    <TableCell>£{item.wholesale_cost?.toFixed(2) || '-'}</TableCell>
                    <TableCell>
                      {item.discount_percent > 0
                        ? `${item.discount_percent}%`
                        : '-'}
                    </TableCell>
                    <TableCell>
                      <strong>£{item.final_price?.toFixed(2) || '-'}</strong>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </TableContainer>
        </Paper>
      )}
    </Box>
  );
}

