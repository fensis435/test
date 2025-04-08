// src/components/Drawer/NodeEditForm.js
import { useState, useEffect } from 'react';
import TextField from '@mui/material/TextField';
import Button from '@mui/material/Button';
import Box from '@mui/material/Box';
import Grid from '@mui/material/Grid';
import Typography from '@mui/material/Typography';
import Divider from '@mui/material/Divider';
import Chip from '@mui/material/Chip';
import IconButton from '@mui/material/IconButton';
import AddIcon from '@mui/icons-material/Add';
import DeleteIcon from '@mui/icons-material/Delete';
import InputAdornment from '@mui/material/InputAdornment';
import MenuItem from '@mui/material/MenuItem';
import Select from '@mui/material/Select';
import FormControl from '@mui/material/FormControl';
import InputLabel from '@mui/material/InputLabel';

export default function NodeEditForm({ node, onSave }) {
  const [formData, setFormData] = useState({
    id: '',
    label: '',
    type: 'server',
    ipAddress: '',
    subnet: '',
    openPorts: [],
    software: [],
    firewallRules: [],
    imageUrl: '',
  });

  const [newPort, setNewPort] = useState('');
  const [newSoftware, setNewSoftware] = useState('');
  const [newFirewallRule, setNewFirewallRule] = useState('');

  useEffect(() => {
    if (node) {
      setFormData({
        id: node.id || '',
        label: node.label || '',
        type: node.type || 'server',
        ipAddress: node.ipAddress || '',
        subnet: node.subnet || '',
        openPorts: node.openPorts || [],
        software: node.software || [],
        firewallRules: node.firewallRules || [],
        imageUrl: node.imageUrl || '',
      });
    }
  }, [node]);

  const handleChange = (e) => {
    const { name, value } = e.target;
    setFormData(prev => ({ ...prev, [name]: value }));
  };

  const handleAddPort = () => {
    if (newPort && !formData.openPorts.includes(parseInt(newPort))) {
      setFormData(prev => ({
        ...prev,
        openPorts: [...prev.openPorts, parseInt(newPort)]
      }));
      setNewPort('');
    }
  };

  const handleDeletePort = (port) => {
    setFormData(prev => ({
      ...prev,
      openPorts: prev.openPorts.filter(p => p !== port)
    }));
  };

  const handleAddSoftware = () => {
    if (newSoftware && !formData.software.includes(newSoftware)) {
      setFormData(prev => ({
        ...prev,
        software: [...prev.software, newSoftware]
      }));
      setNewSoftware('');
    }
  };

  const handleDeleteSoftware = (item) => {
    setFormData(prev => ({
      ...prev,
      software: prev.software.filter(s => s !== item)
    }));
  };

  const handleAddFirewallRule = () => {
    if (newFirewallRule && !formData.firewallRules.includes(newFirewallRule)) {
      setFormData(prev => ({
        ...prev,
        firewallRules: [...prev.firewallRules, newFirewallRule]
      }));
      setNewFirewallRule('');
    }
  };

  const handleDeleteFirewallRule = (rule) => {
    setFormData(prev => ({
      ...prev,
      firewallRules: prev.firewallRules.filter(r => r !== rule)
    }));
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
            <InputLabel>タイプ</InputLabel>
            <Select
              name="type"
              value={formData.type}
              onChange={handleChange}
              label="タイプ"
            >
              <MenuItem value="server">サーバー</MenuItem>
              <MenuItem value="router">ルーター</MenuItem>
              <MenuItem value="switch">スイッチ</MenuItem>
              <MenuItem value="client">クライアント</MenuItem>
            </Select>
          </FormControl>
        </Grid>

        <Grid item xs={12}>
          <TextField
            fullWidth
            label="画像URL"
            name="imageUrl"
            value={formData.imageUrl}
            onChange={handleChange}
          />
        </Grid>

        <Grid item xs={6}>
          <TextField
            fullWidth
            label="IPアドレス"
            name="ipAddress"
            value={formData.ipAddress}
            onChange={handleChange}
          />
        </Grid>

        <Grid item xs={6}>
          <TextField
            fullWidth
            label="サブネットマスク"
            name="subnet"
            value={formData.subnet}
            onChange={handleChange}
          />
        </Grid>

        <Grid item xs={12}>
          <Typography variant="subtitle1" sx={{ mt: 2, mb: 1 }}>
            オープンポート
          </Typography>
          <Box sx={{ display: 'flex', alignItems: 'center', mb: 1 }}>
            <TextField
              label="ポート番号"
              size="small"
              value={newPort}
              onChange={(e) => setNewPort(e.target.value)}
              type="number"
              sx={{ mr: 1 }}
            />
            <IconButton color="primary" onClick={handleAddPort}>
              <AddIcon />
            </IconButton>
          </Box>
          <Box sx={{ display: 'flex', flexWrap: 'wrap', gap: 1 }}>
            {formData.openPorts.map((port) => (
              <Chip
                key={port}
                label={port}
                onDelete={() => handleDeletePort(port)}
                color="primary"
                variant="outlined"
              />
            ))}
          </Box>
        </Grid>

        <Grid item xs={12}>
          <Divider sx={{ my: 2 }} />
          <Typography variant="subtitle1" sx={{ mb: 1 }}>
            インストールされているソフトウェア
          </Typography>
          <Box sx={{ display: 'flex', alignItems: 'center', mb: 1 }}>
            <TextField
              label="ソフトウェア名"
              size="small"
              fullWidth
              value={newSoftware}
              onChange={(e) => setNewSoftware(e.target.value)}
              sx={{ mr: 1 }}
            />
            <IconButton color="primary" onClick={handleAddSoftware}>
              <AddIcon />
            </IconButton>
          </Box>
          <Box sx={{ display: 'flex', flexWrap: 'wrap', gap: 1 }}>
            {formData.software.map((item) => (
              <Chip
                key={item}
                label={item}
                onDelete={() => handleDeleteSoftware(item)}
                color="primary"
                variant="outlined"
              />
            ))}
          </Box>
        </Grid>

        <Grid item xs={12}>
          <Divider sx={{ my: 2 }} />
          <Typography variant="subtitle1" sx={{ mb: 1 }}>
            ファイアウォールルール
          </Typography>
          <Box sx={{ display: 'flex', alignItems: 'center', mb: 1 }}>
            <TextField
              label="ルール"
              size="small"
              fullWidth
              value={newFirewallRule}
              onChange={(e) => setNewFirewallRule(e.target.value)}
              sx={{ mr: 1 }}
            />
            <IconButton color="primary" onClick={handleAddFirewallRule}>
              <AddIcon />
            </IconButton>
          </Box>
          <Box sx={{ display: 'flex', flexWrap: 'wrap', gap: 1 }}>
            {formData.firewallRules.map((rule) => (
              <Chip
                key={rule}
                label={rule}
                onDelete={() => handleDeleteFirewallRule(rule)}
                color="primary"
                variant="outlined"
              />
            ))}
          </Box>
        </Grid>

        <Grid sx={{ display: "flex", gap: 2 }}>
          <Button variant="contained" color="primary" type="submit" fullWidth>保存</Button>
          <Button variant="contained" color="primary" type="submit" fullWidth>戻る</Button>
        </Grid>
      </Grid>
    </Box>
  );
}
