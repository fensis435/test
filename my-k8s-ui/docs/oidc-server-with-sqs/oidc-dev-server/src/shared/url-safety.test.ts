import { describe, it, expect } from "vitest";
import { assertSafeWebhookUrl, UnsafeWebhookUrlError } from "./url-safety.js";

// ----------------------------------------------------------------------------
// [修正: レビュー指摘#5 / #2]
// SSRF対策ロジックのユニットテスト。直接IPリテラルを指すケースは
// DNS解決を経由しないため、外部ネットワークアクセスなしでテスト可能。
// hostname解決を伴うケース(例: example.com)は環境依存になるため
// ここでは検証対象に含めない(統合テストの対象とする)。
// ----------------------------------------------------------------------------

describe("assertSafeWebhookUrl", () => {
  it("rejects non-http(s) protocols", async () => {
    await expect(assertSafeWebhookUrl("ftp://example.com/hook")).rejects.toThrow(UnsafeWebhookUrlError);
  });

  it("rejects malformed URLs", async () => {
    await expect(assertSafeWebhookUrl("not-a-url")).rejects.toThrow(UnsafeWebhookUrlError);
  });

  it("rejects localhost", async () => {
    await expect(assertSafeWebhookUrl("http://localhost:3000/hook")).rejects.toThrow(UnsafeWebhookUrlError);
  });

  it("rejects loopback IPv4 literal", async () => {
    await expect(assertSafeWebhookUrl("http://127.0.0.1/hook")).rejects.toThrow(UnsafeWebhookUrlError);
  });

  it("rejects RFC1918 private ranges (10.0.0.0/8)", async () => {
    await expect(assertSafeWebhookUrl("http://10.1.2.3/hook")).rejects.toThrow(UnsafeWebhookUrlError);
  });

  it("rejects RFC1918 private ranges (172.16.0.0/12)", async () => {
    await expect(assertSafeWebhookUrl("http://172.20.0.5/hook")).rejects.toThrow(UnsafeWebhookUrlError);
  });

  it("rejects RFC1918 private ranges (192.168.0.0/16)", async () => {
    await expect(assertSafeWebhookUrl("http://192.168.1.1/hook")).rejects.toThrow(UnsafeWebhookUrlError);
  });

  it("rejects the cloud metadata endpoint (169.254.169.254)", async () => {
    await expect(assertSafeWebhookUrl("http://169.254.169.254/latest/meta-data/")).rejects.toThrow(
      UnsafeWebhookUrlError
    );
  });

  it("rejects IPv6 loopback", async () => {
    await expect(assertSafeWebhookUrl("http://[::1]/hook")).rejects.toThrow(UnsafeWebhookUrlError);
  });

  it("allows a public IPv4 literal", async () => {
    await expect(assertSafeWebhookUrl("http://8.8.8.8/hook")).resolves.toBeUndefined();
  });
});
