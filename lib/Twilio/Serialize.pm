package Twilio::Serialize;

use 5.016;
use warnings;

use POSIX        ();
use Scalar::Util qw(blessed);

use Twilio::Json;

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

  return _utc_format($value, '%Y-%m-%dT%H:%M:%SZ');
}

sub iso8601_date {
  my ($value) = @_;
  return _utc_format($value, '%Y-%m-%d');
}

# Time::Piece and DateTime both have epoch, so neither has to be a dependency here.
sub _utc_format {
  my ($value, $format) = @_;
  if (blessed($value) && $value->can('epoch')) {
    return POSIX::strftime($format, gmtime $value->epoch);
  }
  return $value;
}

sub json_object {
  my ($value) = @_;

  # An object could encode to anything, so only plain data is turned into JSON here.
  my $type = ref $value;
  return $type eq 'HASH' || $type eq 'ARRAY' ? Twilio::Json::encode($value) : $value;
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

Inside a hash, C<< Time::Piece->gmtime >> returns a list of date parts instead of
an object, and that breaks the options. Keep the date in a variable first, or
use C<scalar>:

  my $send_at = gmtime(time + 3600);    # with "use Time::Piece"

  $client->messages->create($to, { schedule_type => 'fixed', send_at => $send_at });

=head2 iso8601_date

Returns any object with an C<epoch> method as a UTC date in the form
C<2026-11-06>, for values that have no time. Anything else is returned as it is.

=head2 json_object

Returns a hash or array reference as JSON. Anything else is returned as it is, so
a value can also be given as text that is already JSON.

=head2 path_segment

Returns a value encoded for use as one part of a URL path.

=head1 LICENSE

Copyright (c) 2026 Francisco Zarabozo. Released under the MIT License.

=cut
