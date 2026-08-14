# テスト実行方法

## セットアップ

```bash
npm install
npx prisma generate
```

## 実行

```bash
npm test          # 全テストを1回実行
npm run test:watch  # watchモード
```

## テスト構成

| ファイル | 種別 | 依存 |
|---|---|---|
| `src/shared/pagination.test.ts` | ユニット | なし(純粋関数) |
| `src/shared/url-safety.test.ts` | ユニット | なし(直接IPリテラルのケースのみ、DNS解決なし) |
| `src/identity/users.service.test.ts` | 統合 | 一時SQLiteファイル(`prisma db push`で自動セットアップ) |

## DIパターンについて

`src/webhooks/event-publisher.ts` の `setEventPublisher()` / `resetEventPublisher()` により、
Identity層(users.service / groups.service)のテスト時にWebhook実配信(ネットワークI/O)を
フェイク実装に差し替えられる。新しいサービスのテストを書く際もこのパターンに従うこと。

## 既知の制約

- `url-safety.test.ts` はホスト名解決を伴うケース(一般ドメイン名からの
  DNS Rebinding検知)を意図的にテスト対象から除外している。CI環境での
  DNS到達性に依存させないための判断。実運用では結合テスト環境で別途検証すること。
- `users.service.test.ts` はテスト実行のたびに一時SQLiteファイルを作成する。
  CI実行時間短縮のため、将来的にはテストDBの使い回し(トランザクション
  ロールバックによる分離)への切り替えを検討してもよい。
