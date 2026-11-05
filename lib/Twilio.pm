package Twilio;

use 5.016;
use warnings;

our $VERSION = '2.000000';

1;

__END__

=encoding UTF-8

=head1 NAME

Twilio - Community Perl library for the Twilio API

=head1 VERSION

Version 2.000000

=head1 STATUS

This distribution is being rewritten and has no usable API client yet. The
planned interface follows Twilio's official helper libraries, so that any
Twilio documentation example can be translated to Perl with a few simple rules:

  my $client = Twilio::Rest::Client->new($account_sid, $auth_token);

  my $message = $client->messages->create('+15558675309', {
    from => '+15017250604',
    body => 'Hello',
  });

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
