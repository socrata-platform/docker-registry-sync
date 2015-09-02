module Docker
  module Registry
    module Sync
      module STDLogLvl
        class << self
          def debug
            1
          end

          def info
            2
          end

          def error
            3
          end

          def off
            4
          end
        end
      end

      module STDLogger
        class << self
          def do_log?(requested_lvl, curr_lvl)
            curr_lvl = Docker::Registry::Sync::STDLogLvl.send(curr_lvl.to_sym)
            requested_lvl = Docker::Registry::Sync::STDLogLvl.send(requested_lvl.to_sym)
            requested_lvl >= curr_lvl
          end

          def debug(msg)
            if do_log?(:debug, Docker::Registry::Sync.config.log_level)
              STDOUT.puts "[DEBUG] #{msg}"
            end
          end

          def info(msg)
            if do_log?(:info, Docker::Registry::Sync.config.log_level)
              STDOUT.puts "[INFO] #{msg}"
            end
          end

          def error(msg)
            if do_log?(:error, Docker::Registry::Sync.config.log_level)
              STDERR.puts "[ERROR] #{msg}"
            end
          end
        end
      end

      class Configuration
        attr_accessor :source_bucket, :source_region, :target_buckets, :sqs_region, :sqs_url, :empty_queue_sleep_time
        attr_accessor :log_level, :logger

        def initialize
          @source_bucket = nil
          @source_region = nil

          @target_buckets = nil

          @sqs_region = nil
          @sqs_url = nil

          @empty_queue_sleep_time = 5

          @log_level = :debug
          @logger = Docker::Registry::Sync::STDLogger
        end
      end
    end
  end
end
