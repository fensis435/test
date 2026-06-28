module Helpers
  module RequestHelpers
    def json_body
      JSON.parse(response.body, symbolize_names: true)
    end

    def post_json(path, params: {}, headers: {})
      post path, params: params.to_json, headers: headers.merge("Content-Type" => "application/json")
    end

    def patch_json(path, params: {}, headers: {})
      patch path, params: params.to_json, headers: headers.merge("Content-Type" => "application/json")
    end

    def put_json(path, params: {}, headers: {})
      put path, params: params.to_json, headers: headers.merge("Content-Type" => "application/json")
    end
  end
end

RSpec.configure do |config|
  config.include Helpers::RequestHelpers, type: :request
end
