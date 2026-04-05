---

# 完全private構成（AWS込み）

```mermaid
flowchart TB

%% =========================
%% User Access Layer
%% =========================
User["User PC<br/>Browser"]

subgraph Access["Access Layer"]
    SSM["AWS Systems Manager (SSM)<br/>Port Forward"]
    VPN["VPN / Direct Connect"]
end

User -->|Dev| SSM
User -->|Prod| VPN

%% =========================
%% VPC Layer
%% =========================
subgraph VPC["VPC (Private Only)"]

    %% Subnets
    subgraph SubnetA["Private Subnet A"]
        Bastion["EC2 Bastion<br/>(SSM Target)"]
    end

    subgraph SubnetB["Private Subnet B"]
        ALB["Internal ALB"]
    end

    %% EKS
    subgraph EKS["Amazon EKS Cluster (Private Endpoint)"]

        subgraph NodeGroup["Managed Node Group"]
            Nginx["nginx-ingress"]
        end

        subgraph KarpenterNodes["Karpenter Nodes"]
            Envoy["envoy (per workspace)"]
            App["Workspace Web App"]
        end

    end

    %% Flow inside VPC
    Bastion --> ALB
    ALB --> Nginx
    Nginx --> Envoy
    Envoy --> App

end

%% =========================
%% AWS Services Layer
%% =========================
subgraph AWS["AWS Managed Services"]

    Route53["Route53 Private Hosted Zone"]
    ECR["Amazon ECR"]
    S3["Amazon S3"]
    STS["AWS STS"]
    Logs["CloudWatch Logs"]

end

%% =========================
%% VPC Endpoints
%% =========================
subgraph VPCE["VPC Endpoints"]

    ECR_EP["ECR Endpoint"]
    S3_EP["S3 Gateway Endpoint"]
    STS_EP["STS Endpoint"]
    Logs_EP["Logs Endpoint"]

end

%% =========================
%% External Connections
%% =========================

EKS --> ECR_EP
EKS --> S3_EP
EKS --> STS_EP
EKS --> Logs_EP

ECR_EP --> ECR
S3_EP --> S3
STS_EP --> STS
Logs_EP --> Logs

%% =========================
%% DNS
%% =========================

Route53 --> ALB

%% =========================
%% Access Paths
%% =========================

SSM --> Bastion
VPN --> ALB
```

---

# 🧠 図の読み方（重要ポイント）

---

## 🎯 アクセス経路

---

### 開発

```text
User → SSM → Bastion → ALB
```

---

### 本番

```text
User → VPN → ALB
```

---

## 🎯 トラフィックの本線

```text
ALB → nginx → envoy → app
```

---

👉 あなたの設計そのまま：

* 1段目：nginx（rewrite）
* 2段目：envoy（workspace routing）

---

## 🎯 完全privateのポイント

---

### ❌ インターネットなし

* IGWなしでも成立
* Public ALBなし

---

### ✅ 外部通信

すべて👇

```text
VPC Endpoint経由
```

---

## 🎯 AWSサービスの役割

---

### 👉 AWS Systems Manager

* 踏み台アクセス
* SSH不要

---

### 👉 Amazon Route 53

* private DNS

---

### 👉 Amazon ECR

* イメージ取得

---

### 👉 Amazon S3

* layer storage

---

---

# 💡 実務での補足

---

## ❗ Bastionは必須ではない

---

👉 SSM直接でもOK：

```text
User → SSM → ALB（port forward）
```

---

---

## ❗ NAT Gatewayを使うか？

---

### この図は👇

👉 **NATなし構成**

---

### 必要な代替

* ECR Endpoint
* S3 Endpoint
* STS Endpoint

---

---

## ❗ DNS設計

---

```text
app.dev.internal.example.com
```

👉 ALBに向ける

---

---

# 🎯 この構成の強み

---

## ✔ セキュリティ最強

* 外部公開ゼロ
* 攻撃面ほぼなし

---

## ✔ オンプレ互換

* reverse proxy 2段
* tenant分離

---

## ✔ 拡張性

* Karpenterで自動スケール
* workspace増加OK

---

---

