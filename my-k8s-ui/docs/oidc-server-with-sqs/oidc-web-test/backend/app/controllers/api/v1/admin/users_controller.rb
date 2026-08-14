module Api
  module V1
    module Admin
      # ----------------------------------------------------------------------------
      # 駆動アダプター(Driving Adapter / Primary Adapter)の最小デモ。
      #
      # [配置について] Ports and Adaptersの図では"REST Controller Adapter"を
      # app/adapters 配下に置きたくなるが、RailsのZeitwerkオートローダーと
      # ルーティングの規約上、Controllerは必ず app/controllers 配下に
      # ネームスペースと一致するパスで置く必要がある。そのため物理的な配置は
      # Railsの規約に従い、「これはPorts and Adaptersにおける駆動アダプターの
      # 役割を担っている」という位置づけをコメントで明示する形にしている
      # (SqsUserEventAdapterのようにRails外の素のRubyクラスであれば
      # app/adapters 配下に自由に置けるが、Controllerはフレームワークの
      # ルーティング機構と密結合なため事情が異なる)。
      #
      # オンプレの既存実装では、WebGUIからのユーザー操作がこのような
      # REST Controllerを経由してユーザーDBに反映されている(既に実装済みとの
      # ことなので、実際のコントローラはこのリポジトリの外にある)。
      #
      # ここで示したいのは「入力元がSQSでもRESTでも、最終的に同じ
      # UserSyncUseCase(Port)・UserSyncApplicationService(コアロジック)を
      # 通る」という設計の骨格そのもの。オンプレ側の既存実装をこの構造に
      # 寄せる場合、既存のユーザーDB書き込みロジックを
      # UserSyncApplicationService 相当に置き換え、コントローラ側は
      # UserChangeEvent を組み立てて渡すだけの薄いアダプターにする、
      # という移行方針になる。
      #
      # ---------------------------------------------------------------------------
      # [設計方針の注意点 その1: 同期/非同期のレスポンス設計]
      #
      # RESTはSQSと異なり、クライアント(WebGUI)がレスポンスを待っている。
      # そのためここでは同期的にUseCaseを呼び、結果に応じて即座に
      # 200/400/500を返す(SQSアダプターのような「エラー時は何もしない」
      # 設計にはしない。クライアントに失敗を明示的に伝える必要があるため)。
      # ----------------------------------------------------------------------------
      class UsersController < ApplicationController
        def create
          event = build_event(default_event_name: "AdminCreateUser")
          result = UserSyncApplicationService.new.sync_user_change(event)
          render json: { result: result, userId: event.user_id }, status: :ok
        rescue ActionController::ParameterMissing, ArgumentError => e
          render json: { error: e.message }, status: :bad_request
        end

        def update
          event = build_event(default_event_name: "AdminUpdateUserAttributes")
          result = UserSyncApplicationService.new.sync_user_change(event)
          render json: { result: result, userId: event.user_id }, status: :ok
        rescue ActionController::ParameterMissing, ArgumentError => e
          render json: { error: e.message }, status: :bad_request
        end

        def destroy
          event = UserChangeEvent.new(
            event_id: SecureRandom.uuid,
            event_name: "AdminDeleteUser",
            user_id: params.require(:user_id),
            event_time: Time.current,
            attributes: {}
          )
          result = UserSyncApplicationService.new.sync_user_change(event)
          render json: { result: result, userId: event.user_id }, status: :ok
        rescue ActionController::ParameterMissing, ArgumentError => e
          render json: { error: e.message }, status: :bad_request
        end

        private

        def build_event(default_event_name:)
          UserChangeEvent.new(
            event_id: SecureRandom.uuid,
            event_name: params.fetch(:event_name, default_event_name),
            user_id: params.require(:user_id),
            event_time: Time.current,
            attributes: params.fetch(:attributes, {}).permit!.to_h
          )
        end
      end
    end
  end
end
