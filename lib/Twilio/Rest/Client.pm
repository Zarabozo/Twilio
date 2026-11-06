package Twilio::Rest::Client;

use 5.016;
use warnings;

use parent 'Twilio::Base::BaseClient';

our $VERSION = '2.000000';

# twilio-php caches these objects. Here each is built on demand: a child holds its parent, so
# a parent that also held its child would be a reference cycle, which Perl never frees, and
# long-running processes would leak every client they create. Requiring on demand keeps
# startup fast when hundreds of resources exist.
sub api {
  my ($self) = @_;
  require Twilio::Rest::Api;
  return Twilio::Rest::Api->new($self);
}

sub account {
  my ($self) = @_;
  return $self->api->v2010->account;
}

sub messages {
  my ($self, $sid) = @_;
  return $self->account->messages($sid);
}

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

  my $message = $client->messages->create('+15558675309', {
    from => '+15017250604',
    body => 'Hello',
  });

=head1 DESCRIPTION

The entry point to the Twilio API. Credentials, routing and low-level requests
are described in L<Twilio::Base::BaseClient>. For now, the only resource is
L<Twilio::Rest::Api::V2010::Account::Message>.

=head1 METHODS

=head2 messages

  my $list    = $client->messages;
  my $context = $client->messages($sid);

Returns the list of messages of the account, or the context of one message. See
L<Twilio::Rest::Api::V2010::Account::Message>.

=head2 account

Returns the context of the client's account. See
L<Twilio::Rest::Api::V2010::Account>.

=head2 api

Returns L<Twilio::Rest::Api>, the domain of the main API.

=head1 LICENSE

Copyright (c) 2026 Francisco Zarabozo. Released under the MIT License.

=cut
