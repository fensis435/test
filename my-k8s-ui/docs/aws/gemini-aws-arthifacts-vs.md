詳細に、特に **Nexus OSS（無料版）と Pro（有料版）の違い** や、競合となる JFrog、AWS との「ライセンス構造」の差に焦点を当てて整理します。

---

## 1. Nexus Repository のライセンス詳細
Nexusは、コミュニティ版（OSS）の機能が非常に強力である点が最大の特徴です。

| 機能 | **Nexus Repository OSS** | **Nexus Repository Pro** |
| :--- | :--- | :--- |
| **ライセンス料** | **無料** | 有料（ユーザー数 or 消費型） |
| **主な対象** | 個人、小規模〜中規模開発 | エンタープライズ、ミッションクリティカル |
| **認証** | 基本的なLDAP連携 | SAML, OIDC, 高度なLDAP連携 |
| **可用性** | シングルインスタンス | **高可用性（HA）構成可能** |
| **セキュリティ** | 基本的な管理機能 | **Sonatype Lifecycle (IQ)** との統合、コンプライアンス分析 |
| **サポート** | コミュニティベース | 24/7 メーカーサポート |
| **デプロイ** | 手動 / スクリプト | ステージングワークフロー、タグ付け、クリーンアップ |

* **エンジニア視点のポイント:** OSS版でも Docker, npm, PyPI, RubyGems, Maven, NuGet などの主要フォーマットはほぼ全て対応しています。**「まずOSSで立てて、HA化やSAML連携が必要になったらProへ」**という移行パスが明確です。

---

## 2. アーティファクトリポジトリ 4大製品 比較

「自前運用（Self-Hosted）かフルマネージド（SaaS）か」という軸で比較すると、コスト構造の違いが明確になります。

| ツール名 | ライセンス体系 | 2026年現在の傾向 | 選定すべきケース |
| :--- | :--- | :--- | :--- |
| **Sonatype Nexus** | **ユーザー数 / 容量課金** | OSS版の安定性が高く、オンプレミス・自前構築のデファクト。 | **コストを抑えつつ、かつ主要なパッケージ形式を網羅したい場合。** |
| **JFrog Artifactory** | **サブスクリプション (ティア制)** | 最も高価だが、30以上の形式対応と拠点間レプリケーションが最強。 | **大規模組織で、世界中に拠点が分散しており、かつ極めて高い堅牢性が求められる場合。** |
| **AWS CodeArtifact** | **完全従量課金 (S3+API)** | インフラ管理が不要。IAMで権限管理が完結する。 | **AWS EKS等を使用しており、自前でEC2やK8s上にリポジトリを立てる工数を削減したい場合。** |
| **GitHub Packages** | **無料枠 + 超過分課金** | GitHub Actionsとの親和性が極限まで高い。 | **開発基盤がGitHubで完結しており、設定の手間を最小限にしたい場合。** |

---

## 3. ロジックに基づく選定ガイド

### A. インフラ運用コストを「ゼロ」にしたい場合
* **AWS CodeArtifact**
    * **理由:** サーバーのパッチ当て、バックアップ、ディスク容量の心配が不要。AWS EKS等の環境であれば、VPCエンドポイント経由で安全かつ高速にアクセス可能。
    * **注意:** RubyGemsやnpmには強いが、対応フォーマットがJFrogやNexusより少ない（Swift/Ruby/Python/Java/JavaScript/NuGet/Generic等）。

### B. 自前でコントロールしつつ、コストを最小化したい場合
* **Sonatype Nexus Repository OSS**
    * **理由:** ローカルのKVM環境やプライベートVPC内のEC2/EKS上に構築可能。ライセンス料が無料のため、ストレージ費用（S3やEBS）のみで運用可能。
    * **構成案:** ArgoCD等のGitOpsツールと組み合わせ、Helmチャートリポジトリやコンテナレジストリとしても活用可能。

### C. 究極の「万能性」と「セキュリティ」を求める場合
* **JFrog Artifactory (Enterprise)**
    * **理由:** 依存関係の脆弱性スキャン（Xray）が非常に優秀。バイナリのプロモーション（ビルド済み成果物をDevからStaging, Prodへ昇格させる）というCI/CDワークフローの管理機能が最も洗練されている。
    * **コスト:** 非常に高い。最低でも年間数百万円〜の予算が必要になるケースが多い。

---

## 結論：どれを選ぶべきか？

* **開発効率とインフラ保守の観点:**
    AWS環境がメインであれば、まずは **AWS CodeArtifact** が最も「合理的」です。独自サーバーの管理（アップデートや監視）にかかる人件費を削れます。
* **パッケージの多様性と実績の観点:**
    AWSでサポートされていない形式が必要だったり、既に社内で使い慣れている場合は **Nexus OSS** が最も無難です。

特定の開発環境（例えば、特定のパッケージマネージャの使用頻度や、EKSでのGitOps構成など）において、さらに深く比較が必要なポイントはありますか？

---
---

結論から申し上げますと、**Sonatype Nexus Repository OSS版は「商用利用」が可能**です。

Nexus Repository OSSは **Eclipse Public License (EPL-1.0)** に基づいて配布されており、企業内での開発や、商用サービスの成果物管理に利用することに法的制限はありません。

---

## 商用利用における主なポイント

### 1. ライセンス費用
* **無料**です。ユーザー数や保存容量に関わらず、ライセンス料を支払う必要はありません。

### 2. 権利と義務
* **複製・配布:** 社内サーバーへのインストールや複製は自由です。
* **ソースコードの開示:** Nexus OSS自体のソースコードを改変して**「再配布」**する場合には、改変部分のソースコード公開義務（コピーレフト）が生じますが、単に**「リポジトリとして利用するだけ」**であれば、自社の製品コードを公開する必要はありません。

### 3. サポートの欠如
* 商用利用は可能ですが、Sonatype社による**公式サポートはありません。**
* トラブル発生時やセキュリティパッチの適用、アップグレードなどは自社のエンジニアが責任を持って行う必要があります。

---

## 企業の「商用運用」で検討すべき3つの制約

OSS版を業務で使う場合、ライセンス面よりも以下の「機能面」がボトルネックになることが一般的です。

1.  **高可用性 (HA) 構成:**
    OSS版はシングルインスタンスでの運用が前提です。サーバーがダウンするとCI/CDパイプライン全体が止まるため、ミッションクリティカルな環境では冗長化が可能な **Pro版** や、フルマネージドの **AWS CodeArtifact** が選ばれる理由になります。
2.  **認証基盤の統合:**
    基本的なLDAP連携は可能ですが、**SAML / OIDC (SSO)** や、きめ細かなロールベースアクセス制御 (RBAC) はPro版の限定機能です。全社規模で利用する場合は管理コストが増大する可能性があります。
3.  **脆弱性スキャン:**
    OSS版単体では、保存されているライブラリの脆弱性検知（CVEの自動スキャン）機能が制限されています。これを補うには、別途 **Trivy** や **Dependency-Check** などのツールと組み合わせる設計が必要です。

### 結論
社内プロジェクトや、自分たちでサーバー運用（EKSやEC2、オンプレミスなど）を行う前提であれば、**Nexus OSSを商用で使い始めることにライセンス上の問題はありません。**

コスト効率を重視する現場では「まずはOSS版で運用し、将来的にダウンタイムが許容できなくなったり、SSO統合が必要になったタイミングでPro版へ移行する」という判断がよく取られます。

---
---

結論から申し上げますと、**AWS CodeArtifactは現在 yum (RPM) や apt (DEB) のパッケージ形式をサポートしていません。**

そのため、AWS環境でこれらのOSパッケージリポジトリが必要になった場合、エンジニアは以下の3つのいずれかのパターンで対応するのが一般的です。

---

### 1. Amazon S3 をリポジトリとして使用する（最も一般的）
yumやaptのリポジトリは、実態としては「特定のディレクトリ構造とメタデータファイル」の集まりです。これをS3に配置し、HTTP経由で公開することでリポジトリとして機能させます。

* **yum (Amazon Linux / RHEL):** `createrepo` コマンドでメタデータを作成し、S3にアップロードします。クライアント側（EC2等）の `.repo` ファイルの `baseurl` にS3のURL（またはCloudFrontのURL）を指定します。
* **apt (Ubuntu / Debian):** `reprepro` や `aptly` といったツールを使用してリポジトリ構造を作成し、S3に同期します。
* **メリット:** フルマネージドで安価。サーバー管理が不要。
* **デメリット:** パッケージの追加・削除のたびにメタデータの再生成と同期を自前で自動化（CodeBuild等を利用）する必要があります。



---

### 2. EC2 または EKS 上に Nexus Repository (OSS) を構築する
前回の比較でも触れた **Nexus** を自前で運用する方法です。

* **やり方:** EC2インスタンスやEKSクラスター上にNexusを立ち上げ、yum/apt用リポジトリを作成します。
* **メリット:** GUIで簡単にパッケージ管理ができ、メタデータの更新もツール側が自動で行ってくれます。プロキシリポジトリ機能を使えば、外部リポジトリ（CentOSミラー等）のキャッシュも可能です。
* **デメリット:** サーバー（EC2/EBS）の運用保守コストがかかります。

---

### 3. AWS Systems Manager (SSM) Distributor を検討する
もし「独自のソフトウェアを各EC2に配布・インストールしたい」という目的であれば、リポジトリを作らずに **SSM Distributor** を使う選択肢もあります。

* **やり方:** パッケージ（zip形式など）をSSMに登録し、SSM Agent経由でターゲットのEC2に配布・実行します。
* **メリット:** リポジトリサーバーの概念が不要。
* **デメリット:** 標準的な `yum install` ワークフローとは異なる運用になります。

---

### 選択の判断基準

システム構成や運用ポリシーに基づいて、以下のように使い分けるのが合理的です。

1.  **「AWSネイティブで、極力サーバーを持ちたくない」場合**
    * **S3 + CloudFront** を推奨。CI/CDパイプライン（CodePipeline/CodeBuild）の中で `createrepo` や `aptly` を叩いてS3へプッシュする構成が、AWSエンジニアの間では「定石」とされています。
2.  **「既にCodeArtifact以外の形式（Docker等）も一元管理したい、GUIが欲しい」場合**
    * **Nexus Repository (OSS)** をプライベートサブネットに構築。
3.  **「特定の数台のEC2に、自社開発ツールを入れたいだけ」の場合**
    * **SSM Distributor** または **S3から直接バイナリを `wget`**。

現在のプロジェクトにおいて、どの程度の頻度でパッケージの更新が発生し、何台程度のサーバーに配布する予定でしょうか？それによって、S3での自動化の組み込み方が変わってきます。

---
---

はい、**CloudFormation (CFn) を使用して、完全にインターネットから隔離された（Private VPC）環境で CodeArtifact を構築することは十分に可能**です。

単にリポジトリを作成するだけでなく、クライアント（EC2やEKS内のPod）が外部に出ずにアクセスするための **VPCエンドポイント（AWS PrivateLink）** の構成が鍵となります。

---

## 構築に必要な主要リソース

CFnテンプレートで定義すべきリソースは以下の通りです。

### 1. CodeArtifact 本体
* **`AWS::CodeArtifact::Domain`**: リポジトリを束ねるドメイン。
* **`AWS::CodeArtifact::Repository`**: 実際のパッケージを保存するリポジトリ。

### 2. インターフェース型 VPC エンドポイント (Interface Endpoints)
CodeArtifactには、機能に応じて**2つのエンドポイント**が必要です。
* **`com.amazonaws.[region].codeartifact.api`**:
    `get-authorization-token` などのAPI呼び出し用。
* **`com.amazonaws.[region].codeartifact.repositories`**:
    `npm install` や `mvn install` などのデータ通信用。

### 3. S3 ゲートウェイエンドポイント (Gateway Endpoint)
* **`com.amazonaws.[region].s3`**:
    **これが最も重要です。** CodeArtifactはパッケージの実体をS3に保存しているため、S3へのルートがないと接続エラーになります。

### 4. STS インターフェースエンドポイント (推奨)
* **`com.amazonaws.[region].sts`**:
    認証トークンを取得する際（`aws codeartifact get-authorization-token`）にSTSを呼び出すため、プライベート環境では必須となります。

---

## CFnテンプレートの構成ポイント

論理的・構造的なアプローチを好まれる方向けに、ネットワーク構成を整理した図解と、テンプレートの要点をまとめます。



### テンプレートの実装例 (抜粋)

```yaml
Resources:
  # 1. CodeArtifact ドメイン
  MyDomain:
    Type: "AWS::CodeArtifact::Domain"
    Properties:
      DomainName: "my-private-domain"

  # 2. CodeArtifact リポジトリ
  MyRepository:
    Type: "AWS::CodeArtifact::Repository"
    Properties:
      DomainName: !GetAtt MyDomain.Name
      RepositoryName: "my-internal-repo"

  # 3. VPC エンドポイント (API)
  CodeArtifactApiEndpoint:
    Type: "AWS::EC2::VPCEndpoint"
    Properties:
      VpcId: !Ref MyVpcId
      ServiceName: !Sub "com.amazonaws.${AWS::Region}.codeartifact.api"
      VpcEndpointType: "Interface"
      SubnetIds: !Ref PrivateSubnets
      SecurityGroupIds: [!Ref EndpointSecurityGroup]
      PrivateDnsEnabled: true

  # 4. S3 ゲートウェイエンドポイント
  S3Endpoint:
    Type: "AWS::EC2::VPCEndpoint"
    Properties:
      VpcId: !Ref MyVpcId
      ServiceName: !Sub "com.amazonaws.${AWS::Region}.s3"
      VpcEndpointType: "Gateway"
      RouteTableIds: !Ref PrivateRouteTableIds
```

---

## 運用上の留意点

1.  **Private DNS の有効化**:
    インターフェースエンドポイントの `PrivateDnsEnabled: true` は必ず設定してください。これにより、通常のCodeArtifactのURLが自動的にVPCエンドポイントのプライベートIPに解決されます。
2.  **セキュリティグループの設計**:
    エンドポイントに付与するセキュリティグループで、**HTTPS (443)** ポートをクライアント（EC2やEKS Node）のIP帯域から許可する必要があります。
3.  **トークンの有効期限**:
    プライベート環境であっても、認証には `aws codeartifact login` 等で取得するトークンが必要です。このコマンドを実行する実行環境（CI/CD runnerなど）に、前述の **STSエンドポイント** への疎通があることを確認してください。

エンタープライズなシステム構成（例えば、EKS Pod Identityとの組み合わせや、特定のアカウントのみに絞ったエンドポイントポリシーなど）について、さらに具体的な制御が必要でしょうか？

---
---

S3をバックエンドにしたyum/aptリポジトリの構築は、EC2やEKSなどのAWS環境において、外部ネットワークへの依存を排除しつつ低コストでパッケージ管理を行うための非常に強力な手法です。

ご要望に合わせて、S3での構築手順、クライアント（EC2）の設定、およびEKS Pod Identityを組み合わせた高度な設定詳細を解説します。

---

## 1. S3によるリポジトリ構築手順

リポジトリの本質は「静的ファイルの配信」です。以下のステップで構築します。

### A. S3バケットの準備
1.  **バケット作成**: `my-private-repo-bucket` のような名前で作成。
2.  **バケットポリシー**: VPCエンドポイント（S3 Gateway）経由のアクセスのみを許可するように制限します。

### B. リポジトリメタデータの作成
パッケージをアップロードした後、インデックスファイル（メタデータ）を生成する必要があります。

* **yum (RPM) の場合**:
    ```bash
    # パッケージを配置したディレクトリで実行
    createrepo_c .
    # 生成された repodata/ ディレクトリごとS3に同期
    aws s3 sync . s3://my-private-repo-bucket/yum/x86_64/
    ```
* **apt (DEB) の場合**: `aptly` などのツールを使用するのが一般的です。
    ```bash
    aptly repo create my-repo
    aptly repo add my-repo ./packages/
    aptly publish repo my-repo s3:my-private-repo-bucket:apt/
    ```

---

## 2. クライアント（EC2等）の設定方法

インターネット接続がない環境では、S3のURL（`https://bucket-name.s3.region.amazonaws.com/...`）をリポジトリ参照先に指定します。



### yumの設定 (`/etc/yum.repos.d/s3-repo.repo`)
```ini
[s3-repo]
name=My Private S3 Repository
# S3のパスを指定
baseurl=https://my-private-repo-bucket.s3.ap-northeast-1.amazonaws.com/yum/x86_64/
enabled=1
gpgcheck=0
# インスタンスプロファイル（IAMロール）を利用してアクセスするため、認証プラグインが必要な場合もありますが、
# バケットポリシーでVPC内からの参照を許可していれば、標準のHTTPアクセスとして動作します。
```

---

## 3. EKSクラスタでの設定（EKS Pod Identityの活用）

EKS上で動作するPod（ビルド用PodやアプリケーションPod）がS3上のリポジトリを利用する場合、**EKS Pod Identity** を使用して安全に権限を付与するのが最新のベストプラクティスです。

### 構成の全体像
1.  **IAMロールの作成**: S3バケットへの `s3:GetObject` および `s3:ListBucket` 権限を持つロールを作成。
2.  **Pod Identity Association**: EKSクラスターで、対象の `Namespace` と `ServiceAccount` を上記IAMロールに紐付け。
3.  **Podの設定**: 特定のServiceAccountを使用するようにPodを指定。

### 具体的なCFn/Terraform設定のポイント
EKS Pod Identityを使用すると、従来のIRSA（OIDC）よりも管理が簡素化されます。

* **IAMロールの信頼ポリシー**:
    `pods.eks.amazonaws.com` サービスプリンシパルを許可します。
* **Pod Identity Association (AWS CLI例)**:
    ```bash
    aws eks create-pod-identity-association \
      --cluster-name my-cluster \
      --namespace build-ns \
      --service-account s3-repo-sa \
      --role-arn arn:aws:iam::123456789012:role/S3ReaderRole
    ```

### EKS Pod内でのyum/apt利用の課題と解決策
コンテナ内（Dockerfileのビルド時や実行時）で `yum install` を行う際、S3への認証をどう通すかが課題になります。

1.  **サイドカーまたはInitコンテナでの同期**:
    Pod Identityで付与された権限を使い、`aws s3 sync` でS3からローカルボリュームにパッケージを落としてから `yum` を実行する。
2.  **S3リポジトリへの認証プロキシ**:
    バケットを「パブリック非公開・VPC内公開」に制限している場合、認証なしのHTTPSリクエストとして `yum` から直接参照可能です。

---

## 4. 完全プライベート環境をCFnで構築する際の重要事項

CodeArtifactと同様、yum/aptをS3で運用する場合も、**VPCエンドポイントのポリシー**が重要です。

* **S3ゲートウェイエンドポイントのポリシー**:
    ```json
    {
      "Statement": [
        {
          "Effect": "Allow",
          "Principal": "*",
          "Action": "s3:GetObject",
          "Resource": "arn:aws:s3:::my-private-repo-bucket/*",
          "Condition": {
            "StringEquals": {
              "aws:SourceVpce": "vpce-xxxxxx" 
            }
          }
        }
      ]
    }
    ```
    このように「特定のVPCエンドポイントからのアクセスのみ、特定のリポジトリバケットへの参照を許可」することで、インターネットから完全に隔離された状態でも、セキュアにパッケージ配布が可能になります。

この構成において、特に「パッケージの自動更新（CI/CD）」の部分や「特定OS（Amazon Linux 2023など）固有の挙動」について、さらに詳細な情報が必要な箇所はありますか？

---
---

結論から申し上げますと、**Amazon LinuxのOSパッケージ（RPM）を「CodeArtifactのリポジトリ」として直接利用することはできません。** CodeArtifactは現在、yumやdnfが要求するリポジトリ形式（メタデータ生成機能）をサポートしていないためです。

---

## 1. Amazon Linux パッケージと CodeArtifact の関係

CodeArtifactが公式にサポートしているのは、あくまで**アプリケーション開発用**のパッケージマネージャ（npm, PyPI, Maven, NuGet, RubyGems, Swift等）です。

* **OSパッケージ（RPM）の場合:** CodeArtifactに「汎用（Generic）パッケージ」としてファイルをアップロードすること自体は可能ですが、`yum install` や `dnf install` が動作するために必要な `repodata`（インデックス情報）をCodeArtifact側で自動生成してくれません。
* **代替案:** 前述の通り、OSパッケージに関しては **Amazon S3** をリポジトリサーバーとして活用するのがAWSにおける標準的な構成です。

---

## 2. Amazon Linux実機なしでパッケージを収集する方法

「インターネットに繋がる環境（手元のMacやWindowsなど）にAmazon Linuxがなくても、パッケージを収集できるか？」という点については、**Dockerを利用することで可能**です。

Amazon Linuxの実機を用意しなくても、Dockerが動く環境であれば、コンテナ内でパッケージをダウンロードし、それを取り出すことができます。

### 具体的な手順（Amazon Linux 2023の場合）

1.  **コンテナ内でパッケージを取得する**
    インターネットに繋がる環境のターミナルで以下を実行します。
    ```bash
    # Amazon Linux 2023のコンテナを起動
    docker run --rm -it -v $(pwd)/pkgs:/tmp/pkgs amazonlinux:2023 bash

    # コンテナ内での操作
    # 例: openssl とその依存関係をすべてダウンロード
    dnf download --releasever=2023 --alldownloads --resolve --destdir=/tmp/pkgs openssl
    exit
    ```

2.  **ホストOS側に保存されたファイルを確認**
    カレントディレクトリの `pkgs` フォルダに、OSパッケージ（.rpmファイル）が収集されています。

3.  **収集したパッケージをプライベート環境へ送る**
    収集したRPMファイルを、プライベート環境のS3バケットへアップロードします。

---

## 3. プライベート環境での「yumリポジトリ」構築フロー

インターネットから隔離されたEC2で `yum install` を実行可能にするための全体像は以下のようになります。



### ステップ1：パッケージの準備（インターネット環境）
* Docker（`amazonlinux` イメージ）を使用して、必要なRPMファイルを収集。
* `createrepo_c` ツールを使用して、メタデータ（`repodata` フォルダ）を作成。

### ステップ2：S3へアップロード
* `aws s3 sync` を使い、RPMファイルとメタデータをS3バケットへアップロード。

### ステップ3：プライベート環境のEC2設定
* EC2にS3へのアクセス権限（IAMロール）を付与。
* `/etc/yum.repos.d/s3.repo` を作成し、S3のURLを `baseurl` に指定。
* VPCエンドポイント（S3 Gateway）経由でS3へアクセス。

---

## 補足：なぜCodeArtifactではなくS3なのか？

* **互換性:** `yum` クライアントは、静的なHTTPサーバー（S3など）をリポジトリとして認識できますが、CodeArtifactのような動的なAPIベースの認証・取得フローには対応していません。
* **コスト:** OSパッケージ（特に全ミラーを作成する場合）は容量が大きくなりがちですが、S3はCodeArtifactのストレージ料金よりも安価に運用できます。

もし、特定のアプリケーションライブラリ（RubyGemsやnpm）の管理ではなく、**「OS自体のアップデートや、ミドルウェア（NGINXなど）のインストール」**が目的であれば、S3リポジトリ構成を軸に検討されるのが最も現実的です。

この収集作業自体をAWS CodeBuildなどで自動化し、定期的にS3リポジトリを更新する仕組みについても、必要であれば詳細を解説できます。

---
---

AWS CodeArtifactにRuby、Python、JavaScriptの各パッケージを登録（パブリッシュ）するための具体的な手順を整理しました。

基本的な流れは、**「AWS CLIによる認証トークンの取得」→「各言語のパッケージマネージャの設定」→「アップロード（Push/Publish）」**となります。

---

## 共通の準備
作業を行う環境（ローカルPC、CI/CD Runner、EKS Podなど）に、対象のCodeArtifactリポジトリへの `codeartifact:GetAuthorizationToken` 権限を持つIAMロールまたはユーザーが設定されている必要があります。



---

## 1. JavaScript (npm) の登録手順

npmの場合、`aws codeartifact login` コマンドを使用するのが最も簡単です。これにより、`.npmrc` ファイルが自動的に更新されます。

1.  **認証と設定**
    ```bash
    aws codeartifact login --tool npm --repository [リポジトリ名] --domain [ドメイン名] --domain-owner [アカウントID]
    ```
    * これにより、ログイン中の一時トークンが `~/.npmrc` に書き込まれます。

2.  **パッケージの登録**
    `package.json` があるディレクトリで以下を実行します。
    ```bash
    npm publish
    ```

---

## 2. Python (twine) の登録手順

Pythonパッケージのアップロードには、標準的なツールである `twine` を使用します。

1.  **認証トークンの取得**
    環境変数にトークンを格納します。
    ```bash
    export CODEARTIFACT_AUTH_TOKEN=$(aws codeartifact get-authorization-token --domain [ドメイン名] --domain-owner [アカウントID] --query authorizationToken --output text)
    ```

2.  **パッケージのビルド**
    ```bash
    python3 -m build
    ```

3.  **twineによる登録**
    リポジトリのURLは `aws codeartifact get-repository-endpoint` コマンドで確認できます。
    ```bash
    # エンドポイントの取得
    ENDPOINT=$(aws codeartifact get-repository-endpoint --domain [ドメイン名] --domain-owner [アカウントID] --repository [リポジトリ名] --format pypi --query repositoryEndpoint --output text)

    # アップロード
    twine upload --repository-url $ENDPOINT -u aws -p $CODEARTIFACT_AUTH_TOKEN dist/*
    ```

---

## 3. Ruby (gem) の登録手順

RubyGemsの場合、`~/.gem/credentials` に認証情報を設定してアップロードします。

1.  **認証トークンの取得**
    ```bash
    export CODEARTIFACT_AUTH_TOKEN=$(aws codeartifact get-authorization-token --domain [ドメイン名] --domain-owner [アカウントID] --query authorizationToken --output text)
    ```

2.  **エンドポイントの取得**
    ```bash
    ENDPOINT=$(aws codeartifact get-repository-endpoint --domain [ドメイン名] --domain-owner [アカウントID] --repository [リポジトリ名] --format ruby --query repositoryEndpoint --output text)
    ```

3.  **パッケージの登録**
    `gem push` コマンドで対象のホストを指定します。
    ```bash
    # .gem ファイルをビルド
    gem build [名前].gemspec

    # アップロード（ユーザー名は "aws"、パスワードにトークンを指定）
    gem push [作成されたgemファイル] --host $ENDPOINT --key codeartifact
    ```
    ※ 初回実行時に認証を求められた場合は、ユーザー名に `aws`、パスワードに `$CODEARTIFACT_AUTH_TOKEN` の値を入力します。

---

## 完全に隔離された環境（Private VPC）での注意点

前述の通り、インターネット接続がない環境でこれらを実行する場合、以下のエンドポイントへの疎通が必須です。

* **APIエンドポイント**: `aws codeartifact get-authorization-token` などの実行に必要。
* **Repositoryエンドポイント**: 実際のファイルアップロードに必要。
* **STSエンドポイント**: トークン発行の際の認証（IAMロールの引き受け）に必要。

### CI/CDパイプライン（GitOps等）での自動化
EKS上のビルドPod（Argo WorkflowsやJenkins Agentなど）で実行する場合、**EKS Pod Identity** を使用してPodに権限を付与し、シェルスクリプト内で `aws codeartifact get-authorization-token` を呼び出して動的に環境変数をセットする構成が一般的です。トークンの有効期限はデフォルトで12時間であるため、ビルドの直前に取得するように設計します。

これらの手順において、特定の言語でのエラーハンドリングや、より詳細な `.npmrc` / `~/.pypirc` の永続的な設定方法について深掘りが必要な部分はありますか？

