// src/components/Drawer/EdgeEditForm.js
import { useState, useEffect } from 'react';
import TextField from '@mui/material/TextField';
import Button from '@mui/material/Button';
import Box from '@mui/material/Box';
import Grid from '@mui/material/Grid';
import MenuItem from '@mui/material/MenuItem';
import Select from '@mui/material/Select';
import FormControl from '@mui/material/FormControl';
import InputLabel from '@mui/material/InputLabel';

export default function EdgeEditForm({ edge, onSave }) {
  const [formData, setFormData] = useState({
    id: '',
    source: '',
    target: '',
    label: '',
    protocol: '',
    bandwidth: '',
  });

  useEffect(() => {
    if (edge) {
      setFormData({
        id: edge.id || '',
        source: edge.source || '',
        target: edge.target || '',
        label: edge.label || '',
        protocol: edge.protocol || '',
        bandwidth: edge.bandwidth || '',
      });
    }
  }, [edge]);

  const handleChange = (e) => {
    const { name, value } = e.target;
    setFormData(prev => ({ ...prev, [name]: value }));
  };

  const handleSubmit = (e) => {
    e.preventDefault();
    onSave(formData);
  };

  return (
    <Box component="form" onSubmit={handleSubmit} sx={{ mt: 2 }}>
      <Grid container spacing={2}>
        <Grid item xs={12}>
          <TextField
            fullWidth
            label="ID"
            name="id"
            value={formData.id}
            onChange={handleChange}
            disabled  // IDは編集不可
          />
        </Grid>
        
        <Grid item xs={6}>
          <TextField
            fullWidth
            label="ソース"
            name="source"
            value={formData.source}
            onChange={handleChange}
            disabled  // ソースノードは編集不可
          />
        </Grid>
        
        <Grid item xs={6}>
          <TextField
            fullWidth
            label="ターゲット"
            name="target"
            value={formData.target}
            onChange={handleChange}
            disabled  // ターゲットノードは編集不可
          />
        </Grid>

        <Grid item xs={12}>
          <TextField
            required
            fullWidth
            label="ラベル"
            name="label"
            value={formData.label}
            onChange={handleChange}
          />
        </Grid>

        <Grid item xs={12}>
          <FormControl fullWidth>
            <InputLabel>プロトコル</InputLabel>
            <Select
              name="protocol"
              value={formData.protocol}
              onChange={handleChange}
              label="プロトコル"
            >
              <MenuItem value="HTTP/HTTPS">HTTP/HTTPS</MenuItem>
              <MenuItem value="SSH">SSH</MenuItem>
              <MenuItem value="FTP">FTP</MenuItem>
              <MenuItem value="MySQL">MySQL</MenuItem>
              <MenuItem value="HTTP/REST">HTTP/REST</MenuItem>
              <MenuItem value="TCP/IP">TCP/IP</MenuItem>
              <MenuItem value="UDP">UDP</MenuItem>
            </Select>
          </FormControl>
        </Grid>

        <Grid item xs={12}>
          <FormControl fullWidth>
            <InputLabel>帯域幅</InputLabel>
            <Select
              name="bandwidth"
              value={formData.bandwidth}
              onChange={handleChange}
              label="帯域幅"
            >
              <MenuItem value="100Mbps">100Mbps</MenuItem>
              <MenuItem value="1Gbps">1Gbps</MenuItem>
              <MenuItem value="10Gbps">10Gbps</MenuItem>
              <MenuItem value="40Gbps">40Gbps</MenuItem>
            </Select>
          </FormControl>
        </Grid>

        <Grid item xs={12} sx={{ mt: 2 }}>
          <Button variant="contained" color="primary" type="submit" fullWidth>
            保存
          </Button>
        </Grid>
      </Grid>
    </Box>
  );
}
