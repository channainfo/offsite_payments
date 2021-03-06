module OffsitePayments #:nodoc:
  module Integrations #:nodoc:
    module PayflowLink
      mattr_accessor :service_url
      self.service_url = 'https://payflowlink.paypal.com'

      def self.notification(post, options = {})
        Notification.new(post)
      end

      def self.return(query_string, options = {})
        OffsitePayments::Return.new(query_string)
      end

      class Helper < OffsitePayments::Helper
        include ActiveUtils::PostsData

        def initialize(order, account, options = {})
          super
          add_field('login', account)
          add_field('echodata', 'True')
          add_field('user2', self.test?)
          add_field('invoice', order)
          add_field('vendor', account)
          add_field('user', options[:credential4].presence || account)
          add_field('trxtype', options[:transaction_type] || 'S')
        end

        mapping :account, 'login'
        mapping :credential2, 'pwd'
        mapping :credential3, 'partner'
        mapping :order, 'user1'

        mapping :amount, 'amt'


        mapping :billing_address,  :city    => 'city',
                                   :address => 'address',
                                   :state   => 'state',
                                   :zip     => 'zip',
                                   :country => 'country',
                                   :phone   => 'phone',
                                   :name    => 'name'

        mapping :customer, { :first_name => 'first_name', :last_name => 'last_name' }

        def description(value)
          add_field('description', normalize("#{value}").delete("#"))
        end

        def customer(params = {})
          add_field(mappings[:customer][:first_name], params[:first_name])
          add_field(mappings[:customer][:last_name], params[:last_name])
        end

        def billing_address(params = {})
          # Get the country code in the correct format
          # Use what we were given if we can't find anything
          country_code = lookup_country_code(params.delete(:country))
          add_field(mappings[:billing_address][:country], country_code)

          add_field(mappings[:billing_address][:address], [params.delete(:address1), params.delete(:address2)].compact.join(' '))

          province_code = params.delete(:state)
          add_field(mappings[:billing_address][:state], province_code.blank? ? 'N/A' : province_code.upcase)

          # Everything else
          params.each do |k, v|
            field = mappings[:billing_address][k]
            add_field(field, v) unless field.nil?
          end
        end

        def form_fields
          token, token_id = request_secure_token

          {"securetoken" => token, "securetokenid" => token_id, "mode" => test? ? "test" : "live"}
        end

        private

        def secure_token_id
          @secure_token_id ||= SecureRandom.hex(16)
        end

        def secure_token_url
          test? ? "https://pilot-payflowpro.paypal.com" : "https://payflowpro.paypal.com"
        end

        def request_secure_token
          @fields["securetokenid"] = secure_token_id
          @fields["createsecuretoken"] = "Y"

          fields = @fields.collect {|key, value| "#{key}[#{value.length}]=#{value}" }.join("&")

          response = ssl_post(secure_token_url, fields)

          parse_response(response)
        end

        def parse_response(response)
          response = response.split("&").inject({}) do |hash, param|
            key, value = param.split("=")
            hash[key] = value
            hash
          end

          [response['SECURETOKEN'], response['SECURETOKENID']] if response['RESPMSG'] && response['RESPMSG'].downcase == "approved"
        end

        def normalize(text)
          return unless text

          if ActiveSupport::Inflector.method(:transliterate).arity == -2
            ActiveSupport::Inflector.transliterate(text,'')
          elsif RUBY_VERSION >= '1.9'
            text.gsub(/[^\x00-\x7F]+/, '')
          else
            ActiveSupport::Inflector.transliterate(text).to_s
          end
        end
      end

      class Notification < OffsitePayments::Notification

        # Was the transaction complete?
        def complete?
          status == "Completed"
        end

        # When was this payment received by the client.
        # sometimes it can happen that we get the notification much later.
        # One possible scenario is that our web application was down. In this case paypal tries several
        # times an hour to inform us about the notification
        def received_at
          DateTime.parse(params['TRANSTIME']) if params['TRANSTIME']
        rescue ArgumentError
          nil
        end

        # Id of this transaction (paypal number)
        def transaction_id
          params['PNREF']
        end

        # What type of transaction are we dealing with?
        def type
          params['TYPE']
        end

        # the money amount we received in X.2 decimal.
        def gross
          params['AMT']
        end

        # What currency have we been dealing with
        def currency
          nil
        end

        def status
          params['RESULT'] == '0' ? 'Completed' : 'Failed'
        end

        # This is the item number which we submitted to paypal
        def item_id
          params['USER1']
        end

        # This is the invoice which you passed to paypal
        def invoice
          params['INVNUM']
        end

        # Was this a test transaction?
        def test?
          params['USER2'] == 'true'
        end

        def account
          params["ACCT"]
        end

        def acknowledge(authcode = nil)
          true
        end
      end
    end
  end
end
