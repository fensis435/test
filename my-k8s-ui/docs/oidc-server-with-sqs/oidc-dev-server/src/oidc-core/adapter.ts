import { createHash } from "node:crypto";
import { prisma } from "../infra/persistence/prisma-client.js";

// ----------------------------------------------------------------------------
// oidc-provider が要求する Adapter インターフェースの実装。
//
// 設計方針:
//   - Client / AuthorizationCode / RefreshToken は、前回のDB設計で定義した
//     業務テーブル(clients / authorization_codes / refresh_tokens)に
//     そのままマッピングする。仕様(ER図・PK・FK・Index)は変更しない。
//   - それ以外の oidc-provider 内部モデル(Session, Interaction, Grant,
//     DeviceCode, BackchannelAuthenticationRequest,
//     PushedAuthorizationRequest, ReplayDetection, AccessToken,
//     RegistrationAccessToken, InitialAccessToken)は、業務要件の設計対象外
//     (oidc-providerの内部実装詳細)であるため、汎用KVストア
//     (OidcGenericStore)に格納する。
//
// [修正: レビュー指摘#11] OCP違反の解消
//   従来は upsert/find/consume/destroy の各メソッド内で
//   `switch (this.model)` によりモデル種別ごとの分岐を行っており、
//   新しいモデル対応の追加のたびにこのクラス自体を修正する必要があった
//   (Open-Closed Principle違反)。
//   本修正では ModelStrategy インターフェースを定義し、モデル名から
//   戦略オブジェクトを引くマップ(MODEL_STRATEGIES)に置き換える。
//   新しいモデル固有の永続化ロジックが必要になった場合は、
//   このマップにエントリを追加するだけでよく、既存コードの修正は不要になる。
// ----------------------------------------------------------------------------

export function sha256(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

export interface AdapterPayload {
  [key: string]: unknown;
  grantId?: string;
  userCode?: string;
  uid?: string;
}

export interface ModelStrategy {
  upsert(id: string, payload: AdapterPayload, expiresIn: number, modelName: string): Promise<void>;
  find(id: string): Promise<AdapterPayload | undefined>;
  consume(id: string): Promise<void>;
  destroy(id: string): Promise<void>;
}

// ------------------------------------------------------------------------
// Client戦略
// ------------------------------------------------------------------------

const clientStrategy: ModelStrategy = {
  async upsert(id, payload) {
    const isPublic = payload.token_endpoint_auth_method === "none";
    await prisma.client.upsert({
      where: { clientId: id },
      create: {
        clientId: id,
        clientSecretHash: payload.client_secret ? sha256(String(payload.client_secret)) : null,
        isPublic,
        tokenEndpointAuthMethod: mapAuthMethod(String(payload.token_endpoint_auth_method ?? "none")),
        redirectUris: JSON.stringify(payload.redirect_uris ?? []),
        postLogoutRedirectUris: JSON.stringify(payload.post_logout_redirect_uris ?? []),
        allowedScopes: JSON.stringify(String(payload.scope ?? "").split(" ").filter(Boolean)),
        grantTypes: JSON.stringify(payload.grant_types ?? ["authorization_code", "refresh_token"]),
      },
      update: {
        redirectUris: JSON.stringify(payload.redirect_uris ?? []),
        postLogoutRedirectUris: JSON.stringify(payload.post_logout_redirect_uris ?? []),
        allowedScopes: JSON.stringify(String(payload.scope ?? "").split(" ").filter(Boolean)),
        grantTypes: JSON.stringify(payload.grant_types ?? ["authorization_code", "refresh_token"]),
      },
    });
    invalidateClientCache(id);
  },

  async find(id) {
    const client = await prisma.client.findFirst({ where: { clientId: id, deletedAt: null } });
    if (!client) return undefined;

    return {
      client_id: client.clientId,
      client_secret: undefined, // ハッシュのみ保持。平文は返さない。
      token_endpoint_auth_method: mapAuthMethodReverse(client.tokenEndpointAuthMethod),
      redirect_uris: JSON.parse(client.redirectUris),
      post_logout_redirect_uris: JSON.parse(client.postLogoutRedirectUris),
      scope: (JSON.parse(client.allowedScopes) as string[]).join(" "),
      grant_types: JSON.parse(client.grantTypes),
      response_types: ["code"],
    };
  },

  async consume() {
    // Clientはconsume概念を持たない(oidc-providerからも呼ばれない)。
  },

  async destroy(id) {
    await prisma.client.updateMany({ where: { clientId: id }, data: { deletedAt: new Date() } });
    invalidateClientCache(id);
  },
};

// ------------------------------------------------------------------------
// AuthorizationCode戦略
// ------------------------------------------------------------------------

const authorizationCodeStrategy: ModelStrategy = {
  async upsert(id, payload, expiresIn) {
    const codeHash = sha256(id);
    const expiresAt = new Date(Date.now() + expiresIn * 1000);

    await prisma.authorizationCode.create({
      data: {
        codeHash,
        userId: String(payload.accountId),
        clientId: await resolveClientRowId(String(payload.clientId)),
        redirectUri: String(payload.redirectUri ?? ""),
        codeChallenge: String(payload.codeChallenge ?? ""),
        codeChallengeMethod: "S256",
        scope: String(payload.scope ?? ""),
        nonce: payload.nonce ? String(payload.nonce) : null,
        // [修正] grantId を正式カラムに保存する。以前はOidcGenericStoreへの
        // 副次インデックスとしてのみ書き込み、find()で読み返していなかったため、
        // oidc-providerのGrant解決が常に失敗していた(invalid_grant原因)。
        grantId: payload.grantId ? String(payload.grantId) : null,
        // [修正] resource(Resource Indicators)の保存が完全に抜けていた。
        // oidc-providerは常に単一resourceに解決した後の値(文字列)を
        // payload.resource として渡してくる(このシステムはリソースサーバーを
        // 1つしか持たないため配列になることはない)。これが欠落していたため、
        // /token交換時に resolveResource() が code.resource === undefined と
        // 判定し、Access Tokenが常にopaqueで発行されていた。
        resource: payload.resource ? String(payload.resource) : null,
        expiresAt,
      },
    });
  },

  async find(id) {
    const codeHash = sha256(id);
    const row = await prisma.authorizationCode.findUnique({ where: { codeHash }, include: { client: true } });
    if (!row) return undefined;
    if (row.expiresAt.getTime() < Date.now()) return undefined;

    return {
      // [修正] jti が欠落していたため、oidc-providerがモデルを再構築した際
      // this.jti が undefined になり、後続の code.consume() が
      // adapter.consume(undefined) を呼んでクラッシュしていた。
      // BaseModelのコンストラクタは payload.jti から this.jti を設定するため、
      // find() で返すpayloadには必ず jti(=検索に使ったidそのもの)を
      // 含める必要がある。
      jti: id,
      accountId: row.userId,
      clientId: row.client.clientId,
      redirectUri: row.redirectUri,
      codeChallenge: row.codeChallenge,
      codeChallengeMethod: row.codeChallengeMethod,
      scope: row.scope,
      nonce: row.nonce ?? undefined,
      // [修正] 保存時のgrantIdをここで正しく返却する。
      grantId: row.grantId ?? undefined,
      // [修正] resourceをここで正しく返却する。
      resource: row.resource ?? undefined,
      consumed: row.usedAt ? Math.floor(row.usedAt.getTime() / 1000) : undefined,
    };
  },

  async consume(id) {
    const codeHash = sha256(id);
    await prisma.authorizationCode.updateMany({
      where: { codeHash },
      data: { usedAt: new Date() },
    });
  },

  async destroy(id) {
    const codeHash = sha256(id);
    await prisma.authorizationCode.deleteMany({ where: { codeHash } });
  },
};

// ------------------------------------------------------------------------
// RefreshToken戦略
// ------------------------------------------------------------------------

const refreshTokenStrategy: ModelStrategy = {
  async upsert(id, payload, expiresIn) {
    const tokenHash = sha256(id);
    const expiresAt = new Date(Date.now() + expiresIn * 1000);
    const familyId = String(payload.grantId ?? id);

    await prisma.refreshToken.create({
      data: {
        tokenHash,
        familyId,
        userId: String(payload.accountId),
        clientId: await resolveClientRowId(String(payload.clientId)),
        scope: String(payload.scope ?? ""),
        // [修正] AuthorizationCodeと同じ理由でresourceが欠落していた。
        // Refresh Token Grant(トークン更新)でもJWT形式のAccess Token
        // を再発行できるようにするために必要。
        resource: payload.resource ? String(payload.resource) : null,
        expiresAt,
      },
    });
  },

  async find(id) {
    const tokenHash = sha256(id);
    const row = await prisma.refreshToken.findUnique({ where: { tokenHash }, include: { client: true } });
    if (!row) return undefined;
    if (row.revokedAt) return undefined;
    if (row.expiresAt.getTime() < Date.now()) return undefined;

    return {
      // [修正] AuthorizationCodeと同じ理由でjtiが欠落していた。
      // Refresh Token Grant(トークン更新)を使うと同じ
      // ERR_INVALID_ARG_TYPE クラッシュが再現するはずだった潜在バグ。
      jti: id,
      accountId: row.userId,
      clientId: row.client.clientId,
      scope: row.scope,
      grantId: row.familyId,
      // [修正] resourceをここで正しく返却する。
      resource: row.resource ?? undefined,
    };
  },

  async consume(id) {
    const tokenHash = sha256(id);
    await prisma.refreshToken.updateMany({
      where: { tokenHash },
      data: { revokedAt: new Date(), revokedReason: "CONSUMED" },
    });
  },

  async destroy(id) {
    const tokenHash = sha256(id);
    await prisma.refreshToken.deleteMany({ where: { tokenHash } });
  },
};

// ------------------------------------------------------------------------
// Generic戦略 (Session, Interaction, Grant, DeviceCode, etc.)
// oidc-provider内部モデルのうち業務テーブルを持たないものすべての既定挙動。
// ------------------------------------------------------------------------

const genericStrategy: ModelStrategy = {
  async upsert(id, payload, expiresIn, modelName) {
    const expiresAt = expiresIn ? new Date(Date.now() + expiresIn * 1000) : null;
    await prisma.oidcGenericStore.upsert({
      where: { modelName_key: { modelName, key: id } },
      create: {
        modelName,
        key: id,
        payload: JSON.stringify(payload),
        grantId: payload.grantId ?? null,
        userCode: payload.userCode ?? null,
        uid: payload.uid ?? null,
        expiresAt,
      },
      update: {
        payload: JSON.stringify(payload),
        grantId: payload.grantId ?? null,
        userCode: payload.userCode ?? null,
        uid: payload.uid ?? null,
        expiresAt,
      },
    });
  },

  async find(_id) {
    // modelNameはfind時に受け取れないため、呼び出し元(PrismaOidcAdapter)で解決する。
    // ここではidのみでの解決はできないため、findはPrismaOidcAdapter側でmodelNameを
    // 補って直接クエリする(下記 PrismaOidcAdapter.find 参照)。
    throw new Error("genericStrategy.find must be called via PrismaOidcAdapter with modelName bound.");
  },

  async consume(id) {
    throw new Error(`genericStrategy.consume must be called via PrismaOidcAdapter with modelName bound: ${id}`);
  },

  async destroy(id) {
    throw new Error(`genericStrategy.destroy must be called via PrismaOidcAdapter with modelName bound: ${id}`);
  },
};

// モデル名 -> 戦略 のマップ。新しい専用戦略を追加する場合はここにエントリを足すだけでよい。
const MODEL_STRATEGIES: Record<string, ModelStrategy> = {
  Client: clientStrategy,
  AuthorizationCode: authorizationCodeStrategy,
  RefreshToken: refreshTokenStrategy,
};

function resolveStrategy(modelName: string): ModelStrategy {
  return MODEL_STRATEGIES[modelName] ?? genericStrategy;
}

// ----------------------------------------------------------------------------
// PrismaOidcAdapter
// oidc-providerから見た薄いディスパッチャ。モデル固有ロジックは一切持たず、
// resolveStrategy() で得た戦略オブジェクトに処理を委譲する。
// genericStrategyのみ modelName を必要とするため、ここでバインドして渡す。
// ----------------------------------------------------------------------------

export class PrismaOidcAdapter {
  public readonly model: string;
  private readonly strategy: ModelStrategy;

  constructor(name: string) {
    this.model = name;
    this.strategy = resolveStrategy(name);
  }

  async upsert(id: string, payload: AdapterPayload, expiresIn: number): Promise<void> {
    await this.strategy.upsert(id, payload, expiresIn, this.model);
  }

  async find(id: string): Promise<AdapterPayload | undefined> {
    if (this.strategy === genericStrategy) {
      return findGeneric(this.model, id);
    }
    return this.strategy.find(id);
  }

  async findByUserCode(userCode: string): Promise<AdapterPayload | undefined> {
    const row = await prisma.oidcGenericStore.findFirst({
      where: { modelName: this.model, userCode },
    });
    return row ? (JSON.parse(row.payload) as AdapterPayload) : undefined;
  }

  async findByUid(uid: string): Promise<AdapterPayload | undefined> {
    const row = await prisma.oidcGenericStore.findFirst({
      where: { modelName: this.model, uid },
    });
    return row ? (JSON.parse(row.payload) as AdapterPayload) : undefined;
  }

  async consume(id: string): Promise<void> {
    if (this.strategy === genericStrategy) {
      await prisma.oidcGenericStore.updateMany({
        where: { modelName: this.model, key: id },
        data: { consumedAt: new Date() },
      });
      return;
    }
    await this.strategy.consume(id);
  }

  async destroy(id: string): Promise<void> {
    if (this.strategy === genericStrategy) {
      await prisma.oidcGenericStore.deleteMany({ where: { modelName: this.model, key: id } });
      return;
    }
    await this.strategy.destroy(id);
  }

  async revokeByGrantId(grantId: string): Promise<void> {
    // RefreshToken / AuthorizationCode は grantId を familyId として保持している。
    await prisma.refreshToken.updateMany({
      where: { familyId: grantId, revokedAt: null },
      data: { revokedAt: new Date(), revokedReason: "GRANT_REVOKED" },
    });
    await prisma.oidcGenericStore.deleteMany({ where: { grantId } });
  }
}

async function findGeneric(modelName: string, id: string): Promise<AdapterPayload | undefined> {
  const row = await prisma.oidcGenericStore.findUnique({
    where: { modelName_key: { modelName, key: id } },
  });
  if (!row) return undefined;
  if (row.expiresAt && row.expiresAt.getTime() < Date.now()) return undefined;

  const payload = JSON.parse(row.payload) as AdapterPayload;
  if (row.consumedAt) {
    payload.consumed = Math.floor(row.consumedAt.getTime() / 1000);
  }
  return payload;
}

// ----------------------------------------------------------------------------
// Helpers
// ----------------------------------------------------------------------------

export function mapAuthMethod(value: string): "NONE" | "CLIENT_SECRET_BASIC" | "CLIENT_SECRET_POST" {
  if (value === "client_secret_basic") return "CLIENT_SECRET_BASIC";
  if (value === "client_secret_post") return "CLIENT_SECRET_POST";
  return "NONE";
}

export function mapAuthMethodReverse(value: string): string {
  if (value === "CLIENT_SECRET_BASIC") return "client_secret_basic";
  if (value === "CLIENT_SECRET_POST") return "client_secret_post";
  return "none";
}

// ----------------------------------------------------------------------------
// [補足改善: レビューの性能項目より] Client行IDの解決キャッシュ。
// AuthorizationCode/RefreshTokenの発行のたびにClientテーブルへ問い合わせる
// N+1傾向を緩和する。Clientはほぼ不変のため、TTL付きの単純なメモリキャッシュで
// 十分(単一レプリカ構成のためキャッシュ無効化の分散問題も発生しない)。
// ----------------------------------------------------------------------------

const CLIENT_ROW_ID_CACHE_TTL_MS = 5 * 60 * 1000;
const clientRowIdCache = new Map<string, { rowId: string; cachedAt: number }>();

function invalidateClientCache(clientId: string): void {
  clientRowIdCache.delete(clientId);
}

async function resolveClientRowId(clientId: string): Promise<string> {
  const cached = clientRowIdCache.get(clientId);
  if (cached && Date.now() - cached.cachedAt < CLIENT_ROW_ID_CACHE_TTL_MS) {
    return cached.rowId;
  }

  const client = await prisma.client.findUniqueOrThrow({ where: { clientId } });
  clientRowIdCache.set(clientId, { rowId: client.id, cachedAt: Date.now() });
  return client.id;
}
