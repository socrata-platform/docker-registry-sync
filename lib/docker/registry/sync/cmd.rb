require 'json'
require 'docker/registry/sync/s3'
require 'docker/registry/sync/sqs'

module Docker
  module Registry
    module Sync
      module CMD
        include Docker::Registry::Sync

        class << self
          def configure(source_bucket, target_buckets, sqs_queue, use_sse, source_uses_sse)
            unless source_bucket.nil?
              source_region, source_bucket = source_bucket.split(':')
            else
              source_region, source_bucket = nil, nil
            end

            unless target_buckets.nil?
              target_buckets = target_buckets.split(',').collect { |bucket| bucket.split(':') }
            else
              target_buckets = nil
            end

            unless sqs_queue.nil?
              sqs_region, sqs_uri = sqs_queue.split(':')
            else
              sqs_region, sqs_uri = nil, nil
            end
            Docker::Registry::Sync.configure do |config|
              config.source_bucket = source_bucket
              config.source_region = source_region
              config.target_buckets = target_buckets
              config.source_sse = source_uses_sse
              config.sse = use_sse
              config.sqs_region = sqs_region
              config.sqs_url = "https://#{sqs_uri}"
            end
            @config = Docker::Registry::Sync.config
          end

          def configure_signal_handlers
            @terminated = false

            Signal.trap('INT') do
              @config.logger.error 'Received INT signal...'
              @terminated = true
            end
            Signal.trap('TERM') do
              @config.logger.error 'Received TERM signal...'
              @terminated = true
            end
          end

          def sync(image, tag)
            success = false
            @config.target_buckets.each do |region, bucket|
              if image_exists?(image, bucket, region)
                success = sync_tag(image, tag, bucket, region)
              else
                success = sync_repo(image, bucket, region)
              end
            end
            success ? 0 : 1
          end

          def queue_sync(image, tag)
            msgs = @config.target_buckets.map do |region, bucket|
              JSON.dump(retries: 0,
                        image: image,
                        tag: tag,
                        source: {
                          bucket: @config.source_bucket,
                          region: @config.source_region
                        },
                        target: {
                          bucket: bucket,
                          region: region
                        })
            end
            send_message_batch(msgs) ? 0 : 1
          end

          def run_sync
            ec = 1
            configure_signal_handlers
            begin
              @config.logger.info 'Polling queue for images to sync...'
              sqs = Aws::SQS::Client.new(region: @config.sqs_region)
              resp = sqs.receive_message(
                queue_url: @config.sqs_url,
                max_number_of_messages: 1,
                visibility_timeout: 900, # Give ourselves 15min to sync the image
                wait_time_seconds: 10, # Wait a maximum of 10s for a new message
              )
              @config.logger.info "SQS returned #{resp.messages.length} new images to sync..."
              if resp.messages.length == 1
                message = resp.messages[0]
                data = JSON.load(message.body)
                @config.logger.info "Image sync data:  #{data}"

                if image_exists?(data['image'], data['target']['bucket'], data['target']['region'])
                  @config.logger.info("Syncing tag: #{data['image']}:#{data['tag']} to #{data['target']['region']}:#{data['target']['bucket']}")
                  if sync_tag(data['image'], data['tag'], data['target']['bucket'], data['target']['region'], data['source']['bucket'], data['source']['region'])
                    @config.logger.info("Finished syncing tag: #{data['image']}:#{data['tag']} to #{data['target']['region']}:#{data['target']['bucket']}")
                    finalize_message(message.receipt_handle)
                  else
                    @config.logger.info("Falied to sync tag, leaving on queue: #{data['image']}:#{data['tag']} to #{data['target']['region']}:#{data['target']['bucket']}")
                  end
                else
                  @config.logger.info("Syncing image: #{data['image']} to #{data['target']['region']}:#{data['target']['bucket']}")
                  if sync_repo(data['image'], data['target']['bucket'], data['target']['region'], data['source']['bucket'], data['source']['region'])
                    @config.logger.info("Finished syncing image: #{data['image']} to #{data['target']['region']}:#{data['target']['bucket']}")
                    finalize_message(message.receipt_handle)
                  else
                    @config.logger.error("Failed to sync image, leaving on queue: #{data['image']} to #{data['target']['region']}:#{data['target']['bucket']}")
                  end
                end
              end
              ec = 0
              sleep @config.empty_queue_sleep_time unless @terminated
            rescue Exception => e
              @config.logger.error "An unknown error occurred while monitoring queue: #{e}"
              @config.logger.error 'Exiting...'
              @terminated = true
              ec = 1
            end until @terminated
            ec
          end
        end
      end
    end
  end
end
