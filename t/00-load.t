use 5.016;
use warnings;

use Test::More;

my @modules = qw(
  Twilio
  Twilio::ApiV1Version
  Twilio::Base::BaseClient
  Twilio::Base::PhoneNumberCapabilities
  Twilio::Deserialize
  Twilio::Domain
  Twilio::Exceptions::ConfigurationException
  Twilio::Exceptions::DeserializeException
  Twilio::Exceptions::EnvironmentException
  Twilio::Exceptions::RestException
  Twilio::Exceptions::RestExceptionV1
  Twilio::Exceptions::TwilioException
  Twilio::Http::Client
  Twilio::Http::FakeClient
  Twilio::Http::Response
  Twilio::Http::TinyClient
  Twilio::InstanceContext
  Twilio::InstanceResource
  Twilio::Json
  Twilio::Jwt::AccessToken
  Twilio::Jwt::Client::ScopeURI
  Twilio::Jwt::ClientToken
  Twilio::Jwt::Grants::ChatGrant
  Twilio::Jwt::Grants::Grant
  Twilio::Jwt::Grants::PlaybackGrant
  Twilio::Jwt::Grants::SyncGrant
  Twilio::Jwt::Grants::TaskRouterGrant
  Twilio::Jwt::Grants::VideoGrant
  Twilio::Jwt::Grants::VoiceGrant
  Twilio::Jwt::JWT
  Twilio::Jwt::TaskRouter::CapabilityToken
  Twilio::Jwt::TaskRouter::Policy
  Twilio::Jwt::TaskRouter::TaskQueueCapability
  Twilio::Jwt::TaskRouter::WorkerCapability
  Twilio::Jwt::TaskRouter::WorkspaceCapability
  Twilio::ListResource
  Twilio::Page
  Twilio::Rest::Api
  Twilio::Rest::Api::V2010
  Twilio::Rest::Api::V2010::Account
  Twilio::Rest::Api::V2010::Account::Message
  Twilio::Rest::Client
  Twilio::Security::RequestValidator
  Twilio::Serialize
  Twilio::Stream
  Twilio::TokenPaginationPage
  Twilio::TwiML::GenericNode
  Twilio::TwiML::TwiML
  Twilio::Version
);

use_ok($_) or BAIL_OUT("$_ failed to load") for @modules;

like(Twilio->VERSION, qr/\A\d+\.\d{6}\z/, 'version uses the six-decimal format');

diag("Testing Twilio $Twilio::VERSION on Perl $] ($^O)");

done_testing;
