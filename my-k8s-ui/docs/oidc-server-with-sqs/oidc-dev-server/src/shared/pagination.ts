// ----------------------------------------------------------------------------
// [修正: レビュー指摘#13]
// users/groups/clients/webhooks の各サービスに重複していたカーソル
// ページネーションロジック(take/cursor/hasMore/nextCursor計算)を
// 共通ユーティリティとして抽出する。
//
// Prismaの findMany に共通する `take` / `cursor` / `skip` オプションを
// 構築する関数と、取得結果から `items` / `nextCursor` を算出する関数の
// 2つに分離している。
// ----------------------------------------------------------------------------

export interface CursorPageQuery {
  limit: number;
  cursor?: string;
}

export interface PrismaCursorArgs {
  take: number;
  cursor?: { id: string };
  skip?: number;
}

export interface CursorPageResult<T> {
  items: T[];
  nextCursor: string | null;
}

/**
 * Prismaの findMany に渡す take/cursor/skip を構築する。
 * limit + 1件多く取得することで「次ページの有無」を判定する。
 */
export function buildPrismaCursorArgs(query: CursorPageQuery): PrismaCursorArgs {
  return {
    take: query.limit + 1,
    ...(query.cursor ? { cursor: { id: query.cursor }, skip: 1 } : {}),
  };
}

/**
 * findMany の結果(limit+1件まで取得済み)から、実際に返却するitemsと
 * nextCursorを算出する。rows.length が limit+1 の場合のみ「次ページあり」。
 */
export function toCursorPage<T extends { id: string }>(rows: T[], limit: number): CursorPageResult<T> {
  const hasMore = rows.length > limit;
  const items = hasMore ? rows.slice(0, limit) : rows;
  const nextCursor = hasMore ? items[items.length - 1].id : null;
  return { items, nextCursor };
}
