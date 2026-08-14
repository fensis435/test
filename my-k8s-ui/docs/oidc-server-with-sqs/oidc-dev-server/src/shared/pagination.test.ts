import { describe, it, expect } from "vitest";
import { buildPrismaCursorArgs, toCursorPage } from "./pagination.js";

// ----------------------------------------------------------------------------
// [修正: レビュー指摘#5] テストコードが皆無だった問題への対応。
// 純粋関数であるページネーションユーティリティから着手する
// (DB/ネットワーク依存がなく、DIなしでもテスト可能なため)。
// ----------------------------------------------------------------------------

describe("buildPrismaCursorArgs", () => {
  it("returns take only when cursor is not provided", () => {
    const args = buildPrismaCursorArgs({ limit: 20 });
    expect(args).toEqual({ take: 21 });
  });

  it("returns take/cursor/skip when cursor is provided", () => {
    const args = buildPrismaCursorArgs({ limit: 10, cursor: "abc-123" });
    expect(args).toEqual({ take: 11, cursor: { id: "abc-123" }, skip: 1 });
  });
});

describe("toCursorPage", () => {
  const rows = [{ id: "1" }, { id: "2" }, { id: "3" }];

  it("returns all items and null nextCursor when rows.length <= limit", () => {
    const result = toCursorPage(rows, 3);
    expect(result.items).toHaveLength(3);
    expect(result.nextCursor).toBeNull();
  });

  it("truncates to limit and returns nextCursor when rows.length > limit", () => {
    const result = toCursorPage(rows, 2);
    expect(result.items).toHaveLength(2);
    expect(result.items.map((i) => i.id)).toEqual(["1", "2"]);
    expect(result.nextCursor).toBe("2");
  });

  it("handles empty rows", () => {
    const result = toCursorPage([], 20);
    expect(result.items).toEqual([]);
    expect(result.nextCursor).toBeNull();
  });
});
