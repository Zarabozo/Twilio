package Twilio::Rest::Api;

use 5.016;
use warnings;

use parent 'Twilio::Domain';

our $VERSION = '2.000000';

sub new {
  my ($class, $client) = @_;
  my $self = $class->SUPER::new($client);
  $self->{base_url} = 'https://api.twilio.com';
  return $self;
}

sub v2010 {
  my ($self) = @_;
  require Twilio::Rest::Api::V2010;
  return Twilio::Rest::Api::V2010->new($self);
}

1;

__END__

=encoding UTF-8

=head1 NAME

Twilio::Rest::Api - The main Twilio REST API host

=head1 SYNOPSIS

  my $messages = $client->api->v2010->account->messages;

=head1 DESCRIPTION

The C<api.twilio.com> domain. See L<Twilio::Domain> for the inherited methods.

=head1 METHODS

=head2 new

  my $api = Twilio::Rest::Api->new($client);

=head2 v2010

Returns L<Twilio::Rest::Api::V2010>.

=head1 LICENSE

Copyright (c) 2026 Francisco Zarabozo. Released under the MIT License.

=cut
