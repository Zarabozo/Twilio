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

done_testing;

package Local::Moment;

sub new {
  my ($class, $epoch) = @_;
  return bless { epoch => $epoch }, $class;
}

sub epoch { return $_[0]{epoch} }
