require 'digest'
require 'aws-sdk'

module Docker
  module Registry
    module Sync
      module CMD
        include Docker::Registry::Sync

        class << self
          def send_message_batch(messages, retries = 5)
            if retries <= 0
              success = false
              messages.each do |msg|
                @config.logger.Error "Failed to Enqueue message: #{msg}"
              end
            else
              entries = messages.map do |msg|
                @config.logger.info "Enqueuing message: #{msg}"
                { id: Digest::MD5.hexdigest(msg), message_body: msg }
              end
              sqs = Aws::SQS::Client.new(region: @config.sqs_region)
              resp = sqs.send_message_batch(queue_url: @config.sqs_url,
                                            entries: entries)
              if resp.failed.length > 0
                rerun = resp.failed.map do |failed|
                  @config.logger.warn "Failed to Enqueue message, re-enqueuing: #{msg}"
                  messages.select { |m| Digest::MD5.hexdigest(m) == failed.id }[0]
                end
                sleep 1 # short sleep before trying again...
                success = send_message_batch(rerun, retries - 1)
              else
                success = true
              end
            end
            success
          end

          def finalize_message(receipt_handle)
            sqs = Aws::SQS::Client.new(region: @config.sqs_region)
            resp = sqs.delete_message(queue_url: @config.sqs_url,
                                      receipt_handle: receipt_handle)
          end
        end
      end
    end
  end
end
