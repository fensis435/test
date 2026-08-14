import type { Response } from "express";

// ----------------------------------------------------------------------------
// RFC 7807 (application/problem+json) 準拠のエラーレスポンス構築。
// Management API設計で定義した共通エラーフォーマットの実装。
// ----------------------------------------------------------------------------

export interface FieldError {
  field: string;
  code: string;
  message: string;
}

export interface ProblemDetails {
  type: string;
  title: string;
  status: number;
  detail: string;
  instance: string;
  errors?: FieldError[];
}

const BASE_TYPE_URI = "https://idp.internal/errors";

export class ApiError extends Error {
  public readonly status: number;
  public readonly code: string;
  public readonly errors?: FieldError[];

  constructor(status: number, code: string, message: string, errors?: FieldError[]) {
    super(message);
    this.status = status;
    this.code = code;
    this.errors = errors;
  }
}

export function sendProblem(
  res: Response,
  instance: string,
  status: number,
  code: string,
  title: string,
  detail: string,
  errors?: FieldError[]
): void {
  const body: ProblemDetails = {
    type: `${BASE_TYPE_URI}/${code}`,
    title,
    status,
    detail,
    instance,
    ...(errors ? { errors } : {}),
  };
  res.status(status).contentType("application/problem+json").send(JSON.stringify(body));
}
