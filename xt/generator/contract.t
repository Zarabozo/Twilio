use 5.016;
use warnings;

use JSON::PP ();
use Test::More;
use Time::Local qw(timegm);

use lib 'tools/lib';

use Twilio::Generator::Contract;
use Twilio::Generator::Spec;
use Twilio::Generator::Tree;

my @ROOT = (['demo', 0], ['v1', 0]);

subtest 'a version with nothing in the URL' => sub {
  my $document = document();
  my $paths    = $document->{paths};
  $paths->{s{\A/v1}{}r} = delete $paths->{$_} for keys %{$paths};

  my $spec = Twilio::Generator::Spec->new('demo', 'versionless', $document);
  $spec->{version_path} = q{};
  my ($entry) = grep { $_->{id} eq 'FetchThing' }
    @{ Twilio::Generator::Contract::entries($spec, Twilio::Generator::Tree::build($spec)) };

  is($entry->{url}, 'https://demo.test/Things/id1.json', 'the path follows the host');
};

subtest 'the walk from the client' => sub {
  my %entries = map { $_->{id} => $_ } @{ entries(document()) };

  is_deeply(
    $entries{ListKind}{chain},
    [@ROOT, ['things', 0], ['kinds', 0]],
    'a child of a list leaves out the id, though its parent can take one'
  );
  is_deeply($entries{ListThing}{chain},  [@ROOT, ['things', 0]], 'a list takes no id');
  is_deeply($entries{FetchThing}{chain}, [@ROOT, ['things', 1]], 'an instance takes one');
  is_deeply(
    $entries{FetchPart}{chain},
    [@ROOT, ['things', 1], ['parts', 1]],
    'a child passes through its parent'
  );
  is_deeply(
    $entries{ListRow}{chain},
    [@ROOT, ['things', 1], ['sections', 0], ['rows', 0]],
    'a section takes no id'
  );
  is_deeply(
    $entries{FetchData}{chain},
    [@ROOT, ['things', 1], ['data', 0]],
    'a singleton takes no id'
  );
};

subtest 'URLs come from the path in the spec' => sub {
  my %entries = map { $_->{id} => $_ } @{ entries(document()) };

  is($entries{ListThing}{url},  'https://demo.test/v1/Things.json',     'no ids');
  is($entries{FetchThing}{url}, 'https://demo.test/v1/Things/id1.json', 'one id');
  is(
    $entries{FetchPart}{url},
    'https://demo.test/v1/Things/id1/Parts/id2.json',
    'ids in the order of the path'
  );
};

subtest 'methods' => sub {
  my %entries = map { $_->{id} => $_ } @{ entries(document()) };

  is($entries{ListThing}{method},      'page',   'a list is checked one page at a time');
  is($entries{ListThing}{http},        'GET',    'HTTP method');
  is($entries{CreateThing}{method},    'create', 'create');
  is($entries{CreateThing}{http},      'POST',   'HTTP method');
  is($entries{ListThing}{records_key}, 'things', 'the key of the records');
  ok(!exists $entries{FetchThing}{records_key}, 'only for lists');
};

subtest 'values' => sub {
  my %entries = map { $_->{id} => $_ } @{ entries(document()) };
  my $create  = $entries{CreateThing};

  is_deeply($create->{required}, ['v_name', 411], 'required values in the order of the spec');
  is_deeply(
    $create->{options},
    {
      active => 1,
      amount => 628.5,
      config => { v_config => 11 },
      day    => { epoch    => timegm(5, 4, 3, 7, 0, 2026) },
      free   => { v_free   => 23 },
      items  => [{ v_items => 1 }, { v_items => 2 }],
      mode   => 'slow',
      tags   => ['v_tags_1', 'v_tags_2'],
      when   => { epoch => timegm(5, 4, 3, 11, 0, 2026) },
    },
    'options under their Perl names'
  );

  my %wire;
  push @{ $wire{ $_->[0] } }, $_->[1] for @{ $create->{expected} };
  is_deeply(
    \%wire,
    {
      Active => ['true'],
      Amount => [628.5],
      Config => ['{"v_config":11}'],
      Day    => ['2026-01-07'],
      Free   => ['{"v_free":23}'],
      Items  => ['{"v_items":1}', '{"v_items":2}'],
      Mode   => ['slow'],
      Name   => ['v_name'],
      Size   => ['411'],
      Tags   => ['v_tags_1', 'v_tags_2'],
      When   => ['2026-01-11T03:04:05Z'],
    },
    'what must arrive, under the names in the spec'
  );

  my $read = $entries{ListThing};
  is_deeply(
    $read->{options},
    {
      status         => 'v_status',
      created_before => { epoch => timegm(5, 4, 3, 1, 0, 2026) },
      add_ons_data   => { one   => { two => 'v_add_ons_data' } },
    },
    'filters'
  );
  is_deeply(
    [sort map { $_->[0] } @{ $read->{expected} }],
    ['AddOns.one.two', 'Created<', 'Status'],
    'paging is left out, and wire names stay'
  );
  is_deeply(
    [grep { $_->[0] =~ /\AAddOns/ } @{ $read->{expected} }],
    [['AddOns.one.two', 'v_add_ons_data']],
    'a map is sent as one parameter for each key, under its prefix'
  );
};

subtest 'the order is stable' => sub {
  my @ids = map { $_->{id} } @{ entries(document()) };
  is_deeply(\@ids, [sort @ids], 'sorted by operation');

  my $json    = Twilio::Generator::Contract::to_json(entries(document()));
  my $decoded = JSON::PP->new->utf8->decode($json);
  is(scalar @{$decoded}, scalar @ids,                                  'it can be read back');
  is($json, Twilio::Generator::Contract::to_json(entries(document())), 'the same text each time');
};

subtest 'ids the parent does not hold go to the child' => sub {
  my $document = document();
  $document->{paths}{'/v1/Things/{Sid}/{Extra}/More/{MoreSid}.json'} = {
    'x-twilio' => { pathType    => 'instance',  parent    => '/Things/{Sid}.json' },
    get        => { operationId => 'FetchMore', responses => { 200 => answer() } },
  };
  my %entries = map { $_->{id} => $_ } @{ entries($document) };

  is_deeply(
    $entries{FetchMore}{chain},
    [@ROOT, ['things', 1], ['more', 2]],
    'the extra, then its own'
  );
  is(
    $entries{FetchMore}{url},
    'https://demo.test/v1/Things/id1/id2/More/id3.json',
    'in the order of the URL'
  );
};

subtest 'a child can leave out an id of its parent' => sub {
  my $document = document();
  $document->{paths}{'/v1/Things/Totals.json'} = {
    'x-twilio' => { pathType    => 'instance',   parent    => '/Things/{Sid}.json' },
    get        => { operationId => 'FetchTotal', responses => { 200 => answer() } },
  };
  my %entries = map { $_->{id} => $_ } @{ entries($document) };

  is_deeply(
    $entries{FetchTotal}{chain},
    [@ROOT, ['things', 1], ['totals', 0]],
    'reached through a thing, as TaskRouter\'s worker statistics are'
  );
  is($entries{FetchTotal}{url}, 'https://demo.test/v1/Things/Totals.json', 'with no id in the URL');
};

subtest 'what each field of an answer must read' => sub {
  my $document = document();
  $document->{components}{schemas}{thing}{properties} = {
    sid          => { type => 'string' },
    friendlyName => { type => 'string' },
    active       => { type => 'boolean' },
    size         => { type => 'integer' },
    amount       => { type => 'number' },
    tags         => { type => 'array', items => { type => 'string' } },
    config       => { type => 'object' },
    free         => {},
    mode         => { '$ref' => '#/components/schemas/thing_enum_mode' },
    created      => { type   => 'string', format => 'date-time' },
    sent         => { type   => 'string', format => 'date-time-rfc-2822' },
    day          => { type   => 'string', format => 'date' },
    capabilities => { type   => 'object', format => 'phone-number-capabilities' },
  };
  my %entries = map { $_->{id} => $_ } @{ entries($document) };

  my ($answer) = @{ $entries{FetchThing}{answers} };
  is($answer->{status}, 200, 'the status');
  my %field = map { $_->[1] => $_ } @{ $answer->{fields} };
  my $body  = $answer->{body};

  is_deeply(
    $field{friendlyName},
    ['friendly_name', 'friendlyName', 'plain'],
    'a camelCase field has a snake_case method'
  );
  is($body->{friendlyName}, 'a_friendlyName', 'text is named after its field');
  ok(JSON::PP::is_bool($body->{active}) && $body->{active}, 'a boolean');
  like($body->{size},   qr/\A[0-9]+\z/,     'an integer');
  like($body->{amount}, qr/\A[0-9]+[.]5\z/, 'a number');
  is_deeply($body->{tags},   ['a_tags'], 'an array');
  is_deeply($body->{config}, { a_config => 1 }, 'an object');
  is_deeply($body->{free},   { a_free   => 1 }, 'a value of no type');
  like($body->{mode}, qr/\A(?:fast|slow)\z/, 'one of the choices of an enum');

  my %epoch = map { $_ => $field{$_}[3] } qw(created sent day);
  is($field{$_}[2], 'date', "$_ is read as a date") for sort keys %epoch;
  like($body->{created}, qr/\A2026-01-\d\dT03:04:05Z\z/, 'ISO 8601 date and time');
  is($epoch{created}, iso_epoch($body->{created}), 'with its epoch');
  like($body->{sent}, qr/\A[A-Z][a-z]{2}, \d\d Jan 2026 03:04:05 [+]0000\z/, 'RFC 2822');
  is(
    substr($body->{sent}, 0, 3),
    (qw(Sun Mon Tue Wed Thu Fri Sat))[(gmtime $epoch{sent})[6]],
    'on the right day of the week'
  );
  is($epoch{sent}, rfc_epoch($body->{sent}), 'with its epoch');
  like($body->{day}, qr/\A2026-01-\d\d\z/, 'a date alone');
  is($epoch{day},             iso_epoch($body->{day}), 'at midnight');
  is($field{capabilities}[2], 'capabilities',          'phone number capabilities');
  is_deeply([sort keys %{ $body->{capabilities} }], [qw(MMS SMS fax voice)],
    'as Twilio sends them');
  is($field{size}[2], 'plain', 'the rest is read as it is');
};

subtest 'answers of a list, a delete and several statuses' => sub {
  my $document = document();
  my $item     = $document->{paths}{'/v1/Things/{Sid}.json'};
  $item->{delete} = { operationId => 'DeleteThing', responses => { 204 => {} } };
  $item->{post} =
    { operationId => 'UpdateThing', responses => { 202 => answer(), 200 => other() } };
  $document->{components}{schemas}{other} = { properties => { note => { type => 'string' } } };
  my %entries = map { $_->{id} => $_ } @{ entries($document) };

  my ($page) = @{ $entries{ListThing}{answers} };
  is_deeply($page->{body}, { things => [{ sid => 'a_sid' }], meta => {} },
    'a page with one record');
  is_deeply($page->{fields}, [['sid', 'sid', 'plain']], 'the fields of the record');

  is_deeply($entries{DeleteThing}{answers}, [{ status => 204 }], 'no body');
  is_deeply(
    [map { [$_->{status}, sort keys %{ $_->{body} }] } @{ $entries{UpdateThing}{answers} }],
    [[200, 'note'], [202, 'sid']],
    'each status with its own body'
  );
};

subtest 'an answer that is one of several objects' => sub {
  my $document = document();
  $document->{components}{schemas}{other} = { properties => { note => { type => 'string' } } };
  $document->{paths}{'/v1/Things/{Sid}.json'}{get}{responses}{200} = {
    content => {
      'application/scim+json' => { schema => { oneOf => [thing_reference(), other_reference()] } }
    }
  };
  my %entries = map { $_->{id} => $_ } @{ entries($document) };

  my ($answer) = @{ $entries{FetchThing}{answers} };
  is_deeply([sort keys %{ $answer->{body} }],
    [qw(note sid)], 'the fields of all of them, from SCIM');
};

subtest 'a redirect on a list is not a page' => sub {
  my $document = document();
  my $list     = $document->{paths}{'/v1/Things.json'}{get};
  $list->{responses}{301} = other();
  $document->{components}{schemas}{other} = { properties => { note => { type => 'string' } } };

  my %entries = map { $_->{id} => $_ } @{ entries($document) };
  is_deeply([map { $_->{status} } @{ $entries{ListThing}{answers} }], [200], 'left out');
};

subtest 'calls that do not fit the path stop generation' => sub {

  # The list and the instance of one resource disagree on the ids before the instance's own.
  my $document = document();
  $document->{paths}{'/v1/Odds/{A}.json'} = {
    'x-twilio' => { pathType    => 'list',    parent    => '/Things.json' },
    get        => { operationId => 'ListOdd', responses => { 200 => records('odds') } },
  };
  $document->{paths}{'/v1/Odds/{A}/{B}/{Sid}.json'} = {
    'x-twilio' => { pathType    => 'instance', parent    => '/Things.json' },
    get        => { operationId => 'FetchOdd', responses => { 200 => answer() } },
  };

  my $ok    = eval { entries($document); 1 };
  my $error = $@;
  ok(!$ok, 'refused');
  like($error, qr/FetchOdd: 3 parameters in the path and 2 in the calls/, 'says why');
};

done_testing;

sub entries {
  my ($document) = @_;

  my $spec = Twilio::Generator::Spec->new('demo', 'v1', $document);
  return Twilio::Generator::Contract::entries($spec, Twilio::Generator::Tree::build($spec));
}

sub thing_reference {
  return { '$ref' => '#/components/schemas/thing' };
}

sub answer {
  return { content => { 'application/json' => { schema => thing_reference() } } };
}

sub other_reference {
  return { '$ref' => '#/components/schemas/other' };
}

sub other {
  return { content => { 'application/json' => { schema => other_reference() } } };
}

sub iso_epoch {
  my ($text) = @_;
  my ($year, $month, $day, $hours, $minutes, $seconds) =
    $text =~ /\A(\d{4})-(\d\d)-(\d\d)(?:T(\d\d):(\d\d):(\d\d)Z)?\z/;
  return timegm($seconds // 0, $minutes // 0, $hours // 0, $day, $month - 1, $year);
}

sub rfc_epoch {
  my ($text) = @_;
  my ($day, $hours, $minutes, $seconds) = $text =~ /, (\d\d) Jan 2026 (\d\d):(\d\d):(\d\d) /;
  return timegm($seconds, $minutes, $hours, $day, 0, 2026);
}

sub records {
  my ($key) = @_;
  my $properties = { $key => { type => 'array', items => thing_reference() } };
  return { content => { 'application/json' => { schema => { properties => $properties } } } };
}

sub document {
  my $parent = '/Things/{Sid}.json';

  my %properties = (
    Active => { type => 'boolean' },
    Amount => { type => 'number' },
    Day    => { type => 'string', format => 'date' },
    Config => { type => 'object' },
    Free   => {},
    Items  => { type   => 'array', items => {} },
    Mode   => { '$ref' => '#/components/schemas/thing_enum_mode' },
    Name   => { type   => 'string' },
    Size   => { type   => 'integer' },
    Tags   => { type   => 'array',  items  => { type => 'string' } },
    When   => { type   => 'string', format => 'date-time' },
  );
  my $form = { type => 'object', required => [qw(Name Size)], properties => \%properties };

  return {
    servers => [{ url => 'https://demo.test' }],
    paths   => {
      '/v1/Things.json' => {
        'x-twilio' => { pathType => 'list' },
        get        => {
          operationId => 'ListThing',
          parameters  => [
            { name => 'Status',   in => 'query', schema => { type => 'string' } },
            { name => 'Created<', in => 'query', schema => { type => 'string', format => 'date' } },
            { name => 'PageSize', in => 'query', schema => { type => 'integer' } },
            { name => 'Page',     in => 'query', schema => { type => 'integer' } },
            { name => 'PageToken', in => 'query', schema => { type => 'string' } },
            {
              name   => 'AddOnsData',
              in     => 'query',
              schema => { type => 'object', format => 'prefixed-collapsible-map-AddOns' },
            },
          ],
          responses => { 200 => records('things') },
        },
        post => {
          operationId => 'CreateThing',
          requestBody =>
            { content => { 'application/x-www-form-urlencoded' => { schema => $form } } },
          responses => { 201 => answer() },
        },
      },
      '/v1/Things/{Sid}.json' => {
        'x-twilio' => { pathType    => 'instance' },
        get        => { operationId => 'FetchThing', responses => { 200 => answer() } },
      },
      '/v1/Things/{ThingSid}/Parts/{Sid}.json' => {
        'x-twilio' => { pathType    => 'instance',  parent    => $parent },
        get        => { operationId => 'FetchPart', responses => { 200 => answer() } },
      },
      '/v1/Things/{ThingSid}/Parts.json' =>
        { 'x-twilio' => { pathType => 'list', parent => $parent } },
      '/v1/Things/Kinds.json' => {
        'x-twilio' => { pathType    => 'list',     parent    => '/Things.json' },
        get        => { operationId => 'ListKind', responses => { 200 => records('kinds') } },
      },
      '/v1/Things/{ThingSid}/Data.json' => {
        'x-twilio' => { pathType    => 'instance',  parent    => $parent },
        get        => { operationId => 'FetchData', responses => { 200 => answer() } },
      },
      '/v1/Things/{ThingSid}/Sections.json' =>
        { 'x-twilio' => { pathType => 'list', parent => $parent } },
      '/v1/Things/{ThingSid}/Sections/Rows.json' => {
        'x-twilio' => { pathType    => 'list',    parent    => '/Things/{ThingSid}/Sections.json' },
        get        => { operationId => 'ListRow', responses => { 200 => records('rows') } },
      },
    },
    components => {
      schemas => {
        thing           => { properties => { sid => { type => 'string' } } },
        thing_enum_mode => { type       => 'string', enum => [qw(fast slow)] },
      },
    },
  };
}
