import express, { type Express } from "express";
import cookieParser from "cookie-parser";
import helmet from "helmet";
import rateLimit from "express-rate-limit";
import type Provider from "oidc-provider";
import { createOidcProvider } from "../../oidc-core/provider.js";
import { buildInteractionsRouter } from "../../oidc-core/interactions.js";
import { adminAuthRouter } from "../../auth/admin-auth.routes.js";
import { usersRouter } from "../../identity/users.routes.js";
import { passwordRouter } from "../../identity/password.routes.js";
import { groupsRouter } from "../../identity/groups.routes.js";
import { clientsRouter } from "../../identity/clients.routes.js";
import { webhooksRouter } from "../../webhooks/webhooks.routes.js";
import { errorHandler, notFoundHandler } from "./error-handler.js";

// ----------------------------------------------------------------------------
// アプリケーション構成の境界を明示する。
//
//   1. OIDC Core (oidc-provider本体)
//        - /.well-known/openid-configuration, /authorize, /token,
//          /userinfo, /jwks.json, /logout, /revoke, /introspect
//        - Reactが直接利用してよい唯一の領域(標準準拠)
//        - /interaction/* (独自ログイン画面)
//
//   2. Management API (/api/v1/*)
//        - User CRUD, Password, Enable/Disable, Groups, Clients,
//          管理者Login/Logout, Webhook
//        - Cognito本番に対応物が存在しないか形態が変わる領域
//        - Reactからの直接利用は禁止。Rails経由でのみ利用される想定
//
// [修正: レビュー指摘#10] セキュリティヘッダ(helmet)とレート制限
// (express-rate-limit)を追加。特に管理者ログインは総当たり攻撃対象に
// なりやすいため、他エンドポイントより厳しい制限を個別に設定する。
// ----------------------------------------------------------------------------

export function createApp(): { app: Express; provider: Provider } {
  const app = express();
  const provider = createOidcProvider();

  app.disable("x-powered-by");
  app.set("trust proxy", 1); // Ingress配下での実クライアントIP解決(レート制限に必要)

  app.use(
    helmet({
      // oidc-providerが自前でCSP等を制御する画面(discovery/authorize等)と
      // 干渉しないよう、独自インタラクション画面側で個別にCSPを検討する前提とし、
      // ここではベースラインの防御(HSTS, X-Content-Type-Options等)に留める。
      contentSecurityPolicy: false,
    })
  );

  app.use(cookieParser());
  // [修正] express.json() の type オプションに
  // "application/x-www-form-urlencoded" を誤って含めていたため、
  // フォーム送信(/interaction/:uid/login のHTMLフォームや、OAuth2標準の
  // /token エンドポイントへのリクエスト)までJSONとしてパースしようとして
  // クラッシュしていた。JSONパーサーは application/json のみを、
  // フォームパーサーは application/x-www-form-urlencoded のみを
  // それぞれ担当するよう分離する(本来あるべき状態)。
  app.use(express.json({ type: "application/json" }));
  app.use(express.urlencoded({ extended: true, type: "application/x-www-form-urlencoded" }));

  // 全体の緩やかなレート制限(DoS的な連打を抑止する目的)
  app.use(
    rateLimit({
      windowMs: 60 * 1000,
      limit: 300,
      standardHeaders: true,
      legacyHeaders: false,
    })
  );

  // 管理者ログインは総当たり攻撃の主要対象のため個別に厳しく制限する
  const adminLoginLimiter = rateLimit({
    windowMs: 15 * 60 * 1000,
    limit: 10,
    standardHeaders: true,
    legacyHeaders: false,
    message: { title: "Too Many Requests", detail: "Too many login attempts. Please try again later." },
  });
  app.use("/api/v1/auth/login", adminLoginLimiter);

  // --- 2. Management API ---------------------------------------------------
  app.use("/api/v1", adminAuthRouter);
  app.use("/api/v1", usersRouter);
  app.use("/api/v1", passwordRouter);
  app.use("/api/v1", groupsRouter);
  app.use("/api/v1", clientsRouter);
  app.use("/api/v1", webhooksRouter);

  // --- 1. OIDC Core: 独自ログイン/Consentインタラクション画面 ---------------
  app.use(buildInteractionsRouter(provider));

  // --- 1. OIDC Core: oidc-provider本体(discovery/authorize/token/jwks等) ---
  app.use(provider.callback());

  app.use(notFoundHandler);
  app.use(errorHandler);

  return { app, provider };
}
