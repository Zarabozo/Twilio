use 5.016;
use warnings;

use Carp       qw(croak);
use File::Temp qw(tempdir);
use Test::More;

use lib 'tools/lib';

use Twilio::Generator::Names qw(camelize segment_class singular snake);
use Twilio::Generator::Spec;
use Twilio::Generator::Tree;

subtest 'names' => sub {
  my %singular = (
    Messages   => 'Message',
    Addresses  => 'Address',
    Address    => 'Address',
    Entities   => 'Entity',
    Keys       => 'Key',
    Queues     => 'Queue',
    Media      => 'Media',
    Feedback   => 'Feedback',
    Boxes      => 'Box',
    Branches   => 'Branch',
    Dishes     => 'Dish',
    Conference => 'Conference',
    Status     => 'Status',
    Statuses   => 'Status',
  );
  is(singular($_), $singular{$_}, "singular of $_") for sort keys %singular;

  is(camelize('auth_types'),           'AuthTypes',      'camelize');
  is(snake('AddOnResults'),            'add_on_results', 'snake');
  is(snake('SIP'),                     'sip',            'snake of an acronym');
  is(snake('Addresses2Go'),            'addresses2_go',  'snake with a digit');
  is(snake('Calls'),                   'calls',          'snake of one word');
  is(segment_class('SIP'),             'Sip',            'class of an acronym');
  is(segment_class('CredentialLists'), 'CredentialList', 'class of a plural');
  is(segment_class('token'),           'Token',          'class of a lowercase segment');
};

subtest 'list and instance form one resource' => sub {
  my $tree = build(
    '/Things.json'       => list([get => 'ListThing'], [post => 'CreateThing']),
    '/Things/{Sid}.json' => instance([get => 'FetchThing'], [delete => 'DeleteThing']),
  );

  is(scalar @{ $tree->{resources} }, 1, 'one resource');
  my $thing = $tree->{resources}[0];
  is($thing->{class},          'Thing',              'class');
  is($thing->{mount},          'things',             'mount');
  is($thing->{list}{path},     '/Things.json',       'list path');
  is($thing->{instance}{path}, '/Things/{Sid}.json', 'instance path');
  is($thing->{instance}{key},  'Sid',                'instance key');
  is_deeply([map { [$_->{verb}, $_->{method}, $_->{id}] } @{ $thing->{list}{operations} }],
    [['list', 'GET', 'ListThing'], ['create', 'POST', 'CreateThing']], 'operations');
  is($thing->{parent}, undef,  'no parent');
  is($tree->{domain},  'demo', 'domain');
  is($tree->{version}, 'v1',   'version');
};

subtest 'children are nested under their parents' => sub {
  my $tree = build(
    '/Things.json'                        => list(),
    '/Things/{Sid}.json'                  => instance(),
    '/Things/{ThingSid}/Parts.json'       => list(parent => '/Things/{Sid}.json'),
    '/Things/{ThingSid}/Parts/{Sid}.json' => instance(parent => '/Things/{Sid}.json'),
  );
  my %by_class = map { $_->{class} => $_ } @{ $tree->{resources} };

  is_deeply([sort keys %by_class], ['Thing', 'Thing::Part'], 'classes');
  is($by_class{'Thing::Part'}{parent}, 'Thing', 'parent');
  is($by_class{'Thing::Part'}{mount},  'parts', 'mount');
};

subtest 'the parent in the spec can skip a path segment' => sub {
  my $tree = build(
    '/Things/{Sid}.json'                => instance(),
    '/Things/{ThingSid}/SMS/Codes.json' => list(parent => '/Things/{Sid}.json'),
  );
  my %by_class = map { $_->{class} => $_ } @{ $tree->{resources} };

  is_deeply([sort keys %by_class], ['Thing', 'Thing::Code'], 'no level for the segment');
  is($by_class{'Thing::Code'}{mount}, 'codes', 'mount');
};

subtest 'one path can hold two resources' => sub {
  my $tree = build(
    '/Things/{Sid}.json' => instance(
      dependents => {
        keys     => { resource_url => '/v1/Things/{thing_sid}/Keys.json' },
        new_keys => { resource_url => '/v1/Things/{thing_sid}/Keys.json' },
      }
    ),
    '/Things/{ThingSid}/Keys.json' =>
      list([get => 'ListKey'], [post => 'CreateNewKey'], parent => '/Things/{Sid}.json'),
    '/Things/{ThingSid}/Keys/{Sid}.json' =>
      instance([get => 'FetchKey'], parent => '/Things/{Sid}.json'),
  );
  my %by_class = map { $_->{class} => $_ } @{ $tree->{resources} };

  is_deeply([sort keys %by_class], ['Thing', 'Thing::Key', 'Thing::NewKey'], 'two classes');

  my ($key, $new_key) = @by_class{qw(Thing::Key Thing::NewKey)};
  is($key->{mount},           'keys',     'mount of the first');
  is($new_key->{mount},       'new_keys', 'mount of the second');
  is($new_key->{parent},      'Thing',    'same parent');
  is($new_key->{parent_side}, 'instance', 'on the same side of it');
  is_deeply([map { $_->{id} } @{ $key->{list}{operations} }], ['ListKey'], 'the list stays');
  is_deeply([map { $_->{id} } @{ $new_key->{list}{operations} }],
    ['CreateNewKey'], 'the create moves');
  ok($key->{instance},      'the instance stays');
  ok(!$new_key->{instance}, 'and does not move');
};

subtest 'a section with no path of its own' => sub {
  my $tree     = build('/Usage/Records.json' => list());
  my %by_class = map { $_->{class} => $_ } @{ $tree->{resources} };

  is_deeply([sort keys %by_class], ['Usage', 'Usage::Record'], 'the section exists');
  ok(!$by_class{Usage}{list} && !$by_class{Usage}{instance}, 'it has no operations');
};

subtest 'the class name in the spec wins' => sub {
  my $tree = build(
    '/Domains/{DomainSid}/Auth.json'       => list(class_name => 'auth_types'),
    '/Domains/{DomainSid}/Auth/Calls.json' => list(class_name => 'auth_type_calls'),
  );
  my @classes = map { $_->{class} } @{ $tree->{resources} };

  is_deeply(
    \@classes,
    ['Domain', 'Domain::AuthTypes', 'Domain::AuthTypes::AuthTypeCalls'],
    'used in the class and in those below it'
  );
  is($tree->{resources}[1]{mount}, 'auth', 'the mount still comes from the path');
};

subtest 'the mount name in the spec names the class' => sub {
  my $tree = build(
    '/Users/{Sid}.json'                 => instance(),
    '/Users/{UserSid}/Channels.json'    => list(mount_name => 'user_channels'),
    '/Builds/{Sid}/Status.json'         => instance(mount_name => 'build_status'),
    '/Builds/{Sid}.json'                => instance(),
    '/Users/{UserSid}/Plain/{Sid}.json' => instance(),
  );
  my %by_class = map { $_->{class} => $_ } @{ $tree->{resources} };

  ok($by_class{'User::UserChannel'}, 'a user channel, as twilio-php names it');
  is($by_class{'User::UserChannel'}{mount}, 'user_channels', 'and the mount');
  ok($by_class{'Build::BuildStatus'}, 'a singleton too');
  ok($by_class{'User::Plain'},        'with no mount name, the path names it');
};

subtest 'the class name in the spec wins over the mount name' => sub {
  my $tree = build('/Things.json' => list(class_name => 'stuff', mount_name => 'many_things'));
  is($tree->{resources}[0]{class}, 'Stuff',       'class');
  is($tree->{resources}[0]{mount}, 'many_things', 'mount');
};

subtest 'the mount named in the spec wins' => sub {
  my $tree = build(
    '/Things/{Sid}.json' => instance(
      dependents => { best_parts => { resource_url => '/v1/Things/{thing_sid}/Parts.json' } }
    ),
    '/Things/{ThingSid}/Parts.json' => list(),
  );
  my %by_class = map { $_->{class} => $_ } @{ $tree->{resources} };

  is($by_class{'Thing::Part'}{mount}, 'best_parts', 'mount');
};

subtest 'paths with no JSON suffix' => sub {
  my $tree = build('/Things' => list(), '/Things/{Sid}' => instance());

  is(scalar @{ $tree->{resources} },       1,     'one resource');
  is($tree->{resources}[0]{instance}{key}, 'Sid', 'key');
};

subtest 'an instance with no key is a singleton' => sub {
  my $tree     = build('/Things/{ThingSid}/Data.json' => instance([get => 'FetchData']));
  my %by_class = map { $_->{class} => $_ } @{ $tree->{resources} };

  ok($by_class{'Thing::Data'}{instance}, 'it is an instance');
  is($by_class{'Thing::Data'}{instance}{key}, undef, 'with no key');
};

subtest 'render' => sub {
  my $tree = build(
    '/Things.json'                 => list([post => 'CreateThing'], [get => 'ListThing']),
    '/Things/{Sid}.json'           => instance([get => 'FetchThing']),
    '/Things/{ThingSid}/Data.json' => instance([get => 'FetchData']),
    '/Usage/Records.json'          => list(),
  );

  is_deeply(
    [Twilio::Generator::Tree::render($tree)],
    [
      "Thing [things] list(create list) instance:Sid(fetch)\n",
      "Thing::Data [data] instance:singleton(fetch)\n",
      "Usage [usage]\n",
      "Usage::Record [records] list()\n",
    ],
    'one line for each resource'
  );
};

subtest 'anything that cannot be placed stops the build' => sub {
  my @cases = (
    [
      'unknown path type',
      qr/unknown path type 'other'/,
      '/A.json' => { 'x-twilio' => { pathType => 'other' } }
    ],
    ['missing path type', qr/unknown path type ''/,      '/A.json'       => {}],
    ['list with a key',   qr/cannot end in a parameter/, '/A/{Sid}.json' => list()],
    [
      'wrong parent',
      qr/parent \/C.json does not contain it/,
      '/A/B.json' => list(parent => '/C.json')
    ],
    ['parent is itself', qr/does not contain it/, '/A/B.json' => list(parent => '/A/B.json')],
    ['parent below it',  qr/does not contain it/, '/A.json'   => list(parent => '/A/B.json')],
    [
      'two parents',
      qr{parent A conflicts with A/B},
      '/A/B/C.json'       => list(parent => '/A/B.json'),
      '/A/B/C/{Sid}.json' => instance(parent => '/A.json'),
    ],
    ['unknown verb', qr/verb from operation 'SendThing'/, '/A.json' => list([post => 'SendThing'])],
    ['no operation id', qr/verb from operation ''/,       '/A.json' => list([post => q{}])],
    [
      'unknown entry', qr/unknown path entry 'options'/, '/A.json' => { %{ list() }, options => {} }
    ],
    ['second list', qr/a second list/, '/A/{P}/B.json' => list(), '/A/{Q}/B.json' => list()],
    [
      'mount name conflict',
      qr/mount name b conflicts with a/,
      '/A.json'       => list(mount_name => 'a'),
      '/A/{Sid}.json' => instance(mount_name => 'b'),
    ],
    [
      'class name conflict',
      qr/class name b conflicts with a/,
      '/A.json'       => list(class_name => 'a'),
      '/A/{Sid}.json' => instance(class_name => 'b'),
    ],
    ['same class twice', qr/are both A/, '/As.json' => list(), '/A.json' => list()],
    [
      'two nouns, neither its own',
      qr/no operation is named after A/,
      '/As.json' => list([get => 'ListB'], [post => 'CreateC'])
    ],
    [
      'same mount twice',
      qr/are both [.]same/,
      '/A.json' => list(dependents => { same => { resource_url => '/B.json' } }),
      '/B.json' => list(),
      '/C.json' => list(dependents => { same => { resource_url => '/D.json' } }),
      '/D.json' => list(),
    ],
    [
      'child with two names',
      qr/called both first and second/,
      '/A.json' => list(dependents => { first  => { resource_url => '/C.json' } }),
      '/B.json' => list(dependents => { second => { resource_url => '/C.json' } }),
      '/C.json' => list(),
    ],
  );

  for my $case (@cases) {
    my ($name, $expected, @paths) = @{$case};
    my $ok    = eval { build(@paths); 1 };
    my $error = $@;
    ok(!$ok, "$name: refused");
    like($error, $expected, "$name: says why");
  }
};

subtest 'an instance with an id gets a list' => sub {
  my $tree = build('/Things/{Sid}.json' => instance());
  my ($thing) = @{ $tree->{resources} };

  is($thing->{list}{path}, '/Things.json', 'at the path before the id');
  is_deeply($thing->{list}{operations}, [], 'with no operations');
  ok($thing->{list}{implied}, 'and it says no path declared it');

  my $plain = build('/Things/{Sid}' => instance());
  is($plain->{resources}[0]{list}{path}, '/Things', 'without .json as well');
};

subtest 'a singleton gets no list' => sub {
  my $tree = build('/Things/{Sid}.json' => instance(), '/Things/{Sid}/Data.json' => instance());
  my ($data) = grep { $_->{class} eq 'Thing::Data' } @{ $tree->{resources} };

  ok($data,          'the singleton is there');
  ok(!$data->{list}, 'with no list');
};

subtest 'spec files without a version in their name' => sub {
  my $dir = tempdir(CLEANUP => 1);
  for my $name (qw(preview iam_organizations)) {
    my $file = "$dir/twilio_$name.json";
    open my $handle, '>', $file or croak "$file: $!";
    print {$handle} '{"paths":{}}';
    close $handle or croak "$file: $!";

    my $spec = Twilio::Generator::Spec->load($file);
    ok(!defined $spec->version, "$name: no version");

    my $ok    = eval { Twilio::Generator::Tree::build($spec); 1 };
    my $error = $@;
    ok(!$ok, "$name: refused for now");
    like($error, qr/several versions/, "$name: says why");
  }

  is(Twilio::Generator::Spec->load("$dir/twilio_preview.json")->domain, 'preview', 'the name');
  is(Twilio::Generator::Spec->load("$dir/twilio_iam_organizations.json")->domain,
    'preview_iam', 'the name in twilio-php');
};

subtest 'references to shared schemas and parameters' => sub {
  my $page = { name => 'PageSize', in => 'query', schema => { type => 'integer' } };
  my $spec = Twilio::Generator::Spec->new(
    'demo', 'v1',
    {
      paths      => {},
      components =>
        { schemas => { thing => { type => 'object' } }, parameters => { page => $page } },
    }
  );

  is_deeply(
    $spec->resolve({ '$ref' => '#/components/schemas/thing' }),
    { type => 'object' },
    'a schema'
  );
  is($spec->resolve({ '$ref' => '#/components/parameters/page' }), $page, 'a parameter');

  my $plain = { type => 'string' };
  is($spec->resolve($plain), $plain, 'anything else is returned as it is');

  my $ok    = eval { $spec->resolve({ '$ref' => '#/components/parameters/none' }); 1 };
  my $error = $@;
  ok(!$ok, 'a missing parameter is refused');
  like($error, qr/No parameter none/, 'says why');
};

subtest 'loading a spec file' => sub {
  my $dir  = tempdir(CLEANUP => 1);
  my $file = "$dir/twilio_api_v2010.json";
  open my $handle, '>', $file or croak "$file: $!";
  print {$handle} '{"paths":{"/2010-04-01/Accounts.json":{},"/v1/Things":{},"/Plain.json":{}}}';
  close $handle or croak "$file: $!";

  my $spec = Twilio::Generator::Spec->load($file);
  is($spec->domain,  'api',   'domain from the file name');
  is($spec->version, 'v2010', 'version from the file name');
  is_deeply(
    [sort keys %{ $spec->paths }],
    ['/Accounts.json', '/Plain.json', '/Things'],
    'version prefixes removed'
  );

  my $ok    = eval { Twilio::Generator::Spec->load("$dir/other.json"); 1 };
  my $error = $@;
  ok(!$ok, 'other names are refused');
  like($error, qr/Not a spec file name/, 'says why');

  $ok    = eval { Twilio::Generator::Spec->load("$dir/twilio_api_v1.json"); 1 };
  $error = $@;
  ok(!$ok, 'a missing file is refused');
  like($error, qr/Cannot read/, 'says why');

  my $document =
    { paths => { '/2010-04-01/Accounts.json' => {} }, servers => [{ url => 'https://a.test' }] };
  my $full = Twilio::Generator::Spec->new('api', 'v2010', $document);
  is($full->version_path, '2010-04-01',     'the version in the paths');
  is($full->base_url,     'https://a.test', 'the host');

  my $empty = Twilio::Generator::Spec->new('api', 'v2010', { paths => { '/Accounts.json' => {} } });
  $ok    = eval { $empty->version_path; 1 };
  $error = $@;
  ok(!$ok, 'paths with no version are refused');
  like($error, qr/No version in the paths/, 'says why');

  $ok    = eval { $empty->base_url; 1 };
  $error = $@;
  ok(!$ok, 'no server is refused');
  like($error, qr/No server in the spec/, 'says why');
};

done_testing;

sub build {
  my (%paths)   = @_;
  my %versioned = map { ("/v1$_" => $paths{$_}) } keys %paths;
  my $spec      = Twilio::Generator::Spec->new('demo', 'v1', { paths => \%versioned });
  return Twilio::Generator::Tree::build($spec);
}

sub list {
  my (@arguments) = @_;
  return path_item('list', @arguments);
}

sub instance {
  my (@arguments) = @_;
  return path_item('instance', @arguments);
}

sub path_item {
  my ($type, @arguments) = @_;

  my %item     = ('x-twilio' => { pathType => $type });
  my %note_for = (
    parent     => 'parent',
    class_name => 'className',
    mount_name => 'mountName',
    dependents => 'dependentProperties'
  );

  while (my $argument = shift @arguments) {
    if (ref $argument) {
      my ($method, $id) = @{$argument};
      $item{$method} = { operationId => $id };
    }
    else {
      $item{'x-twilio'}{ $note_for{$argument} } = shift @arguments;
    }
  }
  return \%item;
}
