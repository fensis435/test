class ApplicationJob < ActiveJob::Base
  include Dry::Monads[:result]

  discard_on ActiveJob::DeserializationError

  around_perform do |job, block|
    OpenTelemetry::Trace.with_span(
      "job.#{job.class.name}",
      attributes: { "job.id" => job.job_id, "job.queue" => job.queue_name }
    ) do
      block.call
    end
  rescue OpenTelemetry::Error
    block.call
  end
end
