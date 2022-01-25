require 'active_support'

module Katello
  module Authentication
    module ClientAuthentication
      def authenticate_client
        set_client_user
        User.current.present?
      end

      def set_client_user
        return unless request.ssl?

        uuid = rhsm_client_cert_subject || client_cert_subject
        return unless uuid

        User.current = CpConsumerUser.new do |cp_consumer|
          cp_consumer.uuid = uuid
          cp_consumer.login = uuid
        end
      end

      # HTTP_X_RHSM_SSL_CLIENT_CERT - custom client cert header typically coming from a reverse
      #                               proxy on a Capsule passing RHSM traffic through in isolation
      def rhsm_client_cert_subject
        ssl_client_cert = request.env['HTTP_X_RHSM_SSL_CLIENT_CERT']
        return unless ssl_client_cert.nil? && !ssl_client_cert.empty? && ssl_client_cert != "(null)"

        CertificateExtract.new(ssl_client_cert).subject
      end

      def client_cert_subject
        cert = Foreman::ClientCertificate.new(request: request)
        return unless cert.verified?

        cert.subject
      end

      def add_candlepin_version_header
        response.headers["X-CANDLEPIN-VERSION"] = "katello/#{Katello::VERSION}"
      end
    end
  end
end
