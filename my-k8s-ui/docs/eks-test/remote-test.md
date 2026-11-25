前提は以下です。

| 項目              | 確定条件                                |
| --------------- | ----------------------------------- |
| アクセス元           | KVM上のVM                             |
| DNS参照先          | KVM HostのローカルDNS                    |
| VM側DNS応答        | `127.0.0.1`                         |
| 中継方式            | AWS Systems Manager Port Forwarding |
| 中継サーバー          | AWS EC2（SSM Managed Node）           |
| 接続先             | Internal NLB                        |
| NLB Target Type | IP                                  |
| NLBの後段          | EKS Pod                             |
| TLS終端           | EKS側                                |
| 内部ドメイン          | Route 53 Private Hosted Zoneに登録     |



推奨構成

**SSM Remote Host Port Forwarding ＋ Internal NLB（TCP 443）＋ EKS側TLS終端**



この構成では、TLS通信を中継EC2で復号する必要はありません。VMのブラウザからEKSのアプリケーションまで、TLSを維持したままTCPトンネルで接続できます。

# **1. 最終AWS構成図**

オンプレミス / KVM環境

**KVM上のVM**

- Webブラウザ
- AWS CLI
- Session Manager Plugin
- ローカルDNS参照

`app.internal.example.com`

DNS応答：`127.0.0.1`

ローカルポート 18443で待受

KVM Host → 企業内Intra → AWS SSM

HTTPS 443（SSM通信）

**AWS VPC**

**SSM接続先EC2**

SSM Managed Node / 中継サーバー

SSM Agent 3.1.1374.0以上

TCP 443 / Remote Host Forwarding

**Route 53 Private Hosted Zone**

app.internal.example.com → Internal NLB

**Internal NLB**

Listener：TCP 443

Target Type：IP

Target：EKS Pod IP:443

**Amazon EKS**

- Kubernetes Service
- Application Pod
- TLS終端（証明書）
- Webアプリケーション

通信経路を整理すると、次のようになります。

| 区間                   | 通信内容         |
| -------------------- | ------------ |
| VM → SSM             | SSMセッション確立   |
| VM → localhost:18443 | HTTPSアクセス    |
| SSM → 中継EC2          | トンネル通信       |
| 中継EC2 → Internal NLB | TCP 443      |
| Internal NLB → Pod   | TCP 443      |
| Pod                  | TLS終端・HTTP処理 |

重要なのは、**SSM接続先EC2がTLSを終端するわけではない**という点です。

# **2. DNS設定**

今回の構成では、同じFQDNに対して、アクセス環境ごとに異なるDNS応答を返します。

## **2-1. KVM HostのローカルDNS**

| 項目     | 設定                         |
| ------ | -------------------------- |
| ドメイン   | `app.internal.example.com` |
| レコード   | A                          |
| IPアドレス | `127.0.0.1`                |
| 用途     | SSMトンネルの入口                 |

VMから確認します。

```
nslookup app.internal.example.com
```

期待値：

```
Name:    app.internal.example.com
Address: 127.0.0.1
```

## **2-2. Route 53 Private Hosted Zone**

AWS側は、Internal NLBをAliasレコードとして登録します。

| 項目              | 設定                     |
| --------------- | ---------------------- |
| Hosted Zone     | `internal.example.com` |
| Record Name     | `app`                  |
| Record Type     | A                      |
| Alias           | Yes                    |
| Alias Target    | Internal NLB           |
| VPC Association | 対象VPC                  |

この設定により、SSM接続先EC2から同じFQDNを問い合わせると、NLBのプライベートIPが返ります。

```
# SSM接続先EC2上で実行
nslookup app.internal.example.com
```

期待値：

```
Name: app.internal.example.com
Address: 10.0.x.x
```

NLBのIPは複数返る場合があり、固定値との一致を合格条件にする必要はありません。

**注意：** KVM VM側で127.0.0.1を返すことは、Route 53 Private Hosted ZoneがVMから直接参照できていることを意味しません。Route 53の試験はAWS側のEC2から別途実施します。

# **3. SSMポートフォワーディング設定**

今回使用するSSMドキュメントは以下です。

`AWS-StartPortForwardingSessionToRemoteHost`

通常のポートフォワーディングではなく、Remote Host方式を使用します。

AWS公式仕様では、SSM Agent 3.1.1374.0以上が必要です。また、転送先ホストの名前解決と通信はSSM接続先のManaged Node側で行われます。

[image](https://www.google.com/s2/favicons?domain=https://docs.aws.amazon.com\&sz=32)

AWS Systems Manager+1



## **3-1. 事前条件**

| 項目           | 設定例                                          |
| ------------ | -------------------------------------------- |
| SSM接続先EC2    | `i-0123456789abcdef0`                        |
| Remote Host  | `app.internal.example.com`                   |
| Remote Port  | `443`                                        |
| Local Port   | `18443`                                      |
| SSM Document | `AWS-StartPortForwardingSessionToRemoteHost` |

## **3-2. SSMセッション開始**

KVM上のVMから実行します。

```
aws ssm start-session \
  --target i-0123456789abcdef0 \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters '{"host":["app.internal.example.com"],"portNumber":["443"],"localPortNumber":["18443"]}'
```

各パラメータの意味は以下です。

| パラメータ           | 意味                   |
| --------------- | -------------------- |
| target          | SSM接続先EC2            |
| host            | 接続先Internal NLBのFQDN |
| portNumber      | Internal NLBのポート443  |
| localPortNumber | VM側の待受ポート18443       |

このとき、`host` はVM側のDNSで127.0.0.1に向けたドメインと同じ文字列ですが、実際の名前解決はSSM接続先EC2側で行われます。

つまり、今回の構成で重要なポイントです。

- VM側：`app.internal.example.com → 127.0.0.1`
- EC2側：`app.internal.example.com → Internal NLBのIP`

同じドメインでも、DNSの参照環境によって応答が異なります。

## **3-3. ポートフォワーディング確認**

別ターミナルで実行します。

```
ss -lntp | grep 18443
```

期待結果：

```
LISTEN 0 128 127.0.0.1:18443
```

実際の待受アドレスや表示形式はOS・Session Manager Pluginのバージョンによって異なる場合があります。

## **3-4. ブラウザアクセス**

VMのブラウザから以下を開きます。

```
https://app.internal.example.com:18443
```

DNSで127.0.0.1が返るため、ブラウザはVM自身の18443番ポートに接続します。

このときTLSのSNIとHTTP Hostには `app.internal.example.com` が使われます。

したがって、EKS側の証明書にこのFQDNが含まれている必要があります。

また、VMのブラウザがその証明書の発行元CAを信頼している必要があります。

**重要：** `curl -k` は証明書検証を無効化するため、最終合格判定では使用しないでください。

# **4. Internal NLBとEKSの設定確認**

今回のTarget TypeはIPなので、NLBからEKSのPod IPへ直接転送する構成です。

AWS Load Balancer Controllerを使用する場合、Serviceの設定例は以下のようになります。

## **4-1. Kubernetes Serviceの参考設定**

以下は構成イメージです。既存のServiceにそのまま適用するのではなく、現在の設定と照合してください。

```
apiVersion: v1
kind: Service
metadata:
  name: app-service
  namespace: application
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "external"
    service.beta.kubernetes.io/aws-load-balancer-scheme: "internal"
    service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: "ip"
spec:
  type: LoadBalancer
  selector:
    app: application
  ports:
    - name: https
      port: 443
      targetPort: 8443
      protocol: TCP
```

この例では、

- NLB：443番
- Pod：8443番
- TLS終端：Podの8443番

となります。

実際のPodの待受ポートに合わせて変更してください。

AWS公式資料でも、NLBのIPターゲットはPodを直接ターゲットとして登録する方式と説明されています。

[image](https://www.google.com/s2/favicons?domain=https://docs.aws.amazon.com\&sz=32)

Amazon EKS+1



## **4-2. NLBの確認**

AWSマネジメントコンソールで以下を確認します。

EC2 → ロードバランサー → 対象NLB

| 確認項目          | 期待値        |
| ------------- | ---------- |
| Scheme        | Internal   |
| Listener      | TCP:443    |
| Target Type   | IP         |
| Target        | EKS Pod IP |
| Target Port   | 8443（例）    |
| Target Health | Healthy    |

TLS終端がEKS側なので、基本的にはNLBでTLSを終端せず、TCP 443でPod側へ転送します。

## **4-3. セキュリティグループ・通信許可**

以下の通信を許可する必要があります。

| 通信元     | 通信先          | ポート         | 用途         |
| ------- | ------------ | ----------- | ---------- |
| KVM VM  | SSM関連エンドポイント | TCP 443     | SSM接続      |
| 中継EC2   | Internal NLB | TCP 443     | Web通信      |
| NLB     | EKS Pod      | TCP 8443（例） | アプリ通信      |
| EKS Pod | 必要なAWSサービス   | 環境依存        | アプリケーション処理 |

NLBにセキュリティグループを関連付けている場合は、NLBのセキュリティグループとPod側の受信ルールを確認します。

NLBにセキュリティグループがない場合は、Pod側の受信ルールをNLBからの通信元CIDRなどに合わせて設計してください。

また、NLBのIPターゲットでは、Pod IPへの直接到達性が必要です。

# **5. 試験項目書（実務向け）**

ここからは、そのまま試験仕様書に転記できる粒度でまとめます。

## **5-1. DNS試験**

| No.    | 試験項目        | 試験手順                                | 期待結果             |
| ------ | ----------- | ----------------------------------- | ---------------- |
| DNS-01 | VM DNS参照先確認 | `cat /etc/resolv.conf`              | KVM HostのDNSを参照  |
| DNS-02 | VM名前解決      | `nslookup app.internal.example.com` | 127.0.0.1が返る     |
| DNS-03 | VM DNS切替    | KVM HostのDNSレコードを変更                 | 変更後の応答が反映される     |
| DNS-04 | AWS側名前解決    | EC2で`nslookup`                      | NLBのプライベートIPが返る  |
| DNS-05 | Route 53設定  | AWSコンソール確認                          | PHZとVPCの関連付けが正しい |

## **5-2. SSM試験**

| No.    | 試験項目           | 試験手順                            | 期待結果         |
| ------ | -------------- | ------------------------------- | ------------ |
| SSM-01 | Managed Node確認 | `describe-instance-information` | 対象EC2がOnline |
| SSM-02 | SSMセッション開始     | `start-session`                 | セッション開始成功    |
| SSM-03 | Remote Host接続  | RemoteHost方式で転送                 | エラーなく接続      |
| SSM-04 | ローカルポート確認      | `ss -lntp`                      | 18443番が待受    |
| SSM-05 | SSM終了          | セッション終了                         | トンネル切断       |

## **5-3. NLB・EKS試験**

| No.    | 試験項目          | 試験手順                                       | 期待結果         |
| ------ | ------------- | ------------------------------------------ | ------------ |
| EKS-01 | NLB内部設定       | AWSコンソール確認                                 | Internal     |
| EKS-02 | Listener確認    | NLB Listener確認                             | TCP 443      |
| EKS-03 | Target Type確認 | Target Group確認                             | IP           |
| EKS-04 | Target Health | Target Group確認                             | Healthy      |
| EKS-05 | Service確認     | `kubectl get svc -n application`           | 対象Serviceが存在 |
| EKS-06 | Pod確認         | `kubectl get pods -n application -o wide`  | PodがRunning  |
| EKS-07 | Pod IP確認      | `kubectl get endpointslice -n application` | 対象Pod IPが登録  |
| EKS-08 | TLS確認         | `openssl s_client`                         | 証明書が正しい      |

## **5-4. Webアクセス試験**

| No.    | 試験項目         | 試験手順             | 期待結果        |
| ------ | ------------ | ---------------- | ----------- |
| WEB-01 | SSM起動状態でアクセス | ブラウザで内部ドメインにアクセス | Web画面が表示    |
| WEB-02 | TLS証明書確認     | ブラウザの証明書情報確認     | FQDNと証明書が一致 |
| WEB-03 | HTTP応答確認     | curlでアクセス        | 想定したHTTP応答  |
| WEB-04 | SSM終了後アクセス   | セッション終了後に再アクセス   | 接続不可        |
| WEB-05 | SSM再接続       | 再度セッション開始        | Web画面が再表示   |

# **6. 動作確認コマンド集**

実際の試験で使うコマンドをまとめます。

**① VM側 DNS**

```
nslookup app.internal.example.com
```

期待値：`127.0.0.1`

**② SSM接続先EC2側 DNS**

```
nslookup app.internal.example.com
```

期待値：Internal NLBのIPアドレス

**③ SSMポートフォワーディング**

```
aws ssm start-session \
  --target i-0123456789abcdef0 \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters '{"host":["app.internal.example.com"],"portNumber":["443"],"localPortNumber":["18443"]}'
```

**④ VM側ポート確認**

```
ss -lntp | grep 18443
```

**⑤ HTTPS疎通確認**

```
curl -v https://app.internal.example.com:18443/
```

**⑥ TLS証明書確認**

```
openssl s_client \
  -connect 127.0.0.1:18443 \
  -servername app.internal.example.com
```

期待値：

- TLSハンドシェイク成功
- 証明書のSubject Alternative Nameに対象FQDNが存在
- 証明書チェーンが信頼できる
- TLS接続が正常終了

**⑦ EKS Pod確認**

```
kubectl get pods -n application -o wide
```

```
kubectl get endpointslice -n application
```

**⑧ NLB Target Health確認（AWS CLI）**

```
aws elbv2 describe-target-health \
  --target-group-arn <TARGET_GROUP_ARN>
```

期待値：登録対象のPod IPがHealthy。

# **7. 異常系試験も実施する**

正常系だけではなく、今回の構成では以下の異常系も重要です。

| No.   | 異常系試験    | 操作                    | 期待結果                   |
| ----- | -------- | --------------------- | ---------------------- |
| NG-01 | DNS不正    | VM側DNSを誤ったIPに変更       | 想定したWeb接続ができない         |
| NG-02 | SSM停止    | SSMセッションを終了           | トンネル経由で接続できない          |
| NG-03 | NLB停止相当  | Targetを全てUnhealthyにする | 正常なアプリ応答が得られない         |
| NG-04 | Pod停止    | 対象Podを停止              | NLBのヘルスチェックに応じて接続不可となる |
| NG-05 | TLS証明書不正 | 信頼されない証明書で確認          | ブラウザが証明書エラーを表示         |
| NG-06 | 接続ポート不正  | Remote Portを誤設定       | 接続失敗                   |
| NG-07 | DNS切替    | ローカルDNSを変更            | 変更したDNS応答に応じてアクセス先が変わる |

※ NG-03、NG-04は検証環境で実施してください。本番環境で意図的にPodを停止することは避けてください。

# **8. 最も注意してほしい設計ポイント**

今回の構成で、私が特に注意したいのは3点です。

**① TLS証明書とポート番号**

ブラウザは以下のURLでアクセスします。

```
https://app.internal.example.com:18443
```

証明書は `app.internal.example.com` に対応していればよく、18443というポート番号は証明書の名前検証には影響しません。

ただし、ブラウザが証明書の発行元を信頼している必要があります。

**② NLBのヘルスチェック**

NLBはPod IPを直接ターゲットにするため、Pod IPへの通信とヘルスチェックが重要です。

NLBのターゲットがHealthyであることを必ず試験してください。

**③ SSM接続先EC2のDNS**

今回の構成では、ここが非常に重要です。

SSM Remote Host Port Forwardingの接続先ホスト名は、SSM接続先EC2から名前解決できる必要があります。

VM側で127.0.0.1を返すように設定していても、AWS側のEC2ではPrivate Hosted ZoneからNLBのアドレスが返ることを確認してください。

# **9. 最終的なおすすめ試験構成**

試験の実施順序は以下がおすすめです。

## **試験実施フロー**

1. **KVM VMのDNS確認**

   `app.internal.example.com → 127.0.0.1`
2. **AWS EC2のDNS確認**

   `app.internal.example.com → Internal NLB`
3. **SSM接続確認**

   Managed NodeがOnlineであること
4. **SSM Remote Host Port Forwarding**

   EC2からNLBの443番へ転送できること
5. **NLB・EKS確認**

   Target TypeがIP、Target HealthがHealthyであること
6. **TLS確認**

   EKS側でTLSが正常に終端されること
7. **ブラウザ接続確認**

   内部ドメインでWeb画面が表示されること
8. **SSM切断試験**

   トンネル終了後にアクセスできなくなること

## **参考にするAWS公式ドキュメント**

- [Systems Manager：Remote Host Port Forwarding](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-sessions-start.html?utm_source=chatgpt.com)
- [EKS：Load Balancing Best Practices](https://docs.aws.amazon.com/eks/latest/best-practices/load-balancing.html?utm_source=chatgpt.com)
- [EKS：Network Load Balancing](https://docs.aws.amazon.com/eks/latest/userguide/network-load-balancing.html?utm_source=chatgpt.com)
- [Route 53：Private Hosted Zones](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/hosted-zones-private.html?utm_source=chatgpt.com)

**私のおすすめとしては、今回の試験仕様書では「Route 53 Private Hosted Zone単体の試験」と「KVM VMからEKSアプリケーションまでのE2E試験」を明確に分けることです。**

これによって、DNS設定の正当性と、実際に業務で使うアクセス経路の正常性を、それぞれ独立して証明できます。
