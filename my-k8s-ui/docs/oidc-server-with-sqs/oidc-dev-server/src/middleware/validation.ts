import type { NextFunction, Request, Response } from "express";
import type { ZodSchema } from "zod";
import { ApiError, type FieldError } from "../infra/http/problem-json.js";

// ----------------------------------------------------------------------------
// リクエストボディ/クエリをzodスキーマで検証する共通ミドルウェア。
// 失敗時はApiError(400)としてグローバルエラーハンドラに委譲する。
// ----------------------------------------------------------------------------

export function validateBody(schema: ZodSchema) {
  return (req: Request, _res: Response, next: NextFunction): void => {
    const result = schema.safeParse(req.body);
    if (!result.success) {
      const errors: FieldError[] = result.error.issues.map((issue) => ({
        field: issue.path.join(".") || "(root)",
        code: issue.code.toUpperCase(),
        message: issue.message,
      }));
      next(new ApiError(400, "validation-error", "Request body validation failed.", errors));
      return;
    }
    req.body = result.data;
    next();
  };
}

export function validateQuery(schema: ZodSchema) {
  return (req: Request, _res: Response, next: NextFunction): void => {
    const result = schema.safeParse(req.query);
    if (!result.success) {
      const errors: FieldError[] = result.error.issues.map((issue) => ({
        field: issue.path.join(".") || "(root)",
        code: issue.code.toUpperCase(),
        message: issue.message,
      }));
      next(new ApiError(400, "validation-error", "Query parameter validation failed.", errors));
      return;
    }
    (req as Request & { validatedQuery: unknown }).validatedQuery = result.data;
    next();
  };
}
