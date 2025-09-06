import React from 'react';
import axios from 'axios';
import { DataGrid, GridColDef } from '@mui/x-data-grid';
import Box from '@mui/material/Box';
import Chip from '@mui/material/Chip';
import TagEditCell, { MenuNode } from './components/TagEditCell';

interface RowData {
  id: number;
  name: string;
  tags: string[];
}

const initialRows: RowData[] = [
  { id: 1, name: '太郎', tags: ['apple'] },
  { id: 2, name: '花子', tags: [] },
];

export default function App() {
  const [rows, setRows] = React.useState<RowData[]>(initialRows);
  const [menuTree, setMenuTree] = React.useState<MenuNode[]>([]);
  const [loading, setLoading] = React.useState(false);
  const [error, setError] = React.useState<string | null>(null);

  React.useEffect(() => {
    setLoading(true);
    axios
      .get<{ tags: MenuNode[] }>('/tags.json')
      .then((res) => {
        setMenuTree(res.data.tags);
        setError(null);
      })
      .catch(() => {
        setError('タグ取得失敗');
      })
      .finally(() => {
        setLoading(false);
      });
  }, []);

  const processRowUpdate = (newRow: RowData) => {
    setRows((prev) =>
      prev.map((r) => (r.id === newRow.id ? newRow : r))
    );
    return newRow;
  };

  const columns: GridColDef[] = [
    {
      field: 'name',
      headerName: '名前',
      width: 120,
      editable: true,
    },
    {
      field: 'tags',
      headerName: 'タグ',
      width: 300,
      editable: true,
      renderCell: (params) => (
        <>
          {Array.isArray(params.value) &&
            params.value.map((tag: string) => (
              <Chip
                key={tag}
                label={tag}
                size="small"
                sx={{ mr: 0.5 }}
              />
            ))}
        </>
      ),
      renderEditCell: (params) => (
        <TagEditCell
          {...params}
          menuTree={menuTree}
          loading={loading}
          error={error}
        />
      ),
    },
  ];

  return (
    <Box height={400} width="100%">
      <DataGrid
        rows={rows}
        columns={columns}
        editMode="cell"
        processRowUpdate={processRowUpdate}
      />
    </Box>
  );
}

