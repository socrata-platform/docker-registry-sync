require 'json'
require 'thread'
require 'monitor'
require 'docker/registry/sync/s3'
require 'docker/registry/sync/sqs'

module Docker
  module Registry
    module Sync
      module CMD
        include Docker::Registry::Sync

        class << self
          attr_accessor :config, :producer_finished, :work_queue, :status_queue, :threads

          def configure(source_bucket, target_buckets, sqs_queue, use_sse, source_uses_sse, pool, log_level = :debug)
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

            @synced_images = RingBuffer.new 10000

            Docker::Registry::Sync.configure do |config|
              config.source_bucket = source_bucket
              config.source_region = source_region
              config.target_buckets = target_buckets
              config.source_sse = source_uses_sse
              config.sse = use_sse
              config.sqs_region = sqs_region
              config.pool_size = pool
              config.sqs_url = "https://#{sqs_uri}"
              config.log_level = log_level
            end
            @config = Docker::Registry::Sync.config
          end

          def configure_signal_handlers
            @terminated = false

            Signal.trap('INT') do
              @config.logger.error 'Received INT signal...'
              @threads.synchronize do
                @producer_finished = true
                @terminated = true
                @work_queue.clear
              end
            end
            Signal.trap('TERM') do
              @config.logger.error 'Received TERM signal...'
              @threads.synchronize do
                @producer_finished = true
                @terminated = true
                @work_queue.clear
              end
            end
          end

          def configure_workers
            @threads = Array.new(@config.pool_size)
            @work_queue = Queue.new
            @status_queue = Queue.new

            @threads.extend(MonitorMixin)
            @threads_available = @threads.new_cond

            @producer_finished = false
          end

          def start_workers
            @consumer_thread = Thread.new do
              sync_key_consumer
            end
          end

          def finalize_workers
            @threads.synchronize do
              @producer_finished = true
            end
            @consumer_thread.join
            @consumer_thread = nil
            @threads.each { |t| t.join unless t.nil? }
            @config.logger.info "Processing job results..."

            success = true
            loop do
              begin
                # One job filure is a run failure
                success &&= @status_queue.pop(true)
              rescue ThreadError
                @config.logger.info "Finished processing job results..."
                break
              end
            end
            success && !@terminated
          end

          def sync(image, tag)
            configure_signal_handlers
            configure_workers
            start_workers
            success = false
            @config.target_buckets.each do |region, bucket, sse|
              if image_exists?(image, bucket, region)
                success = sync_tag(image, tag, bucket, region, !sse.nil?)
              else
                success = sync_repo(image, bucket, region, !sse.nil?)
              end
            end
            success = finalize_workers && success
            success ? 0 : 1
          end

          def queue_sync(image, tag)
            msgs = @config.target_buckets.map do |region, bucket, sse|
              JSON.dump(retries: 0,
                        image: image,
                        tag: tag,
                        source: {
                          bucket: @config.source_bucket,
                          region: @config.source_region
                        },
                        target: {
                          bucket: bucket,
                          region: region,
                          sse: !sse.nil?
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
                  configure_workers
                  start_workers
                  @config.logger.info("Syncing tag: #{data['image']}:#{data['tag']} to #{data['target']['region']}:#{data['target']['bucket']}")
                  success = sync_tag(data['image'], data['tag'], data['target']['bucket'], data['target']['region'], data['target']['sse'], data['source']['bucket'], data['source']['region'])
                  success = finalize_workers && success

                  if success
                    @config.logger.info("Finished syncing tag: #{data['image']}:#{data['tag']} to #{data['target']['region']}:#{data['target']['bucket']}")
                    finalize_message(message.receipt_handle)
                  else
                    @config.logger.info("Falied to sync tag, leaving on queue: #{data['image']}:#{data['tag']} to #{data['target']['region']}:#{data['target']['bucket']}")
                  end
                else
                  configure_workers
                  start_workers
                  success = sync_repo(data['image'], data['target']['bucket'], data['target']['region'], data['target']['sse'], data['source']['bucket'], data['source']['region'])
                  success = finalize_workers && success
                  @config.logger.info("Syncing image: #{data['image']} to #{data['target']['region']}:#{data['target']['bucket']}")
                  if success
                    @config.logger.info("Finished syncing image: #{data['image']} to #{data['target']['region']}:#{data['target']['bucket']}")
                    finalize_message(message.receipt_handle)
                  else
                    @config.logger.error("Failed to sync image, leaving on queue: #{data['image']} to #{data['target']['region']}:#{data['target']['bucket']}")
                  end
                end
              end
              ec = 0
              sleep @config.empty_queue_sleep_time unless @terminated
            rescue StandardError => e
              @config.logger.error "An unknown error occurred while monitoring queue: #{e}"
              @config.logger.error e.traceback
              @config.logger.error 'Exiting...'
              @terminated = true
              ec = 1
              finalize_workers # make sure there are no hangers-on
            end until @terminated
            ec
          end
        end
      end
    end
  end
end
