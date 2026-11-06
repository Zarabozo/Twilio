package Twilio::Rest::Api::V2010::Account;

use 5.016;
use warnings;

our $VERSION = '2.000000';

package Twilio::Rest::Api::V2010::AccountContext;

use parent 'Twilio::InstanceContext';

use Twilio::Serialize;

sub new {
  my ($class, $version, $sid) = @_;
  my $self = $class->SUPER::new($version);
  $self->{solution} = { sid => $sid };
  $self->{uri}      = '/Accounts/' . Twilio::Serialize::path_segment($sid) . '.json';
  return $self;
}

sub messages {
  my ($self, $sid) = @_;
  require Twilio::Rest::Api::V2010::Account::Message;
  my $list =
    Twilio::Rest::Api::V2010::Account::MessageList->new($self->{version}, $self->{solution}{sid});
  return defined $sid ? $list->get_context($sid) : $list;
}

1;

__END__

=encoding UTF-8

=head1 NAME

Twilio::Rest::Api::V2010::Account - A Twilio account

=head1 SYNOPSIS

  my $messages = $client->account->messages;

=head1 DESCRIPTION

This file holds C<Twilio::Rest::Api::V2010::AccountContext>, the entry point to the
resources of an account. For now it only offers messages.

=head1 METHODS

=head2 new

  my $account = Twilio::Rest::Api::V2010::AccountContext->new($version, $sid);

=head2 messages

  my $list    = $account->messages;
  my $context = $account->messages($sid);

Returns the L<Twilio::Rest::Api::V2010::Account::Message> list, or the context of
one message.

=head1 LICENSE

Copyright (c) 2026 Francisco Zarabozo. Released under the MIT License.

=cut
