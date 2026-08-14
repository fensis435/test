import { Router } from "express";
import type Provider from "oidc-provider";
import argon2 from "argon2";
import { prisma } from "../infra/persistence/prisma-client.js";

// ----------------------------------------------------------------------------
// oidc-provider の features.devInteractions は無効化し、
// 独自のログイン/Consent画面をここで実装する。
// Consentは1st-party Reactクライアントに対してはスキップする方針
// (Client.skipConsent相当のフラグをallowedScopesに含めて判定)。
// ----------------------------------------------------------------------------

interface ConsentPromptDetails {
  missingOIDCScope?: string[];
  missingOIDCClaims?: string[];
  missingResourceScopes?: Record<string, string[]>;
}

export function buildInteractionsRouter(provider: Provider): Router {
  const router = Router();

  router.get("/interaction/:uid", async (req, res, next) => {
    try {
      // [修正] accountId は prompt.details ではなく session.accountId から
      // 取得する必要がある。session を分割代入し忘れていたため、
      // accountId が常に undefined になり、Grant保存後のトークン発行で
      // server_error になっていた。
      //
      // [修正] interactionDetails() はトップレベルでも grantId を返す
      // (node_modules/oidc-provider/lib/actions/interaction.js の
      // 公式devInteractions実装で確認済み)。これは「既に存在する
      // Grantに新しいスコープ/リソースを追記する」場合に使うためのもの。
      // 以前はこれを無視して毎回 `new provider.Grant(...)` していたため、
      // 一度ログイン済みのアカウントが新しいリソース(Rails API等)を
      // 要求した際、古いGrantを空のGrantで実質的に上書きしてしまい、
      // 結果としてAccess Tokenにリソース(=JWT化に必要な情報)が
      // 正しく付与されないケースがあった。
      const { uid, prompt, params, session, grantId: existingGrantId } = await provider.interactionDetails(
        req,
        res
      );

      if (prompt.name === "login") {
        res.type("html").send(renderLoginPage(uid, params.client_id as string, null));
        return;
      }

      if (prompt.name === "consent") {
        const accountId = session?.accountId;

        if (!accountId) {
          next(new Error("interaction session has no accountId during 'consent' prompt"));
          return;
        }

        // 1st-party クライアントは Consent画面をスキップして即許可する。
        // oidc-provider公式の実装例に倣い、既存Grantがあれば読み込んで
        // 追記し、なければ新規作成する。missingOIDCScope等の
        // "不足分のみ" をGrantに追加する(全requested scopeを無条件に
        // 付与するのではなく、再認可時の再利用性を正しく保つため)。
        let grant: InstanceType<typeof provider.Grant>;
        if (existingGrantId) {
          const found = await provider.Grant.find(existingGrantId);
          if (!found) {
            next(new Error(`Grant '${existingGrantId}' referenced by interaction was not found`));
            return;
          }
          grant = found;
        } else {
          grant = new provider.Grant({ accountId, clientId: params.client_id as string });
        }

        const details = prompt.details as ConsentPromptDetails;

        if (details.missingOIDCScope?.length) {
          grant.addOIDCScope(details.missingOIDCScope.join(" "));
        }
        if (details.missingOIDCClaims?.length) {
          grant.addOIDCClaims(details.missingOIDCClaims);
        }
        if (details.missingResourceScopes) {
          for (const [indicator, scopes] of Object.entries(details.missingResourceScopes)) {
            grant.addResourceScope(indicator, scopes.join(" "));
          }
        }

        const grantId = await grant.save();

        const result = { consent: { grantId } };
        await provider.interactionFinished(req, res, result, { mergeWithLastSubmission: true });
        return;
      }

      next(new Error(`Unsupported interaction prompt: ${prompt.name}`));
    } catch (err) {
      next(err);
    }
  });

  router.post("/interaction/:uid/login", async (req, res, next) => {
    try {
      const { uid } = req.params;
      const { email, password } = req.body as { email?: string; password?: string };

      if (!email || !password) {
        res.type("html").status(400).send(renderLoginPage(uid, "", "メールアドレスとパスワードを入力してください。"));
        return;
      }

      const normalizedEmail = email.trim().toLowerCase();
      const user = await prisma.user.findFirst({ where: { normalizedEmail, deletedAt: null } });

      if (!user || user.status !== "ACTIVE") {
        res.type("html").status(401).send(renderLoginPage(uid, "", "認証に失敗しました。"));
        return;
      }

      const passwordValid = await argon2.verify(user.passwordHash, password);
      if (!passwordValid) {
        res.type("html").status(401).send(renderLoginPage(uid, "", "認証に失敗しました。"));
        return;
      }

      const result = {
        login: { accountId: user.id },
      };

      await provider.interactionFinished(req, res, result, { mergeWithLastSubmission: false });
    } catch (err) {
      next(err);
    }
  });

  return router;
}

function renderLoginPage(uid: string, _clientId: string, errorMessage: string | null): string {
  return `<!DOCTYPE html>
<html lang="ja">
<head><meta charset="utf-8"><title>Sign in</title></head>
<body>
  <h1>Sign in</h1>
  ${errorMessage ? `<p style="color:red;">${escapeHtml(errorMessage)}</p>` : ""}
  <form method="post" action="/interaction/${encodeURIComponent(uid)}/login">
    <label>Email <input type="email" name="email" required /></label><br/>
    <label>Password <input type="password" name="password" required /></label><br/>
    <button type="submit">Sign in</button>
  </form>
</body>
</html>`;
}

function escapeHtml(value: string): string {
  return value.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c] as string));
}
