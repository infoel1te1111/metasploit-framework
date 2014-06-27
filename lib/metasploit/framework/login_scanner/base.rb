require 'metasploit/framework/login_scanner'

module Metasploit
  module Framework
    module LoginScanner

      # This module provides the base behaviour for all of
      # the LoginScanner classes. All of the LoginScanners
      # should include this module to establish base behaviour
      module Base
        extend ActiveSupport::Concern
        include ActiveModel::Validations

        included do
          # @!attribute connection_timeout
          #   @return [Fixnum] The timeout in seconds for a single SSH connection
          attr_accessor :connection_timeout
          # @!attribute cred_details
          #   @return [CredentialCollection] Collection of Credential objects
          attr_accessor :cred_details
          # @!attribute failures
          #   @return [Array<Result>] Array of failing {Result results}
          attr_accessor :failures
          # @!attribute host
          #   @return [String] The IP address or hostname to connect to
          attr_accessor :host
          # @!attribute port
          #   @return [Fixnum] The port to connect to
          attr_accessor :port
          # @!attribute proxies
          #   @return [String] The proxy directive to use for the socket
          attr_accessor :proxies
          # @!attribute stop_on_success
          #   @return [Boolean] Whether the scanner should stop when it has found one working Credential
          attr_accessor :stop_on_success
          # @!attribute successes
          #   @return [Array<Result>] Array of successful {Result results}
          attr_accessor :successes

          validates :connection_timeout,
                    presence: true,
                    numericality: {
                      only_integer:             true,
                      greater_than_or_equal_to: 1
                    }

          validates :cred_details, presence: true

          validates :host, presence: true

          validates :port,
                    presence: true,
                    numericality: {
                      only_integer:             true,
                      greater_than_or_equal_to: 1,
                      less_than_or_equal_to:    65535
                    }

          validates :stop_on_success,
                    inclusion: { in: [true, false] }

          validate :host_address_must_be_valid

          validate :validate_cred_details

          # @param attributes [Hash{Symbol => String,nil}]
          def initialize(attributes={})
            attributes.each do |attribute, value|
              public_send("#{attribute}=", value)
            end
            self.successes = []
            self.failures = []
            set_sane_defaults
          end

          # Attempt a single login against the service with the given
          # {Credential credential}.
          #
          # @param credential [Credential] The credential object to attmpt to
          #   login with
          # @return [Result] A Result object indicating success or failure
          # @abstract Protocol-specific scanners must implement this for their
          #   respective protocols
          def attempt_login(credential)
            raise NotImplementedError
          end

          # Attempt to login with every {Credential credential} in
          # {#cred_details}, by calling {#attempt_login} once for each.
          #
          # All {Result results} are stored in {#successes} and {#failures}.
          #
          # @yieldparam result [Result] The {Result} object for each attempt
          # @yieldreturn [void]
          # @return [void]
          def scan!
            valid!

            # Keep track of connection errors.
            # If we encounter too many, we will stop.
            consecutive_error_count = 0
            total_error_count = 0

            cred_details.each do |raw_credential|
              credential = raw_credential.to_credential
              result = attempt_login(credential)
              result.freeze

              yield result if block_given?

              if result.success?
                successes << result
                consecutive_error_count = 0
                break if stop_on_success
              else
                failures << result
                if result.status == :connection_error
                  consecutive_error_count += 1
                  total_error_count += 1
                  break if consecutive_error_count >= 3
                  break if total_error_count >= 10
                end
              end
            end
            nil
          end

          # Raise an exception if this scanner's attributes are not valid.
          #
          # @raise [Invalid] if the attributes are not valid on this scanner
          # @return [void]
          def valid!
            unless valid?
              raise Metasploit::Framework::LoginScanner::Invalid.new(self)
            end
            nil
          end


          private

          # This method validates that the host address is both
          # of a valid type and is resolveable.
          # @return [void]
          def host_address_must_be_valid
            if host.kind_of? String
              begin
                resolved_host = ::Rex::Socket.getaddress(host, true)
                if host =~ /^\d{1,3}(\.\d{1,3}){1,3}$/
                  unless host =~ Rex::Socket::MATCH_IPV4
                    errors.add(:host, "could not be resolved")
                  end
                end
                self.host = resolved_host
              rescue
                errors.add(:host, "could not be resolved")
              end
            else
              errors.add(:host, "must be a string")
            end
          end

          # This is a placeholder method. Each LoginScanner class
          # will override this with any sane defaults specific to
          # its own behaviour.
          # @abstract
          # @return [void]
          def set_sane_defaults
            self.connection_timeout = 30 if self.connection_timeout.nil?
          end

          # This method validates that the credentials supplied
          # are all valid.
          # @return [void]
          def validate_cred_details
            unless cred_details.respond_to? :each
              errors.add(:cred_details, "must respond to :each")
            end
          end

        end


      end

    end
  end
end