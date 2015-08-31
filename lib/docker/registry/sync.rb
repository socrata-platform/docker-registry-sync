require 'docker/registry/sync/cmd'
require 'docker/registry/sync/configuration'
require 'docker/registry/sync/version'

module Docker
  module Registry
    module Sync
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
