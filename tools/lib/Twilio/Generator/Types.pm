package Twilio::Generator::Types;

use 5.016;
use warnings;

use Carp     qw(croak);
use Exporter qw(import);

use Twilio::Generator::Names qw(snake);

our @EXPORT_OK = qw(field_reader map_prefix option_name request_writer);

our $VERSION = '2.000000';

# An entry with no value is sent or read as it is. A format that is not listed stops generation:
# guessing would either send a value in a form Twilio rejects, or hide a date behind a string.
# The rules are twilio-php's, and xt/generator/formats.t checks that every spec in scope has one.
my %REQUEST_WRITER = (
  q{}                    => 'json_object',         # a schema with no type holds free-form data
  'AccountSid'           => undef,
  'IamRoleAssignmentSid' => undef,
  'OrganizationSid'      => undef,
  'Proc_JobTtid'         => undef,
  'Sid'                  => undef,
  'UserSid'              => undef,
  'boolean'              => 'boolean_to_string',
  'date'                 => 'iso8601_date',
  'date-time'            => 'iso8601_date_time',
  'endpoint'             => undef,
  'http-method'          => undef,
  'int32'                => undef,
  'int64'                => undef,
  'integer'              => undef,
  'iso-country-code'     => undef,
  'number'               => undef,
  'object'               => 'json_object',
  'phone-number'         => undef,
  'string'               => undef,
  'twiml'                => undef,
  'uri'                  => undef,
);

# Formats named after a kind of id, like Sid or IamRoleSid, are plain strings.
my %FIELD_READER = (
  q{}                         => undef,
  'AccountSid'                => undef,
  'IamRoleAssignmentSid'      => undef,
  'IamRoleSid'                => undef,
  'Proc_JobTtid'              => undef,
  'Sid'                       => undef,
  'UserSid'                   => undef,
  'array'                     => undef,
  'boolean'                   => undef,
  'currency'                  => undef,
  'date'                      => 'date_time',
  'date-time'                 => 'date_time',
  'date-time-rfc-2822'        => 'date_time',
  'duration'                  => undef,
  'email'                     => undef,
  'float'                     => undef,
  'http-method'               => undef,
  'inbound-call-price'        => undef,
  'int32'                     => undef,
  'int64'                     => undef,
  'integer'                   => undef,
  'iso-country-code'          => undef,
  'number'                    => undef,
  'object'                    => undef,
  'outbound-call-price'       => undef,
  'phone-number'              => undef,
  'phone-number-capabilities' => 'phone_number_capabilities',
  'string'                    => undef,
  'uri'                       => undef,
  'uri-map'                   => undef,
);

# Twilio names the prefix in the format, as in prefixed-collapsible-map-AddOns.
my $PREFIXED_MAP = qr/\Aprefixed-collapsible-map-(\w+)\z/;

sub option_name {
  my ($wire_name) = @_;

  # The official libraries turn Date< and Date> into dateBefore and dateAfter, and
  # Parameter1.Name into parameter1Name.
  my $name = $wire_name;
  $name =~ s/<\z/_before/;
  $name =~ s/>\z/_after/;
  $name =~ s/[.]/_/g;

  croak "Cannot name an option from '$wire_name'" if $name !~ /\A\w+\z/;

  # They lower the first letter before splitting words, so EId is e_id and not eid.
  return snake(lcfirst $name);
}

# For an array, the writer of each element, as twilio-php maps it over the array.
sub request_writer {
  my ($spec, $where, $schema) = @_;

  my $resolved = $spec->resolve($schema);
  if (($resolved->{type} // q{}) eq 'array') {
    my $items = $spec->resolve($resolved->{items} // {});
    croak "$where: no rule for an array of arrays" if ($items->{type} // q{}) eq 'array';
    croak "$where: no rule for an array of maps" if defined map_prefix($spec, $items);
    return request_writer($spec, $where, $items);
  }
  return 'prefixed_collapsible_map' if defined map_prefix($spec, $resolved);
  return _rule(\%REQUEST_WRITER, $where, $resolved);
}

# The prefix of a map that is sent as one parameter per key, or undef for any other value.
sub map_prefix {
  my ($spec, $schema) = @_;

  my ($prefix) = ($spec->resolve($schema)->{format} // q{}) =~ $PREFIXED_MAP;
  return $prefix;
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
