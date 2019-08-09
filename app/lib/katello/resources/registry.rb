require 'katello/util/data'

module Katello
  module Resources
    require 'rest_client'

    module Registry
      class Proxy
        def self.logger
          ::Foreman::Logging.logger('katello/registry_proxy')
        end

        def self.get(path, headers = {:accept => :json})
          logger.debug "Sending GET request to Registry: #{path}"
          client = RegistryResource.load_class.rest_client(Net::HTTP::Get, :get, path)
          client.get(headers)
        end
      end

      class RegistryResource < HttpResource
        extend Concerns::SmartProxyExtensions

        class << self
          def load_class
            container_config = SETTINGS.dig(:katello, :container_image_registry)
            registry_url = nil
            ca_cert_file = nil

            if content_pulp3_support?(::Katello::DockerBlob::CONTENT_TYPE)
              registry_url = self.setting('Pulp3', 'registry_url')
              # Assume the registry uses the same CA as the Smart Proxy
              ca_cert_file = Setting[:ssl_ca_file]
            elsif container_config
              registry_url = container_config[:crane_url]
              ca_cert_file = container_config[:crane_ca_cert_file]
            end

            logger.send(:error, "No container registry url specified") unless registry_url
            logger.send(:warning, "No container ca cert file specified") unless ca_cert_file

            uri = URI.parse(registry_url)
            self.prefix = uri.path
            self.site = "#{uri.scheme}://#{uri.host}:#{uri.port}"
            self.ca_cert_file = ca_cert_file
            self
          end

          def process_response(response)
            debug_level = response.code >= 400 ? :error : :debug
            logger.send(debug_level, "Registry request returned with code #{response.code}")
            super
          end
        end
      end
    end
  end
end
