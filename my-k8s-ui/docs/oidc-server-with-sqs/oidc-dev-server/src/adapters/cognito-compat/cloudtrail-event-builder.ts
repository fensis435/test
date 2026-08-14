import { randomUUID } from "node:crypto";
import { env } from "../../config/env.js";

// ----------------------------------------------------------------------------
// oidc-dev-server内部のイベント(users.service.ts / groups.service.ts が
// publishUserLifecycleEvent() に渡している "user.created" 等)を、
// 本番でCognitoが実際に発行する経路
// (Cognito Admin API呼び出し → CloudTrail → EventBridge → SQS)
// で届くメッセージと同じJSON構造に変換する。
//
// この変換ロジックはCognito固有の知識(イベント名・フィールド形状)を
// 扱う唯一の場所であり、"Cognito固有機能への依存はアダプタ層に限定する"
// という最優先要件をこの機能でも踏襲している。
//
// 参考: 実際のCloudTrail管理イベント(cognito-idp.amazonaws.com)を
// EventBridge経由でSQSに転送した場合のメッセージBodyの形状に準拠。
// ----------------------------------------------------------------------------

export interface CognitoStyleCloudTrailEvent {
  version: string;
  id: string;
  "detail-type": string;
  source: string;
  account: string;
  time: string;
  region: string;
  resources: string[];
  detail: {
    eventVersion: string;
    eventTime: string;
    eventSource: string;
    eventName: string;
    awsRegion: string;
    sourceIPAddress: string;
    userAgent: string;
    requestParameters: Record<string, unknown>;
    responseElements: Record<string, unknown> | null;
    requestID: string;
    eventID: string;
    eventType: string;
    managementEvent: boolean;
    recipientAccountId: string;
  };
}

// 内部イベント種別 -> Cognito Admin API のeventName相当。
// 未対応の内部イベント(user.password_set等)は同期対象外として
// buildCognitoStyleEvent()がnullを返す(呼び出し側でスキップする)。
const EVENT_NAME_MAP: Record<string, string> = {
  "user.created": "AdminCreateUser",
  "user.updated": "AdminUpdateUserAttributes",
  "user.deleted": "AdminDeleteUser",
  "user.enabled": "AdminEnableUser",
  "user.disabled": "AdminDisableUser",
  "user.password_set": "AdminSetUserPassword",
  "user.password_reset": "AdminResetUserPassword",
};

interface UserAttribute {
  Name: string;
  Value: string;
}

function buildUserAttributes(payload: Record<string, unknown>): UserAttribute[] {
  const attrs: UserAttribute[] = [];
  if (typeof payload.email === "string") attrs.push({ Name: "email", Value: payload.email });
  if (typeof payload.givenName === "string") attrs.push({ Name: "given_name", Value: payload.givenName });
  if (typeof payload.familyName === "string") attrs.push({ Name: "family_name", Value: payload.familyName });
  return attrs;
}

/**
 * users.service.ts / groups.service.ts から渡される内部イベントを、
 * Cognito CloudTrail管理イベントの形状に変換する。
 *
 * @param internalEventType "user.created" 等(event-publisher.tsが受け取るのと同じ文字列)
 * @param payload イベントに付随する内部データ(userId, email等)
 * @returns Cognito形状のイベント。変換対象外のイベント種別ならnull。
 */
export function buildCognitoStyleEvent(
  internalEventType: string,
  payload: Record<string, unknown>
): CognitoStyleCloudTrailEvent | null {
  let eventName: string | undefined;

  if (internalEventType === "group.membership.changed") {
    // group.membership.changed は action フィールドで追加/削除を判定する
    // (event-publisher.ts経由でこの形で渡ってくる。groups.service.ts参照)。
    eventName = payload.action === "removed" ? "AdminRemoveUserFromGroup" : "AdminAddUserToGroup";
  } else {
    eventName = EVENT_NAME_MAP[internalEventType];
  }

  if (!eventName) {
    return null;
  }

  const now = new Date().toISOString();
  const userId = String(payload.userId ?? "");

  const requestParameters: Record<string, unknown> = {
    userPoolId: env.OIDC_ISSUER,
    username: userId,
  };

  let responseElements: Record<string, unknown> | null = null;

  switch (eventName) {
    case "AdminCreateUser": {
      const userAttributes = buildUserAttributes(payload);
      requestParameters.userAttributes = userAttributes;
      responseElements = {
        user: {
          username: userId,
          attributes: userAttributes,
          userCreateDate: now,
          userStatus: "FORCE_CHANGE_PASSWORD",
          enabled: true,
        },
      };
      break;
    }
    case "AdminUpdateUserAttributes": {
      requestParameters.userAttributes = buildUserAttributes(payload);
      break;
    }
    case "AdminAddUserToGroup":
    case "AdminRemoveUserFromGroup": {
      requestParameters.groupName = payload.groupId;
      break;
    }
    // AdminDeleteUser / AdminEnableUser / AdminDisableUser / AdminSetUserPassword /
    // AdminResetUserPassword はusername以外の追加パラメータを持たない。
    default:
      break;
  }

  return {
    version: "0",
    id: randomUUID(),
    "detail-type": "AWS API Call via CloudTrail",
    source: "aws.cognito-idp",
    account: "000000000000",
    time: now,
    region: "ap-northeast-1",
    resources: [],
    detail: {
      eventVersion: "1.08",
      eventTime: now,
      eventSource: "cognito-idp.amazonaws.com",
      eventName,
      awsRegion: "ap-northeast-1",
      sourceIPAddress: "oidc-dev-server-internal",
      userAgent: "oidc-dev-server/1.0 (cognito-compat-simulator)",
      requestParameters,
      responseElements,
      requestID: randomUUID(),
      eventID: randomUUID(),
      eventType: "AwsApiCall",
      managementEvent: true,
      recipientAccountId: "000000000000",
    },
  };
}
