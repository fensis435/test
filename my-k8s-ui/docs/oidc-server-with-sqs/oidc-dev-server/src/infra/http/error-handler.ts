import type { NextFunction, Request, Response } from "express";
import { ApiError, sendProblem } from "./problem-json.js";

// ----------------------------------------------------------------------------
// Management API全体で使う共通エラーハンドラ。
// ApiError以外の予期しない例外は500として画一的に扱い、詳細をログにのみ出力する。
// ----------------------------------------------------------------------------

export function notFoundHandler(req: Request, res: Response): void {
  sendProblem(
    res,
    req.originalUrl,
    404,
    "not-found",
    "Not Found",
    `The requested resource ${req.originalUrl} was not found.`
  );
}

// body-parser(express.json/express.urlencoded)が投げるパースエラーの型ガード。
// これらは `expose: true` かつ `statusCode`/`status` を持つが、ApiErrorのインスタンス
// ではないため、そのままだと下のcatch-allに落ちて500として扱われてしまう。
// クライアント起因の不正なリクエストボディは400として返すべきなので、ここで判別する。
function isBodyParserError(err: unknown): err is { status: number; type?: string; message: string } {
  return (
    typeof err === "object" &&
    err !== null &&
    "status" in err &&
    typeof (err as { status: unknown }).status === "number" &&
    "type" in err
  );
}

// eslint-disable-next-line @typescript-eslint/no-unused-vars
export function errorHandler(err: unknown, req: Request, res: Response, _next: NextFunction): void {
  if (err instanceof ApiError) {
    sendProblem(res, req.originalUrl, err.status, err.code, titleFor(err.status), err.message, err.errors);
    return;
  }

  if (isBodyParserError(err) && err.status >= 400 && err.status < 500) {
    sendProblem(
      res,
      req.originalUrl,
      err.status,
      "malformed-request-body",
      titleFor(err.status),
      `Request body could not be parsed (${err.type ?? "unknown"}): ${err.message}`
    );
    return;
  }

  // eslint-disable-next-line no-console
  console.error("Unhandled error:", err);
  sendProblem(
    res,
    req.originalUrl,
    500,
    "internal-server-error",
    "Internal Server Error",
    "An unexpected error occurred."
  );
}

function titleFor(status: number): string {
  switch (status) {
    case 400:
      return "Bad Request";
    case 401:
      return "Unauthorized";
    case 403:
      return "Forbidden";
    case 404:
      return "Not Found";
    case 409:
      return "Conflict";
    case 422:
      return "Unprocessable Entity";
    case 429:
      return "Too Many Requests";
    default:
      return "Error";
  }
}
