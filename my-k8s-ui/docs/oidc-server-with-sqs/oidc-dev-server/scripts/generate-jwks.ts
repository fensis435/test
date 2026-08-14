import { generateKeyPair, exportJWK, calculateJwkThumbprint } from "jose";
import { mkdirSync, writeFileSync, existsSync } from "node:fs";
import { dirname } from "node:path";

// ----------------------------------------------------------------------------
// JWKS(署名鍵セット)の生成スクリプト。
//
// oidc-provider は起動時に OIDC_JWKS_PATH のファイルを読み込む
// (src/oidc-core/provider.ts の loadJwks() 参照)が、このファイル自体を
// 生成する手段がこれまで用意されていなかった(見落とし)。
//
// 使い方:
//   npx tsx scripts/generate-jwks.ts [出力先パス]
//   (省略時は .env の OIDC_JWKS_PATH、それも無ければ ./secrets/jwks.json)
//
// 生成される鍵は RS256 用の RSA鍵ペア。kid は鍵のサムプリント(RFC 7638)から
// 自動算出するため、複数鍵を生成してもkidが衝突しない。
//
// 注意: 既にファイルが存在する場合は上書きしない(誤って本番鍵を消さないため)。
// ローテーションしたい場合は --force を付ける、または出力先を変えて
// 新旧2鍵体制で運用すること(鍵ローテーション手順は別途整備が必要)。
// ----------------------------------------------------------------------------

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  const force = args.includes("--force");
  const positional = args.filter((a) => a !== "--force");

  const outputPath = positional[0] ?? process.env.OIDC_JWKS_PATH ?? "./secrets/jwks.json";

  if (existsSync(outputPath) && !force) {
    console.log(`[generate-jwks] '${outputPath}' already exists. Skipping (use --force to overwrite).`);
    return;
  }

  const { publicKey, privateKey } = await generateKeyPair("RS256", { modulusLength: 2048, extractable: true });

  const privateJwk = await exportJWK(privateKey);
  const kid = await calculateJwkThumbprint(privateJwk, "sha256");

  const jwk = {
    ...privateJwk,
    kid,
    alg: "RS256",
    use: "sig",
  };

  const dir = dirname(outputPath);
  if (dir && dir !== ".") {
    mkdirSync(dir, { recursive: true });
  }

  writeFileSync(outputPath, JSON.stringify({ keys: [jwk] }, null, 2), { mode: 0o600 });

  console.log(`[generate-jwks] Generated RS256 key pair (kid: ${kid}) at '${outputPath}'.`);
  console.log("[generate-jwks] This file contains a PRIVATE key. Do not commit it to version control.");

  // publicKeyは未使用だがexportKeyPairの対称性のため取得している(将来のJWKS公開検証等で利用可能)
  void publicKey;
}

main().catch((err) => {
  console.error("[generate-jwks] Failed:", err);
  process.exitCode = 1;
});
