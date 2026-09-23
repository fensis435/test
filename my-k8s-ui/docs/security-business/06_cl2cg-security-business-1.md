アップロードされた計画書を、2026年9月時点の公開情報と照合して再検証しました。

結論は、**計画書の「参入方法」は妥当ですが、「将来の主力事業」と「AIの位置づけ」は修正した方がよい**、です。

特に重要なのは次の3点です。

> **①「既存受託への付帯サービス」は入口として維持する**
> **②「クラウド診断」を主軸にはしない**
> **③ AIは2029年まで待たず、今から内部利用を始め、2年目頃からAIセキュリティ診断を商品化する**

加えて、今回の再検証で大きな論点が一つ見つかりました。

> **「作った会社が診断し、改修まで一気通貫」という差別化は、民間顧客には有効だが、独立性が求められる案件にはそのまま使えない**

2026年7月のJ-LISのセキュリティ診断調達では、診断対象システムの構築・運用受託者でないことが要件に明記されています。したがって、将来の公共・大企業・第三者保証市場まで考えると、**「開発会社としてのセキュリティレビュー」と「独立した第三者診断」を二層化する**必要があります。([J-LIS][1])

以下を私の再提案とします。

# セキュリティ診断・AIセキュリティ事業計画

## 既存受託開発企業を起点とした段階的参入モデルの再検証・再提案

### 1．総合評価

アップロードされた計画書の最大の長所は、当初提案されていた「診断専門会社へ一気に転換するモデル」を避け、既存の受託開発事業を起点として小さく始める点にある。

計画書では、最初の事業を既存契約への付帯サービスとし、既存顧客への追加提案と既存SIer経由の受注に限定している。また、「診断→改修→再診断」の一気通貫を差別化要因としている。 

この基本方針は引き続き採用する。

一方で、以下の5点は修正する必要がある。

| 論点   | 現計画           | 再提案                                     |
| ---- | ------------- | --------------------------------------- |
| 初期参入 | 既存顧客への付帯サービス  | **維持**                                  |
| 主力商品 | クラウド設定診断      | **「開発・クラウド一体型セキュリティ検証」へ変更**             |
| AI   | 3年目以降に生産性向上用途 | **0年目から内部利用、2年目前後から商品化**                |
| ASM  | 3年目以降         | **2年目頃からChange-triggered Testingとして導入** |
| 差別化  | 開発会社による診断・改修  | **開発一体型＋独立第三者型の二層モデル**                  |

---

# 2．まず「市場の方向」はAIを重視すべき

この点については、元計画よりもAIを重視する方向へ修正する。

IPAの「情報セキュリティ10大脅威2026」では、組織向けの第3位に初めて「AIの利用をめぐるサイバーリスク」が入った。第4位は従来からの「システムの脆弱性を悪用した攻撃」であり、AIリスクと従来型脆弱性の双方が重要な市場になっている。([情報処理推進機構][2])

さらに、AIセーフティ・インスティテュートは2026年7月、AIエージェントの普及を受けて評価ガイドを第1.20版へ改訂し、新たに「観測と制御」を設け、「自律的な挙動」「外部環境との相互作用」を評価対象として追加した。([AI安全研究所][3])

したがって、

> AIセキュリティを3年後まで放置する

という判断は、保守的すぎる。

ただし、

> 今すぐ「AIセキュリティ専門会社」にする

のも適切ではない。

したがって、

**AIを早期導入するが、AI単体の商品化は能力が蓄積してから行う**

という中間案が最も合理的である。

---

# 3．最大の修正点：「クラウド診断」を主軸にしない

現計画ではクラウド設定診断を主軸としている。

これは「参入しやすい」という意味では正しい。

しかし、「主力商品」とするには弱い。

理由は、クラウドプラットフォーム側のセキュリティ機能そのものが高度化しているからである。

例えばMicrosoft Defender for Cloudは、クラウド環境を継続評価し、設定ミス、脆弱性、公開状態、データ感度、横展開可能性、攻撃経路などを考慮したリスクベースの推奨を行っている。([Microsoft Learn][4])

したがって単純な、

> AWS/Azure/GCPの設定をチェックします

では、

**「クラウドのセキュリティ設定ツール＋コンサルティング」**

に近づきやすい。

そこで商品を変更する。

## 新しい主力商品

### 「開発・クラウド一体型セキュリティ検証」

対象は、

```text
Application
    ↓
Web / API
    ↓
Authentication / IAM
    ↓
Cloud
    ↓
Database
    ↓
CI/CD
    ↓
外部公開面
```

とする。

つまり、

**クラウド単体を診断するのではなく、「その会社が作ったシステム全体」を攻撃者の視点から検証する。**

これなら既存の受託開発能力そのものが競争力になる。

---

# 4．「セキュリティ健康診断」は主力ではなく入口商品

計画書の「セキュリティ健康診断」は残す。

ただし位置づけを変更する。

### 健康診断

→ 顧客との接点を作る商品

### 開発・クラウド一体型診断

→ 売上の中心

### Pentest

→ 高単価商品

### 改修・再診断

→ 高LTV化

### 継続検証

→ ストック売上

この階段にする。

```text
健康診断
   ↓
Web/API/Cloud診断
   ↓
診断＋改修
   ↓
Pentest
   ↓
再診断
   ↓
継続セキュリティ検証
```

---

# 5．もう一つ重大な修正：「作った会社が診断する」を二層構造にする

現計画では、

> 「作った会社が診断し、その場で改修まで一気通貫」

を差別化の中心としている。

民間の既存顧客に対しては、これは確かに強い。

顧客側からすると、

> 設計を知っている
> ↓
> 脆弱性を発見する
> ↓
> 改修する
> ↓
> 再診断する

を一つの会社に任せられるからである。

しかし、これを将来の全市場へ一般化してはいけない。

2026年7月のJ-LISの案件では、診断対象システムの構築・運用受託者でないことが明示的な要件になっている。つまり、一定の高信頼・公共案件では「独立性」が重要になる。([J-LIS][1])

したがって、将来は二つのサービスラインを作る。

## A．Development Security Assurance

自社が構築したシステムを対象。

```text
設計レビュー
↓
脆弱性診断
↓
改修
↓
再診断
```

これは既存受託顧客向け。

## B．Independent Security Testing

自社が構築していないシステムを対象。

```text
第三者診断
↓
Pentest
↓
報告
↓
必要に応じて別契約で改修支援
```

こちらは、

* 大企業
* SIer
* 公共案件
* 第三者保証が必要な案件

を狙う。

この構造にしておけば、最初はAで参入し、将来Bへ事業領域を拡張できる。

---

# 6．営業戦略も「新規営業ゼロ」から修正する

計画書では、当面A/Bのみとし、新規営業を非推奨としている。

これは「最初の1年」に限れば合理的である。

しかし、これを長期間維持すると成長限界が来る。

したがって、

### Phase 0～1

既存顧客

＋

既存SIer

### Phase 2

既存顧客

＋

SIerパートナー

＋

紹介

＋

セキュリティ専門会社との協業

### Phase 3

自社ブランドで選択的に新規顧客獲得

とする。

つまり、

> 新規営業をしない

ではなく、

> **初期は新規営業組織を作らない**

と定義し直す。

これは大きな違いである。

---

# 7．AIは「Phase 3から」では遅い

現計画ではAIの生産性ツール化を2029年からとしている。

これは変更する。

AIは、

## Phase 0から導入

する。

ただし顧客向け商品ではない。

### 最初にAIに任せる仕事

* 診断結果の初期分類
* 重複Finding整理
* CVE/CWE/CVSS情報整理
* ログ解析
* レポート初稿
* remediation案の下書き
* テストケース生成
* 過去案件との比較
* テスト証跡整理

とする。

---

# 8．一方、「AIに自律攻撃させる」は慎重に進める

将来的には、

```text
Recon Agent
↓
Web Agent
↓
API Agent
↓
Cloud Agent
↓
Attack Path Agent
↓
Evidence Agent
```

という構造が考えられる。

しかし顧客環境を対象とする以上、

**完全自律化を目標にするのではなくHuman-in-the-Loopを基本にする。**

OWASPのAI Agent Security Cheat Sheetでも、AIエージェントについてTool Abuse、Privilege Escalation、Data Exfiltration、Memory Poisoning、Excessive Autonomyなどをリスクとして扱い、さらに本番投入前およびプロンプト・ツール・メモリ・検索・ポリシー・モデルなどの重要変更後にAdversarial Testingを行う考え方を示している。([OWASP Cheat Sheet Series][5])

したがって、

> AI Attack Agent

ではなく、

> **AI-assisted Attack Validation**

から始める。

---

# 9．AIセキュリティ商品の投入時期

ここは次のように変更する。

### 0～12か月

AIは社内専用。

### 12～24か月

既存顧客のAIシステムを対象に試行。

対象：

* Chatbot
* RAG
* LLM API
* AI SaaS
* AI Agent

### 24～36か月

正式商品化。

```text
AI Security Assessment
+
RAG Security Assessment
+
AI Agent Security Assessment
```

### 36～60か月

AI Red Team

＋

Continuous AI Security Testing

へ進む。

これなら技術の変化に追随できる。

---

# 10．ASMも「3年後から」ではなく、別の商品に変える

現在のASM市場には既に多数の製品が存在する。

したがって、

> 外部資産を監視します

だけでは弱い。

そこで、

## Attack Surface Monitoring

ではなく、

## Change-triggered Security Testing

を狙う。

例えば、

```text
Git Push
   ↓
CI/CD
   ↓
Production Release
   ↓
New Asset Detection
   ↓
AI Risk Analysis
   ↓
Automated Security Test
   ↓
High Risk
   ↓
Human Pentest
```

とする。

これは既存の受託開発事業と非常に相性が良い。

「作っている会社だから、変更を検知できる」という強みを利用できるからである。

---

# 11．したがって、最終的な技術ロードマップは5段階にする

## Phase 0：0～6か月

### Security Delivery基盤

```text
既存開発
+
Security Checklist
+
Web/API診断
+
Cloud/IAM診断
+
AI Copilot
+
品質管理
```

最初に作るべき資産は「AIそのもの」ではない。

**診断手順、チェックリスト、テストケース、報告書、証跡、品質管理プロセスの標準化**である。

IPAの脆弱性診断内製化ガイドでも、診断チームについて幅広い知識・スキル、開発・インフラ・クラウド等の周辺知識、継続的な人材育成の重要性が示されている。([情報処理推進機構][6])

---

# 12．Phase 1：6～18か月

### Development Security Assurance

商品：

**Security Health Check**

↓

**Web/API + Cloud Security Assessment**

↓

**Remediation**

↓

**Retest**

この段階ではまだ高度なPentestを主力にしない。

目的は、

**「診断を売れる会社」になること**

である。

---

# 13．Phase 2：12～30か月

### Independent Security Testing

ここから、

* Web Pentest
* API Pentest
* Cloud Pentest
* External Attack Test

へ拡張する。

このフェーズで重要なのが、

**独立したQAレビュー**

である。

経産省の現行「情報セキュリティサービス基準」では、品質管理の一環として、案件担当者以外による検査実施報告書のレビューなどが求められる。([経済産業省][7])

さらにペネトレーションテストについては、少なくとも1名が指定資格または一定の実務実績を満たすことが基準になっている。現行4.1版では、過去3年間に合計3件以上の所定の実績を持つ者も要件のルートとして認められている。([経済産業省][8])

したがって、

**実績を作ることと制度対応を同時並行で行う。**

「資格を後追いする」のではなく、

> 資格取得を参入条件にはしないが、制度要件を満たせる体制は最初から設計する

と修正する。

---

# 14．Phase 3：24～48か月

### AI Security + Continuous Testing

ここで本格的にAIを商品化する。

```text
AI Security Assessment
RAG Security Assessment
AI Agent Security Assessment
       +
Continuous Security Testing
```

AIセーフティ・インスティテュートが2026年にAIエージェント特有の「観測と制御」「自律的な挙動」「外部環境との相互作用」を評価観点として追加したことを踏まえると、AI Agent Securityは従来のLLMプロンプト診断だけでは足りない領域になっていく。([AI安全研究所][3])

---

# 15．Phase 4：48～72か月

### AI Security Testing Platform

最終形は、

```text
                   ┌─ Web
                   ├─ API
                   ├─ Cloud
                   ├─ IAM
                   ├─ SaaS
                   ├─ AI
                   └─ Agent
                         │
                         ↓
                 AI Testing Engine
                         │
            ┌────────────┼────────────┐
            ↓            ↓            ↓
        Recon Agent   Test Agent   Attack Agent
            └────────────┼────────────┘
                         ↓
                  Human Security Expert
                         ↓
                 Attack Path / Risk
                         ↓
                     Remediation
                         ↓
                     Retest
```

ここまで進めば、最初の「診断受託会社」とはかなり違う事業になる。

---

# 16．人材計画も修正する

現計画は「既存エンジニアの育成を優先し、専門人材採用を後にする」としている。

方向性は維持する。

ただし、**攻撃側の専門家をゼロから社内育成することにはリスクがある。**

したがって、

**既存社員育成＋外部専門家＋1名のコア人材**

の組み合わせを推奨する。

### 初期5人相当

| 役割                           | 主な能力                  |
| ---------------------------- | --------------------- |
| Security Lead                | セキュリティ設計・QA・顧客説明      |
| Offensive Engineer           | Web/API/Pentest       |
| Cloud/App Engineer           | Cloud/IAM/Application |
| Security Automation Engineer | Python/AI/自動化         |
| PM/既存営業                      | 既存顧客への提案              |

このうち1名は将来的に、

**RISS + Offensive / Architecture**

方向へ育成する。

別の1名は、

**OSCP+等 + Pentest**

方向へ育成する。

さらに1名を、

**Python + LLM + Agent Security**

へ振る。

---

# 17．資格についての再提案

資格戦略も変更する。

## 最初から狙う資格

### RISS

日本企業との取引、セキュリティ設計、リスク説明、将来的な対外信用を担う人材向け。

### OSCP+

実践的な攻撃能力を育てるPentester向け。

### GPEN

Pentestの計画・実施・報告まで含めた能力を補完する候補。

### Cloud系資格

AWS / Azure / GCPのいずれかを担当領域に応じて取得。

---

# 18．CISSPは「創業時必須」ではない

前回提案ではCISSPをかなり重視したが、今回の計画においては優先順位を下げる。

理由は、

**最初の会社のボトルネックは経営・アーキテクチャの総合資格より、実際に診断を実行できる人材だからである。**

したがって、

```text
初期
OSCP+/実務攻撃力
+
Cloud
+
RISS候補
```

↓

```text
成長期
CISSP
+
Advanced Pentest
+
AI Security
```

とする。

---

# 19．資格取得の考え方は「後追い」から「並走」へ

現計画の「実績を先に作り、資格・制度登録を後追い」は、そのままだと少し危険である。

現在のIPAの情報セキュリティサービス基準適合サービスリストは2026年9月18日に更新され、脆弱性診断とペネトレーションテストのサービス区分を掲載している。ペネトレーションテストは脆弱性診断のオプションとして位置づけられている。([情報処理推進機構][9])

また、SCS評価制度では、2026年度から「技術検証事業者」という区分が設けられ、脆弱性診断・ペネトレーションテスト事業者が対象となっている。2026年度の申請受付は9月18日～10月26日で、指定期間は3年間である。([情報処理推進機構][10])

したがって、

**実績作り**
+
**資格**
+
**品質管理**
+
**制度対応**

を同時に進める。

---

# 20．特に今から記録すべきもの

将来の制度登録や大型案件を考えるなら、すべての案件について、

```text
案件名
対象システム
実施期間
実施者
資格
診断方式
使用ツール
手動テスト内容
発見Finding
攻撃成立結果
顧客への報告
再診断結果
QAレビュー
```

を保存する。

これは単なる社内記録ではなく、

**将来の「実績資産」**

になる。

---

# 21．最終的なサービス体系

最終的には次の6商品を基本とする。

| 商品                                   | 役割        |
| ------------------------------------ | --------- |
| Security Health Check                | 顧客への入口    |
| Development Security Assessment      | 既存受託との付帯  |
| Independent Vulnerability Assessment | 第三者診断     |
| Penetration Test                     | 高単価専門サービス |
| AI/RAG/Agent Security                | 将来の成長領域   |
| Continuous Security Testing          | ストック収益    |

そして、

**Remediation / Retest**

を全商品の横断サービスにする。

---

# 22．収益モデルも「診断単体」から変える

理想的な顧客の流れは、

```text
Health Check
    ↓
50～100万円程度の診断
    ↓
改修
    ↓
再診断
    ↓
Pentest
    ↓
AI Security
    ↓
Continuous Testing
```

となる。

ここで重要なのは、

**診断1件の売上を最大化することではない。**

一社について、

> 診断 → 改修 → 再診断 → Pentest → 継続契約

へ移行することである。

現計画が掲げている「単価・粗利」「解約率」「次期案件受注率」というKPIは、この観点から引き続き有効である。

ただし、次のKPIを追加する。

### 追加すべきKPI

**診断付帯率**

既存開発案件の何％に診断を付けられたか。

**改修転換率**

診断案件の何％が改修案件につながったか。

**再診断率**

何％の顧客が再診断したか。

**継続契約率**

単発売上からストック売上へ何％移行したか。

**AI生産性改善率**

1案件当たりの診断工数をAI導入によって何％削減できたか。

---

# 23．3年間の再提案

## 2026～2027

### 「既存開発会社＋Security Assurance」

重点：

```text
Web/API
Cloud
IAM
Security Review
AI社内活用
品質管理
```

目標は「セキュリティ診断会社になる」ことではなく、

**既存開発案件にセキュリティを組み込むこと。**

---

## 2027～2028

### 「Independent Security Testing」

重点：

```text
Web/API Pentest
Cloud Pentest
External Attack
Independent QA
SSS対応
AI/RAG Pilot
```

ここからセキュリティサービスとしての独立性を高める。

---

## 2028～2029

### 「Continuous Security Testing」

重点：

```text
Change-triggered Testing
ASM
AI Security
AI Agent Security
継続契約
```

ここで初めて「セキュリティ事業単体でも成長する」状態を作る。

---

## 2029年以降

### 「AI Security Testing Platform」

```text
AI-assisted Testing
+
Human Pentest
+
Continuous Testing
+
AI/Agent Red Team
```

を統合する。

---

# 24．最終的な事業コンセプト

今回の再検証を踏まえると、会社の最終ポジショニングは、

> **「脆弱性診断会社」ではない。**

と考える方がよい。

また、

> **「AIセキュリティ会社」**

と最初から名乗る必要もない。

最終的には、

> **AIを活用して、企業のシステム・クラウド・AI・エージェントを継続的に攻撃者視点で検証するSecurity Assurance Company**

とする。

日本語では、

> **「AIを活用した継続的セキュリティ検証会社」**

という位置づけが近い。

---

# 25．今回の最終判断

アップロードされた計画について、私なら以下のように意思決定する。

### そのまま採用する

**「既存受託契約を入口にする」**

これは非常に合理的。

**「最初から大規模な新規営業組織を作らない」**

これも合理的。

**「既存エンジニアを活用する」**

これも合理的。

**「診断→改修→再診断」**

これも事業上の重要な柱として維持する。

---

### 修正する

**「クラウド診断を主軸にする」**

↓

**開発・Web/API・Cloud・IAMを一体化する。**

**「AIは3年目以降」**

↓

**AIは0年目から内部利用、2年目頃から顧客向けAI Securityへ。**

**「ASMは3年目以降」**

↓

**2年目頃からChange-triggered Testingとして開発。**

**「資格・制度登録は後追い」**

↓

**サービス開始時から制度要件を意識し、実績・QA・資格を並走。**

**「作った会社が診断することが唯一の差別化」**

↓

**開発一体型サービスと独立第三者診断を分離する。**

---

# 26．最終ロードマップ

最終的には、次の一本の線で考えることを推奨する。

```text
既存受託開発
      │
      ↓
Security Review
      │
      ↓
Web / API / Cloud / IAM診断
      │
      ├────────→ 改修
      │             │
      ↓             ↓
Independent VA ─→ Retest
      │
      ↓
Pentest
      │
      ↓
AI / RAG / Agent Security
      │
      ↓
Change-triggered Security Testing
      │
      ↓
AI-assisted Continuous Pentest
      │
      ↓
AI Security Testing Platform
      │
      ↓
AI Attack Agent
      +
Human Security Expert
```

この構造なら、現在の「既存受託開発企業」という立ち位置を捨てることなく、将来的には**AIを活用した高度なセキュリティ検証プラットフォーム事業**へ移行できる。

そして今回もっとも重要な修正は、

> **「AIを後から追加する」のではなく、「AIを最初から使いながら、AIそのものを売り物にするのは能力と実績ができてから」**

という考え方である。

これが、現在の事業体力と2026年以降の技術トレンドを両立させる現実的なロードマップである。

今回の再検証では、特に**「開発会社だから診断・改修までできる」という強みを残しつつ、「第三者性が要求される市場」へ進出できる構造に変えたこと**が大きなポイントです。経産省の現行基準も第4.1版になっており、制度対応は「実績を作ってから考える」より、最初から品質管理・証跡・資格要件を意識して設計する方が安全です。([経済産業省][11])

特に次に経営計画へ落とすべきなのは、**「このロードマップを5人で開始した場合、各人をいつ・何のスキルまで育成し、どの資格をいつ取得し、何件の案件実績を積めばSSS・Pentestまで到達できるか」**という人員・資格・案件実績の3年間の連動表です。

[1]: https://www.j-lis.go.jp/about/announce/penetration_20260728.html?utm_source=chatgpt.com "J-LIS 「令和８年度セキュリティ診断業務」に係る入札公告（令和８年７月28日）"
[2]: https://www.ipa.go.jp/security/10threats/10threats2026.html?utm_source=chatgpt.com "情報セキュリティ10大脅威 2026 | 情報セキュリティ | IPA 独立行政法人 情報処理推進機構"
[3]: https://aisi.go.jp/output/output_information/260707/?utm_source=chatgpt.com "AIセーフティに関する評価観点ガイド(第1.20版)の公開 - Japan AISI"
[4]: https://learn.microsoft.com/en-us/azure/defender-for-cloud/review-security-recommendations?utm_source=chatgpt.com "Review Security Recommendations in Microsoft Defender for Cloud - Microsoft Defender for Cloud | Microsoft Learn"
[5]: https://cheatsheetseries.owasp.org/cheatsheets/AI_Agent_Security_Cheat_Sheet.html?utm_source=chatgpt.com "AI Agent Security - OWASP Cheat Sheet Series"
[6]: https://www.ipa.go.jp/jinzai/ics/core_human_resource/final_project/2025/Vulnerability-assessment.html?utm_source=chatgpt.com "脆弱性診断内製化ガイド | デジタル人材の育成 | IPA 独立行政法人 情報処理推進機構"
[7]: https://www.meti.go.jp/policy/netsecurity/shinsatouroku/zyouhoukizyun4.pdf?utm_source=chatgpt.com "情報セキュリティサービス基準"
[8]: https://www.meti.go.jp/policy/netsecurity/shinsatouroku/zyouhoukizyun4_1.pdf?utm_source=chatgpt.com "情報セキュリティサービス基準"
[9]: https://www.ipa.go.jp/security/service_list.html?utm_source=chatgpt.com "情報セキュリティサービス基準適合サービスリスト | 情報セキュリティ | IPA 独立行政法人 情報処理推進機構"
[10]: https://www.ipa.go.jp/security/scs/security-experts-organization/shiteishinsei.html "指定申請について（評価機関・技術検証事業者・研修事業者向け） | 情報セキュリティ | IPA 独立行政法人 情報処理推進機構"
[11]: https://www.meti.go.jp/policy/netsecurity/shinsatouroku/touroku.html?catsConversionApi=true&ct_1I61546c0e0IM827=15.2.365.DxAaqTPAPjkAIAW8.365.DwOIb02APjDZwyhy.DxAaqTPAPjkAIAW8.null&utm_source=chatgpt.com "情報セキュリティサービス審査登録制度（METI/経済産業省）"
