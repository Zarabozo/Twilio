package Twilio;

use 5.016;
use warnings;

our $VERSION = '2.000000';

# 1.x took named arguments; passed to the 2.x constructor they would become the
# credentials and fail only at the first request, as a 401 from Twilio.
my %IS_V1_ARGUMENT = map { $_ => 1 } qw(sid token trace debug use_threads);

# The client is loaded here, not at compile time, so that "use Twilio" stays cheap.
sub new {
  my ($class, @arguments) = @_;
  if (@arguments && defined $arguments[0] && $IS_V1_ARGUMENT{ $arguments[0] }) {
    require Twilio::Exceptions::ConfigurationException;
    Twilio::Exceptions::ConfigurationException->throw(
          "Twilio->new($arguments[0] => ...) is the 1.x interface; "
        . 'since 2.0 it takes ($username, $password, \%options), like Twilio::Rest::Client->new');
  }
  require Twilio::Rest::Client;
  return Twilio::Rest::Client->new(@arguments);
}

1;

__END__

=encoding UTF-8

=head1 NAME

Twilio - Community Perl library for the Twilio API

=head1 VERSION

Version 2.000000

=head1 SYNOPSIS

  use Twilio;

  my $client = Twilio->new($account_sid, $auth_token);

  my $message = $client->messages->create('+15558675309', {
    from => '+15017250604',
    body => 'Hello',
  });

=head1 STATUS

This distribution is being rewritten, and so far it covers the main REST API, at
C<api.twilio.com>. The interface follows Twilio's official helper libraries, so that any
Twilio documentation example can be translated to Perl with a few simple rules.
The client is L<Twilio::Rest::Client>, and C<< Twilio->new >> is a short way to make one.

TwiML is built with L<Twilio::TwiML::VoiceResponse>,
L<Twilio::TwiML::MessagingResponse> and L<Twilio::TwiML::FaxResponse>.

=head1 METHODS

=head2 new

  my $client = Twilio->new($username, $password, \%options);

The same as C<< Twilio::Rest::Client->new >>, with the same arguments, and it returns a
L<Twilio::Rest::Client>. With no arguments, the credentials come from the
C<TWILIO_ACCOUNT_SID> and C<TWILIO_AUTH_TOKEN> environment variables. See
L<Twilio::Base::BaseClient> for the options.

Version 1.x took named arguments (C<< sid => ..., token => ... >>). Those are refused with a
L<Twilio::Exceptions::ConfigurationException>, so that old code fails at once instead of
at its first request.

=head1 COMMUNITY LIBRARY

This is an independent, community-maintained library. It is not written,
endorsed or supported by Twilio Inc. "Twilio" is a trademark of Twilio Inc.

=head1 BUGS

Please report bugs at L<https://github.com/Zarabozo/Twilio/issues>.

=head1 AUTHOR

Francisco Zarabozo <zarabozo@cpan.org>

=head1 LICENSE

Copyright (c) 2026 Francisco Zarabozo.

This library is free software, released under the MIT License. See the
F<LICENSE> file in this distribution.

=cut
