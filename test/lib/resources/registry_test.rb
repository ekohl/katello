require 'katello_test_helper'

module Katello
  module Resources
    class RegistryTest < ActiveSupport::TestCase
      before do
        SETTINGS[:katello][:container_image_registry] = {
          crane_url: "https://localhost:5000",
          pulp_registry_url: "http://localhost:24816"
        }
      end

      def test_pulp3_registry_url
        Registry::RegistryResource.expects(:content_pulp3_support?).returns(true)
        pulp_registry_url = SETTINGS[:katello][:container_image_registry][:pulp_registry_url]
        assert_equal Registry::RegistryResource.load_class.site, pulp_registry_url
      end

      def test_crane_registry_url
        Registry::RegistryResource.expects(:content_pulp3_support?).returns(false)
        crane_url = SETTINGS[:katello][:container_image_registry][:crane_url]
        assert_equal Registry::RegistryResource.load_class.site, crane_url
      end
    end
  end
end
