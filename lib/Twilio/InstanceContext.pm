package Twilio::InstanceContext;

use 5.016;
use warnings;

our $VERSION = '2.000000';

sub new {
  my ($class, $version) = @_;
  return bless { version => $version, solution => {}, uri => undef }, $class;
}

1;

__END__

=encoding UTF-8

=head1 NAME

Twilio::InstanceContext - Base class for the operations on one record

=head1 DESCRIPTION

A context points at one record by its identifiers and offers its operations,
without having fetched it, as in C<< $client->messages($sid)->fetch >>. Each
resource has a subclass that sets C<uri> and C<solution> in its constructor.

=head1 METHODS

=head2 new

  my $context = Twilio::InstanceContext->new($version);

=head1 LICENSE

Copyright (c) 2026 Francisco Zarabozo. Released under the MIT License.

=cut
