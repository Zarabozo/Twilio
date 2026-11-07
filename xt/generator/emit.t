use 5.016;
use warnings;

use Test::More;

use lib 'tools/lib';

use Twilio::Domain;
use Twilio::Generator::Emit;
use Twilio::Generator::Resource;
use Twilio::Generator::Spec;
use Twilio::Generator::Tree;
use Twilio::Generator::Types qw(option_name);
use Twilio::Http::FakeClient;
use Twilio::Rest::Client;
use Twilio::Version;

my $ACCOUNT = 'AC1';
our $NAMESPACE = 'Twilio::Rest::Demo::V1::Account::';

load_generated(emit(document()));

subtest 'create sends required values and options under their wire names' => sub {
  my ($list, $http) = list();
  $http->mock(201, { sid => 'TH1', name => 'one' });

  my $thing = $list->create(
    'one', 3,
    {
      active    => 0,
      when      => bless({}, 'Local::Date'),
      tags      => ['a', 'b'],
      mode      => 'fast',
      not_known => 'ignored',
    }
  );

  my ($request) = $http->requests;
  is($request->{method}, 'POST', 'method');
  like($request->{url}, qr{/v1/Accounts/AC1/Things[.]json\z}, 'url');
  my %sent = map { split /=/ } split /&/, $request->{content};
  is($sent{Name},   'one',                      'first required value');
  is($sent{Size},   '3',                        'second required value');
  is($sent{Active}, 'false',                    'boolean written as text');
  is($sent{When},   '1970-01-01T00%3A00%3A07Z', 'date written in ISO 8601');
  is($sent{Mode},   'fast',                     'enum sent as it is');
  like($request->{content}, qr/Tags=a&Tags=b/, 'array sent once for each value');
  ok(!exists $sent{not_known}, 'unknown options are not sent');

  isa_ok($thing, "${NAMESPACE}ThingInstance");
  is($thing->sid, 'TH1', 'the instance comes from the response');
};

subtest 'create with no options' => sub {
  my ($list, $http) = list();
  $http->mock(201, { sid => 'TH1' });

  $list->create('one', 3);

  my ($request) = $http->requests;
  is($request->{content}, 'Name=one&Size=3', 'only the required values');
};

subtest 'reading a list' => sub {
  my ($list, $http) = list();
  $http->mock(200, { things => [{ sid => 'TH1' }, { sid => 'TH2' }], meta => {} });

  my @things = $list->read({ status => 'on', created_before => bless({}, 'Local::Date') }, 2, 50);

  is_deeply([map { $_->sid } @things], ['TH1', 'TH2'], 'records');
  my ($request) = $http->requests;
  like($request->{url}, qr/Status=on/,                           'filter');
  like($request->{url}, qr/Created%3C=1970-01-01T00%3A00%3A07Z/, 'date filter with a wire name');
  like($request->{url}, qr/PageSize=50/,                         'page size');
  unlike($request->{url}, qr/AddOns/, 'no map, no parameters');

  $http->mock(200, { things => [], meta => {} });
  $list->read({ add_ons_data => { lookup => { Key => 'v', List => [1, 2] } } });
  my $url = ($http->requests)[-1]{url};
  like($url, qr/AddOns[.]lookup[.]Key=v(?:&|\z)/,      'a map, one parameter for each key');
  like($url, qr/AddOns[.]lookup[.]List[.]1=2(?:&|\z)/, 'arrays inside by index');
  unlike($url, qr/AddOnsData/, 'its own name is never sent');
};

subtest 'stream, page and get_page' => sub {
  my ($list, $http) = list();
  $http->mock(200, { things => [{ sid => 'TH1' }], meta => {} });
  my $stream = $list->stream({}, 1);
  is($stream->next->sid, 'TH1', 'stream');

  $http->mock(200, { things => [{ sid => 'TH2' }], meta => {} });
  my $page = $list->page({}, 5, 'token', 2);
  isa_ok($page, "${NAMESPACE}ThingPage");
  is($page->next->sid, 'TH2', 'page');
  my $url = ($http->requests)[-1]{url};
  like($url, qr/PageSize=5/,      'page size');
  like($url, qr/PageToken=token/, 'page token');
  like($url, qr/Page=2/,          'page number');

  $http->mock(200, { things => [{ sid => 'TH3' }], meta => {} });
  is($list->get_page('https://demo.test/next')->next->sid, 'TH3', 'get_page');
  is(($http->requests)[-1]{url}, 'https://demo.test/next',        'get_page uses the URL');
};

subtest 'a context uses both parts of the path' => sub {
  my ($list, $http) = list();
  my $context = $list->get_context('TH/1');
  isa_ok($context, "${NAMESPACE}ThingContext");

  $http->mock(200, { sid => 'TH1' });
  is($context->fetch->sid, 'TH1', 'fetch');
  my ($fetch) = $http->requests;
  is($fetch->{method}, 'GET', 'fetch method');
  like($fetch->{url}, qr{/Accounts/AC1/Things/TH%2F1[.]json\z}, 'the id is encoded');

  $http->mock(200, { sid => 'TH1', name => 'two' });
  is($context->update({ name => 'two' })->name, 'two', 'update');
  my $update = ($http->requests)[-1];
  is($update->{method},  'POST',     'update method');
  is($update->{content}, 'Name=two', 'update body');

  $http->mock(204, q{});
  is($context->delete,              1,        'delete returns true');
  is(($http->requests)[-1]{method}, 'DELETE', 'delete method');
};

subtest 'an instance reaches its own context' => sub {
  my ($list, $http) = list();
  $http->mock(201, { sid => 'TH1', name => 'one' });
  my $thing = $list->create('one', 3);

  $http->mock(200, { sid => 'TH1', name => 'two' });
  is($thing->fetch->name, 'two', 'fetch');
  like(($http->requests)[-1]{url}, qr{/Accounts/AC1/Things/TH1[.]json\z}, 'sid from the payload');

  $http->mock(200, { sid => 'TH1', name => 'three' });
  is($thing->update({ name => 'three' })->name, 'three', 'update');

  $http->mock(204, q{});
  is($thing->delete, 1, 'delete');
};

subtest 'fields' => sub {
  my ($list, $http) = list();
  $http->mock(201,
    { sid => 'TH1', name => 'one', date_created => 'Thu, 30 Jul 2015 20:12:31 +0000' });
  my $thing = $list->create('one', 3);

  isa_ok($thing->date_created, 'Time::Piece');
  is($thing->date_created->ymd, '2015-07-30', 'dates are read');
  is($thing->mode,              undef,        'a field with an enum');
};

subtest 'optional pieces are left out' => sub {
  my $document = document();
  delete $document->{paths}{'/v1/Accounts/{AccountSid}/Things/{Sid}.json'};
  delete $document->{paths}{'/v1/Accounts/{AccountSid}/Things.json'}{get};

  my $code = emit($document);
  unlike($code, qr/^package \S+ThingContext/m, 'no context package');
  unlike($code, qr/^package \S+ThingPage/m,    'no page package');
  unlike($code, qr/^sub get_context/m,         'no get_context');
  unlike($code, qr/^sub read/m,                'no read');
  like($code, qr/^package \S+ThingInstance/m, 'the instance stays');
  ok(compiles($code), 'it compiles') or diag($@);
};

subtest 'the other value types' => sub {
  my $document   = document();
  my $path       = '/v1/Accounts/{AccountSid}/Things.json';
  my $form       = 'application/x-www-form-urlencoded';
  my $body       = $document->{paths}{$path}{post}{requestBody}{content}{$form}{schema}{properties};
  my $properties = $document->{components}{schemas}{thing}{properties};

  $body->{Day}               = { type => 'string', format => 'date' };
  $body->{Parameter}         = {};
  $body->{'Parameter1.Name'} = { type => 'string' };
  $body->{Settings}          = { type => 'object' };
  $body->{Items}   = { type => 'array', items => {} };
  $body->{Moments} = { type => 'array', items => { type => 'string', format => 'date-time' } };
  $properties->{capabilities} = { type => 'object',  format => 'phone-number-capabilities' };
  $properties->{start_date}   = { type => 'string',  format => 'date' };
  $properties->{tags}         = { type => 'array',   items  => { type => 'string' } };
  $properties->{created_at}   = { type => 'string',  format => 'date-time' };
  $properties->{expires_in}   = { type => 'integer', format => 'int64' };

  local $NAMESPACE = 'Twilio::Rest::Demo::V1::Other::';
  my $code = emit($document) =~ s/V1::Account::/V1::Other::/gr;
  load_generated($code);

  my ($list, $http) = list();
  $http->mock(
    201,
    {
      capabilities => { MMS => \1 },
      start_date   => '2026-11-06',
      tags         => ['a'],
      created_at   => '2026-11-06T10:20:30Z',
      expires_in   => 3600,
    }
  );

  my $thing = $list->create(
    'one', 3,
    {
      day             => bless({}, 'Local::Date'),
      parameter       => { a => 1 },
      parameter1_name => 'first',
      settings        => { b => 2 },
      items           => [{ c => 3 },               '{"d":4}'],
      moments         => [bless({}, 'Local::Date'), '2026-11-06T00:00:00Z'],
    }
  );

  my ($request) = $http->requests;
  like($request->{content}, qr/Day=1970-01-01(?:&|\z)/,      'date with no time');
  like($request->{content}, qr/Parameter=%7B%22a%22%3A1%7D/, 'free-form data as JSON');
  like($request->{content}, qr/Parameter1[.]Name=first/,     'a dotted wire name');
  like($request->{content}, qr/Settings=%7B%22b%22%3A2%7D/,  'an object as JSON');
  like(
    $request->{content},
    qr/Items=%7B%22c%22%3A3%7D&Items=%7B%22d%22%3A4%7D/,
    'each element of an array of free-form data as JSON, and text as it is'
  );
  my $first_moment  = qr/Moments=1970-01-01T00%3A00%3A07Z/;
  my $second_moment = qr/Moments=2026-11-06T00%3A00%3A00Z/;
  like($request->{content}, qr/$first_moment&$second_moment/, 'each date in an array');

  isa_ok($thing->capabilities, 'Twilio::Base::PhoneNumberCapabilities');
  is($thing->capabilities->mms, 1,            'capabilities are read');
  is($thing->start_date->ymd,   '2026-11-06', 'a date field is read');
  is_deeply($thing->tags, ['a'], 'an array field stays as it is');
  isa_ok($thing->created_at, 'Time::Piece');
  is($thing->created_at->datetime, '2026-11-06T10:20:30', 'an ISO 8601 date field is read');
  is($thing->expires_in,           3600,                  'a 64-bit integer stays as it is');

};

subtest 'parents and their children' => sub {
  my $document = family();
  my %models   = map { ($_->{module} =~ s/.*V1:://r) => $_ } all_models($document);

  my ($thing, $section) = @models{qw(Thing Thing::Section)};
  my @children = @{ $thing->{context}{children} };
  is_deeply(
    [sort map { $_->{mount} } @children],
    [qw(data notes parts sections)],
    'the children of an instance are on the context'
  );
  is_deeply([map { $_->{mount} } @{ $thing->{list}{children} // [] }],
    ['kinds'], 'a list link stays on the list');
  is_deeply([map { $_->{mount} } @{ $section->{list}{children} }],
    ['rows'], 'a section has children');
  ok(!$section->{has_instance}, 'and no instance');

  for my $model (values %models) {
    my $code = Twilio::Generator::Emit::module($model);
    compiles($code) or BAIL_OUT("$model->{module} does not compile: $@");
    my $file = ($model->{module} =~ s{::}{/}gr) . '.pm';
    $INC{$file} = 1;    ## no critic (RequireLocalizedPunctuationVars)
  }

  my $http = Twilio::Http::FakeClient->new;
  my $client =
    Twilio::Rest::Client->new('ACxx', 'token', { http_client => $http, environment => {} });
  my $domain = Twilio::Domain->new($client);
  $domain->{base_url} = 'https://demo.test';
  my $version = Twilio::Version->new($domain);
  $version->{version} = 'v1';

  my $list    = 'Twilio::Rest::Demo::V1::ThingList'->new($version);
  my $context = $list->get_context('T1');

  isa_ok($context->parts,       'Twilio::Rest::Demo::V1::Thing::PartList');
  isa_ok($context->parts('P1'), 'Twilio::Rest::Demo::V1::Thing::PartContext');
  isa_ok($context->notes,       'Twilio::Rest::Demo::V1::Thing::NoteList');
  ok(!$context->notes->can('get_context'), 'a child with no instance has no context');
  isa_ok($context->data,           'Twilio::Rest::Demo::V1::Thing::DataContext');
  isa_ok($list->kinds,             'Twilio::Rest::Demo::V1::Thing::KindList');
  isa_ok($context->sections->rows, 'Twilio::Rest::Demo::V1::Thing::Section::RowList');

  $http->mock(200, { sid => 'T1', name => 'one' });
  my $thing_instance = $context->fetch({ deep => 1 });
  like(($http->requests)[-1]{url}, qr{/v1/Things/T1[.]json\?Deep=true\z}, 'options on a fetch');

  isa_ok($thing_instance->parts('P1'), 'Twilio::Rest::Demo::V1::Thing::PartContext');
  like(
    ($context->data)->{uri},
    qr{\A/Things/T1/Data[.]json\z},
    'a singleton uses the id of its parent'
  );

  $http->mock(200, { name => 'total' });
  is($list->kinds->fetch->name, 'total', 'a fetch on a list');

  is($models{'Thing::Data'}{context}{own}, undef, 'a singleton has no id of its own');
  is($models{'Thing::Part'}{context}{own}, 'sid', 'other instances do');

  my $part = Twilio::Generator::Emit::module($models{'Thing::Part'});
  unlike($part, qr/_build_instance/, 'nothing is built when nothing answers with an instance');

  my $section_code = Twilio::Generator::Emit::module($section);
  unlike($section_code, qr/^package \S+SectionInstance/m, 'a section has no instance class');

  my $parent_pod = Twilio::Generator::Emit::module($thing);
  like($parent_pod, qr/require \S+Thing::Part;/, 'a child is loaded when it is reached');
  like($parent_pod, qr/->fetch\(\\%options\)/,   'the call with options is documented');
  like($parent_pod, qr/=head2 parts/,            'children are documented');
  like($parent_pod, qr/C<deep>/,                 'fetch options are documented');
};

subtest 'a family that does not fit stops generation' => sub {
  my @cases = (
    [
      'a method with a reserved name',
      qr/method read is reserved/,
      sub {
        $_[0]{paths}{'/v1/Things/{Sid}.json'}{'x-twilio'}{dependentProperties} =
          { read => { resource_url => '/v1/Things/{thing_sid}/Parts.json' } };
      },
    ],
    [
      'a method that is also a field',
      qr/method name is also a field/,
      sub {
        $_[0]{paths}{'/v1/Things/{Sid}.json'}{'x-twilio'}{dependentProperties} =
          { name => { resource_url => '/v1/Things/{thing_sid}/Parts.json' } };
      },
    ],
    [
      'a child with an extra parameter',
      qr/its path does not fit the parameters of its parent/,
      sub {
        my ($document) = @_;
        $document->{paths}{'/v1/Things/{ThingSid}/{Extra}/Parts.json'} =
          delete $document->{paths}{'/v1/Things/{ThingSid}/Parts.json'};
      },
    ],
    [
      'a child of an instance that does not exist',
      qr/its parent has no context/,
      sub { delete $_[0]{paths}{'/v1/Things/{Sid}.json'} },
    ],
    [
      'a level with no operations',
      qr/a level with no operations of its own/,
      sub {
        delete $_[0]{paths}{'/v1/Things.json'};
        delete $_[0]{paths}{'/v1/Things/{Sid}.json'};
      },
    ],
    [
      'a child of a list, when its parent is a singleton',
      qr/its parent has no list/,
      sub {
        my ($document) = @_;
        my $paths = $document->{paths};
        delete $paths->{$_} for grep { /ThingSid/ } keys %{$paths};
        $paths->{'/v1/Things.json'} = delete $paths->{'/v1/Things/{Sid}.json'};
      },
    ],
  );

  for my $case (@cases) {
    my ($name, $expected, $change) = @{$case};
    my $document = family();
    $change->($document);

    my $ok    = eval { all_models($document); 1 };
    my $error = $@;
    ok(!$ok, "$name: refused");
    like($error, $expected, "$name: says why");
  }
};

subtest 'top-level modules' => sub {
  my $top = {
    account_context => 'Demo::AccountContext',
    account_module  => 'Demo::Account',
    base_url        => 'https://demo.test',
    domain_class    => 'Twilio::Rest::Demo',
    roots           => [
      {
        mount   => 'accounts',
        module  => 'Demo::Account',
        list    => 'Demo::AccountList',
        context => 'Demo::AccountContext',
        own     => 'sid',
      }
    ],
    shortcuts      => [{ mount => 'things', module => 'Demo::Thing' }],
    version_class  => 'Twilio::Rest::Demo::V1',
    version_method => 'v1',
    version_path   => '2026-01-01',
  };
  my $model = {
    method   => 'demo',
    class    => 'Twilio::Rest::Demo',
    base_url => 'https://demo.test',
    versions => [$top],
    main     => $top,
  };

  my $version = Twilio::Generator::Emit::version($top);
  like($version, qr/\{version\} = '2026-01-01'/,                    'the version in URLs');
  like($version, qr/sub accounts .*sub account .*sub things/s,      'accounts and shortcuts');
  like($version, qr/return \$self->account->things\(\@arguments\)/, 'forwarded to the account');
  like($version, qr/get_account_sid/,                               'the account of the client');

  my $domain = Twilio::Generator::Emit::domain($model);
  like($domain, qr/\{base_url\} = 'https:\/\/demo.test'/,       'the host');
  like($domain, qr/sub v1 /,                                    'the version');
  like($domain, qr/return \$self->v1->accounts\(\@arguments\)/, 'forwarded to the version');
  like($domain, qr/=head2 things/,                              'documented');

  my $client = Twilio::Generator::Emit::client([$model]);
  like($client, qr/require Twilio::Rest::Demo;/,                'the domain');
  like($client, qr/return \$self->api->things\(\@arguments\)/,  'forwarded to the domain');
  like($client, qr/return \$self->api->account\(\@arguments\)/, 'with the account');
  unlike($client, qr/sub accounts/, 'accounts is left for its own domain');
  like($client, qr/=head2 things/, 'documented');

  compiles($_) or BAIL_OUT("Does not compile: $@") for $version, $domain, $client;
};

subtest 'descriptions reach the documentation' => sub {
  my $document = document();
  my $path     = '/v1/Accounts/{AccountSid}/Things.json';
  my $form     = 'application/x-www-form-urlencoded';
  my $body     = $document->{paths}{$path}{post}{requestBody}{content}{$form}{schema}{properties};

  $document->{paths}{$path}{post}{description} = 'Makes a thing.';
  $body->{Name}{description}                   = 'Its name, in the body.';
  $body->{Mode}{description}                   = 'The mode.';
  $body->{Tags}{items} = { '$ref' => '#/components/schemas/thing_enum_mode' };
  $document->{paths}{$path}{get}{parameters}[1]{description}             = 'Only with this status.';
  $document->{components}{schemas}{thing}{properties}{name}{description} = 'What it is called.';

  my $code = emit($document);

  like($code, qr/Makes a thing[.] Returns a C<ThingInstance>/, 'the operation');
  like($code, qr/=item C<\$name>\n\nIts name, in the body[.]/, 'a body value');
  like(
    $code,
    qr/=item C<mode>\n\nThe mode[.] One of C<fast> or C<slow>[.]/,
    'the choices of an enum'
  );
  like(
    $code,
    qr/=item C<tags>\n\nOne of C<fast> or C<slow>[.] An array/,
    'the choices inside an array'
  );
  like($code, qr/=item C<status>\n\nOnly with this status[.]/, 'a query parameter');
  like($code, qr/=item name\n\nWhat it is called[.]/,          'a field');
  like($code, qr/=item mode\n\nOne of C<fast> or C<slow>[.]/,  'the choices of a field');
  like($code, qr/\$client->demo->v1->accounts/,                'how to reach it');
};

subtest 'a resource of an account has a shortcut, and others do not' => sub {
  my $model = model(document(), 'api');
  is($model->{calls}{list}, '$client->things', 'the account');

  my %models = map { ($_->{module} =~ s/.*V1:://r) => $_ } all_models(family(), 'api');
  like($models{'Thing::Part'}{calls}{list}, qr/\A\$client->api->/, 'another root');
};

subtest 'how a resource is reached' => sub {
  my %models = map { ($_->{module} =~ s/.*V1:://r) => $_ } all_models(family());

  is($models{Thing}{calls}{list},    '$client->demo->v1->things',       'the root');
  is($models{Thing}{calls}{context}, '$client->demo->v1->things($sid)', 'one of them');
  is(
    $models{'Thing::Part'}{calls}{list},
    '$client->demo->v1->things($thing_sid)->parts',
    'below the root'
  );
  is(
    $models{'Thing::Part'}{calls}{context},
    '$client->demo->v1->things($thing_sid)->parts($sid)',
    'one of those'
  );
  is(
    $models{'Thing::Data'}{calls}{context},
    '$client->demo->v1->things($thing_sid)->data',
    'a singleton'
  );
  is($models{'Thing::Kind'}{calls}{list}, '$client->demo->v1->things->kinds', 'below a list');
  is(
    $models{'Thing::Section::Row'}{calls}{list},
    '$client->demo->v1->things($thing_sid)->sections->rows',
    'below a section'
  );
};

subtest 'option names' => sub {
  is(option_name('StatusCallback'), 'status_callback',  'plain');
  is(option_name('DateSent<'),      'date_sent_before', 'before');
  is(option_name('DateSent>'),      'date_sent_after',  'after');

  is(option_name('Parameter1.Name'), 'parameter1_name', 'dot');
  is(option_name('EId'),             'e_id',            'two capitals at the start, as in Python');

  my $ok    = eval { option_name('X-Header'); 1 };
  my $error = $@;
  ok(!$ok, 'a name with a dash is refused');
  like($error, qr/Cannot name an option from 'X-Header'/, 'says why');
};

subtest 'anything with no rule stops generation' => sub {
  my $list_path = '/v1/Accounts/{AccountSid}/Things.json';
  my $item_path = '/v1/Accounts/{AccountSid}/Things/{Sid}.json';
  my $form      = 'application/x-www-form-urlencoded';

  my @cases = (
    [
      'unknown request format',
      qr/CreateThing Name: no rule for format 'secret'/,
      sub {
        $_[0]{paths}{$list_path}{post}{requestBody}{content}{$form}{schema}{properties}{Name}
          {format} = 'secret';
      },
    ],
    [
      'unknown field format',
      qr/Field name: no rule for format 'secret'/,
      sub { $_[0]{components}{schemas}{thing}{properties}{name}{format} = 'secret' },
    ],
    [
      'array of arrays',
      qr/CreateThing Tags: no rule for an array of arrays/,
      sub {
        $_[0]{paths}{$list_path}{post}{requestBody}{content}{$form}{schema}{properties}{Tags}{items}
          = { type => 'array', items => { type => 'string' } };
      },
    ],
    [
      'array of maps',
      qr/CreateThing Tags: no rule for an array of maps/,
      sub {
        $_[0]{paths}{$list_path}{post}{requestBody}{content}{$form}{schema}{properties}{Tags}{items}
          = { type => 'object', format => 'prefixed-collapsible-map-Tags' };
      },
    ],
    [
      'unknown format in an array',
      qr/CreateThing Tags: no rule for format 'secret'/,
      sub {
        $_[0]{paths}{$list_path}{post}{requestBody}{content}{$form}{schema}{properties}{Tags}
          {items}{format} = 'secret';
      },
    ],
    [
      'header parameter',
      qr/CreateThing: no rule for header parameter X-Thing/,
      sub {
        push @{ $_[0]{paths}{$list_path}{post}{parameters} },
          { in => 'header', name => 'X-Thing', schema => {} };
      },
    ],
    [
      'query parameter on create',
      qr/CreateThing: no rule for query parameter Extra/,
      sub {
        push @{ $_[0]{paths}{$list_path}{post}{parameters} },
          { in => 'query', name => 'Extra', schema => {} };
      },
    ],
    [
      'header parameter on a list',
      qr/ListThing: no rule for header parameter X-Thing/,
      sub {
        push @{ $_[0]{paths}{$list_path}{get}{parameters} },
          { in => 'header', name => 'X-Thing', schema => {} };
      },
    ],
    [
      'JSON body',
      qr/CreateThing: no rule for a body of application\/json/,
      sub { $_[0]{paths}{$list_path}{post}{requestBody}{content} = { 'application/json' => {} } },
    ],
    [
      'two kinds of body',
      qr/CreateThing: no rule for a body of/,
      sub { $_[0]{paths}{$list_path}{post}{requestBody}{content}{'text/plain'} = {} },
    ],
    [
      'query parameter on a delete',
      qr/DeleteThing: no rule for query parameter Extra/,
      sub {
        push @{ $_[0]{paths}{$item_path}{delete}{parameters} },
          { in => 'query', name => 'Extra', schema => {} };
      },
    ],
    [
      'body on a fetch',
      qr/FetchThing: no rule for a body here/,
      sub { $_[0]{paths}{$item_path}{get}{requestBody} = {} },
    ],
    [
      'body on a delete',
      qr/DeleteThing: no rule for a body here/,
      sub { $_[0]{paths}{$item_path}{delete}{requestBody} = {} },
    ],
    [
      'update on a list',
      qr/UpdateThing: no rule for update on a list/,
      sub { $_[0]{paths}{$list_path}{put} = { operationId => 'UpdateThing' } },
    ],
    [
      'create on an instance',
      qr/CreateThing: no rule for create on an instance/,
      sub { $_[0]{paths}{$item_path}{put} = { operationId => 'CreateThing' } },
    ],
    [
      'no records',
      qr/ListThing: expected one list of records, found 0/,
      sub {
        delete $_[0]{paths}{$list_path}{get}{responses}{200}{content}{'application/json'}{schema}
          {properties}{things};
      },
    ],
    [
      'two lists of records',
      qr/ListThing: expected one list of records, found 2/,
      sub {
        $_[0]{paths}{$list_path}{get}{responses}{200}{content}{'application/json'}{schema}
          {properties}{others} = array_of_things();
      },
    ],
    [
      'required query parameter',
      qr/ListThing Extra: no rule for a required query parameter/,
      sub {
        push @{ $_[0]{paths}{$list_path}{get}{parameters} },
          { in => 'query', name => 'Extra', required => 1, schema => {} };
      },
    ],
    [
      'no schema for a response',
      qr/FetchThing: no schema for its response/,
      sub { $_[0]{paths}{$item_path}{get}{responses} = { 200 => {} } },
    ],
    [
      'a field read in two ways',
      qr/field name is read in two ways/,
      sub {
        my ($document) = @_;
        my $schemas = $document->{components}{schemas};
        $schemas->{other} = { properties => { name => { type => 'string', format => 'date' } } };
        $document->{paths}{$item_path}{get}{responses}{200} =
          response({ '$ref' => '#/components/schemas/other' });
      },
    ],
    [
      'reserved field',
      qr/Field fetch is reserved/,
      sub { $_[0]{components}{schemas}{thing}{properties}{fetch} = { type => 'string' } }
    ],
    [
      'reference outside the schemas',
      qr/Cannot follow #\/other/,
      sub {
        $_[0]{paths}{$list_path}{post}{requestBody}{content}{$form}{schema}{properties}{Name} =
          { '$ref' => '#/other' };
      },
    ],
    [
      'reference to nothing',
      qr/No schema missing/,
      sub {
        $_[0]{paths}{$list_path}{post}{requestBody}{content}{$form}{schema}{properties}{Name} =
          { '$ref' => '#/components/schemas/missing' };
      },
    ],
  );

  for my $case (@cases) {
    my ($name, $expected, $change) = @{$case};
    my $document = document();
    $change->($document);

    my $ok    = eval { model($document); 1 };
    my $error = $@;
    ok(!$ok, "$name: refused");
    like($error, $expected, "$name: says why");
  }
};

done_testing;

sub model {
  my ($document, $domain) = @_;

  my $spec    = Twilio::Generator::Spec->new($domain // 'demo', 'v1', $document);
  my $tree    = Twilio::Generator::Tree::build($spec);
  my ($thing) = grep { $_->{class} eq 'Account::Thing' } @{ $tree->{resources} };
  return Twilio::Generator::Resource::build($spec, $tree, $thing);
}

sub emit {
  my ($document) = @_;
  return Twilio::Generator::Emit::module(model($document));
}

sub load_generated {
  my ($code) = @_;
  compiles($code) or BAIL_OUT("The generated code does not compile: $@");
  return;
}

# This is the one place here where a string has to be compiled, because that is the output.
sub compiles {
  my ($code) = @_;
  no warnings 'redefine';    ## no critic (ProhibitNoWarnings)
  return eval "$code; 1";    ## no critic (ProhibitStringyEval)
}

sub list {
  my $http = Twilio::Http::FakeClient->new;
  my $client =
    Twilio::Rest::Client->new('ACxx', 'token', { http_client => $http, environment => {} });
  my $domain = Twilio::Domain->new($client);
  $domain->{base_url} = 'https://demo.test';
  my $version = Twilio::Version->new($domain);
  $version->{version} = 'v1';
  return ("${NAMESPACE}ThingList"->new($version, $ACCOUNT), $http);
}

sub all_models {
  my ($document, $domain) = @_;

  my $spec = Twilio::Generator::Spec->new($domain // 'demo', 'v1', $document);
  my $tree = Twilio::Generator::Tree::build($spec);
  return map { Twilio::Generator::Resource::build($spec, $tree, $_) } @{ $tree->{resources} };
}

# A parent with one child of each kind.
sub family {
  my $item = sub {
    my ($type, $parent, %operations) = @_;
    return {
      'x-twilio' => { pathType => $type, defined $parent ? (parent => $parent) : () },
      %operations
    };
  };
  my $answer = { responses => { 200 => response(thing_reference()) } };
  my $query  = { name => 'Deep', in => 'query', schema => { type => 'boolean' } };

  return {
    paths => {
      '/v1/Things.json'       => $item->('list', undef),
      '/v1/Things/{Sid}.json' => $item->(
        'instance', undef,
        get => { %{$answer}, operationId => 'FetchThing', parameters => [$query] }
      ),
      '/v1/Things/{ThingSid}/Parts.json'         => $item->('list',     '/Things/{Sid}.json'),
      '/v1/Things/{ThingSid}/Parts/{Sid}.json'   => $item->('instance', '/Things/{Sid}.json'),
      '/v1/Things/{ThingSid}/Notes.json'         => $item->('list',     '/Things/{Sid}.json'),
      '/v1/Things/{ThingSid}/Data.json'          => $item->('instance', '/Things/{Sid}.json'),
      '/v1/Things/{ThingSid}/Sections.json'      => $item->('list',     '/Things/{Sid}.json'),
      '/v1/Things/{ThingSid}/Sections/Rows.json' =>
        $item->('list', '/Things/{ThingSid}/Sections.json'),
      '/v1/Things/Kinds.json' =>
        $item->('list', '/Things.json', get => { %{$answer}, operationId => 'FetchKind' }),
    },
    components => {
      schemas => {
        thing => { properties => { name => { type => 'string' }, sid => { type => 'string' } } },
      },
    },
  };
}

sub thing_reference {
  return { '$ref' => '#/components/schemas/thing' };
}

sub array_of_things {
  return { type => 'array', items => thing_reference() };
}

sub response {
  my ($schema) = @_;
  return { content => { 'application/json' => { schema => $schema } } };
}

sub path_parameters {
  my (@names) = @_;
  return [map { { name => $_, in => 'path', schema => { type => 'string' } } } @names];
}

sub form {
  my (@required) = @_;

  my %properties = (
    Active => { type   => 'boolean' },
    Mode   => { '$ref' => '#/components/schemas/thing_enum_mode' },
    Name   => { type   => 'string' },
    Size   => { type   => 'integer' },
    Tags   => { type   => 'array',  items  => { type => 'string' } },
    When   => { type   => 'string', format => 'date-time' },
  );
  return {
    content => {
      'application/x-www-form-urlencoded' =>
        { schema => { type => 'object', required => \@required, properties => \%properties } }
    },
  };
}

# A fresh copy each time, because each failure case changes it.
sub document {
  my $query = sub {
    my ($name, %schema) = @_;
    return { name => $name, in => 'query', schema => { type => 'string', %schema } };
  };

  return {
    paths => {
      '/v1/Accounts/{AccountSid}/Things.json' => {
        description => 'A list of <things >.',
        'x-twilio'  => { pathType => 'list' },
        get         => {
          operationId => 'ListThing',
          parameters  => [
            @{ path_parameters('AccountSid') },
            $query->('Status'),
            $query->('Created<', format => 'date-time'),
            $query->('PageSize'),
            $query->('Page'),
            $query->('PageToken'),
            $query->('AddOnsData', type => 'object', format => 'prefixed-collapsible-map-AddOns'),
          ],
          responses => {
            200 => response(
              {
                type       => 'object',
                properties => { things => array_of_things(), meta => { type => 'object' } }
              }
            ),
          },
        },
        post => {
          operationId => 'CreateThing',
          parameters  => path_parameters('AccountSid'),
          requestBody => form(qw(Name Size)),
          responses   => { 201 => response(thing_reference()) },
        },
      },
      '/v1/Accounts/{AccountSid}/Things/{Sid}.json' => {
        'x-twilio' => { pathType => 'instance' },
        get        => {
          operationId => 'FetchThing',
          parameters  => path_parameters(qw(AccountSid Sid)),
          responses   => { 200 => response(thing_reference()) },
        },
        post => {
          operationId => 'UpdateThing',
          parameters  => path_parameters(qw(AccountSid Sid)),
          requestBody => form(),
          responses   => { 200 => response(thing_reference()) },
        },
        delete => {
          operationId => 'DeleteThing',
          parameters  => path_parameters(qw(AccountSid Sid)),
          responses   => { 204 => {} },
        },
      },
    },
    components => {
      schemas => {
        thing_enum_mode => { type => 'string', enum => [qw(fast slow)] },
        thing           => {
          properties => {
            date_created => { type   => 'string', format => 'date-time-rfc-2822' },
            mode         => { '$ref' => '#/components/schemas/thing_enum_mode' },
            name         => { type   => 'string' },
            sid          => { type   => 'string' },
          },
        },
      },
    },
  };
}

package Local::Date;

sub epoch { return 7 }
