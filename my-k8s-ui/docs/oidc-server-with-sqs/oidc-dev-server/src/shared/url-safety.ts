import { lookup } from "node:dns/promises";
import { isIP } from "node:net";

// ----------------------------------------------------------------------------
// [修正: レビュー指摘#2] Webhook targetUrl のSSRF対策。
// z.string().url() は形式検証のみでプライベートIP/localhost/クラウド
// メタデータエンドポイントへの登録を防げないため、専用のガードを追加する。
// ----------------------------------------------------------------------------

const BLOCKED_HOSTNAMES = new Set(["localhost", "metadata.google.internal"]);

// クラウドメタデータエンドポイント(AWS/GCP/Azure共通の169.254.169.254含む)
const METADATA_IP = "169.254.169.254";

function isPrivateOrReservedIPv4(ip: string): boolean {
  const parts = ip.split(".").map(Number);
  if (parts.length !== 4 || parts.some((p) => Number.isNaN(p))) return false;
  const [a, b] = parts;

  if (a === 127) return true; // loopback
  if (a === 10) return true; // 10.0.0.0/8
  if (a === 172 && b >= 16 && b <= 31) return true; // 172.16.0.0/12
  if (a === 192 && b === 168) return true; // 192.168.0.0/16
  if (a === 169 && b === 254) return true; // link-local (metadata含む)
  if (a === 0) return true; // 0.0.0.0/8
  return false;
}

function isPrivateOrReservedIPv6(ip: string): boolean {
  const normalized = ip.toLowerCase();
  return (
    normalized === "::1" || // loopback
    normalized.startsWith("fc") || // unique local fc00::/7
    normalized.startsWith("fd") ||
    normalized.startsWith("fe80") // link-local
  );
}

export class UnsafeWebhookUrlError extends Error {}

/**
 * Webhook登録・テスト送信・実配信のいずれの経路でも必ずこの関数を通し、
 * SSRFにつながる宛先を拒否する。DNS解決結果まで検証することで、
 * 一般ドメインを装ってプライベートIPを指すDNS Rebinding攻撃も防ぐ。
 */
export async function assertSafeWebhookUrl(rawUrl: string): Promise<void> {
  let url: URL;
  try {
    url = new URL(rawUrl);
  } catch {
    throw new UnsafeWebhookUrlError("targetUrl is not a valid URL.");
  }

  if (url.protocol !== "https:" && url.protocol !== "http:") {
    throw new UnsafeWebhookUrlError("targetUrl must use http or https.");
  }

  const hostname = url.hostname.toLowerCase();

  if (BLOCKED_HOSTNAMES.has(hostname)) {
    throw new UnsafeWebhookUrlError(`targetUrl hostname '${hostname}' is not allowed.`);
  }

  // hostnameが直接IPリテラルの場合
  const directIpVersion = isIP(hostname);
  if (directIpVersion === 4 && (isPrivateOrReservedIPv4(hostname) || hostname === METADATA_IP)) {
    throw new UnsafeWebhookUrlError("targetUrl resolves to a private/reserved IP address.");
  }
  if (directIpVersion === 6 && isPrivateOrReservedIPv6(hostname)) {
    throw new UnsafeWebhookUrlError("targetUrl resolves to a private/reserved IP address.");
  }

  // ホスト名の場合はDNS解決結果まで検証する(Rebinding対策)
  if (directIpVersion === 0) {
    let resolved: { address: string; family: number }[];
    try {
      resolved = [await lookup(hostname)];
    } catch {
      throw new UnsafeWebhookUrlError(`targetUrl hostname '${hostname}' could not be resolved.`);
    }

    for (const { address, family } of resolved) {
      if (family === 4 && (isPrivateOrReservedIPv4(address) || address === METADATA_IP)) {
        throw new UnsafeWebhookUrlError("targetUrl resolves to a private/reserved IP address.");
      }
      if (family === 6 && isPrivateOrReservedIPv6(address)) {
        throw new UnsafeWebhookUrlError("targetUrl resolves to a private/reserved IP address.");
      }
    }
  }
}
