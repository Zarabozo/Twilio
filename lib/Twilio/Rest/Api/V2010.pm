package Twilio::Rest::Api::V2010;

use 5.016;
use warnings;

use parent 'Twilio::Version';

our $VERSION = '2.000000';

sub new {
  my ($class, $domain) = @_;
  my $self = $class->SUPER::new($domain);
  $self->{version} = '2010-04-01';
  return $self;
}

sub account {
  my ($self) = @_;
  require Twilio::Rest::Api::V2010::Account;
  return Twilio::Rest::Api::V2010::AccountContext->new($self,
    $self->get_domain->get_client->get_account_sid);
}

1;

__END__

=encoding UTF-8

=head1 NAME

Twilio::Rest::Api::V2010 - Version 2010-04-01 of the Twilio REST API

=head1 DESCRIPTION

See L<Twilio::Version> for the inherited methods.

=head1 METHODS

=head2 new

  my $version = Twilio::Rest::Api::V2010->new($domain);

=head2 account

Returns the L<Twilio::Rest::Api::V2010::Account> context of the client's account.

=head1 LICENSE

Copyright (c) 2026 Francisco Zarabozo. Released under the MIT License.

=cut
