package Twilio::Rest::Client;

use 5.016;
use warnings;

use parent 'Twilio::Base::BaseClient';

our $VERSION = '2.000000';

1;

__END__

=encoding UTF-8

=head1 NAME

Twilio::Rest::Client - Client for the Twilio REST API

=head1 SYNOPSIS

  use Twilio::Rest::Client;

  my $client = Twilio::Rest::Client->new($account_sid, $auth_token);

  # With an API key, which is what Twilio recommends for applications
  my $client = Twilio::Rest::Client->new($api_key_sid, $api_key_secret, {
    account_sid => $account_sid,
  });

  my $response = $client->request('GET',
    "https://api.twilio.com/2010-04-01/Accounts/$account_sid.json");

=head1 DESCRIPTION

The entry point to the Twilio API. Credentials, routing and low-level requests
are described in L<Twilio::Base::BaseClient>. Access to the API resources is
being added: this version only offers L<Twilio::Base::BaseClient/request>.

=head1 LICENSE

Copyright (c) 2026 Francisco Zarabozo. Released under the MIT License.

=cut
