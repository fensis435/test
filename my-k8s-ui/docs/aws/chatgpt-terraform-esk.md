※ 今日は **「EKSが立ち、kubectlが通るところまで」**に集中します。
（Karpenter / Argo CD / cert-manager は次段）

---

# 全体像（今日やること）

まずゴールを明確に👇

> **ゴール**
>
> * Private Subnet のみで EKS を構築
> * NAT Gateway なし
> * 外向き通信は Proxy のみ
> * ECR / S3 / STS は VPC Endpoint
> * 管理Nodeが1〜2台常駐して kubectl が使える

---

# Terraformを知らない人向け・超重要な前提

## Terraformの考え方（3行で）

* **HCL** という設定ファイルで
* **AWSリソースの完成形**を書き
* `terraform apply` すると **AWSがその通りになる**

👉 *CLIでポチポチ作る代わりに、設計図をコードで持つ*

---

# ディレクトリ構成（まずこれを真似る）

```text
eks-proxy/
├── main.tf        # メイン定義
├── vpc.tf         # VPC・Subnet
├── endpoints.tf   # VPC Endpoint
├── eks.tf         # EKS本体
├── nodes.tf       # 管理Node
├── variables.tf   # 変数
└── outputs.tf     # 出力
```

---

# ① Provider とリージョン（main.tf）

```hcl
terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-northeast-1"
}
```

### 解説

* Terraform と AWS Provider の宣言
* **閉網でもOK**（apply時はあなたの端末がAWS APIを叩く）

---

# ② VPC（Private only）（vpc.tf）

```hcl
resource "aws_vpc" "this" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
}

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "ap-northeast-1a"
}

resource "aws_subnet" "private_c" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "ap-northeast-1c"
}
```

### 解説

* **Public Subnetは作らない**
* NAT Gateway も作らない
* EKSは **Private Subnetだけで問題なし**

👉 審査向けに最高の構成

---

# ③ VPC Endpoint（endpoints.tf）

```hcl
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.this.id
  service_name = "com.amazonaws.ap-northeast-1.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = []
}

resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.ap-northeast-1.ecr.api"
  vpc_endpoint_type = "Interface"
  subnet_ids        = [aws_subnet.private_a.id, aws_subnet.private_c.id]
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.ap-northeast-1.ecr.dkr"
  vpc_endpoint_type = "Interface"
  subnet_ids        = [aws_subnet.private_a.id, aws_subnet.private_c.id]
}

resource "aws_vpc_endpoint" "sts" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.ap-northeast-1.sts"
  vpc_endpoint_type = "Interface"
  subnet_ids        = [aws_subnet.private_a.id, aws_subnet.private_c.id]
}
```

### 解説（超重要）

* **ECR** → コンテナイメージ取得に必須
* **STS** → IAM Role for ServiceAccount に必須
* **S3** → 成果物保存用

👉 **「外向き通信ゼロ」だと説明できる核心**

---

# ④ EKS クラスタ本体（eks.tf）

```hcl
resource "aws_iam_role" "eks_cluster" {
  name = "eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_eks_cluster" "this" {
  name     = "proxy-eks"
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    subnet_ids = [
      aws_subnet.private_a.id,
      aws_subnet.private_c.id
    ]
    endpoint_private_access = true
    endpoint_public_access  = false
  }
}
```

### 解説

* EKS Control Plane は AWS管理
* **API Endpointは Private のみ**
* kubectl は：

  * VPN
  * Bastion
  * 社内NW接続
    から叩く

👉 審査で評価される設定

---

# ⑤ 管理Node（nodes.tf）

```hcl
resource "aws_iam_role" "node" {
  name = "eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_eks_node_group" "default" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "default"
  node_role_arn  = aws_iam_role.node.arn

  subnet_ids = [
    aws_subnet.private_a.id,
    aws_subnet.private_c.id
  ]

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  instance_types = ["t3.medium"]
}
```

### 解説

* **常駐管理Node**
* Argo CD / cert-manager / CoreDNS が乗る
* Karpenterは後で追加

---

# ⑥ Proxy設定（ここ超重要）

Node起動時に Proxy を渡します。

```hcl
resource "aws_launch_template" "proxy" {
  name_prefix = "eks-proxy-"

  user_data = base64encode(<<EOF
#!/bin/bash
cat <<EOT >> /etc/environment
HTTP_PROXY=http://proxy.corp.local:8080
HTTPS_PROXY=http://proxy.corp.local:8080
NO_PROXY=169.254.169.254,localhost,127.0.0.1,.cluster.local
EOT
EOF
)
}
```

👉 **ここが「Proxy前提EKS」の肝**

---

# ⑦ 実行手順（初回）

```bash
terraform init
terraform plan
terraform apply
```

---

# 今日の到達点まとめ

ここまでで：

* ✅ 閉網・Proxy前提EKS
* ✅ NATなし
* ✅ VPC Endpoint完備
* ✅ kubectlが通る

---
