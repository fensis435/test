
もし以下の上記スクリプトで作成されないなら、作成されるように修正して。
 - NAT Gateway
 - VPC Endpoints
 - CloudWatch
 - Secrets Manager

---

## 変更サマリー

### 新規作成

**`05-vpc-endpoints.yaml`** (588行) — 15個のエンドポイント + VPC Flow Log

| 種別 | エンドポイント |
|------|---------------|
| Gateway (無料) | S3, DynamoDB |
| Interface | ECR API, ECR DKR, EC2, STS, CloudWatch Logs, CloudWatch Monitoring, **Secrets Manager**, EKS, EFS, **KMS**, SQS, SSM/SSMMessages/EC2Messages, AutoScaling, ELB |
| その他 | VPC Flow Log → CloudWatch Logs (NAT通信含む全トラフィック記録) |

**`06-observability.yaml`** (846行) — CloudWatch & Secrets Manager を一元管理

| リソース種別 | 内容 |
|-------------|------|
| SNS Topic | アラート通知先（メール購読オプション） |
| Log Groups (9個) | EKS Control Plane / Container Insights (app・perf・host・dataplane) / RDS / アプリ / Karpenter / ArgoCD |
| Metric Alarms (14個) | NAT GW ポート枯渇・パケットドロップ / RDS CPU・接続数・メモリ・レプリカLag・デッドロック / ALB 5xx・レイテンシ・Unhealthy hosts / アプリ5xx / Karpenter errors |
| Dashboard | 全主要メトリクス + ログInsightsウィジェット |
| Secrets Manager (5個) | RDS Master / Cognito config / ArgoCD repo / ArgoCD admin / App general secrets |
| Secret Rotation | RDS自動ローテーション（30日、AWS管理Lambda使用） |
| KMS Key | Secrets Manager専用キー（年次ローテーション） |

### 既存ファイルの修正

- **`01-base.yaml`** — `PrivateRouteTable1/2/3Id`, `DBRouteTableId`, `NatGateway1/2/3Id` のExportを追加（05・06スタックが参照）
- **`04-eks-rds-efs.yaml`** — DBSecretをインライン定義から `06-observability` のクロススタック参照に変更（Secret一元管理）
- **`deploy.sh`** — Phase 5（VPC Endpoints）→ Phase 6（Observability）を新規追加、Container Insights自動デプロイ関数追加、全16フェーズに整理