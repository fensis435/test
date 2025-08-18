class Api::V1::BaseController < Api::BaseController
  include ApiAuthorization
  before_action :set_api_version

  private

  def set_api_version
    response.headers['API-Version'] = 'v1'
  end

end
