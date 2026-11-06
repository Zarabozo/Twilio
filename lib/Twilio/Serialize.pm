package Twilio::Serialize;

use 5.016;
use warnings;

use POSIX        ();
use Scalar::Util qw(blessed);

our $VERSION = '2.000000';

sub boolean_to_string {
  my ($value) = @_;
  return $value if !defined $value;

  # The text "false" is true to Perl, and it is what a caller copying from a Twilio example
  # is likely to write.
  return $value if $value eq 'true' || $value eq 'false';
  return $value ? 'true' : 'false';
}

sub iso8601_date_time {
  my ($value) = @_;

  # Time::Piece and DateTime both have epoch, so neither has to be a dependency here.
  if (blessed($value) && $value->can('epoch')) {
    return POSIX::strftime('%Y-%m-%dT%H:%M:%SZ', gmtime $value->epoch);
  }
  return $value;
}

sub path_segment {
  my ($value) = @_;
  my $encoded = "$value";
  utf8::encode($encoded) if utf8::is_utf8($encoded);
  $encoded =~ s/([^A-Za-z0-9._~-])/sprintf('%%%02X', ord $1)/ge;
  return $encoded;
}

1;

__END__

=encoding UTF-8

=head1 NAME

Twilio::Serialize - Convert Perl values to what the Twilio API expects

=head1 SYNOPSIS

  my $flag = Twilio::Serialize::boolean_to_string(1);    # 'true'

  my $now  = Time::Piece->gmtime;
  my $date = Twilio::Serialize::iso8601_date_time($now);

=head1 DESCRIPTION

Functions that generated resources use to build their requests. None of them are
exported.

=head1 FUNCTIONS

=head2 boolean_to_string

Returns C<true> or C<false> for a Perl boolean. The strings C<true> and C<false>,
and C<undef>, are returned as they are.

=head2 iso8601_date_time

Returns any object with an C<epoch> method, such as L<Time::Piece> or C<DateTime>,
as a UTC date in ISO 8601 format. Anything else is returned as it is, so a date
can also be given as a string.

=head2 path_segment

Returns a value encoded for use as one part of a URL path.

=head1 LICENSE

Copyright (c) 2026 Francisco Zarabozo. Released under the MIT License.

=cut
