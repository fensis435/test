import type { NextFunction, Request, RequestHandler, Response } from "express";

// ----------------------------------------------------------------------------
// async/awaitを使うExpressハンドラで発生した例外を
// 確実に next(err) へ委譲するためのラッパー。
// ----------------------------------------------------------------------------

export function asyncHandler(
  fn: (req: Request, res: Response, next: NextFunction) => Promise<void>
): RequestHandler {
  return (req, res, next) => {
    fn(req, res, next).catch(next);
  };
}
