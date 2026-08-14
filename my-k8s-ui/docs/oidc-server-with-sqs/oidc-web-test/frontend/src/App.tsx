import { useEffect, useState } from "react";
import type { User } from "oidc-client-ts";
import { userManager, logout } from "./auth";
import { getRuntimeConfig } from "./runtime-config";

// ----------------------------------------------------------------------------
// このページの唯一の目的:
//   oidc-dev-server(Cognito Hosted UI相当) → React(Vite) → Rails v8 API
// という認証チェーン全体が、実際にトークンレベルで繋がっていることを
// 目視確認できるだけのトップページ。業務的なUIやルーティングは持たない。
// ----------------------------------------------------------------------------

type JsonRecord = Record<string, unknown>;

export default function App() {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);
  const [authError, setAuthError] = useState<string | null>(null);

  const [whoami, setWhoami] = useState<JsonRecord | null>(null);
  const [whoamiError, setWhoamiError] = useState<string | null>(null);
  const [whoamiLoading, setWhoamiLoading] = useState(false);

  useEffect(() => {
    void (async () => {
      try {
        if (window.location.pathname === "/callback") {
          const loggedInUser = await userManager.signinRedirectCallback();
          setUser(loggedInUser);
          window.history.replaceState({}, "", "/");
        } else {
          const existing = await userManager.getUser();
          setUser(existing && !existing.expired ? existing : null);
        }
      } catch (e) {
        setAuthError(e instanceof Error ? e.message : String(e));
      } finally {
        setLoading(false);
      }
    })();
  }, []);

  const handleLogin = () => {
    void userManager.signinRedirect();
  };

  const handleLogout = () => {
    void logout();
  };

  const handleCallRailsApi = async () => {
    if (!user) return;

    setWhoamiLoading(true);
    setWhoamiError(null);
    setWhoami(null);

    try {
      const baseUrl = getRuntimeConfig().RAILS_API_BASE_URL;
      const response = await fetch(`${baseUrl}/api/v1/whoami`, {
        headers: { Authorization: `Bearer ${user.access_token}` },
      });
      const body = (await response.json()) as JsonRecord;

      if (!response.ok) {
        setWhoamiError(`Rails APIが ${response.status} を返却しました: ${JSON.stringify(body)}`);
        return;
      }

      setWhoami(body);
    } catch (e) {
      setWhoamiError(
        e instanceof Error
          ? `${e.message}(Rails APIが起動しているか、CORS設定を確認してください)`
          : String(e)
      );
    } finally {
      setWhoamiLoading(false);
    }
  };

  if (loading) {
    return (
      <main className="page">
        <p>Loading...</p>
      </main>
    );
  }

  return (
    <main className="page">
      <h1>OIDC End-to-End Verification</h1>
      <p className="subtitle">
        oidc-dev-server(Cognito Hosted UI相当)→ React(Vite)→ Rails v8 API
        という認証チェーン全体の疎通確認用トップページです。
      </p>

      {authError && <p className="error">{authError}</p>}

      {!user ? (
        <button onClick={handleLogin}>ログイン</button>
      ) : (
        <>
          <p className="status">
            ✅ ログイン済み(sub: <code>{String(user.profile.sub)}</code>)
          </p>

          <section>
            <h2>1. ID Token claims</h2>
            <p className="hint">oidc-client-tsが署名・iss/aud/nonceを検証済みのクレーム。</p>
            <pre>{JSON.stringify(user.profile, null, 2)}</pre>
          </section>

          <section>
            <h2>2. Rails APIによるAccess Token検証</h2>
            <p className="hint">
              このボタンはAccess TokenをBearerとしてRails v8 APIに送り、Rails側がJWKS経由で
              署名検証した結果を表示します。ここが成功して初めて「バックエンドでのトークン検証」まで
              疎通していると言えます。
            </p>
            <button onClick={() => void handleCallRailsApi()} disabled={whoamiLoading}>
              {whoamiLoading ? "検証中..." : "Rails APIを呼ぶ (/api/v1/whoami)"}
            </button>
            {whoamiError && <p className="error">{whoamiError}</p>}
            {whoami && <pre>{JSON.stringify(whoami, null, 2)}</pre>}
          </section>

          <button onClick={handleLogout} className="secondary">
            ログアウト
          </button>
        </>
      )}
    </main>
  );
}
