package Twilio::Generator::Types;

use 5.016;
use warnings;

use Carp     qw(croak);
use Exporter qw(import);

use Twilio::Generator::Names qw(snake);

our @EXPORT_OK = qw(field_reader option_name request_writer);

our $VERSION = '2.000000';

# An entry with no value is sent or read as it is. A format that is not listed stops generation:
# guessing would either send a value in a form Twilio rejects, or hide a date behind a string.
my %REQUEST_WRITER = (
  'boolean'      => 'boolean_to_string',
  'date-time'    => 'iso8601_date_time',
  'integer'      => undef,
  'number'       => undef,
  'phone-number' => undef,
  'string'       => undef,
  'uri'          => undef,
);

my %FIELD_READER = (
  'boolean'            => undef,
  'currency'           => undef,
  'date-time-rfc-2822' => 'date_time',
  'integer'            => undef,
  'number'             => undef,
  'object'             => undef,
  'phone-number'       => undef,
  'string'             => undef,
  'uri'                => undef,
  'uri-map'            => undef,
);

sub option_name {
  my ($wire_name) = @_;

  # The official libraries turn Date< and Date> into dateBefore and dateAfter.
  my $name = $wire_name =~ s/<\z/_before/r;
  $name =~ s/>\z/_after/;
  croak "Cannot name an option from '$wire_name'" if $name !~ /\A\w+\z/;
  return snake($name);
}

sub request_writer {
  my ($spec, $where, $schema) = @_;

  my $resolved = $spec->resolve($schema);
  if (($resolved->{type} // q{}) eq 'array') {
    my $writer = request_writer($spec, $where, $resolved->{items} // {});
    croak "$where: no rule for an array of converted values" if defined $writer;
    return;
  }
  return _rule(\%REQUEST_WRITER, $where, $resolved);
}

sub field_reader {
  my ($spec, $where, $schema) = @_;
  return _rule(\%FIELD_READER, $where, $spec->resolve($schema));
}

sub _rule {
  my ($rules, $where, $schema) = @_;

  my $format = $schema->{format} // $schema->{type} // q{};
  croak "$where: no rule for format '$format'" if !exists $rules->{$format};
  return $rules->{$format};
}

1;
