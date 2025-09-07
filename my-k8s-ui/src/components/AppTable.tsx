// src/components/AppTable.tsx
import React, { useEffect } from 'react';
import { DataGrid, useGridApiRef } from '@mui/x-data-grid';
import type { GridColDef, GridApi } from '@mui/x-data-grid';
import { useApps } from '../hooks/useK8s';
import OperationsCell from './OperationsCell';

export function AppTable() {
  // DataGrid API 用の ref
  const apiRef = useGridApiRef<GridApi>();
  const { data: apps = [], isLoading, refetch } = useApps();

  // テーブル再マウント用キー
  const gridKey = apps.map(a => `${a.name}:${a.status}`).join('|');

  // 外部イベントで強制 refetch
  useEffect(() => {
    const handler = () => refetch();
    window.addEventListener('appsUpdated', handler);
    return () => window.removeEventListener('appsUpdated', handler);
  }, [refetch]);

  console.log('[AppTable] apps:', apps);

  const rows = apps.map(app => ({
    id:     app.name,
    name:   app.name,
    status: app.status,
  }));

  const columns: GridColDef[] = [
    { field: 'name', headerName: 'アプリ名', flex: 1, minWidth: 120 },
    { field: 'status', headerName: '状態', width: 120 },
    {
      field: 'operations',
      headerName: '操作／進捗',
      flex: 2,
      sortable: false,
      filterable: false,
      renderCell: params => (
        <OperationsCell
          name={params.row.name}
          status={params.row.status}
          apiRef={apiRef}
        />
      ),
    },
  ];

  return (
    <div style={{ width: '100%' }}>
      <DataGrid
        apiRef={apiRef}
        key={gridKey}
        rows={rows}
        columns={columns}
        loading={isLoading}
        disableSelectionOnClick
        autoHeight
      />
    </div>
  );
}
