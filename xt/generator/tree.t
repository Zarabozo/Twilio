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
    Messages       => 'Message',
    Addresses      => 'Address',
    Address        => 'Address',
    Entities       => 'Entity',
    Keys           => 'Key',
    Queues         => 'Queue',
    Media          => 'Media',
    Feedback       => 'Feedback',
    Boxes          => 'Box',
    Branches       => 'Branch',
    Dishes         => 'Dish',
    Conference     => 'Conference',
    Status         => 'Status',
    Statuses       => 'Status',
    Bases          => 'Basis',
    KnowledgeBases => 'KnowledgeBasis',
    Databases      => 'Database',
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
    '/Things/{ThingSid}/Keys.json' => list(
      [get  => 'ListKey'],
      [post => 'CreateNewKey', { mountName => 'new_keys' }],
      parent => '/Things/{Sid}.json'
    ),
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

# Verify's /Passkeys/Challenges holds only NewChallenge's create.
subtest 'a path left with nothing after a move is no resource' => sub {
  my $tree = build(
    '/Things/{Sid}.json'      => instance([get => 'FetchThing']),
    '/Things/{Sid}/Keys.json' =>
      list([post => 'CreateNewKey', { mountName => 'new_keys' }], parent => '/Things/{Sid}.json'),
    '/Things/{Sid}/Tags.json' => list(
      [post => 'CreateNewTag', { mountName => 'new_tags' }], parent => '/Things/{Sid}.json'
    ),
    '/Things/{Sid}/Tags/{TagSid}/Notes.json' =>
      list([get => 'ListNote'], parent => '/Things/{Sid}/Tags.json'),
  );
  my %by_class = map { $_->{class} => $_ } @{ $tree->{resources} };

  ok($by_class{'Thing::NewKey'}, 'what moved is there');
  ok(!$by_class{'Thing::Key'},   'and the empty path is gone');
  ok($by_class{'Thing::Tag'},    'unless a child hangs from it');
};

# twilio-oai-generator splits by the names on the operation, not by the noun in its id.
subtest 'an operation id alone does not split a path' => sub {
  my $tree = build('/Applications.json' =>
      list([get => 'ListShortCodeApplication'], [post => 'CreateShortCodeApplication']));

  is(scalar @{ $tree->{resources} }, 1,             'one resource');
  is($tree->{resources}[0]{class},   'Application', 'named after the path');
};

subtest 'a list and an instance that name themselves apart are two resources' => sub {
  my $tree = build(
    '/Keys.json'       => list([get => 'ListGetKeys'], class_name => 'get_api_keys'),
    '/Keys/{Sid}.json' => instance([get => 'FetchKey'], mount_name => 'api_key'),
  );
  my %by_class = map { $_->{class} => $_ } @{ $tree->{resources} };

  is_deeply([sort keys %by_class], ['ApiKey', 'GetApiKeys'], 'as in IAM v1');
  ok($by_class{ApiKey}{list}{implied}, 'the instance gets a list of its own');
};

subtest 'a section with no path of its own' => sub {
  my $tree     = build('/Usage/Records.json' => list(parent => '/Usage.json'));
  my %by_class = map { $_->{class} => $_ } @{ $tree->{resources} };

  is_deeply([sort keys %by_class], ['Usage', 'Usage::Record'], 'the section exists');
  ok(!$by_class{Usage}{list} && !$by_class{Usage}{instance}, 'it has no operations');
};

subtest 'a parent that no path describes keeps its id' => sub {
  my $tree = build('/Organizations/{OrganizationSid}/Users.json' =>
      list(parent => '/Organizations/{OrganizationSid}'));
  my %by_class = map { $_->{class} => $_ } @{ $tree->{resources} };

  my $organization = $by_class{Organization};
  is($organization->{instance}{key}, 'OrganizationSid', 'an instance with its id');
  is_deeply($organization->{instance}{operations}, [], 'and no operations');
  is($by_class{'Organization::User'}{parent_side}, 'instance', 'the child hangs from it');
};

subtest 'a path that declares no parent hangs from the version' => sub {
  my $tree = build(
    '/Configuration.json'           => instance([get => 'FetchConfiguration']),
    '/Configuration/Addresses.json' => list([get => 'ListAddress']),
  );
  my %by_class = map { $_->{class} => $_ } @{ $tree->{resources} };

  is_deeply([sort keys %by_class], ['Address', 'Configuration'], 'next to the other, as in PHP');
  is($by_class{Address}{parent}, undef, 'with no parent');
};

subtest 'a parent written with the version is not one' => sub {
  my $tree = build('/Roles/{RoleSid}/Permissions.json' => list(parent => '/v1/Roles/{Sid}'));
  is_deeply([map { $_->{class} } @{ $tree->{resources} }],
    ['Permission'], 'twilio-php puts IAM\'s RolePermission at the root');
};

subtest 'a parent need not be part of the path' => sub {
  my $tree = build(
    '/DialingPermissions.json' => list(),
    '/Settings.json' => instance([get => 'FetchSettings'], parent => '/DialingPermissions.json'),
  );
  my %by_class = map { $_->{class} => $_ } @{ $tree->{resources} };

  is($by_class{'DialingPermission::Setting'}{parent}, 'DialingPermission', 'as Voice has it');
};

subtest 'children of a singleton hang from it' => sub {
  my $tree = build(
    '/Configuration.json'          => instance([get => 'FetchConfiguration']),
    '/Configuration/Webhooks.json' =>
      instance([get => 'FetchWebhook'], parent => '/Configuration.json'),
  );
  my %by_class = map { $_->{class} => $_ } @{ $tree->{resources} };

  is($by_class{'Configuration::Webhook'}{parent_side}, 'instance', 'not from a list it lacks');
};

subtest 'what a path does not say' => sub {
  my $tree = build(
    '/Plain.json'       => { get => { operationId => 'ListPlain' } },
    '/Plain/{Sid}.json' => { get => { operationId => 'FetchPlain' } },
  );
  my ($plain) = @{ $tree->{resources} };

  ok($plain->{list}, 'a path with no id is a list');
  is($plain->{instance}{key}, 'Sid', 'and one with an id is an instance');
};

subtest 'patch is a verb' => sub {
  my $tree = build('/Things/{Sid}.json' => instance([patch => 'PatchThing']));
  is($tree->{resources}[0]{instance}{operations}[0]{verb}, 'patch', 'as twilio-php has it');
};

subtest 'a list can end in an id' => sub {
  my $tree = build('/Reports/{ReportId}.json' => list([get => 'ListReport']));
  my ($report) = @{ $tree->{resources} };

  ok($report->{list},      'it is a list');
  ok(!$report->{instance}, 'and not an instance');
  is($report->{list}{key}, undef, 'the id is not a key of its own');
};

subtest 'a list that ends in an id names its resource' => sub {
  my $tree =
    build('/ShortCodes/{IsoCountryCode}/{ShortCode}.json' => instance([get => 'FetchShortCode']));
  my ($code) = @{ $tree->{resources} };

  is($code->{class}, 'IsoCountryCode',   'as twilio-php names Routes v3\'s short codes');
  is($code->{mount}, 'iso_country_code', 'and the method');
};

subtest 'a mount name in camelCase' => sub {
  my $tree = build('/Overrides/{Field}.json' =>
      instance([get => 'FetchOverride'], mount_name => 'lookupOverrides'));
  is($tree->{resources}[0]{mount}, 'lookup_overrides', 'is in snake case like the others');
  is($tree->{resources}[0]{class}, 'LookupOverride',   'and names the class');
};

subtest 'names match the URL a parent gives, ids included' => sub {
  my $tree = build(
    '/Exports.json' =>
      list(dependents => { custom_jobs => { resource_url => '/v1/Exports/{type}/Jobs' } }),
    '/Exports/{Type}.json'      => instance([get => 'FetchExport']),
    '/Exports/{Type}/Jobs.json' =>
      list([get => 'ListCustomJob'], parent => '/Exports/{Type}.json', class_name => 'custom_job'),
    '/Exports/Jobs/{Sid}.json' => instance([get => 'FetchJob'], parent => '/Exports.json'),
  );
  my %by_class = map { $_->{class} => $_ } @{ $tree->{resources} };

  is($by_class{'Export::CustomJob'}{mount}, 'custom_jobs', 'the jobs of an export');
  is($by_class{'Export::Job'}{mount},       'jobs',        'and not the jobs below the list');
};

subtest 'a list and its instances can each have a child by the same name' => sub {
  my $tree = build(
    '/Queues.json'            => list([get => 'ListQueue']),
    '/Queues/{Sid}.json'      => instance([get => 'FetchQueue']),
    '/Queues/Statistics.json' => list(
      [get => 'ListQueuesStatistics'],
      parent     => '/Queues.json',
      class_name => 'queues_statistics'
    ),
    '/Queues/{QueueSid}/Statistics.json' => instance(
      [get => 'FetchQueueStatistics'],
      parent     => '/Queues/{Sid}.json',
      class_name => 'queue_statistics'
    ),
  );
  my @mounts = sort map { "$_->{class} $_->{mount} $_->{parent_side}" }
    grep { $_->{parent} } @{ $tree->{resources} };

  is_deeply(
    \@mounts,
    ['Queue::QueueStatistics statistics instance', 'Queue::QueuesStatistics statistics list'],
    'as TaskRouter\'s queues have'
  );
};

subtest 'the class name in the spec wins' => sub {
  my $tree = build(
    '/Domains/{DomainSid}/Auth.json' =>
      list(class_name => 'auth_types', parent => '/Domains/{Sid}.json'),
    '/Domains/{DomainSid}/Auth/Calls.json' =>
      list(class_name => 'auth_type_calls', parent => '/Domains/{DomainSid}/Auth.json'),
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
    '/Users/{Sid}.json'              => instance(),
    '/Users/{UserSid}/Channels.json' =>
      list(mount_name => 'user_channels', parent => '/Users/{Sid}.json'),
    '/Builds/{Sid}/Status.json' =>
      instance(mount_name => 'build_status', parent => '/Builds/{Sid}.json'),
    '/Builds/{Sid}.json'                => instance(),
    '/Users/{UserSid}/Plain/{Sid}.json' => instance(parent => '/Users/{Sid}.json'),
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
    '/Things/{ThingSid}/Parts.json' => list(parent => '/Things/{Sid}.json'),
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
  my $tree = build('/Things/{ThingSid}/Data.json' =>
      instance([get => 'FetchData'], parent => '/Things/{Sid}.json'));
  my %by_class = map { $_->{class} => $_ } @{ $tree->{resources} };

  ok($by_class{'Thing::Data'}{instance}, 'it is an instance');
  is($by_class{'Thing::Data'}{instance}{key}, undef, 'with no key');
};

subtest 'render' => sub {
  my $tree = build(
    '/Things.json'                 => list([post => 'CreateThing'], [get => 'ListThing']),
    '/Things/{Sid}.json'           => instance([get => 'FetchThing']),
    '/Things/{ThingSid}/Data.json' =>
      instance([get => 'FetchData'], parent => '/Things/{Sid}.json'),
    '/Usage/Records.json' => list(parent => '/Usage.json'),
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
      'two resources by one name',
      qr/are both [.]a/,
      '/A.json'       => list(class_name => 'a'),
      '/A/{Sid}.json' => instance(class_name => 'b'),
    ],
    ['same class twice', qr/are both A/, '/As.json' => list(), '/A.json' => list()],
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
  my $tree = build(
    '/Things/{Sid}.json'      => instance(),
    '/Things/{Sid}/Data.json' => instance(parent => '/Things/{Sid}.json'),
  );
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
    ok(!$ok, "$name: not one tree");
    like($error, qr/several versions/, "$name: says why");
  }

  is(Twilio::Generator::Spec->load("$dir/twilio_preview.json")->domain, 'preview', 'the name');
  is(Twilio::Generator::Spec->load("$dir/twilio_iam_organizations.json")->domain,
    'preview_iam', 'the name in twilio-php');
};

subtest 'a spec with several versions is split' => sub {
  my $list = { 'x-twilio' => { pathType => 'list' }, get => { operationId => 'ListDocument' } };
  my $spec = Twilio::Generator::Spec->new(
    'preview',
    undef,
    {
      paths => {
        '/HostedNumbers/AuthorizationDocuments' => {
          %{$list},
          'x-twilio' => {
            pathType            => 'list',
            dependentProperties =>
              { documents => { resource_url => '/HostedNumbers/AuthorizationDocuments' } },
          },
        },
        '/marketplace/AvailableAddOns' => $list,
      },
    }
  );
  my %by_version = map { $_->version => $_ } $spec->versions;

  is_deeply([sort keys %by_version], ['hosted_numbers', 'marketplace'], 'each first segment');
  my $hosted = $by_version{hosted_numbers};
  is($hosted->version_path, 'HostedNumbers', 'which goes in the URL');
  is_deeply([keys %{ $hosted->paths }], ['/AuthorizationDocuments'], 'and not in the paths');
  is($hosted->domain, 'preview', 'in the same domain');

  my ($resource) = @{ Twilio::Generator::Tree::build($hosted)->{resources} };
  is($resource->{mount}, 'documents', 'its own version leaves the URLs of dependents too');
};

subtest 'a version that twilio-php names apart' => sub {
  my $spec = Twilio::Generator::Spec->new(
    'preview_iam',
    undef,
    {
      paths => {
        '/v1/token' =>
          { 'x-twilio' => { pathType => 'list' }, post => { operationId => 'CreateToken' } },
        '/Organizations/{OrganizationSid}/Users' => {
          'x-twilio' => { pathType    => 'list', parent => '/Organizations/{OrganizationSid}' },
          get        => { operationId => 'ListUser' },
        },
      },
    }
  );
  my %by_version = map { $_->version => $_ } $spec->versions;

  is_deeply([sort keys %by_version], ['v1', 'versionless'], 'as PreviewIam has them');
  my $versionless = $by_version{versionless};
  is($versionless->version_path, q{}, 'with nothing of its own in the URL');
  is_deeply(
    [keys %{ $versionless->paths }],
    ['/Organizations/{OrganizationSid}/Users'],
    'so its paths keep their first segment'
  );

  my %by_class =
    map { $_->{class} => $_ } @{ Twilio::Generator::Tree::build($versionless)->{resources} };
  is($by_class{Organization}{mount},
    'organization', 'named as twilio-php and twilio-python name it');
  is($by_class{'Organization::User'}{mount}, 'users', 'with its children below');
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
      my ($method, $id, $notes) = @{$argument};
      $item{$method} = { operationId => $id, $notes ? ('x-twilio' => $notes) : () };
    }
    else {
      $item{'x-twilio'}{ $note_for{$argument} } = shift @arguments;
    }
  }
  return \%item;
}
