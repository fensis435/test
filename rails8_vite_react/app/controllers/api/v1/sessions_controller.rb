#class SessionsController < Devise::SessionsController
#  def create
#    super do |user|
#      session[:just_signed_in] = true if user.persisted?
#    end
#  end
#
#  def destroy
#    # セッション終了時にアプリ停止をスケジュール
#    current_user&.stop_app_on_timeout if current_user
#    super
#  end
#end
