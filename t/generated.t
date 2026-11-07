use 5.016;
use warnings;

use Scalar::Util qw(weaken);
use Test::More;

use Twilio::Http::FakeClient;
use Twilio::Rest::Client;

my $ACCOUNT = 'https://api.twilio.com/2010-04-01/Accounts/ACxx';

subtest 'a required argument comes before the options' => sub {
  my ($client, $http) = client();
  $http->mock(201, { sid => 'CA1', to => '+1', from => '+2' });

  my $call = $client->calls->create('+1', '+2', { twiml => '<Response/>', timeout => 20 });

  my ($request) = $http->requests;
  is($request->{url}, "$ACCOUNT/Calls.json", 'url');
  like($request->{content}, qr/To=%2B1/,           'first required value');
  like($request->{content}, qr/From=%2B2/,         'second required value');
  like($request->{content}, qr/Timeout=20/,        'option');
  like($request->{content}, qr/Twiml=%3CResponse/, 'TwiML');
  is($call->sid, 'CA1', 'result');
};

subtest 'children of a context' => sub {
  my ($client, $http) = client();

  $http->mock(200, { recordings => [{ sid => 'RE1' }], meta => {} });
  my ($recording) = $client->calls('CA1')->recordings->read({}, 1);
  is(last_url($http), "$ACCOUNT/Calls/CA1/Recordings.json?PageSize=1", 'list');
  is($recording->sid, 'RE1',                                           'record');

  $http->mock(200, { sid => 'RE2' });
  $client->calls('CA1')->recordings('RE2')->fetch;
  is(last_url($http), "$ACCOUNT/Calls/CA1/Recordings/RE2.json", 'context');
};

subtest 'children of an instance' => sub {
  my ($client, $http) = client();
  $http->mock(201, { sid => 'SM1' });
  my $message = $client->messages->create('+1');

  $http->mock(200, { media_list => [{ sid => 'ME1' }], meta => {} });
  my ($media) = $message->media->read({}, 1);
  is(
    last_url($http),
    "$ACCOUNT/Messages/SM1/Media.json?PageSize=1",
    'list from the sid in the payload'
  );

  $http->mock(200, { sid => 'ME2' });
  $message->media('ME2')->fetch;
  is(last_url($http), "$ACCOUNT/Messages/SM1/Media/ME2.json", 'context');

  $http->mock(201, { sid => 'MF1' });
  $message->feedback->create({ outcome => 'confirmed' });
  is(last_url($http), "$ACCOUNT/Messages/SM1/Feedback.json", 'a child with only a list');
};

subtest 'a child that uses the key of its parent' => sub {
  my ($client, $http) = client();
  $http->mock(200, { sid => 'PA1' });

  $client->conferences('CF1')->participants('CA1')->fetch;
  is(last_url($http), "$ACCOUNT/Conferences/CF1/Participants/CA1.json", 'the call sid is the key');
};

subtest 'sections have children and no operations' => sub {
  my ($client, $http) = client();

  ok(!$client->usage->can('read'), 'a section cannot be read');

  $http->mock(200, { usage_records => [{ category => 'sms' }], meta => {} });
  my ($usage) = $client->usage->records->read({ category => 'sms' }, 1);
  like(last_url($http), qr{\Q$ACCOUNT\E/Usage/Records[.]json\?Category=sms}, 'list');
  is($usage->category, 'sms', 'record');

  $http->mock(200, { usage_records => [], meta => {} });
  $client->usage->records->this_month->read({}, 1);
  like(last_url($http), qr{\Q$ACCOUNT\E/Usage/Records/ThisMonth[.]json}, 'a child of a list');

  $http->mock(200, { sid => 'UT1' });
  $client->usage->triggers('UT1')->fetch;
  is(last_url($http), "$ACCOUNT/Usage/Triggers/UT1.json", 'a context below a section');
};

subtest 'a deep path' => sub {
  my ($client, $http) = client();
  $http->mock(200, { contents => [], meta => {} });

  my $list = $client->sip->domains('SD1')->auth->calls->credential_list_mappings;
  isa_ok($list,
    'Twilio::Rest::Api::V2010::Account::Sip::Domain::AuthTypes::AuthTypeCalls::AuthCallsCredentialListMappingList'
  );

  $list->read({}, 1);
  like(last_url($http), qr{/SIP/Domains/SD1/Auth/Calls/CredentialListMappings[.]json}, 'url');
};

subtest 'a child reached through the list of its parent' => sub {
  my ($client, $http) = client();
  $http->mock(200, { incoming_phone_numbers => [], meta => {} });

  $client->incoming_phone_numbers->local->read({}, 1);
  like(last_url($http), qr{/IncomingPhoneNumbers/Local[.]json}, 'url');
};

subtest 'a singleton has no list' => sub {
  my ($client, $http) = client();
  $http->mock(200, { redirect_to => 'https://example.test/data' });

  my $data = $client->recordings('RE1')->add_on_results('XR1')->payloads('XH1')->data->fetch;

  is(last_url($http),    "$ACCOUNT/Recordings/RE1/AddOnResults/XR1/Payloads/XH1/Data.json", 'url');
  is($data->redirect_to, 'https://example.test/data', 'field');

  $http->mock(200, { redirect_to => 'https://example.test/again' });
  is($data->fetch->redirect_to, 'https://example.test/again', 'an instance can fetch itself');

  $http->mock(200, { sid => 'XH2' });
  my $payload = $client->recordings('RE1')->add_on_results('XR1')->payloads('XH2')->fetch;
  $http->mock(200, { redirect_to => 'https://example.test/more' });
  is($payload->data->fetch->redirect_to, 'https://example.test/more', 'through an instance');
};

subtest 'a list that answers with one object' => sub {
  my ($client, $http) = client();
  $http->mock(200, { balance => '12.50', currency => 'USD' });

  my $balance = $client->balance->fetch;

  is(last_url($http),    "$ACCOUNT/Balance.json", 'url');
  is($balance->balance,  '12.50',                 'field');
  is($balance->currency, 'USD',                   'another field');
};

subtest 'options on a fetch' => sub {
  my ($client, $http) = client();

  $http->mock(200, { sid => 'RE1' });
  $client->recordings('RE1')->fetch({ include_soft_deleted => 1 });
  is(last_url($http), "$ACCOUNT/Recordings/RE1.json?IncludeSoftDeleted=true", 'sent');

  $http->mock(200, { sid => 'RE1' });
  $client->recordings('RE1')->fetch;
  is(last_url($http), "$ACCOUNT/Recordings/RE1.json", 'nothing is sent without them');

  $http->mock(200, { sid => 'RE1' });
  my $recording = $client->recordings('RE1')->fetch;
  $http->mock(200, { sid => 'RE1' });
  $recording->fetch({ include_soft_deleted => 0 });
  is(
    last_url($http),
    "$ACCOUNT/Recordings/RE1.json?IncludeSoftDeleted=false",
    'through an instance'
  );
};

subtest 'fields of a record and of a fetch can differ' => sub {
  my ($client, $http) = client();
  $http->mock(200, { sid => 'NO1', request_variables => 'x=1' });

  is($client->notifications('NO1')->fetch->request_variables, 'x=1', 'only a fetch sends it');

  $http->mock(200, { notifications => [{ sid => 'NO2' }], meta => {} });
  my ($notification) = $client->notifications->read({}, 1);
  is($notification->request_variables, undef, 'a record does not');
};

subtest 'resources that share a path' => sub {
  my ($client, $http) = client();

  $http->mock(200, { keys => [{ sid => 'SK1' }], meta => {} });
  my ($key) = $client->keys->read({}, 1);
  isa_ok($key, 'Twilio::Rest::Api::V2010::Account::KeyInstance');

  $http->mock(201, { sid => 'SK2', secret => 'hidden' });
  my $new_key = $client->new_keys->create({ friendly_name => 'mine' });
  isa_ok($new_key, 'Twilio::Rest::Api::V2010::Account::NewKeyInstance');
  is(last_url($http),  "$ACCOUNT/Keys.json", 'the same URL');
  is($new_key->secret, 'hidden',             'with its own fields');

  ok(!$client->keys->can('create'),   'the list of keys does not create');
  ok(!$client->new_keys->can('read'), 'the new keys are not read');

  $http->mock(201, { validation_code => '123456' });
  is($client->validation_requests->create('+1')->validation_code, '123456', 'validation request');
  is(last_url($http), "$ACCOUNT/OutgoingCallerIds.json",                    'its URL');
};

subtest 'value types of real fields' => sub {
  my ($client, $http) = client();
  $http->mock(200, { sid => 'PN1', capabilities => { sms => \1, voice => \0 } });

  my $capabilities = $client->incoming_phone_numbers('PN1')->fetch->capabilities;
  is($capabilities->sms,   1, 'capability');
  is($capabilities->voice, 0, 'false capability');

  $http->mock(200, { available_phone_numbers => [{ capabilities => { SMS => \1 } }], meta => {} });
  my ($number) = $client->available_phone_numbers('US')->local->read({}, 1);
  is($number->capabilities->sms, 1, 'upper case on an available number');
  like(last_url($http), qr{/AvailablePhoneNumbers/US/Local[.]json}, 'url with the country');
};

subtest 'accounts' => sub {
  my ($client, $http) = client();

  $http->mock(200, { sid => 'ACxx', friendly_name => 'Mine' });
  is($client->account->fetch->friendly_name, 'Mine',          'the account of the client');
  is(last_url($http),                        "$ACCOUNT.json", 'its URL');

  $http->mock(200, { sid => 'ACxx', friendly_name => 'Renamed' });
  is($client->account->update({ friendly_name => 'Renamed' })->friendly_name, 'Renamed', 'update');

  $http->mock(200, { accounts => [{ sid => 'AC1' }], meta => {} });
  my ($account) = $client->api->accounts->read({}, 1);
  is($account->sid, 'AC1', 'the list of accounts');
  like(last_url($http), qr{/2010-04-01/Accounts[.]json}, 'its URL');

  $http->mock(200, { sid => 'SM1' });
  $client->api->accounts('AC2')->messages('SM1')->fetch;
  like(last_url($http), qr{/Accounts/AC2/Messages/SM1[.]json}, 'another account');

  $http->mock(200, { sid => 'SM1' });
  $account->messages('SM1')->fetch;
  like(last_url($http), qr{/Accounts/AC1/Messages/SM1[.]json}, 'from an instance');
};

subtest 'a domain with no account' => sub {
  my ($client, $http) = client();

  isa_ok($client->frontline_api,     'Twilio::Rest::FrontlineApi');
  isa_ok($client->frontline_api->v1, 'Twilio::Rest::FrontlineApi::V1');

  my $users = $client->frontline_api->v1->users;
  isa_ok($users, 'Twilio::Rest::FrontlineApi::V1::UserList');
  ok(!$users->can('read'), 'a list no path declares cannot read');

  $http->mock(200, { sid => 'US1' });
  my $user = $users->get_context('US1')->fetch;
  is(last_url($http), 'https://frontline-api.twilio.com/v1/Users/US1', 'its own host');
  is($user->sid,      'US1',                                           'the record');

  $http->mock(200, { sid => 'US1' });
  $client->frontline_api->v1->users('US1')->fetch;
  is(last_url($http), 'https://frontline-api.twilio.com/v1/Users/US1', 'with the id on the method');
};

subtest 'every domain that is ready' => sub {
  my ($client) = client();

  my %class = (
    chat         => 'Chat',
    content      => 'Content',
    events       => 'Events',
    ip_messaging => 'IpMessaging',
    lookups      => 'Lookups',
    monitor      => 'Monitor',
    notify       => 'Notify',
    oauth        => 'Oauth',
    proxy        => 'Proxy',
    routes       => 'Routes',
    serverless   => 'Serverless',
    studio       => 'Studio',
    supersim     => 'Supersim',
    trunking     => 'Trunking',
    wireless     => 'Wireless',
  );
  isa_ok($client->$_, "Twilio::Rest::$class{$_}") for sort keys %class;
};

subtest 'a map sent as one parameter for each key' => sub {
  my ($client, $http) = client();
  $http->mock(200, { phone_number => '+15108675310' });

  # Add-on data is keyed by add-on, then by the add-on's own field.
  $client->lookups->v1->phone_numbers('+15108675310')->fetch(
    {
      add_ons      => ['payfone_tcpa_compliance'],
      add_ons_data => { 'payfone_tcpa_compliance.RightPartyContactedDate' => '20160101' },
    }
  );

  my ($url, $query) = split /[?]/, last_url($http), 2;
  is($url, 'https://lookups.twilio.com/v1/PhoneNumbers/%2B15108675310', 'url');
  like($query, qr/(?:\A|&)AddOns=payfone_tcpa_compliance(?:&|\z)/, 'the add-on');
  my $add_on = qr/AddOns[.]payfone_tcpa_compliance/;
  like(
    $query,
    qr/(?:\A|&)$add_on[.]RightPartyContactedDate=20160101(?:&|\z)/,
    'its data, under the prefix'
  );
  unlike($query, qr/AddOnsData/, 'never under its own name');
};

subtest 'an array of free-form data' => sub {
  my ($client, $http) = client();
  $http->mock(201, { sid => 'DF1' });

  $client->events->v1->subscriptions->create('Mine', 'DG1',
    [{ type => 'com.twilio.messaging.message.delivered' }, '{"type":"other"}']);

  my $content   = ($http->requests)[-1]{content};
  my $delivered = qr/com[.]twilio[.]messaging[.]message[.]delivered/;
  like($content, qr/Types=%7B%22type%22%3A%22$delivered%22%7D/, 'each element as JSON');
  like($content, qr/Types=%7B%22type%22%3A%22other%22%7D/,      'and text as it is');
};

subtest 'an ISO 8601 date' => sub {
  my ($client, $http) = client();
  $http->mock(200, { sid => 'ZS1', date_created => '2018-11-10T20:00:00Z' });

  my $service = $client->serverless->v1->services('ZS1')->fetch;
  isa_ok($service->date_created, 'Time::Piece');
  is($service->date_created->datetime, '2018-11-10T20:00:00', 'read in UTC');
};

subtest 'names that follow twilio-php' => sub {
  my ($client, $http) = client();

  isa_ok(
    $client->chat->v1->services('IS1')->users('US1')->user_channels,
    'Twilio::Rest::Chat::V1::Service::User::UserChannelList',
    'a class named after its mount'
  );
  isa_ok($client->oauth->v1->token, 'Twilio::Rest::Oauth::V1::TokenList', 'a lowercase path');

  $http->mock(200, { sims => [], meta => {} });
  $client->wireless->v1->sims->read({ e_id => 'E1' }, 1);
  like(last_url($http), qr/EId=E1/, 'e_id, as Python and Ruby call it');
};

subtest 'shortcuts' => sub {
  my ($client) = client();

  ok(!$client->can('accounts'), 'accounts is left for the accounts.twilio.com domain');

  for my $object ($client, $client->api, $client->api->v2010, $client->account) {
    isa_ok($object->calls,        'Twilio::Rest::Api::V2010::Account::CallList');
    isa_ok($object->calls('CA1'), 'Twilio::Rest::Api::V2010::Account::CallContext');
  }

  my @names = qw(
    addresses applications authorized_connect_apps available_phone_numbers balance calls
    conferences connect_apps incoming_phone_numbers keys messages new_keys new_signing_keys
    notifications outgoing_caller_ids queues recordings short_codes signing_keys sip tokens
    transcriptions usage validation_requests
  );
  ok($client->can($_), "client has $_") for @names;
};

subtest 'children do not keep the client alive' => sub {
  my ($client, $http) = client();
  $http->mock(201, { sid => 'SM1' });
  my $message = $client->messages->create('+1');
  my $media   = $message->media;

  my $weak = $client;
  weaken($weak);
  undef $client;
  ok($weak, 'alive while a child holds it');

  undef $media;
  undef $message;
  ok(!$weak, 'freed after the last one');
};

done_testing;

sub client {
  my $http = Twilio::Http::FakeClient->new;
  my $client =
    Twilio::Rest::Client->new('ACxx', 'token', { http_client => $http, environment => {} });
  return ($client, $http);
}

sub last_url {
  my ($http) = @_;
  return ($http->requests)[-1]{url};
}
