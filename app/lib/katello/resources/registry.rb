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

            if container_config
              crane_url = container_config[:crane_url]
              pulp_registry_url = container_config[:pulp_registry_url]
              registry_url = crane_url if crane_url
              # pulp 3 acts as its own registry
              if pulp_registry_url && content_pulp3_support?(::Katello::DockerBlob::CONTENT_TYPE)
                registry_url = pulp_registry_url
              end
            end

            logger.send(:error, "No container registry url specified") unless registry_url

            uri = URI.parse(registry_url)
            self.prefix = uri.path
            self.site = "#{uri.scheme}://#{uri.host}:#{uri.port}"
            self.ca_cert_file = container_config[:registry_ca_cert_file]
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
