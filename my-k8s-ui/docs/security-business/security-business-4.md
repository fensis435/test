前回の「AIを活用した継続的セキュリティ検証会社」という最終像を前提にすると、**必要な人材像は従来の脆弱性診断会社とはかなり変わります**。

結論から言うと、将来必要なのは単なる「セキュリティ資格保有者」ではなく、

> **攻撃技術 × ソフトウェア × クラウド × AI × 自動化 × リスク判断**

の5〜6領域を横断できる人材です。

特に重要なのは、**資格は「最低限の信用・知識証明」、実務スキルは「実際のサービス品質」**と割り切ることです。経産省のペネトレーションテスト基準も、資格だけでなく、過去3年間の実際のペネトレーションテスト経験を明確に評価しています。([経済産業省][1])

---

# 1. 最終的な人材モデル

将来の会社を、例えば以下の5つの技術レイヤーで考えます。

```text
                    ┌─────────────────────┐
                    │  経営・リスク判断     │
                    └─────────┬───────────┘
                              │
                    Security Architect
                              │
          ┌───────────────────┼───────────────────┐
          ↓                   ↓                   ↓
    AI Security         Offensive Security    Cloud Security
          │                   │                   │
          └───────────────────┼───────────────────┘
                              ↓
                    Security Automation
                              │
                              ↓
                     AI Attack Agents
```

この構造にすると、従業員に必要なスキルは大きく、

1. **基礎IT**
2. **攻撃・ペネトレーションテスト**
3. **Web/API・ソフトウェア**
4. **Cloud/Identity**
5. **AI/LLM/Agent**
6. **AI・自動化・プログラミング**
7. **リスク・報告・顧客対応**

の7領域になります。

---

# 2. 全員に必要な「共通基礎スキル」

まず、AI専門家を採用する場合でも、ここを飛ばしてはいけません。

### 必須

* TCP/IP
* DNS
* HTTP/HTTPS
* TLS
* Linux
* Windows
* Active Directory / Entra ID
* 認証・認可
* OAuth/OIDC/SAML
* SQL
* Git
* Python
* JavaScript/TypeScriptの基礎
* Docker
* REST API
* JSON
* IAM
* ログ・監視
* 暗号の基礎

### なぜ必要か

AIが攻撃経路を発見しても、

> 「これは本当に脆弱性なのか？」

を判断するには、**AIの下にあるITシステムを理解していなければならない**からです。

例えばAIエージェントの脆弱性を調べても、最終的には、

```text
LLM
 ↓
Agent
 ↓
API
 ↓
OAuth
 ↓
IAM
 ↓
Cloud
 ↓
Database
```

まで追わなければなりません。

OWASPもAIエージェントのリスクとして、Tool Abuse、Privilege Escalation、Data Exfiltration、Memory Poisoning、Supply Chainなどを挙げています。つまりAIだけではなく、**権限・API・データ・インフラを横断する知識**が必要になります。([OWASP Cheat Sheet Series][2])

---

# 3. 第1の中核人材：Offensive Security Engineer

これは会社の**攻撃技術のコア人材**です。

## 必要スキル

### ネットワーク

* Nmap
* TCP/IP
* Firewall
* VPN
* DNS
* Proxy
* Network segmentation

### Web

* HTTP
* Session
* Cookie
* JWT
* OAuth
* SQL Injection
* XSS
* SSRF
* CSRF
* IDOR/BOLA
* RCE
* File Upload
* Deserialization
* Business Logic

### OS

* Linux privilege escalation
* Windows privilege escalation
* Active Directory
* Kerberos
* NTLM
* PowerShell

### 攻撃技術

* Reconnaissance
* Exploitation
* Post-exploitation
* Privilege escalation
* Lateral movement
* Persistence
* Attack path analysis

### ツール

* Burp Suite
* Nmap
* Metasploit
* BloodHound
* Wireshark
* ffuf
* nuclei等
* Kali Linux

---

# 4. この人材の資格

ここは資格をかなり明確にします。

### 第一候補：OSCP+

実践的なペネトレーションテスト能力を証明する資格として非常に相性が良いです。

現在のOSCP+試験は、実環境を模したネットワークで、

* 初期侵入
* 権限昇格
* Active Directory
* 攻撃手順の文書化

などを実際に行う形式です。([オフセックサポートポータル][3])

**採用時の実技能力確認として価値が高い**です。

---

### 第二候補：GPEN

GIACのGPENは、

* Recon
* Scanning
* Exploitation
* Post-exploitation
* Pivoting
* Penetration Test Planning
* Reporting

などをカバーしています。([GIAC Certifications][4])

したがって、

> OSCP+ = 攻撃実技寄り
> GPEN = ペネトレーションテスト業務全体寄り

と考えると分かりやすいです。

---

### 上級：GXPN

これは全員に必要ありません。

* Exploit development
* Fuzzing
* Source code analysis
* Memory
* Shellcode
* 高度な攻撃

まで必要になった人向けです。([GIAC Certifications][5])

将来的な**Researcher/Advanced Red Team**に1人持たせる程度でよいでしょう。

---

# 5. 第2の中核人材：AI Security Engineer

これは今後かなり重要になります。

従来のセキュリティエンジニアと別に、

> **AIを理解したセキュリティエンジニア**

を育成します。

---

## 必要スキル

### LLM

* Transformerの基本
* Tokenization
* Context Window
* Embedding
* RAG
* Fine-tuning
* Function Calling
* Structured Output
* Model Evaluation

### AI攻撃

* Prompt Injection
* Indirect Prompt Injection
* Jailbreak
* RAG Poisoning
* Data Exfiltration
* System Prompt Leakage
* Tool Abuse
* Model Manipulation
* Agent Hijacking

### AI Agent

* Tool calling
* Memory
* Planning
* Multi-agent
* MCP
* Agent permissions
* Human-in-the-loop
* Guardrails

### AI Security

* Model security
* Data security
* Prompt security
* Agent security
* AI supply chain
* AI governance

---

# 6. AIエージェント人材には特に「権限設計」が重要

これは今後の採用基準にした方がいいと思います。

AIエージェントは、

```text
LLM
 ↓
Tool
 ↓
API
 ↓
Database
 ↓
External System
```

という構造になります。

したがって、

**「AIに詳しい人」だけでは不十分**です。

例えば、

> AIエージェントにCRMの全顧客データを取得する権限を与えていいのか？

> メール送信権限を与えていいのか？

> 決済APIを直接叩かせていいのか？

> AIの判断だけで送金させていいのか？

を判断できなければなりません。

OWASPもAI Agentについて、最小権限、Tool単位の権限分離、高リスク操作への明示的承認、人間による監督を重視しています。([OWASP Cheat Sheet Series][2])

---

# 7. AI Security人材の資格はどうするか

ここは注意が必要です。

**現時点では「AIセキュリティならこの資格」という決定版を会社の必須資格にするべきではありません。**

理由は、AIセキュリティそのものがまだ発展途上だからです。

むしろ、

### 必須

* セキュリティ基礎
* LLM/Agent技術
* Python
* Web/API
* Cloud
* 攻撃技術

### 推奨

* RISS
* CISSP
* OSCP+/GPEN
* Cloud系資格

＋

**AI Securityの実践成果**

を見る方がいいです。

IPA自身も2026年度に「Security for AI」と「AI for Security」の両方を扱うAIセキュリティ実務者向けトレーニングを実施しています。これはまさに、AIセキュリティ人材が単一領域ではなく、AIとセキュリティ双方を理解する必要があることを示しています。([情報処理推進機構][6])

---

# 8. 第3の中核人材：Cloud Security Engineer

AI時代には非常に重要です。

AIサービスのバックエンドは、

* AWS
* Azure
* GCP
* Kubernetes
* Docker
* Serverless

などになります。

したがって、

> **AI Security × Cloud Security**

が必須になります。

---

## 必要スキル

* AWS
* Azure
* GCP
* IAM
* Kubernetes
* Docker
* Terraform
* CI/CD
* Secrets Management
* Cloud Logging
* Network Security
* Container Security
* Serverless Security

さらに、

* IAM privilege escalation
* Metadata service
* Cloud storage exposure
* CI/CD compromise
* Container escape
* Kubernetes attack

などの攻撃技術。

---

# 9. Cloud資格

ここではAWS/Azureの資格を1人に全部取らせる必要はありません。

例えば、

### AWS中心

**AWS Certified Security - Specialty**

### Azure中心

Azure Security系資格

など。

そして高度なペネトレーションテスト担当なら、

**GCPN**

も候補になります。

GIACのGCPNは、AWS/Azure、Cloud Native、Container、CI/CDを含むクラウド向けペネトレーションテストを対象にしています。([GIAC Certifications][7])

---

# 10. 第4の中核人材：Security Automation / AI Engineer

これは**将来の会社価値を左右する人材**だと思います。

この人は「診断をする人」ではありません。

**診断をAIにさせる人**です。

---

## 必須スキル

### プログラミング

最重要：

**Python**

次に、

* Go
* TypeScript
* JavaScript

---

### AI

* LLM API
* Agent Framework
* RAG
* Embedding
* Vector Database
* Function Calling
* Tool Use
* Evaluation
* Prompt Engineering
* Model Context Protocol
* Agent orchestration

---

### Security Automation

例えば、

```text
Asset Discovery
      ↓
Port Scan
      ↓
HTTP Discovery
      ↓
Technology Detection
      ↓
Vulnerability Detection
      ↓
AI Analysis
      ↓
Exploit Verification
      ↓
Evidence Collection
      ↓
Risk Assessment
      ↓
Report
```

を自動化する。

---

# 11. この人材が将来の「最重要人材」になる

なぜなら、

**人間1人がAIエージェント10〜100個を監督する**

モデルになるからです。

例えば、

```text
Security Engineer
       │
       ├── Recon Agent
       ├── Web Agent
       ├── API Agent
       ├── Cloud Agent
       ├── AD Agent
       ├── AI Agent
       ├── Exploit Agent
       └── Report Agent
```

という構造。

これを設計できる人材は非常に価値が高い。

---

# 12. 第5の中核人材：Security Architect

技術が高度化するほど必要になります。

この人は、

> 「脆弱性があるか？」

ではなく、

> **「このシステム全体をどう攻撃できるか？」**

を見る人です。

---

## 必要スキル

* Zero Trust
* IAM
* Cloud Architecture
* Network Architecture
* Application Architecture
* AI Architecture
* Threat Modeling
* Attack Path Analysis
* Data Flow
* Supply Chain
* Security Architecture

特に、

**Threat Modeling**

が重要です。

例えば、

```text
User
 ↓
Web
 ↓
API
 ↓
LLM
 ↓
Agent
 ↓
Tool
 ↓
AWS
 ↓
Database
```

という構造を見て、

> どこが侵入口になり、どこまで権限が伝播するか？

を考えられる能力です。

---

# 13. このポジションにはRISSが非常に合う

日本市場をターゲットにするなら、

**情報処理安全確保支援士（登録セキスペ / RISS）**

はかなり重要です。

これは法律に基づく国家資格です。IPAによれば、セキュリティリスクを分析・評価し、技術・管理の両面から対策を助言する人材を対象としています。([情報処理推進機構][8])

特に、

* 日本企業との取引
* 大企業
* 官公庁
* SIer
* コンサルティング
* セキュリティサービス登録

を考えるなら、社内に複数人いることが信用面でプラスになります。

---

# 14. 第6の人材：Security Consultant / Risk Analyst

技術者だけでは会社は大きくなりません。

最終的に顧客が欲しいのは、

> CVSS 9.8

ではなく、

> **「結局、うちの会社は何を直せばいいの？」**

だからです。

---

## 必要スキル

* Risk Assessment
* Business Impact Analysis
* Threat Modeling
* Security Governance
* Compliance
* ISO 27001
* NIST CSF
* NIST AI RMF
* AI Governance
* Supply Chain Risk
* Executive Reporting

さらに、

**経営者に技術を説明する能力**

が重要。

---

# 15. CISSPはこのポジションに向いている

CISSPは、

* Security & Risk Management
* Asset Security
* Security Architecture
* Network Security
* IAM
* Security Assessment
* Security Operations
* Software Development Security

の8ドメインを扱っています。2026年のISC2要件でも、原則として2ドメイン以上で5年の実務経験が必要とされています。([ISC2][9])

したがって、

> **「高度な技術者」そのものより、技術・組織・リスクを横断する人**

に適しています。

---

# 16. 重要なのは「資格の数」ではない

ここは経営者としてかなり強調したいところです。

例えば、

```text
RISS
CISSP
OSCP+
GPEN
AWS Security
```

を全部持っている人が、

**AI Agentを実際に攻撃したことがない**

なら、AI Security Engineerとしては不十分です。

逆に、

> RISS
> ＋ OSCP+
> ＋ Python
> ＋ AWS
> ＋ LLM
> ＋ AI Agentの攻撃検証10案件

という人材はかなり強い。

したがって採用評価は、

### 資格 20%

### 実務 50%

### 自作・研究・CTF・OSS等 20%

### コミュニケーション 10%

くらいの考え方が良いと思います。

---

# 17. 「資格」と「実績」をこう使い分ける

| 目的               | 重視するもの          |
| ---------------- | --------------- |
| 採用時の最低ライン        | 資格              |
| 技術力              | 実技試験            |
| Pentest能力        | OSCP+/GPEN      |
| 日本企業への信用         | RISS            |
| 経営・コンサル          | CISSP           |
| Cloud            | AWS/Azure/GCP資格 |
| AI Security      | 実務・研究成果         |
| Advanced Pentest | GXPN等           |
| 会社としての信用         | SSS等の制度対応       |
| 高度案件             | 実績・顧客事例         |

---

# 18. 会社としては「RISS＋OSCP系」を二本柱にする

私なら創業期はこれを基本にします。

### 技術側

**OSCP+ / GPEN**

↓

攻撃能力

### 日本市場側

**RISS**

↓

信用・設計・コンサル

そして、

### AI側

**実務・研究・OSS・社内資格**

↓

AI Security能力

という3本柱です。

---

# 19. 創業5人ならこうする

かなり具体的に言うと、

| 人 | ポジション                        | 主資格                 |
| - | ---------------------------- | ------------------- |
| 1 | CTO / Security Architect     | RISS + CISSP        |
| 2 | Senior Pentester             | OSCP+               |
| 3 | AI Security Engineer         | OSCP+/RISS + AI実務   |
| 4 | Cloud Security Engineer      | AWS/Azure + Pentest |
| 5 | Security Automation Engineer | Python + AI/Agent   |

です。

ただし、**資格は採用条件というより育成目標**にします。

---

# 20. 10人になったらこうする

```text
                    CTO
                     │
        ┌────────────┼────────────┐
        ↓            ↓            ↓
 Offensive       AI Security    Platform
 Security          Team         Engineering
   3人              3人            2人
        └────────────┼────────────┘
                     ↓
              Architecture/QA
                  1人
                     +
                 PM/Consult
                  1人
```

### Offensive

* OSCP+
* GPEN
* GXPN

### AI

* AI Security
* LLM
* Agent
* RAG
* MCP
* Python

### Platform

* Python
* Go
* TypeScript
* Cloud
* Kubernetes
* AI Agent

### Architecture

* RISS
* CISSP

という分業。

---

# 21. 20人になったら「研究開発部門」を独立させる

ここからが重要です。

```text
                     CTO
                      │
       ┌──────────────┼──────────────┐
       ↓              ↓              ↓
  Security Lab    Product Team    Consulting
       │              │              │
       ↓              ↓              ↓
 AI Attack Lab   Testing Platform   Enterprise
 Exploit Research AI Agent          Risk
 Red Team        Automation         Governance
```

この段階では、

**「資格を持った人を増やす」**

より、

**「独自の攻撃技術・AI診断技術を持つ会社」**

に変えていく。

---

# 22. ここで「研究者」が重要になる

将来的には1〜2名、

### Security Researcher

を置くべきです。

必要なのは、

* Reverse Engineering
* Fuzzing
* Exploit Development
* Vulnerability Research
* Source Code Analysis
* LLM Research
* Agent Security
* AI Evaluation
* C/C++
* Python

など。

資格より、

**CVE、OSS、論文、CTF、独自ツール**

の方が評価材料になります。

高度な攻撃研究まで行う場合、GXPNの対象領域にもExploit Research、Fuzzing、Source Code Analysis、Memory、Shellcodeなどが含まれます。([GIAC Certifications][5])

---

# 23. そしてAI時代には「AIを使う能力」だけでは足りない

私は従業員教育を、

### AI for Security

と

### Security for AI

に分けます。

IPAもこの2つを明確に区別しています。([情報処理推進機構][6])

---

## AI for Security

AIを使って、

* Recon
* Vulnerability Analysis
* Code Review
* Report Generation
* Threat Modeling
* Log Analysis
* Attack Path Analysis

を高速化する。

---

## Security for AI

AIそのものを、

* 攻撃
* 防御
* 設計
* テスト
* 監視

する。

---

# 24. 最終的な「スキルマップ」

会社全体としては、次のようなT字型ではなく、**π型人材**を目指した方がいいと思います。

```text
              AI
              │
              │
Security ─────┼───── Software
              │
              │
             Cloud
```

つまり、

### 縦棒①

**Security**

### 縦棒②

**AI / Software**

### 横断領域

**Cloud / Business**

です。

---

# 25. 優先順位をつけると

## Sランク：全社として必須

* Web/API Security
* Network
* Linux/Windows
* Cloud
* IAM
* Python
* Git
* Threat Modeling
* Pentest
* AI/LLM基礎
* Agent Security

---

## Aランク：中核人材に必須

* Active Directory
* Kubernetes
* Terraform
* RAG
* MCP
* AI Agent
* Exploit
* Fuzzing
* Reverse Engineering
* Attack Path Analysis
* DevSecOps

---

## Bランク：専門家育成

* Kernel
* Malware
* Advanced Exploit
* Binary Analysis
* Model Security
* Advanced AI Red Team
* Multi-Agent Security

---

# 26. 資格ロードマップ

会社の成長に合わせると、私はこうします。

```text
入社
 │
 ├─ Security基礎
 │
 ├─ Python
 │
 ├─ Web/API
 │
 └─ Cloud
      ↓
  RISS / OSCP+等
      ↓
 ┌────┴─────┐
 ↓          ↓
Pentest    AI Security
 ↓          ↓
GPEN       AI/Agent
 ↓          ↓
GXPN       AI Red Team
 └────┬─────┘
      ↓
Security Architect
      ↓
Research / CTO
```

---

# 27. ただし、経産省の基準上は「資格取得」より実務経験が重要

ここは事業計画上、非常に重要です。

経産省の現行「情報セキュリティサービス基準」では、ペネトレーションテストサービスについて、従事者のうち少なくとも1名が指定資格等を持つか、**過去3年間に3件以上の対象となる実績**を持つことが要件になっています。([経済産業省][1])

したがって創業時から、

```text
案件
 ↓
実施者
 ↓
実施内容
 ↓
対象環境
 ↓
攻撃結果
 ↓
顧客確認
 ↓
実績証跡
```

を保存しておくべきです。

これは単なる人事管理ではなく、

**将来のサービス登録・公共案件・大企業案件に使える「技術資産」**

になります。

---

# 28. さらに報告書を書く能力も技術スキル

意外に見落とされますが、非常に重要です。

経産省のペネトレーションテスト報告書基準では、

* Executive Summary
* Technical Report
* テスト範囲
* テスト方法
* 脅威モデリング
* リスク影響
* 推奨対策
* 実施体制・資格

などを明確にすることが求められています。([経済産業省][10])

したがって、

**「ハッキングができる人」だけでは商品になりません。**

必要なのは、

> **攻撃 → 証拠 → リスク → 経営者への説明 → 改善案**

までできる人です。

---

# 29. 最終的に会社が目指す人材像

私なら採用基準を最終的にこうします。

### Level 1：Security Engineer

```text
IT
+
Web
+
Network
+
Cloud
```

↓

### Level 2：Pentester

```text
Level 1
+
Offensive Security
+
OSCP+/GPEN
```

↓

### Level 3：AI Security Engineer

```text
Level 2
+
LLM
+
RAG
+
Agent
+
MCP
```

↓

### Level 4：AI Red Team Engineer

```text
Level 3
+
Advanced Attack
+
Threat Modeling
+
Attack Automation
```

↓

### Level 5：AI Security Architect

```text
Security
+
AI
+
Cloud
+
Software
+
Business Risk
```

↓

### Level 6：Security Researcher / CTO

```text
Level 5
+
Research
+
Novel Attack
+
Platform
+
Business
```

---

# 30. 最終結論

この事業を本当に将来性のある会社にするなら、**「資格保有者を集める会社」にはしない方がいい**です。

目指すべきは、

> **資格で最低限の信用を作り、実務で攻撃能力を作り、AIで生産性を上げ、独自研究で競争優位を作る会社**

です。

そして人材戦略の中心を、

**RISS**

↓

**OSCP+/GPEN**

↓

**Cloud**

↓

**Python / Automation**

↓

**LLM / RAG / Agent / MCP**

↓

**AI Red Team**

↓

**Security Research**

という順序にする。

特に創業初期の5人については、私は**「RISSを持つArchitect 1名」「実戦型Pentester 1〜2名」「AI Security 1名」「AI/Automation Engineer 1名」**を核にします。

そして最終的には、1人の人間がAI診断エージェント群を大量に指揮できる**「Human-led, AI-operated Security Testing」**の組織へ移行するのが、この会社の技術ロードマップとして最も重要だと考えます。

なお、2026年現在、IPAのサプライチェーン・サイバーセキュリティ対策評価制度では、脆弱性診断・ペネトレーションテスト事業者を技術検証事業者として位置づける制度も始まっているため、将来の事業信用を考えると、**資格ロードマップと同時に「どの制度・登録を取得する会社にするか」まで人材計画に組み込む**べきです。([情報処理推進機構][11])

次の段階では、この人材ロードマップを**「5人→10人→20人→50人」の採用計画に変換し、各ポジションの年収レンジ、採用要件、資格取得費用、育成期間、1人当たり売上、生産性まで入れた人員計画表**にすると、経営計画としてかなり使える形になります。

[1]: https://www.meti.go.jp/policy/netsecurity/shinsatouroku/zyouhoukizyun4.pdf?utm_source=chatgpt.com "情報セキュリティサービス基準"
[2]: https://cheatsheetseries.owasp.org/cheatsheets/AI_Agent_Security_Cheat_Sheet.html?utm_source=chatgpt.com "AI Agent Security - OWASP Cheat Sheet Series"
[3]: https://help.offsec.com/hc/en-us/articles/360040165632-OSCP-Exam-Guide?utm_source=chatgpt.com "OSCP+ Exam Guide – OffSec Support Portal"
[4]: https://www.giac.org/certifications/penetration-tester-gpen?utm_source=chatgpt.com "GIAC Penetration Tester Certification (GPEN)| Cybersecurity Certification"
[5]: https://www.giac.org/certifications/exploit-researcher-advanced-penetration-tester-gxpn?utm_source=chatgpt.com "GIAC Exploit Researcher and Advanced Penetration Tester (GXPN) | Cybersecurity Certification"
[6]: https://www.ipa.go.jp/jinzai/ics/short-pgm/ai-security/ai-security.html?utm_source=chatgpt.com "実務者向けプログラム 重要インフラ分野におけるAIセキュリティトレーニング | デジタル人材の育成 | IPA 独立行政法人 情報処理推進機構"
[7]: https://www.giac.org/certifications/cloud-penetration-tester-gcpn?utm_source=chatgpt.com "GIAC Cloud Penetration Tester (GCPN) | Cybersecurity Certification"
[8]: https://www.ipa.go.jp/jinzai/riss/seido/shikaku.html?utm_source=chatgpt.com "根拠となる法律、資格名称、情報処理安全確保支援士のロゴマークについて | デジタル人材の育成 | IPA 独立行政法人 情報処理推進機構"
[9]: https://www.isc2.org/Insights/2026/05/CISSP-Experiene-Waiver-Updates?utm_source=chatgpt.com "ISC2 CISSP Experience Waiver Updates Requirements"
[10]: https://www.meti.go.jp/policy/netsecurity/shinsatouroku/reiji3.pdf?utm_source=chatgpt.com "別表　ペネトレーションテスト（侵入試験）に関する試験実施報告書において満たすべき事項"
[11]: https://www.ipa.go.jp/security/scs/security-experts-organization/shiteishinsei.html?utm_source=chatgpt.com "指定申請について（評価機関・技術検証事業者・研修事業者向け） | 情報セキュリティ | IPA 独立行政法人 情報処理推進機構"
