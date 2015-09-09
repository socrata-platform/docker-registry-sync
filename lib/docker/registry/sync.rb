require 'docker/registry/sync/cmd'
require 'docker/registry/sync/configuration'
require 'docker/registry/sync/version'

module Docker
  module Registry
    module Sync
      class RingBuffer < Array
        attr_reader :max_size

        def initialize(max_size, enum = nil)
          @max_size = max_size
          enum.each { |e| self << e } if enum
        end

        def <<(el)
          if self.size < @max_size || @max_size.nil?
            super
          else
            self.shift
            self.push(el)
          end
        end

        alias :push :<<
      end

      class << self
        attr_accessor :config

        def configure
          self.config ||= Docker::Registry::Sync::Configuration.new
          yield self.config
        end
      end
    end
  end
end
