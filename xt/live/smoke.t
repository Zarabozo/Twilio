use 5.016;
use warnings;

use Scalar::Util qw(blessed);
use Test::More;

# Free, read-only calls to the real API, to see that Twilio accepts what t/contract.t shows the
# classes send. Nothing here sends a message, buys a number or changes the account.
my %live = map { $_ => $ENV{"TWILIO_LIVE_$_"} } qw(TESTS ACCOUNT_SID API_KEY API_SECRET);
plan skip_all => 'Set TWILIO_LIVE_TESTS=1 to call the real API' if !$live{TESTS};
plan skip_all => 'Set TWILIO_LIVE_ACCOUNT_SID, TWILIO_LIVE_API_KEY and TWILIO_LIVE_API_SECRET'
  if grep { !length($live{$_} // q{}) } qw(ACCOUNT_SID API_KEY API_SECRET);

require Twilio::Rest::Client;

my ($client, $http) = client($live{API_KEY}, $live{API_SECRET});
my ($number);

# A Standard API key can't fetch the account itself, so a record of it stands in.
live(
  'one record, by its sid' => sub {
    my ($listed) = $client->messages->read({}, 1);
    return 'The account has no messages' if !$listed;

    my $message = $client->messages($listed->sid)->fetch;
    is($message->sid,         $listed->sid,       'the same message');
    is($message->account_sid, $live{ACCOUNT_SID}, 'of the account');
    isa_ok($message->date_created, 'Time::Piece', 'its creation date');
    return;
  }
);

live(
  'the balance' => sub {
    my $balance = eval { $client->balance->fetch };
    return 'Twilio keeps the balance of a subaccount in its parent'
      if !$balance && status($@) == 404;
    die $@ if !$balance;    ## no critic (ErrorHandling::RequireCarping)

    like($balance->balance,  qr/\A-?[0-9]+(?:[.][0-9]+)?\z/, 'an amount');
    like($balance->currency, qr/\A[A-Z]{3}\z/,               'in a currency');
    return;
  }
);

live(
  'phone numbers' => sub {
    ($number) = $client->incoming_phone_numbers->read({}, 1);
    return 'The account has no phone numbers' if !$number;

    like($number->phone_number, qr/\A[+][0-9]+\z/, 'in E.164');
    isa_ok($number->capabilities, 'Twilio::Base::PhoneNumberCapabilities', 'its capabilities');
    return;
  }
);

live(
  'a basic Lookup, which is free' => sub {
    return 'The account has no phone numbers' if !$number;

    my $lookup = $client->lookups->v2->phone_numbers($number->phone_number)->fetch;
    ok($lookup->valid, 'the number is valid');
    is($lookup->phone_number, $number->phone_number, 'and the same');
    return;
  }
);

live(
  'prices, on another host' => sub {
    my $country = $client->pricing->v1->messaging->countries('MX')->fetch;
    is($country->iso_country, 'MX', 'Mexico');
    return;
  }
);

live(
  'a list of another product' => sub {
    my @services = $client->verify->v2->services->read({}, 1);
    ok(@services <= 1, 'read');
    return;
  }
);

live(
  'paging' => sub {
    my $before   = () = $http->requests;
    my @messages = $client->messages->read({}, 2, 1);
    my $made     = (() = $http->requests) - $before;

    ok(@messages <= 2, 'no more than the limit');
    is($made, scalar(@messages) || 1, 'one request for each page of one message');
    return;
  }
);

live(
  'OAuth' => sub {
    my ($id, $secret) = map { $ENV{"TWILIO_LIVE_OAUTH_$_"} } qw(CLIENT_ID CLIENT_SECRET);
    return 'Set TWILIO_LIVE_OAUTH_CLIENT_ID and TWILIO_LIVE_OAUTH_CLIENT_SECRET'
      if grep { !length($_ // q{}) } $id, $secret;

    require Twilio::CredentialProvider::ClientCredentialProvider;
    my $provider = Twilio::CredentialProvider::ClientCredentialProvider->new(
      { client_id => $id, client_secret => $secret });
    my ($oauth, $oauth_http) = client(undef, undef, { credential_provider => $provider });

    $oauth->messages->read({}, 1) for 1 .. 2;
    my @urls = map { $_->{url} } $oauth_http->requests;
    is(scalar(grep { m{\Ahttps://oauth[.]twilio[.]com/v2/token} } @urls), 1, 'one token');
    is(scalar(grep { m{/Messages[.]json} } @urls),                        2, 'for two requests');
    return;
  }
);

done_testing;

# Each check is a subtest that returns a reason to skip, or nothing. An error from Twilio fails
# that check alone, so one refused call doesn't hide the others.
sub live {
  my ($name, $code) = @_;
  return subtest $name => sub {
    my $skip;
    my $ok    = eval { $skip = $code->(); 1 };
    my $error = $@;
    if (!$ok) {
      fail('Twilio accepted the requests');
      diag(blessed($error) && $error->can('get_message') ? $error->get_message : $error);
      return;
    }
    plan skip_all => $skip if defined $skip;
    return;
  };
}

sub status {
  my ($error) = @_;
  return blessed($error) && $error->can('get_status_code') ? $error->get_status_code : 0;
}

sub client {
  my ($username, $password, $options) = @_;
  my $transport = Local::RecordingClient->new;
  my $twilio    = Twilio::Rest::Client->new(
    $username,
    $password,
    {
      account_sid => $live{ACCOUNT_SID},
      http_client => $transport,
      environment => {},
      %{ $options // {} },
    }
  );
  return ($twilio, $transport);
}

# Only the method and URL are kept, never headers, so a log of a failure shows no credentials.
package Local::RecordingClient;

use parent -norequire, 'Twilio::Http::TinyClient';

sub send_request {
  my ($self, $request) = @_;
  push @{ $self->{seen} }, { method => $request->{method}, url => $request->{url} };
  return $self->SUPER::send_request($request);
}

sub requests {
  my ($self) = @_;
  return @{ $self->{seen} // [] };
}
