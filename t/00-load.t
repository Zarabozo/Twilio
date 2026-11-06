use 5.016;
use warnings;

use Test::More;

my @modules = qw(
  Twilio
  Twilio::Base::BaseClient
  Twilio::Base::PhoneNumberCapabilities
  Twilio::Deserialize
  Twilio::Domain
  Twilio::Exceptions::ConfigurationException
  Twilio::Exceptions::DeserializeException
  Twilio::Exceptions::EnvironmentException
  Twilio::Exceptions::RestException
  Twilio::Exceptions::TwilioException
  Twilio::Http::Client
  Twilio::Http::FakeClient
  Twilio::Http::Response
  Twilio::Http::TinyClient
  Twilio::InstanceContext
  Twilio::InstanceResource
  Twilio::Json
  Twilio::ListResource
  Twilio::Page
  Twilio::Rest::Api
  Twilio::Rest::Api::V2010
  Twilio::Rest::Api::V2010::Account
  Twilio::Rest::Api::V2010::Account::Message
  Twilio::Rest::Client
  Twilio::Serialize
  Twilio::Stream
  Twilio::Version
);

use_ok($_) or BAIL_OUT("$_ failed to load") for @modules;

like(Twilio->VERSION, qr/\A\d+\.\d{6}\z/, 'version uses the six-decimal format');

diag("Testing Twilio $Twilio::VERSION on Perl $] ($^O)");

done_testing;
