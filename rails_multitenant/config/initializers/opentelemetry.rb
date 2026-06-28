require "opentelemetry/sdk"
require "opentelemetry/exporter/otlp"
require "opentelemetry/instrumentation/rails"
require "opentelemetry/instrumentation/active_record"
require "opentelemetry/instrumentation/pg"

OpenTelemetry::SDK.configure do |c|
  c.service_name = ENV.fetch("OTEL_SERVICE_NAME", "rails-multitenant")
  c.service_version = ENV.fetch("APP_VERSION", "1.0.0")

  if ENV["OTEL_EXPORTER_OTLP_ENDPOINT"].present?
    c.add_span_exporter(
      OpenTelemetry::Exporter::OTLP::Exporter.new(
        endpoint: ENV["OTEL_EXPORTER_OTLP_ENDPOINT"],
        headers: { "Authorization" => "Bearer #{ENV["OTEL_EXPORTER_OTLP_TOKEN"]}" }.compact
      )
    )
  end

  c.use "OpenTelemetry::Instrumentation::Rails"
  c.use "OpenTelemetry::Instrumentation::ActiveRecord"
  c.use "OpenTelemetry::Instrumentation::PG"
end
