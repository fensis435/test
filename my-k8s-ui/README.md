# README

このリポジトリには、Material-UI の DataGrid と React Query を組み合わせて  
- アプリ一覧をテーブル表示  
- 起動／停止／再起動／アンインストール操作  
- 操作進捗バーやステータスチップ  

を実現する再利用可能コンポーネント群と、デフォルトで動作するモック API が含まれています。

---

## 1. 前提条件

- Node.js 14 以上 / npm または yarn  
- React 17 以上  
- 以下のパッケージをインストールしてください  

```bash
npm install @mui/material @mui/icons-material @emotion/react @emotion/styled \
@mui/x-data-grid @tanstack/react-query axios
```

---

## 2. ディレクトリ構成例

```
src/
├─ api.ts               # モックAPI／実API呼び出し切り替え
├─ hooks/
│  └─ useK8s.ts         # React Query フック定義
└─ components/
   ├─ AppTable.tsx      # DataGrid を使った一覧表示
   └─ OperationsCell.tsx# 各行の操作＋進捗表示コンポーネント
App.tsx                  # QueryClientProvider の設定
AppContainer.tsx         # インストールボタン＋AppTable 呼び出し
```

---

## 3. モック API（src/api.ts）

デフォルトで動作するモック実装です。以下のエンドポイントを擬似的にシミュレートします。

- listApps(): App[] を返却  
- installApp(name): { operationId } を返却  
- startApp(name), stopApp(name), restartApp(name), uninstallApp(name): 各操作を受け付けて operationId を返却  
- getOperationStatus(operationId): { phase, progress, targetApp } を返却（ポーリング用）

バックエンド不在でも UI の動作検証が可能です。

---

## 4. REST API 連携方法

実際のサーバーを利用したい場合は、モック実装を次のように置き換えます。

1. axios クライアントの初期化  
   ```ts
   // src/api.ts
   import axios from 'axios';
   export const client = axios.create({
     baseURL: process.env.REACT_APP_API_BASE_URL || 'http://localhost:3000/api',
   });
   ```
2. 各関数を実 API 呼び出しに差し替え  
   ```ts
   export async function listApps() {
     const res = await client.get('/apps');
     return res.data;
   }
   export async function installApp(name: string) {
     const res = await client.post('/apps', { name });
     return { operationId: res.data.operationId };
   }
   // startApp, stopApp, restartApp, uninstallApp, getOperationStatus も同様に実装
   ```
3. 環境変数の設定  
   - `.env` に `REACT_APP_API_BASE_URL=https://your-backend.com/api`  
   - 認証トークンやヘッダーが必要な場合は axios のインターセプター等で設定
4. CORS 対策  
   - バックエンド側で `Access-Control-Allow-Origin` を許可する  
   - 開発時は `package.json` の proxy フィールドを利用可能

---

## 5. React Query フック（src/hooks/useK8s.ts）

以下のカスタムフックを提供しています。

- useApps(): アプリ一覧を取得する useQuery  
- useInstallApp(), useStartApp(), useStopApp(), useRestartApp(), useUninstallApp(): 各操作用の useMutation  
- useOperationStatus(operationId): ポーリングと完了時キャッシュ更新を行う useQuery

必要に応じて `staleTime` や `refetchOnMount` のオプションを調整してください。

---

## 6. コンポーネント

### 6.1 AppTable.tsx

- `useApps()` で取得した配列を DataGrid の `rows` にマッピング  
- `useGridApiRef` で得た `apiRef` を渡し、行単位更新に対応  
- `window` イベント（`appsUpdated`）で強制リフェッチ  

```tsx
import { DataGrid, useGridApiRef, GridColDef } from '@mui/x-data-grid';
import { useEffect } from 'react';
import { useApps } from '../hooks/useK8s';
import OperationsCell from './OperationsCell';

export function AppTable() {
  const apiRef = useGridApiRef();
  const { data: apps = [], isLoading, refetch } = useApps();

  useEffect(() => {
    const h = () => refetch();
    window.addEventListener('appsUpdated', h);
    return () => window.removeEventListener('appsUpdated', h);
  }, [refetch]);

  const rows = apps.map(a => ({ id: a.name, name: a.name, status: a.status }));
  const gridKey = rows.map(r => `${r.id}:${r.status}`).join('|');

  const columns: GridColDef[] = [
    { field: 'name', headerName: 'アプリ名', flex: 1 },
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
```

### 6.2 OperationsCell.tsx

- ボタン（起動／停止／再起動／アンインストール）  
- 操作中はステータスチップ＋プログレスバーを表示  
- 完了時に `apiRef.current.updateRows()` と React Query キャッシュへのパッチを両方実行  
- 必要に応じて `window.dispatchEvent('appsUpdated')` で外部通知  

```tsx
import { useState, useEffect, useCallback } from 'react';
import type { GridApi } from '@mui/x-data-grid';
import { Box, Button, LinearProgress, Stack, Chip } from '@mui/material';
import { useStartApp, useStopApp, useRestartApp, useUninstallApp, useOperationStatus } from '../hooks/useK8s';
import { useQueryClient } from '@tanstack/react-query';

interface Props {
  name: string;
  status: 'running' | 'stopped';
  apiRef: React.MutableRefObject<GridApi>;
}

export default function OperationsCell({ name, status, apiRef }: Props) {
  // ...（前出の実装を参照）...
}
```

---

## 7. エントリポイント  

`QueryClientProvider` でアプリ全体をラップし、`AppContainer`（もしくは `AppTable`）を呼び出します。  

```tsx
// src/App.tsx
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import AppContainer from './AppContainer';

const queryClient = new QueryClient();

export default function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <AppContainer />
    </QueryClientProvider>
  );
}
```

```tsx
// src/AppContainer.tsx
import { Container, Button } from '@mui/material';
import { useState } from 'react';
import { useInstallApp } from './hooks/useK8s';
import { AppTable } from './components/AppTable';

export default function AppContainer() {
  const [seed, setSeed] = useState(0);
  const install = useInstallApp();

  const onAdd = () => {
    install.mutate(`demo-app-${seed}`, {
      onSuccess: () => setSeed(s => s + 1),
    });
  };

  return (
    <Container sx={{ py: 4 }}>
      <Button
        variant="contained"
        onClick={onAdd}
        disabled={install.isLoading}
        sx={{ mb: 2 }}
      >
        新しいアプリをインストール
      </Button>
      <AppTable />
    </Container>
  );
}
```

---

## 8. カスタマイズ  

- DataGrid の列を追加・変更する場合は、`AppTable.tsx` の `columns` 配列を編集してください。  
- ボタンラベルや色を変えたいときは、`OperationsCell.tsx` の `Button`／`Chip` コンポーネントを適宜修正してください。  
- モック API から実 API に切り替える際は、**Section 4** の手順に従って `src/api.ts` を置き換えてください。  
- React Query のキャッシュ挙動を調整したい場合は、`useK8s.ts` 内の `staleTime` や `refetchOnMount` オプションを変更してください。

---

## 9. 動作確認  

1. `npm install` で依存をインストール  
2. `npm run dev` で開発サーバーを起動  
3. ブラウザで `http://localhost:3000` にアクセス  
4. 「新しいアプリをインストール」ボタンで行が追加されること  
5. 各行の「起動／停止／再起動／アンインストール」をクリックし、ステータスや行の消失が反映されること  

---

## 10. ライセンス  

このコンポーネント群は MIT ライセンスのもとで公開されています。詳細は `LICENSE` ファイルをご覧ください。

---

## 11. REST API 部分を Rails に置き換える方法

フロントエンドの API 呼び出しを、Rails で構築したバックエンドに切り替えるには、以下の手順で進めます。

---

### 11.1 Rails API アプリの作成

1. API モードで新規プロジェクトを生成  
   ```bash
   rails new k8s_api --api -d postgresql
   cd k8s_api
   ```

2. データベース設定を編集（`config/database.yml`）し、`rails db:create` で DB を作成

---

### 11.2 モデルの定義

アプリケーション情報を保持する `App` モデルと、非同期操作の進捗を追う `Operation` モデルを用意します。

```bash
rails g model App name:string status:string
rails g model Operation app:references action:string status:string progress:integer
rails db:migrate
```

- `App`: `name`（ユニーク）, `status`（`running`/`stopped`）  
- `Operation`: `app_id`, `action`（start/stop/restart/uninstall/install）, `status`（pending/processing/idle）, `progress`（0?100）

---

### 11.3 ルーティング

`config/routes.rb` にリソースとカスタムアクションを追加します。

```ruby
Rails.application.routes.draw do
  resources :apps, only: [:index, :create, :destroy] do
    member do
      post :start
      post :stop
      post :restart
      delete :uninstall
    end
  end
  resources :operations, only: [] do
    member do
      get :status
    end
  end
end
```

- `GET   /apps` → アプリ一覧  
- `POST  /apps` → インストール  
- `DELETE/ apps/:id` → アンインストール  
- `POST  /apps/:id/start` → 起動  
- `POST  /apps/:id/stop` → 停止  
- `POST  /apps/:id/restart` → 再起動  
- `GET   /operations/:id/status` → ポーリング用ステータス

---

### 11.4 コントローラ実装

#### AppsController

```ruby
class AppsController < ApplicationController
  before_action :set_app, only: [:destroy, :start, :stop, :restart, :uninstall]

  def index
    render json: App.all
  end

  def create
    app = App.create!(name: params[:name], status: 'stopped')
    op  = Operation.create!(app: app, action: 'install', status: 'pending', progress: 0)
    InstallJob.perform_later(op.id)
    render json: { operationId: op.id }, status: :created
  end

  def destroy
    op = Operation.create!(app: @app, action: 'uninstall', status: 'pending', progress: 0)
    UninstallJob.perform_later(op.id)
    render json: { operationId: op.id }, status: :accepted
  end

  def start
    op = Operation.create!(app: @app, action: 'start', status: 'pending', progress: 0)
    StartJob.perform_later(op.id)
    render json: { operationId: op.id }, status: :accepted
  end

  def stop
    op = Operation.create!(app: @app, action: 'stop', status: 'pending', progress: 0)
    StopJob.perform_later(op.id)
    render json: { operationId: op.id }, status: :accepted
  end

  def restart
    op = Operation.create!(app: @app, action: 'restart', status: 'pending', progress: 0)
    RestartJob.perform_later(op.id)
    render json: { operationId: op.id }, status: :accepted
  end

  private

  def set_app
    @app = App.find_by!(name: params[:id])
  end
end
```

#### OperationsController

```ruby
class OperationsController < ApplicationController
  def status
    op = Operation.find(params[:id])
    render json: {
      phase:    op.status,     # 'pending'/'processing'/'idle'
      progress: op.progress,   # 0?100
      target:   op.action,     # 操作種別
      appName:  op.app.name
    }
  end
end
```

---

### 11.5 非同期ジョブの実装

`app/jobs/` 配下に、操作ごとのジョブを定義し、進捗をシミュレートします。例：`StartJob`

```ruby
class StartJob < ApplicationJob
  queue_as :default

  def perform(op_id)
    op = Operation.find(op_id)
    op.update!(status: 'processing')

    (1..10).each do |i|
      sleep 0.5
      op.update!(progress: i * 10)
    end

    app = op.app
    app.update!(status: 'running')
    op.update!(status: 'idle', progress: 100)
  end
end
```

- `processing` → `idle` に移行すると同時に `App` の `status` を更新  
- 他操作（stop/restart/uninstall/install）も同様に実装

---

### 11.6 CORS／環境変数

- `config/initializers/cors.rb` でフロントエンドのオリジンを許可  
- `.env` に `RAILS_API_URL` を定義し、フロントエンドの `src/api.ts` で参照  
  ```ts
  const client = axios.create({
    baseURL: process.env.REACT_APP_API_BASE_URL || 'http://localhost:3000',
  });
  ```

---

### 11.7 フロントエンド設定まとめ

1. `.env` に `REACT_APP_API_BASE_URL=http://localhost:3000` を追加  
2. `src/api.ts` を以下のように書き換え  
   ```ts
   import { client } from './axiosClient'; // axiosClient.ts で上記 Rails client を export
   export function listApps() {
     return client.get<App[]>('/apps').then(res => res.data);
   }
   export function installApp(name: string) {
     return client.post<{operationId:number}>('/apps', { name }).then(res => res.data);
   }
   // start/stop/restart/uninstall
   export function startApp(name: string) {
     return client.post<{operationId:number}>(`/apps/${name}/start`).then(res => res.data);
   }
   // ...他も同様...
   export function getOperationStatus(id:string) {
     return client.get<OpStatus>(`/operations/${id}/status`).then(res => res.data);
   }
   ```

これで React Query と DataGrid ベースの UI が、Rails の実 API にシームレスに接続されるようになります。『モック API 動作』と同じレスポンスフォーマットを守れば、既存のフロント側コードはほぼそのまま流用可能です。
