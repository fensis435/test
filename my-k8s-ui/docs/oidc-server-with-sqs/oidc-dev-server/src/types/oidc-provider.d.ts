// ----------------------------------------------------------------------------
// oidc-provider は公式のTypeScript型定義を提供していない
// (package.json に types/typings フィールドがなく、@types/oidc-provider も
// 存在しない)。これに気づかないまま実装していたため、
// `provider.interactionDetails()` の戻り値から `session` を
// 分割代入し忘れるというバグが、コンパイル時に一切検出されなかった。
//
// 完全な型定義を自前で書き起こすのは現実的でない(ライブラリの内部API面が
// 非常に広い)ため、本アプリが実際に使用している範囲のAPIのみを対象にした
// 最小限のアンビエント宣言とする。ここに定義していないプロパティ/メソッドを
// 新たに使う場合は、この宣言を拡張すること。
// ----------------------------------------------------------------------------

declare module "oidc-provider" {
  export interface InteractionResults {
    login?: { accountId: string; [key: string]: unknown };
    consent?: { grantId: string; [key: string]: unknown };
    [key: string]: unknown;
  }

  export interface InteractionPromptDetails {
    missingOIDCScope?: string[];
    missingOIDCClaims?: string[];
    missingResourceScopes?: Record<string, string[]>;
    [key: string]: unknown;
  }

  export interface InteractionDetails {
    uid: string;
    prompt: { name: string; reasons?: string[]; details: InteractionPromptDetails };
    params: Record<string, unknown>;
    // [重要] session は accountId を含む可能性がある。存在しない場合は
    // undefined になりうるため、呼び出し側は必ずoptional chainingで
    // アクセスすること(このoptionalityがまさに今回発見・修正したバグの
    // 再発防止のためにある)。
    session?: { accountId: string; [key: string]: unknown };
    // 既存Grantへの追記が必要な場合に設定される(interactions.ts参照)。
    grantId?: string;
    [key: string]: unknown;
  }

  export class Grant {
    constructor(opts: { accountId: string; clientId: string });
    // 既存Grantを再取得する静的メソッド(interactions.tsのGrant再利用処理で使用)。
    static find(grantId: string): Promise<Grant | undefined>;
    addOIDCScope(scope: string): void;
    addOIDCClaims(claims: string[]): void;
    addResourceScope(indicator: string, scope: string): void;
    save(): Promise<string>;
  }

  // features.resourceIndicators.getResourceServerInfo等で投げる
  // 標準OAuth2/OIDCエラー(RFC 6749のerror値に対応)。
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  export const errors: Record<string, new (detail?: string) => any>;

  export default class Provider {
    constructor(issuer: string, configuration?: Record<string, unknown>);

    readonly Grant: typeof Grant;

    // configurationオプションではなく、インスタンス生成後に代入する
    // getter/setterプロパティ(リバースプロキシ配下での動作に必要)。
    proxy: boolean;

    callback(): (req: unknown, res: unknown, next?: unknown) => void;

    interactionDetails(req: unknown, res: unknown): Promise<InteractionDetails>;

    interactionFinished(
      req: unknown,
      res: unknown,
      result: InteractionResults,
      options?: { mergeWithLastSubmission?: boolean }
    ): Promise<void>;

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    on(event: string, listener: (...args: any[]) => void): this;
  }
}
