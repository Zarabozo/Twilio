use 5.016;
use warnings;

use Test::More;

my @modules = qw(
  Twilio
  Twilio::Base::BaseClient
  Twilio::Exceptions::ConfigurationException
  Twilio::Exceptions::EnvironmentException
  Twilio::Exceptions::RestException
  Twilio::Exceptions::TwilioException
  Twilio::Http::Client
  Twilio::Http::FakeClient
  Twilio::Http::Response
  Twilio::Http::TinyClient
  Twilio::Json
  Twilio::Rest::Client
);

use_ok($_) or BAIL_OUT("$_ failed to load") for @modules;

like(Twilio->VERSION, qr/\A\d+\.\d{6}\z/, 'version uses the six-decimal format');

diag("Testing Twilio $Twilio::VERSION on Perl $] ($^O)");

done_testing;
