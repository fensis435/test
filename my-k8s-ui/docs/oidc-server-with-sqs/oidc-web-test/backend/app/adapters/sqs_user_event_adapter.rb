# frozen_string_literal: true

require "aws-sdk-sqs"
require "json"
require "time"
require 'pp'

# ----------------------------------------------------------------------------
# 駆動アダプター(Driving Adapter / Primary Adapter)。
#
# [配置について] app/adapters 直下に置いている(app/adapters/inbound/ の
# ようなサブディレクトリにしていない)。RailsのZeitwerkオートローダーは
# ディレクトリ階層をそのままRubyの名前空間として扱うため、サブディレクトリを
# 切ると `Inbound::SqsUserEventAdapter` のような名前空間付きの参照を
# 全箇所で要求される。現時点でこのディレクトリには「駆動アダプター」しか
# 存在しないため、その複雑さに見合うメリットが無いと判断しフラットにした。
# 将来、駆動される側のアダプター(Outbound Adapter、例えば通知送信等)が
# 増えてきたら、その時点で `app/adapters/inbound/` `app/adapters/outbound/`
# のような名前空間付き構成への移行を検討すること。
#
# SQS(本番はCognitoが実際に投入する実SQSキュー、開発はElasticMQ)から
# メッセージを取得し、CloudTrail/EventBridge形状のJSONを
# UserChangeEvent(共通イベント構造)に変換した上で、
# UserSyncUseCase(Port)を呼び出す。
#
# 「オンプレとAWSのコードを同じにしたい」という要件は、aws-sdk-sqs
# そのものをそのまま使う(エンドポイントの向き先だけをENV変数で変える)
# ことで実現している。本番でCognitoを使う場合、このアダプター自体は
# 変更不要(SQS_ENDPOINTを外し、実AWSの認証情報プロバイダに解決させる
# だけでよい)。
#
# ---------------------------------------------------------------------------
# [設計方針の注意点 その1: 同期/非同期のレスポンス設計]
#
# SQSは完全非同期であり、呼び出し元(Cognito/CloudTrail/EventBridge)は
# このアダプターの処理結果を待っていない。そのため:
#   - 処理が成功した場合のみメッセージを明示的に削除する(delete_message)
#   - 処理中に例外が起きた場合は「意図的に」メッセージを削除しない。
#     Visibility Timeout経過後にSQSが自動的に再配信するため、
#     UserSyncApplicationServiceの冪等性ガードにより安全に再試行される。
#   - 何度再試行しても失敗する場合は、SQS標準キューであれば運用者が
#     手動で調査する必要がある(本格運用時はDLQ設定を推奨。ElasticMQも
#     DLQ相当の設定に対応しているが、このアダプター自体はDLQの有無を
#     意識しない設計にしてある=責務が漏れないようにするため)。
# ----------------------------------------------------------------------------

class SqsUserEventAdapter
  # このアダプターが対応するCognito Admin API相当のeventName。
  # 未対応のeventNameは、このシステムに関係ないCognito API呼び出し
  # (例: ListUsers等の読み取り専用操作がCloudTrail経由で流れてくる場合)
  # として黙って読み捨てる。
  SUPPORTED_EVENT_NAMES = %w[
    AdminCreateUser
    AdminUpdateUserAttributes
    AdminDeleteUser
    AdminEnableUser
    AdminDisableUser
    AdminAddUserToGroup
    AdminRemoveUserFromGroup
  ].freeze

  def initialize(use_case: UserSyncApplicationService.new, sqs_client: nil, queue_url: nil)
    @use_case = use_case
    @sqs_client = sqs_client || build_default_sqs_client
    @queue_url = queue_url || ENV.fetch("SQS_QUEUE_URL")
  end

  # 1バッチ分のポーリング(最大10件、ロングポーリング10秒)を行う。
  # 呼び出し元(lib/sqs_poller.rb)がこれをループさせる。
  #
  # @return [Integer] このバッチで処理したメッセージ件数
  def poll_once
    response = @sqs_client.receive_message(
      queue_url: @queue_url,
      max_number_of_messages: 10,
      wait_time_seconds: 10,
      visibility_timeout: 30
    )

    response.messages.each { |message| process_message(message) }

    response.messages.size
  rescue => e
    Rails.logger.error "#{e.class}:#{e.message}"
    raise e
  end

  private

  def process_message(message)
    detail = extract_detail(message.body)
    event_name = detail["eventName"]

    unless SUPPORTED_EVENT_NAMES.include?(event_name)
      delete_message(message)
      return
    end

    event = to_user_change_event(detail)
    result = @use_case.sync_user_change(event)

    Rails.logger.info(
      "[SqsUserEventAdapter] #{event_name} for #{event.user_id} " \
      "(event_id=#{event.event_id}): #{result}"
    )

    delete_message(message)
  rescue StandardError => e
    Rails.logger.error(
      "[SqsUserEventAdapter] Failed to process message #{message.message_id}: " \
      "#{e.class}: #{e.message}"
    )
    # 意図的にメッセージを削除しない(このメソッド冒頭のコメント参照)。
  end

  # EventBridge経由のメッセージは { "detail": {...} } という封筒に
  # 包まれている。テスト等で detail 相当のJSONを直接送る運用も
  # 許容するため、"detail" キーが無ければbody自体をdetailとして扱う。
  def extract_detail(raw_body)
    parsed = JSON.parse(raw_body)
    parsed["detail"] || parsed
  end

  def to_user_change_event(detail)
    request_params = detail["requestParameters"] || {}
    response_elements = detail["responseElements"] || {}

    user_id = request_params["username"] || response_elements.dig("user", "username")

    UserChangeEvent.new(
      event_id: detail["eventID"],
      event_name: detail["eventName"],
      user_id: user_id,
      event_time: Time.iso8601(detail["eventTime"]),
      attributes: extract_attributes(request_params, response_elements, detail["eventName"])
    )
  end

  def extract_attributes(request_params, response_elements, event_name)
    attrs = {}

    raw_attrs = request_params["userAttributes"] ||
                response_elements.dig("user", "attributes") ||
                []

    raw_attrs.each do |attr|
      name = attr["Name"] || attr["name"]
      value = attr["Value"] || attr["value"]
      case name
      when "email" then attrs["email"] = value
      when "given_name" then attrs["given_name"] = value
      when "family_name" then attrs["family_name"] = value
      end
    end

    case event_name
    when "AdminEnableUser" then attrs["status"] = "ACTIVE"
    when "AdminDisableUser" then attrs["status"] = "DISABLED"
    when "AdminCreateUser" then attrs["status"] ||= "ACTIVE"
    end

    attrs
  end

  def delete_message(message)
    @sqs_client.delete_message(queue_url: @queue_url, receipt_handle: message.receipt_handle)
  end

  def build_default_sqs_client
    options = { region: ENV.fetch("AWS_REGION", "ap-northeast-1") }
    options[:endpoint] = ENV["SQS_ENDPOINT"] if ENV["SQS_ENDPOINT"]

    if ENV["AWS_ACCESS_KEY_ID"] && ENV["AWS_SECRET_ACCESS_KEY"]
      # ElasticMQ用のダミー認証情報。実AWSに向ける場合はこれらのENVを
      # 設定せず、SDKのデフォルト認証情報プロバイダチェーン(IRSA等)に
      # 解決させること。
      options[:credentials] = Aws::Credentials.new(ENV["AWS_ACCESS_KEY_ID"], ENV["AWS_SECRET_ACCESS_KEY"])
    end

    Aws::SQS::Client.new(**options)
  end
end
