use 5.016;
use warnings;

use Test::More;

use Time::Piece ();

use Twilio::Serialize;

subtest 'boolean_to_string' => sub {
  my @cases = (
    ['one',          1,       'true'],
    ['zero',         0,       'false'],
    ['empty string', q{},     'false'],
    ['word true',    'true',  'true'],
    ['word false',   'false', 'false'],
    ['undef',        undef,   undef],
  );

  for my $case (@cases) {
    my ($name, $value, $expected) = @{$case};
    is(Twilio::Serialize::boolean_to_string($value), $expected, $name);
  }
};

subtest 'iso8601_date_time' => sub {
  my $moment = 1_438_287_151;

  is(Twilio::Serialize::iso8601_date_time(scalar Time::Piece->gmtime($moment)),
    '2015-07-30T20:12:31Z', 'object in UTC');
  is(Twilio::Serialize::iso8601_date_time(scalar Time::Piece->localtime($moment)),
    '2015-07-30T20:12:31Z', 'local object still gives UTC');
  is(Twilio::Serialize::iso8601_date_time(Local::Moment->new($moment)),
    '2015-07-30T20:12:31Z', 'any object with epoch, as DateTime has');

  is(Twilio::Serialize::iso8601_date_time('2015-07-30'), '2015-07-30', 'string kept');
  is(Twilio::Serialize::iso8601_date_time(undef),        undef,        'undef kept');

  my $no_epoch = bless {}, 'Local::NoEpoch';
  is(Twilio::Serialize::iso8601_date_time($no_epoch), $no_epoch, 'other objects kept');
};

subtest 'path_segment' => sub {
  my @cases = (
    ['plain sid',         'SM123abc',     'SM123abc'],
    ['unreserved kept',   'a-b_c.d~e',    'a-b_c.d~e'],
    ['slash',             'a/b',          'a%2Fb'],
    ['plus',              '+1555',        '%2B1555'],
    ['space is not plus', 'a b',          'a%20b'],
    ['characters',        "\x{263A}",     '%E2%98%BA'],
    ['already UTF-8',     "\xE2\x98\xBA", '%E2%98%BA'],
  );

  for my $case (@cases) {
    my ($name, $value, $expected) = @{$case};
    is(Twilio::Serialize::path_segment($value), $expected, $name);
  }
};

subtest 'iso8601_date' => sub {
  is(Twilio::Serialize::iso8601_date(undef),        undef,        'undef stays undef');
  is(Twilio::Serialize::iso8601_date('2026-11-06'), '2026-11-06', 'a string stays the same');
  is(Twilio::Serialize::iso8601_date(Local::Moment->new(0)), '1970-01-01', 'an object');
  is(Twilio::Serialize::iso8601_date(Local::Moment->new(86_399)),
    '1970-01-01', 'the last second of a day');
  is(Twilio::Serialize::iso8601_date(Local::Moment->new(86_400)),
    '1970-01-02', 'the first second of the next');
  is(Twilio::Serialize::iso8601_date(scalar Time::Piece->gmtime(0)), '1970-01-01', 'Time::Piece');

  my $unknown = bless {}, 'Local::NoEpoch';
  is(Twilio::Serialize::iso8601_date($unknown), $unknown, 'an object with no epoch stays the same');
};

subtest 'json_object' => sub {
  is(Twilio::Serialize::json_object(undef),              undef,           'undef stays undef');
  is(Twilio::Serialize::json_object('{"a":1}'),          '{"a":1}',       'text stays the same');
  is(Twilio::Serialize::json_object({ a => 1, b => 2 }), '{"a":1,"b":2}', 'a hash');
  is(Twilio::Serialize::json_object([1, 'two']),         '[1,"two"]',     'an array');
  is(Twilio::Serialize::json_object({}),                 '{}', 'an empty hash is still sent');

  my $object = bless {}, 'Local::NoEpoch';
  is(Twilio::Serialize::json_object($object), $object, 'an object stays the same');
};

done_testing;

package Local::Moment;

sub new {
  my ($class, $epoch) = @_;
  return bless { epoch => $epoch }, $class;
}

sub epoch { return $_[0]{epoch} }
