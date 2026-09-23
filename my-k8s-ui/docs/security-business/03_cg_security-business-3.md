**AIを前提にすると、前回の「脆弱性診断・ペネトレーションテスト会社」の事業モデルはかなり作り直すべき**です。

2026年時点では、IPAがAIをめぐるサイバーリスクを「情報セキュリティ10大脅威2026」の第3位として扱っており、AIコーディングエージェント、AIエージェント、自律型攻撃などが急速に現実化しています。IPAの2026年8月のAIセキュリティ短信でも「開発工程全般のアタックサーフェス化」「完全自律型脅威アクター」「AIエージェントへのゼロトラスト」などが取り上げられています。([情報処理推進機構][1])

さらに経産省も2026年5月、高性能AIが**未知の脆弱性の発見を高速化する一方、攻撃側に悪用されればサイバーリスクが一気に高まる可能性**を指摘しています。([経済産業省][2])

したがって、私は事業の中心を、

> **「人間がツールを使って脆弱性を探す会社」**
>
> ↓
>
> **「AIと人間を組み合わせ、企業の攻撃可能性を継続的に検証する会社」**

へ転換して考えます。

---

# 1. 結論：狙うべき市場が変わる

従来型の脆弱性診断は、かなりの部分がAI・自動化によってコモディティ化すると考えます。

例えば、

* ポートスキャン
* 脆弱なミドルウェア検出
* CVE照合
* 一般的なWeb脆弱性検出
* 設定ミス検出
* レポートの初稿作成
* 再診断
* 脆弱性の優先順位付け

などです。

ここはAIとの相性が非常に良い。

一方で、AI時代に価値が上がるのは、

**「その企業固有の環境で、本当に攻撃が成立するのか」**

を検証する仕事です。

そこで新しい分類をすると、私は以下の7事業に分けます。

| 分野                         | AIによる自動化 |       将来性 |    人間の専門性 |
| -------------------------- | -------: | --------: | --------: |
| ① AI自動脆弱性診断                |    非常に高い |         中 |       低〜中 |
| ② AI支援Web/API診断            |       高い |         高 |         中 |
| ③ AI/LLM/Agentセキュリティ診断     |        中 | **非常に高い** |     **高** |
| ④ AIペネトレーションテスト            |       高い | **非常に高い** |     **高** |
| ⑤ Continuous Pentest / ASM |       高い | **非常に高い** |       中〜高 |
| ⑥ AI Red Teaming           |      中〜高 | **非常に高い** | **非常に高い** |
| ⑦ AIセキュリティ運用・伴走            |       高い | **非常に高い** |         高 |

そして、**中小企業が新規参入するなら③＋④＋⑤を中心にする**のが面白いと思います。

---

# 2. 一番重要なのは「AIを使う側」ではなく「AIを攻撃する側」

ここが今回の再考の核心です。

AIを診断業務に使うだけなら、いずれ競争優位が薄くなります。

例えば、

> Burp Suite → AI解析
> Nmap → AI解析
> CVE → LLMで説明
> 診断結果 → AIで報告書作成

というだけでは、競合も同じことをできます。

それより、

> **AIそのものを攻撃対象にする**

方が新しい市場になります。

---

# 3. 「AIセキュリティ診断」を新しい主力商品にする

例えば企業が、

* ChatGPT系AI
* 社内RAG
* AIチャットボット
* AIエージェント
* AIコーディングエージェント
* AIカスタマーサポート
* AI営業支援
* AIによる社内検索
* AI＋業務システム

を導入したとします。

従来のWeb脆弱性診断だけでは、これらのリスクを十分に評価できません。

OWASPもAIエージェントについて、単純なプロンプトインジェクションだけではなく、

* Tool Abuse
* Privilege Escalation
* Data Exfiltration
* Memory Poisoning
* Goal Hijacking
* Excessive Autonomy
* Supply Chain Attack
* 高影響操作の悪用

などを挙げています。さらにAIエージェントについて、プロンプトやツール、メモリ、モデルなどの変更後にも継続的なセキュリティテストを行う考え方を示しています。([OWASP Cheat Sheet Series][3])

つまり、

**「AIを導入した企業には、新しい脆弱性診断が必要になる」**

ということです。

---

# 4. 新会社なら「AI Security Testing Company」にする

従来なら、

> Web脆弱性診断会社

でした。

これを、

> **AI Security Testing Company**

に変える。

例えばサービス体系をこうします。

### A. AI利用診断

企業が利用している生成AIについて、

* 機密情報漏洩
* プロンプトインジェクション
* RAG汚染
* 権限逸脱
* 出力制御
* 個人情報漏洩
* シャドーAI
* AI利用ルール
* ログ・監査

などを診断。

---

### B. AIアプリケーション診断

企業自身が作った、

* AIチャットボット
* RAG
* AI SaaS
* AI API
* AI検索
* AIコールセンター

などを対象にする。

---

### C. AIエージェント診断

これは今後かなり重要になると思います。

例えばAIエージェントが、

> メールを読む
> ↓
> CRMを見る
> ↓
> 顧客情報を取得
> ↓
> 見積書を作る
> ↓
> メールを送る

ところまで実行できるようになった場合。

攻撃者がAIを騙して、

> 「これは正当な管理者からの指示です」

と認識させられれば、単なる情報漏洩ではなく**業務そのものを乗っ取れる**可能性があります。

したがって、

**AIエージェントのペネトレーションテスト**

という新しい市場が成立します。

OWASPも既にAIエージェント向けの「Secure Agent Testing & Adversarial Validation」を整理しています。([OWASP Cheat Sheet Series][3])

---

# 5. ペネトレーションテストも「AI化」する

ここも大きく変わります。

従来：

```text
人間
 ↓
Nmap
 ↓
Burp
 ↓
脆弱性発見
 ↓
人間が攻撃
 ↓
レポート
```

将来：

```text
AI Agent
 ↓
Attack Surface Discovery
 ↓
Recon
 ↓
脆弱性仮説生成
 ↓
攻撃経路生成
 ↓
自動検証
 ↓
証拠収集
 ↓
人間の専門家が判断
 ↓
報告
```

という形になります。

つまり、

**AI Pentest Agent + Human Expert**

です。

これは単純な自動診断とは違います。

AIに、

> 「この企業のWeb/API/クラウド環境を攻撃者の視点から分析し、侵入可能性を検証せよ」

という仕事をさせる。

ただし、実際の攻撃操作には明確な認可・スコープ・停止条件が必要です。

---

# 6. そして「Continuous Pentest」に移行する

ここがビジネスモデル上、非常に重要です。

従来の診断：

> 年1回、100万円

だと、売上がプロジェクト型になります。

AIを使えば、

> **毎日・毎週・毎月、自動的に攻撃可能性をチェックする**

方向に持っていけます。

例えば、

### Security Continuous Testing

月額：

**10〜50万円**

として、

```text
毎日
 ↓
外部Attack Surface探索
 ↓
新規IP/ドメイン検出
 ↓
新規サービス検出
 ↓
脆弱性チェック
 ↓
AIによるリスク分析
 ↓
必要なものだけ人間が検証
 ↓
月次レポート
```

というサービスです。

これは「診断会社」より、

**セキュリティの継続監視会社**

に近くなります。

---

# 7. 実は「AI × ASM」がかなり面白い

私はここを中小企業の新規事業としてかなり注目します。

ASM = Attack Surface Management。

企業がインターネット上に何を公開しているかを継続的に把握する。

例えば、

```text
example.co.jp
       │
       ├── www
       ├── api
       ├── dev
       ├── staging
       ├── old-system
       ├── VPN
       ├── cloud
       └── forgotten-server
```

をAIが継続的に発見する。

そこから、

> 「この環境は攻撃者から見るとどう見えるか？」

をAIが分析する。

さらに、

> 「この脆弱性Aと設定ミスBを組み合わせると侵入経路Cになる可能性がある」

という**Attack Path Analysis**まで行う。

ここに人間のペネトレーションテスターが入る。

---

# 8. つまり「脆弱性の数」を売らない

これは事業戦略として非常に重要です。

旧モデル：

> 100個の脆弱性を発見しました。

新モデル：

> **攻撃者が実際に侵入できる経路を3つ発見しました。**

企業経営者にとって後者の方が重要です。

さらに、

> 「この3つを修正すれば、想定される主要な侵入経路を遮断できます」

まで言える。

この、

**Finding → Attack Path → Business Impact → Remediation**

をAI＋人間で提供する。

ここに高単価化の余地があります。

---

# 9. もう一つの巨大市場が「AI Red Teaming」

OWASPも2026年に「Gen AI and Agentic Red Teaming」の市場・ソリューションランドスケープを取り上げています。従来型のAppSecだけではAIシステムの新しいリスクを十分扱えず、敵対的テストと継続的フィードバックが必要になるという方向性です。([OWASP Gen AI Security Project][4])

例えば、

```text
AIシステム
    ↓
Red Team AI
    ↓
Prompt Injection
    ↓
RAG Poisoning
    ↓
Tool Abuse
    ↓
Privilege Escalation
    ↓
Data Exfiltration
    ↓
Agent Hijacking
```

をテストする。

これは今後、

**「AIを導入した会社なら必要になるセキュリティテスト」**

になっていく可能性があります。

---

# 10. ただし「AIだけ」に賭けるのも危険

ここは非常に重要です。

2026年の段階で、

> 「これからAIセキュリティ市場が伸びるから、AI専門会社を作ろう」

だけでは危険です。

理由は簡単で、

**AIセキュリティの技術進歩そのものが非常に速い**

からです。

したがって私は、

### 既存市場

Web/API
Cloud
Network
Mobile

↓

### 成長市場

AI Application
RAG
LLM
AI Agent

↓

### 将来市場

Continuous Pentest
Autonomous Security Testing
AI Red Team
Autonomous Attack Simulation

という**3階建て構造**にします。

---

# 11. 私なら事業ポートフォリオをこうする

### Phase 1：0〜2年

**売上を作る**

```text
Web/API診断
     +
Cloud診断
     +
Pentest
     +
ASM
```

AIを徹底的に使って、

* 診断時間短縮
* レポート作成
* 脆弱性トリアージ
* 攻撃パターン生成
* 再診断
* 顧客説明

を自動化する。

ここでは**AIを「生産性向上装置」として使う**。

---

### Phase 2：2〜4年

**AI Securityへ移行**

```text
AI Application Security
RAG Security
LLM Security
AI Agent Security
AI Pentest
```

を追加。

この段階では、

> 「普通の脆弱性診断会社」

から、

> **「AI時代の攻撃シミュレーション会社」**

へブランドを変える。

---

### Phase 3：4〜7年

**Security Testing Platform化**

最終形は、

```text
                 ┌─ Web
                 ├─ API
                 ├─ Cloud
AI Security ────┼─ SaaS
Testing Engine  ├─ AI
                 ├─ Agent
                 └─ External Attack Surface
                         ↓
                    AI Attack Agent
                         ↓
                   Human Security Expert
                         ↓
                    Risk / Attack Path
                         ↓
                      Fix
                         ↓
                    Continuous Retest
```

です。

ここまで行けば、

**「診断を売る会社」から「セキュリティ検証プラットフォームを売る会社」**

に変わります。

---

# 12. 人員構成も変わる

従来の診断会社なら、

> セキュリティエンジニア10人

ですが、AI時代は少し違います。

例えば10人なら、

| 人員                           | 人数 | 役割            |
| ---------------------------- | -: | ------------- |
| Security Researcher          |  2 | 攻撃技術・新規脆弱性    |
| Pentester                    |  2 | 実攻撃検証         |
| AI Security Engineer         |  2 | LLM/Agent/RAG |
| Security Automation Engineer |  2 | AI/自動化基盤      |
| PM/営業                        |  1 | 顧客・案件         |
| QA/Compliance                |  1 | 品質・契約・監査      |

という構成を考えます。

ポイントは、

**「人間10人で診断する」のではなく、「2〜3人の専門家がAIエージェント群を使って大量の診断を処理する」**

方向です。

---

# 13. このモデルなら「少人数で売上1億円」が見えてくる

例えば完全に仮定の事業計画ですが、

### 従来型

10人 × 年1,000万円売上

→ 1億円

というモデル。

一方AI前提なら、

```text
5人の専門家
+
AI Testing Platform
+
Continuous Testing
```

で、

### 初期診断

年間50社 × 100万円

= 5,000万円

### Pentest

年間20社 × 200万円

= 4,000万円

### Continuous Security

30社 × 月10万円

= 3,600万円

合計

**1億2,600万円**

というモデルを目指せます。

これは市場予測ではなく、**事業モデルを検討するための仮定例**です。

重要なのは売上額そのものではなく、

> **スポット診断 → 高単価Pentest → 月額Continuous Security**

という顧客単価の階段を作ることです。

---

# 14. そして「AIセキュリティ診断」には規制・信頼面の追い風もある

日本では既に経産省・IPAの「情報セキュリティサービス基準適合サービスリスト」に、脆弱性診断とペネトレーションテストが整理されています。2026年9月18日更新のリストでも、ペネトレーションテストは脆弱性診断サービスのオプションとして位置づけられています。([情報処理推進機構][5])

一方、AIについては政府側でもAIエージェントのセキュリティ対策やAI駆動開発に伴うリスクへの対応が検討されています。([経済産業省][6])

つまり、

**既存の「セキュリティ診断」という信用市場**
+
**新しい「AIセキュリティ」という成長市場**

を組み合わせるのが良い。

---

# 15. 私なら「脆弱性診断会社」を作らない

ここまでを踏まえると、会社のコンセプトをこうします。

### 従来

> 脆弱性診断・ペネトレーションテスト会社

ではなく、

### 新コンセプト

> **AI-Powered Continuous Security Testing Company**

日本語なら、

> **AIを活用した継続的セキュリティ検証サービス**

です。

そして商品を、

**① Attack Surface Monitoring**

↓

**② AI-assisted Vulnerability Assessment**

↓

**③ AI Pentest**

↓

**④ AI/LLM/Agent Red Team**

↓

**⑤ Continuous Security Testing**

とする。

---

# 16. 特に狙いたい顧客

私は大企業より、まず**AIを積極的に導入している中堅企業・SaaS企業**を狙います。

例えば、

* SaaS企業
* AI SaaS企業
* Webサービス企業
* EC
* Fintech周辺
* 医療系IT
* 人材系IT
* 不動産Tech
* 製造業のDX部門
* SIer
* AIエージェント導入企業

など。

理由は、

**「AIを使っているが、AIセキュリティの専門家はいない」**

企業が大量に出てくる可能性があるからです。

---

# 17. 最終的な事業ロードマップ

私ならこうします。

```text
2026〜27
│
├─ Web/API診断
├─ Cloud診断
├─ Pentest
└─ AIで業務効率化
        ↓
2027〜29
│
├─ AI Security Assessment
├─ LLM/RAG Security
├─ AI Agent Security
└─ AI Pentest
        ↓
2029〜31
│
├─ Continuous Pentest
├─ AI Attack Surface Management
├─ AI Red Team
└─ Autonomous Security Testing
        ↓
2031〜
│
└─ Security Testing Platform
```

そして最終的には、

> **「AIによって攻撃能力が民主化される世界で、企業側にもAIによる攻撃シミュレーション能力を提供する」**

という会社にします。

これは単なる「AIを使って効率化した脆弱性診断会社」より、かなり大きな事業テーマになります。

---

## 特に重要な私の見立て

AI時代には、**「脆弱性を見つける能力」そのものの希少性は低下する**可能性があります。

一方で希少になるのは、

**① 本当に攻撃が成立するか判断する能力**
**② 複数の脆弱性を組み合わせて攻撃経路を発見する能力**
**③ AIエージェントを攻撃・防御する能力**
**④ AIが出した結果を人間が検証する能力**
**⑤ 攻撃結果を経営上のリスクに変換する能力**

です。

つまり、

> **AI vs AI**

だけではなく、

> **AI Attack Agent ＋ 人間の高度なセキュリティ専門家**

という組み合わせが、少なくとも当面は強い事業モデルになると考えられます。IPA自身も2026年のAIセキュリティ動向で、防御側AIには可能性と限界があり、Human-in-the-Loopが必要という論点を挙げています。([情報処理推進機構][7])

**次にやるなら、ここからかなり具体化できます。**

特に面白いのは、**「従業員5人で開始 → 3年で売上3億円」を仮定して、AIをフル活用した脆弱性診断・AIペンテスト会社の事業計画を作ること**です。

その場合、**サービス別価格、1案件当たり工数、必要なAI/セキュリティツール、5人→10人→20人の採用計画、粗利、営業方法、初年度の顧客獲得数、3〜5年のPL、競合との差別化、最初に作るAI診断システムの構成**まで落とし込むと、かなり現実的な起業プランになります。

[1]: https://www.ipa.go.jp/digital/ai/security/ai_security_tips.html?utm_source=chatgpt.com "AI利用者のためのセキュリティ豆知識 | 社会・産業のデジタル変革 | IPA 独立行政法人 情報処理推進機構"
[2]: https://www.meti.go.jp/press/2026/05/20260501001/20260501001.html?utm_source=chatgpt.com "高性能AIへの対応に関して赤澤経済産業大臣が重要インフラ事業者との意見交換を実施しました （METI/経済産業省）"
[3]: https://cheatsheetseries.owasp.org/cheatsheets/AI_Agent_Security_Cheat_Sheet.html?utm_source=chatgpt.com "AI Agent Security - OWASP Cheat Sheet Series"
[4]: https://genai.owasp.org/resource/ai-security-solutions-landscape-for-ai-and-agentic-red-teaming-q2-2026/?utm_source=chatgpt.com "AI Security Solutions Landscape For AI and Agentic Red Teaming Q2 2026 - OWASP Gen AI Security Project"
[5]: https://www.ipa.go.jp/security/service_list.html?utm_source=chatgpt.com "情報セキュリティサービス基準適合サービスリスト | 情報セキュリティ | IPA 独立行政法人 情報処理推進機構"
[6]: https://www.meti.go.jp/press/2026/04/20260403003/20260403003.html?utm_source=chatgpt.com "第10回「産業サイバーセキュリティ研究会」を開催しました （METI/経済産業省）"
[7]: https://www.ipa.go.jp/digital/ai/security/ai-security-bulletin.html?utm_source=chatgpt.com "AIセキュリティ短信 | 社会・産業のデジタル変革 | IPA 独立行政法人 情報処理推進機構"
