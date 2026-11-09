use 5.016;
use warnings;

use Test::More;

use lib 'tools/lib';

use Twilio::Domain;
use Twilio::Generator;
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

subtest 'headers, query options and JSON bodies' => sub {
  my $document = document();
  my $paths    = $document->{paths};
  my $list     = $paths->{'/v1/Accounts/{AccountSid}/Things.json'};
  my $item     = $paths->{'/v1/Accounts/{AccountSid}/Things/{Sid}.json'};
  my $header   = sub { { in => 'header', name => $_[0], schema => { type => 'string' } } };

  push @{ $list->{post}{parameters} }, $header->('X-Twilio-Webhook-Enabled'),
    { in => 'query', name => 'Extra', schema => { type => 'string' } },
    { in => 'query', name => 'Region', required => 1, schema => { type => 'string' } };
  push @{ $list->{get}{parameters} }, $header->('Ui-Version'),
    { in => 'query', name => 'Channel', required => 1, schema => { type => 'string' } };
  push @{ $item->{delete}{parameters} }, $header->('If-Match');
  $item->{post}{requestBody} = {
    required => 1,
    content  => {
      'application/json' => {
        schema => {
          required   => ['friendlyName'],
          properties => {
            friendlyName => { type => 'string', description => 'Its name.' },
            enabled      => { type => 'boolean' },
            sendAt       => { type => 'string', format => 'date-time' },
            settings     => { type => 'object' },
          },
        },
      },
    },
  };

  local $NAMESPACE = 'Twilio::Rest::Demo::V1::Sent::';
  my $code = emit($document) =~ s/V1::Account::/V1::Sent::/gr;
  load_generated($code);

  my ($things, $http) = list();
  $http->mock(201, { sid => 'TH1' });
  $things->create('one', 3, 'eu', { x_twilio_webhook_enabled => 'true', extra => 'e' });
  my $request = ($http->requests)[-1];
  is($request->{headers}{'X-Twilio-Webhook-Enabled'}, 'true', 'a header, from an option');
  like($request->{url}, qr/[?]Extra=e&Region=eu\z/,
    'query values on a create, required ones after the body\'s');
  like($request->{content}, qr/Name=one/, 'and the body stays');

  $http->mock(201, { sid => 'TH2' });
  $things->create('two', 4, 'us');
  ok(!exists(($http->requests)[-1]{headers}{'X-Twilio-Webhook-Enabled'}), 'no option, no header');

  $http->mock(200, { things => [], meta => {} });
  $things->read('sms', { ui_version => '2' }, 5);
  $request = ($http->requests)[-1];
  like($request->{url}, qr/Channel=sms/, 'a required filter comes first');
  is($request->{headers}{'Ui-Version'}, '2', 'and a header on a list');

  $http->mock(200, { things => [], meta => {} });
  $things->page({ channel => 'voice' });
  like(($http->requests)[-1]{url}, qr/Channel=voice/, 'page takes it with the options');

  my $thing = $things->get_context('TH1');
  $http->mock(200, { sid => 'TH1' });
  my $moment = bless {}, 'Local::Date';
  $thing->update(
    { friendlyName => 'Mine', enabled => 1, sendAt => $moment, settings => { at => $moment } });
  $request = ($http->requests)[-1];
  is($request->{headers}{'Content-Type'}, 'application/json', 'a JSON body says so');
  like($request->{content}, qr/"enabled":true/, 'a boolean is a JSON boolean, not 1');
  is_deeply(
    Twilio::Json::decode($request->{content}),
    {
      friendlyName => 'Mine',
      enabled      => Twilio::Json::decode('true'),
      sendAt       => '1970-01-01T00:00:07Z',
      settings     => { at => '1970-01-01T00:00:07Z' },
    },
    'with Twilio\'s names, a JSON boolean, and dates written as text'
  );

  $http->mock(204, q{});
  $thing->delete({ if_match => 'abc' });
  is(($http->requests)[-1]{headers}{'If-Match'}, 'abc', 'a header on a delete');

  like(
    $code,
    qr/=item C<friendlyName>\n\nRequired[.] Its name[.]/,
    'the fields of the body are documented'
  );
  like($code, qr/->update\(\\%body\)/, 'and how to pass it');
};

subtest 'an answer in SCIM is asked for by name' => sub {
  my $document = document();
  my $fetch    = $document->{paths}{'/v1/Accounts/{AccountSid}/Things/{Sid}.json'}{get};
  $fetch->{responses}{200}{content} =
    { 'application/scim+json' => delete $fetch->{responses}{200}{content}{'application/json'} };

  local $NAMESPACE = 'Twilio::Rest::Demo::V1::Scim::';
  load_generated(emit($document) =~ s/V1::Account::/V1::Scim::/gr);

  my ($things, $http) = list();
  $http->mock(200, { sid => 'TH1' });
  $things->get_context('TH1')->fetch;
  is(($http->requests)[-1]{headers}{Accept}, 'application/scim+json', 'Accept');
};

subtest 'update and delete on a list, create and patch on an instance' => sub {
  my $document = document();
  my $paths    = $document->{paths};
  my $list     = $paths->{'/v1/Accounts/{AccountSid}/Things.json'};
  my $item     = $paths->{'/v1/Accounts/{AccountSid}/Things/{Sid}.json'};
  my $answer   = { 200 => response(thing_reference()) };
  my $before   = { in  => 'query', name => 'Before', schema => { type => 'string' } };

  $list->{patch} = {
    operationId => 'UpdateThings',
    parameters  => path_parameters('AccountSid'),
    requestBody => form('Mode'),
    responses   => $answer,
  };
  $list->{delete} = {
    operationId => 'DeleteThings',
    parameters  => [@{ path_parameters('AccountSid') }, $before],

    # An error with a body is still a delete that returns true.
    responses => { 204 => {}, 400 => response({ type => 'object' }) },
  };
  $item->{put}  = { %{ delete $item->{post} }, requestBody => form('Name') };
  $item->{post} = {
    operationId => 'CreateThingCopy',
    parameters  => path_parameters(qw(AccountSid Sid)),
    responses   => { 201 => response(thing_reference()) },
  };
  $item->{patch} = {
    operationId => 'PatchThing',
    parameters  => path_parameters(qw(AccountSid Sid)),
    requestBody => {
      content => {
        'application/json' => { schema => { properties => { name => { type => 'string' } } } }
      }
    },
    responses => $answer,
  };

  local $NAMESPACE = 'Twilio::Rest::Demo::V1::Verbs::';
  my $code = emit($document) =~ s/V1::Account::/V1::Verbs::/gr;
  load_generated($code);

  my ($things, $http) = list();
  $http->mock(200, { sid => 'TH0', mode => 'slow' });
  my $updated = $things->update('slow', { name => 'all' });
  my $request = ($http->requests)[-1];
  is($request->{method}, 'PATCH', 'update on a list sends the spec\'s method');
  like($request->{url}, qr{/Accounts/AC1/Things[.]json\z}, 'to the list\'s URL');
  is($request->{content}, 'Mode=slow&Name=all', 'with its required value first');
  isa_ok($updated, "${NAMESPACE}ThingInstance");

  $http->mock(204, q{});
  is($things->delete({ before => 'x' }), 1, 'delete on a list returns true');
  $request = ($http->requests)[-1];
  is($request->{method}, 'DELETE', 'delete on a list');
  like($request->{url}, qr{/Things[.]json[?]Before=x\z}, 'with its query option');

  my $context = $things->get_context('TH1');
  $http->mock(201, { sid => 'TH2' });
  is($context->create->sid, 'TH2', 'create on an instance builds the answer');
  $request = ($http->requests)[-1];
  is($request->{method}, 'POST', 'create on an instance');
  like($request->{url}, qr{/Things/TH1[.]json\z}, 'to the instance\'s URL');

  $http->mock(200, { sid => 'TH1', name => 'p' });
  is($context->patch({ name => 'p' })->name, 'p', 'patch builds the answer');
  $request = ($http->requests)[-1];
  is($request->{method},                  'PATCH',            'patch sends PATCH');
  is($request->{headers}{'Content-Type'}, 'application/json', 'with its JSON body');
  is($request->{content},                 '{"name":"p"}',     'as given');

  $http->mock(200, { sid => 'TH1', name => 'u' });
  is($context->update('u')->name,   'u',   'update next to patch');
  is(($http->requests)[-1]{method}, 'PUT', 'update sends PUT when the spec says so');

  $http->mock(200, { sid => 'TH1' });
  my $thing = $context->fetch;
  $http->mock(201, { sid => 'TH3' });
  is($thing->create->sid, 'TH3', 'an instance has create');
  $http->mock(200, { sid => 'TH1', name => 'q' });
  is($thing->patch({ name => 'q' })->name, 'q', 'and patch');
  like(($http->requests)[-1]{url}, qr{/Things/TH1[.]json\z}, 'on its own URL');

  like($code, qr/^=head2 patch\n\n  my \$thing = \S+->patch\(\\%body\);/m, 'patch is documented');
  like($code, qr/^=head2 update\n\n  my \$thing = \S+->things->update/m, 'and update on the list');
  like($code, qr/->things->update\(\$mode, \\%options\);/,               'with its arguments');
  like($code, qr/^=head2 delete\n\n  \S+->things->delete\(\\%options\);/m, 'and delete on it');
  my $listed = 'It has C<create>, C<fetch>, C<patch>, C<update> and C<delete>';
  ok(index($code, $listed) >= 0, 'the instance lists them');
};

subtest 'the v1.0 standard pages by token and has its own errors' => sub {
  my $document = document();
  my $paths    = $document->{paths};
  my $list     = $paths->{'/v1/Accounts/{AccountSid}/Things.json'};
  my $item     = $paths->{'/v1/Accounts/{AccountSid}/Things/{Sid}.json'};
  my $paging   = sub {
    my ($name, %extra) = @_;
    return { in => 'query', name => $name, schema => { type => 'string' }, %extra };
  };
  $document->{info}    = { 'x-twilio' => { apiStandards => 'v1.0' } };
  $document->{servers} = [{ url => 'https://demo.test' }];
  push @{ $list->{get}{parameters} }, $paging->('pageSize'), $paging->('pageToken');
  push @{ $item->{get}{parameters} }, $paging->('pageToken', required => 1);

  my $model = model($document);
  ok($model->{v1_standard}, 'the spec says v1.0');
  my @filters = map { $_->{wire} } @{ $model->{list}{read}{filters} };
  ok(!grep({ /\Apage(?:Size|Token)\z/ } @filters), 'a list sends its paging values from page');
  is_deeply([map { $_->{wire} } @{ $model->{context}{fetch}{options} }],
    ['pageToken'], 'a fetch takes them as options, even when required');

  local $NAMESPACE = 'Twilio::Rest::Demo::V1::Tokens::';
  my $code = emit($document) =~ s/V1::Account::/V1::Tokens::/gr;
  like($code, qr/use parent 'Twilio::TokenPaginationPage';/, 'its page moves by token');
  like(
    $code,
    qr/my \(\$self, \$options, \$page_size, \$page_token\) = \@_;/,
    'page takes no page number'
  );
  unlike($code, qr/PageSize|PageToken/, 'nor the classic names');
  like($code, qr/TokenPaginationPage>[.] This API pages by token/, 'which is documented');
  load_generated($code);

  my ($things, $http) = list();
  $http->mock(200, { things => [{ sid => 'TH1' }], meta => { pageSize => 1, nextToken => 'T2' } });
  $http->mock(200, { things => [{ sid => 'TH2' }], meta => { pageSize => 1 } });
  my @read = $things->read({ status => 'on' }, undef, 1);
  is_deeply([map { $_->sid } @read], [qw(TH1 TH2)], 'both pages are read');
  my ($first_page, $next_page) = $http->requests;
  like($first_page->{url}, qr/[?]Status=on&pageSize=1\z/,           'the first asks for a size');
  like($next_page->{url},  qr/Status=on&pageSize=1&pageToken=T2\z/, 'the next one uses the token');

  my $spec = Twilio::Generator::Spec->new('demo', 'v1', $document);
  my $top  = Twilio::Generator::top_level($spec, Twilio::Generator::Tree::build($spec));
  like(
    Twilio::Generator::Emit::version($top),
    qr/use parent 'Twilio::ApiV1Version';/,
    'its version raises v1.0 errors'
  );
  delete $document->{info};
  $spec = Twilio::Generator::Spec->new('demo', 'v1', $document);
  $top  = Twilio::Generator::top_level($spec, Twilio::Generator::Tree::build($spec));
  like(
    Twilio::Generator::Emit::version($top),
    qr/use parent 'Twilio::Version';/,
    'and other versions keep the classic ones'
  );
};

subtest 'only answers below 400 give fields and Accept' => sub {
  my $document = document();
  my $item     = $document->{paths}{'/v1/Accounts/{AccountSid}/Things/{Sid}.json'};
  $document->{components}{schemas}{problem} =
    { properties => { scimType => { type => 'string' }, detail => { type => 'string' } } };
  my $problem = { '$ref' => '#/components/schemas/problem' };

  $item->{get}{responses} = { 302 => response(thing_reference()), 404 => response($problem) };
  $item->{delete}{responses} =
    { 204 => {}, 404 => { content => { 'application/scim+json' => { schema => $problem } } } };

  my $model  = model($document);
  my @fields = map { $_->{name} } @{ $model->{fields} };
  ok(!grep({ $_ eq 'scimType' } @fields),   'an error schema gives no fields');
  ok(scalar(grep { $_ eq 'name' } @fields), 'a redirect does, as Bulk Exports\' FetchDay needs');
  ok(!exists $model->{context}{delete}{accept}, 'a delete with SCIM errors asks for nothing');
};

subtest 'an instance finds its own id in its sid or id' => sub {
  my $document   = document();
  my $properties = $document->{components}{schemas}{thing}{properties};
  $properties->{id} = delete $properties->{sid};
  is(model($document)->{context}{own_field}, 'id', 'a SCIM user\'s {UserSid} is its id');

  delete $properties->{id};
  my $ok = eval { model($document); 1 };
  ok(!$ok, 'with neither, it stops');
  like($@, qr{Accounts/Things: no field holds its own id sid}, 'and says why');

  my $paths = $document->{paths};
  delete $paths->{'/v1/Accounts/{AccountSid}/Things.json'};
  $paths->{'/v1/Accounts/{AccountSid}/Things/{Sid}.json'}{'x-twilio'}{mountName} = 'things';
  is(model($document)->{context}{own_field}, 'sid', 'without a list, its context knows the id');
};

subtest 'answers written in place, oneOf, and a delete with a body' => sub {
  my $document = document();
  my $paths    = $document->{paths};
  my $schemas  = $document->{components}{schemas};
  my $list     = $paths->{'/v1/Accounts/{AccountSid}/Things.json'};
  my $item     = $paths->{'/v1/Accounts/{AccountSid}/Things/{Sid}.json'};
  $schemas->{other} = { properties => { size => { type => 'integer' } } };
  $list->{get}{responses}{200} = response(
    {
      properties => {
        things   => { type => 'array', items => { %{ $schemas->{thing} } } },
        warnings => { type => 'array', items => { type => 'string' } },
      }
    }
  );
  $item->{get}{responses}{200} =
    response({ oneOf => [thing_reference(), { '$ref' => '#/components/schemas/other' }] });
  $item->{delete}{responses} = { 202 => response(thing_reference()) };

  my $model = model($document);
  is($model->{records_key}, 'things', 'records written in place are records, not plain values');
  is_deeply(
    [map { $_->{name} } @{ $model->{fields} }],
    [qw(date_created mode name sid size)],
    'a oneOf gives the fields of each of its objects'
  );

  local $NAMESPACE = 'Twilio::Rest::Demo::V1::Shapes::';
  my $code = emit($document) =~ s/V1::Account::/V1::Shapes::/gr;
  my $text = $code           =~ s/\s+/ /gr;
  ok(
    index($text, '->delete; Returns a C<ThingInstance>.') >= 0,
    'a delete with a body documents what it returns'
  );
  load_generated($code);

  my ($things, $http) = list();
  $http->mock(202, { sid => 'TH1', size => 3 });
  my $deleted = $things->get_context('TH1')->delete;
  isa_ok($deleted, "${NAMESPACE}ThingInstance", 'what the delete returns');
  is($deleted->size, 3, 'with its fields');
};

subtest 'a delete can be all that builds the resource' => sub {
  my $document = document();
  my $item     = $document->{paths}{'/v1/Accounts/{AccountSid}/Things/{Sid}.json'};
  delete @{$item}{qw(get post)};
  $item->{delete}{responses} = { 202 => response(thing_reference()) };

  local $NAMESPACE = 'Twilio::Rest::Demo::V1::DeleteOnly::';
  load_generated(emit($document) =~ s/V1::Account::/V1::DeleteOnly::/gr);

  my ($things, $http) = list();
  $http->mock(202, { sid => 'TH1', name => 'gone' });
  my $deleted = $things->get_context('TH1')->delete;
  isa_ok($deleted, "${NAMESPACE}ThingInstance", 'what the delete returns');
  is($deleted->name, 'gone', 'with its fields');
};

subtest 'under the v1.0 standard, another object has a class of its own' => sub {
  my $document = document();
  my $paths    = $document->{paths};
  my $list     = $paths->{'/v1/Accounts/{AccountSid}/Things.json'};
  my $item     = $paths->{'/v1/Accounts/{AccountSid}/Things/{Sid}.json'};
  my $note     = { type => 'object', properties => { message => { type => 'string' } } };
  $document->{info}          = { 'x-twilio' => { apiStandards => 'v1.0' } };
  $document->{servers}       = [{ url => 'https://demo.test' }];
  $item->{post}{responses}   = { 200 => response(thing_reference()), 202 => response($note) };
  $item->{delete}{responses} = { 202 => response({ %{$note} }) };
  $list->{post}{responses}   = { 202 => {} };

  my $model = model($document);
  is_deeply(
    [map { $_->{name} } @{ $model->{answer_classes} }],
    ['UpdateThing202ResponseInstance'],
    'one class for one object, named as twilio-php names it'
  );
  is_deeply($model->{answer_classes}[0]{methods}, [qw(update delete)], 'which both return');
  ok(!grep({ $_->{name} eq 'message' } @{ $model->{fields} }), 'the resource keeps its own fields');

  local $NAMESPACE = 'Twilio::Rest::Demo::V1::Notes::';
  my $code = emit($document) =~ s/V1::Account::/V1::Notes::/gr;
  my $text = $code           =~ s/\s+/ /gr;
  my $told = 'Returns a C<UpdateThing202ResponseInstance> when Twilio answers 202, and a '
    . 'C<ThingInstance> otherwise.';
  ok(index($text, $told) >= 0, 'the choice is documented');
  ok(
    index($text, '=head1 UpdateThing202ResponseInstance Returned by C<update> and C<delete>') >= 0,
    'and so is the class'
  );
  load_generated($code);

  my ($things, $http) = list();
  my $thing = $things->get_context('TH1');
  $http->mock(202, { message => 'later' });
  my $noted = $thing->update;
  isa_ok($noted, "${NAMESPACE}UpdateThing202ResponseInstance", 'an update answered with 202');
  is($noted->message, 'later', 'which has its field');
  $http->mock(200, { sid => 'TH1', name => 'done' });
  isa_ok($thing->update, "${NAMESPACE}ThingInstance", 'and answered with 200');
  $http->mock(202, { message => 'gone' });
  is($thing->delete->message, 'gone', 'a delete returns the same kind of object');
  $http->mock(202, q{});
  is($things->create('a', 1), 1, 'a create answered with no body returns true');

  $document->{paths} = { %{$paths} };
  delete $document->{info};
  ok(!model($document)->{answer_classes}, 'older APIs have one object per resource');
};

subtest 'records that are plain values' => sub {
  my $document = document();
  my $list     = $document->{paths}{'/v1/Accounts/{AccountSid}/Things.json'};
  $document->{info} = { 'x-twilio' => { apiStandards => 'v1.0' } };
  $list->{get}{responses}{200} = response(
    {
      properties =>
        { things => { type => 'array', items => { type => 'string', description => 'An id.' } } }
    }
  );
  delete $document->{components}{schemas}{thing}{properties}{sid};
  $document->{components}{schemas}{thing}{properties}{id} = { type => 'string' };

  my $model = model($document);
  my ($id) = grep { $_->{name} eq 'id' } @{ $model->{fields} };
  ok($id, 'each is an instance with an id');
  is($model->{context}{own_field}, 'id', 'which reaches its context');

  delete $document->{info};
  my $ok = eval { model($document); 1 };
  ok(!$ok, 'outside the v1.0 standard, they stop');
  like($@, qr/ListThing: no rule for records that are plain values/, 'and say why');
};

subtest 'an id named like a variable of every class' => sub {
  my $document = document();
  my $paths    = $document->{paths};
  my $item     = delete $paths->{'/v1/Accounts/{AccountSid}/Things/{Sid}.json'};
  $item->{$_}{parameters} = path_parameters(qw(AccountSid Version)) for qw(get post delete);
  $paths->{'/v1/Accounts/{AccountSid}/Things/{Version}.json'}  = $item;
  $document->{components}{schemas}{thing}{properties}{version} = { type => 'string' };

  my $model = model($document);
  is($model->{context}{own}, 'path_version', 'gets the name twilio-php gives it');

  my @warnings;
  local $SIG{__WARN__} = sub { push @warnings, @_ };
  ok(compiles(Twilio::Generator::Emit::module($model) =~ s/V1::Account::/V1::Versions::/gr),
    'the code compiles');
  is_deeply(\@warnings, [], 'and no variable hides another');
};

subtest 'an instance id need not end its path' => sub {
  my $document = {
    paths => {
      '/v1/Inquiries/Initialize' => {
        'x-twilio' => { pathType => 'list' },
        post       => {
          operationId => 'CreateInquiry',
          responses   => { 201 => response(thing_reference()) }
        },
      },
      '/v1/Inquiries/{InquiryId}/Initialize' => {
        'x-twilio' => { pathType => 'instance' },
        post       => {
          operationId => 'UpdateInquiry',
          parameters  => path_parameters('InquiryId'),
          responses   => { 200 => response(thing_reference()) },
        },
      },
    },
    components => { schemas => { thing => { properties => { sid => { type => 'string' } } } } },
  };

  my $spec = Twilio::Generator::Spec->new('demo', 'v1', $document);
  my ($inquiry) = @{ Twilio::Generator::Tree::build($spec)->{resources} };
  is($inquiry->{instance}{key}, 'InquiryId', 'the id its list does not hold is its own');

  my $model =
    Twilio::Generator::Resource::build($spec, Twilio::Generator::Tree::build($spec), $inquiry);
  is($model->{context}{own}, 'inquiry_id', 'and the context takes it');
  is_deeply(
    [map { $_->{literal} // "{$_->{parameter}}" } @{ $model->{context}{uri} }],
    ['/Inquiries/', '{inquiry_id}', '/Initialize'],
    'in the middle of its URL'
  );

  $document->{paths}{'/v1/Inquiries/{InquiryId}/{Step}/Initialize'} =
    delete $document->{paths}{'/v1/Inquiries/{InquiryId}/Initialize'};
  my $ok = eval { Twilio::Generator::Tree::build($spec); 1 };
  ok(!$ok, 'two ids beyond the list\'s are refused');
  like($@, qr/more than one id beyond its list's/, 'and it says why');
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
      'a child named like the new verbs',
      qr/method patch is reserved/,
      sub {
        $_[0]{paths}{'/v1/Things/{Sid}.json'}{'x-twilio'}{dependentProperties} =
          { patch => { resource_url => '/v1/Things/{thing_sid}/Parts.json' } };
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
      'a child of an instance that does not exist',
      qr/its parent has no context/,
      sub { delete $_[0]{paths}{'/v1/Things/{Sid}.json'} },
    ],
    [
      'a level with no operations',
      qr/a level with no operations of its own/,
      sub {
        my ($document) = @_;
        my $paths = $document->{paths};
        delete $paths->{$_} for grep { /Things[.]json|ThingSid|[{]Sid[}]/ } keys %{$paths};
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

# Shapes that twilio-php reaches, and that used to stop generation here.
subtest 'a child with ids its parent does not hold' => sub {
  my $document = family();
  $document->{paths}{'/v1/Things/{ThingSid}/{Extra}/Parts.json'} =
    delete $document->{paths}{'/v1/Things/{ThingSid}/Parts.json'};
  $document->{paths}{'/v1/Things/{ThingSid}/{Extra}/Parts/{Sid}.json'} =
    delete $document->{paths}{'/v1/Things/{ThingSid}/Parts/{Sid}.json'};

  my ($thing) = grep { $_->{class}{list} =~ /::ThingList\z/ } all_models($document);
  my $code = Twilio::Generator::Emit::module($thing);
  like($code, qr/^  my \(\$self, \$extra, \$sid\) = \@_;$/m, 'the extra id comes first');
  my $held = qr/\$self->\{version\}, \$self->\{solution\}\{sid\}/;
  like(
    $code,
    qr/PartList->new\($held, \$extra\)/,
    'and goes to the list after the ids of the parent'
  );
};

subtest 'an id in the URL of a list has its rule' => sub {
  my $day      = { name => 'Day', in => 'path', schema => { type => 'string', format => 'date' } };
  my $document = {
    paths => {
      '/v1/Days/{Day}/Things.json' => {
        'x-twilio' => { pathType => 'list' },
        get        => {
          operationId => 'ListThing',
          parameters  => [$day],
          responses   => { 200 => response({ properties => { things => array_of_things() } }) },
        },
      },
    },
    components => document()->{components},
  };

  my ($thing) = all_models($document);
  like(
    Twilio::Generator::Emit::module($thing),
    qr/path_segment\(Twilio::Serialize::iso8601_date\(\$day\)\)/,
    'a date, as twilio-php writes it'
  );
};

subtest 'a child that leaves out an id of its parent' => sub {
  my $document = family();
  $document->{paths}{'/v1/Things/Totals.json'} = {
    'x-twilio' => { pathType => 'instance', parent => '/Things/{Sid}.json' },
    get => { operationId => 'FetchTotal', responses => { 200 => response(thing_reference()) } },
  };

  my ($thing) = grep { $_->{class}{list} =~ /::ThingList\z/ } all_models($document);
  like(
    Twilio::Generator::Emit::module($thing),
    qr/TotalContext->new\(\$self->\{version\}\);/,
    'none of its parent\'s ids go to it'
  );
};

subtest 'a parent that no path describes' => sub {
  my $document = family();
  delete $document->{paths}{'/v1/Things.json'};
  delete $document->{paths}{'/v1/Things/{Sid}.json'};

  my %models = map { $_->{class}{list} => $_ } all_models($document);
  my ($thing) = grep { /::ThingList\z/ } keys %models;
  ok($thing, 'it is still there');
  like(Twilio::Generator::Emit::module($models{$thing}), qr/^sub parts \{/m, 'with its children');
  unlike(Twilio::Generator::Emit::module($models{$thing}), qr/^sub fetch \{/m, 'and nothing else');
};

subtest 'children of a singleton' => sub {
  my $document = family();
  my $paths    = $document->{paths};
  delete $paths->{$_} for grep { /ThingSid/ } keys %{$paths};
  $paths->{'/v1/Things.json'} = delete $paths->{'/v1/Things/{Sid}.json'};

  my ($thing) = grep { $_->{class}{context} =~ /::ThingContext\z/ } all_models($document);
  my $code = Twilio::Generator::Emit::module($thing);
  like($code, qr/^package \S+ThingContext;.*^sub kinds \{/ms, 'they hang from the singleton');
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
  like($version, qr/\{version\} = '2026-01-01'/,                     'the version in URLs');
  like($version, qr/ - Version 2026-01-01 of the Twilio REST API$/m, 'and in its documentation');

  my $versionless = Twilio::Generator::Emit::version(
    { %{$top}, version_path => q{}, version_method => 'versionless', account_context => undef });
  like($versionless, qr/\{version\} = ''/, 'a version with nothing in the URL');
  like(
    $versionless,
    qr/ - Version versionless of the Twilio REST API$/m,
    'is documented by its name'
  );
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
  like($code, qr/=item C<status>\n\nOnly with this status[.]/,          'a query parameter');
  like($code, qr/=item name\n\nWhat it is called[.]/,                   'a field');
  like($code, qr/=item mode\n\nOne of C<fast> or C<slow>[.]/,           'the choices of a field');
  like($code, qr/\$client->demo->v1->account\(\$account_sid\)->things/, 'how to reach it');
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
  is(Twilio::Generator::Types::header_option_name('X-Twilio-Webhook-Enabled'),
    'x_twilio_webhook_enabled', 'a header, as Python names it');
  is(Twilio::Generator::Types::header_option_name('If-Match'), 'if_match',         'another');
  is(option_name('StatusCallback'),                            'status_callback',  'plain');
  is(option_name('DateSent<'),                                 'date_sent_before', 'before');
  is(option_name('DateSent>'),                                 'date_sent_after',  'after');

  is(option_name('Parameter1.Name'), 'parameter1_name', 'dot');
  is(option_name('EId'),             'e_id',            'two capitals at the start, as in Python');
  is(option_name('A2PProfileBundleSid'), 'a2p_profile_bundle_sid', 'A2P is one word, as in Python');

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
      'required header',
      qr/CreateThing X-Thing: no rule for a required header parameter/,
      sub {
        push @{ $_[0]{paths}{$list_path}{post}{parameters} },
          { in => 'header', name => 'X-Thing', required => 1, schema => { type => 'string' } };
      },
    ],
    [
      'cookie parameter',
      qr/CreateThing: no rule for cookie parameter Crumb/,
      sub {
        push @{ $_[0]{paths}{$list_path}{post}{parameters} },
          { in => 'cookie', name => 'Crumb', schema => { type => 'string' } };
      },
    ],
    [
      'unknown format in a JSON body',
      qr/CreateThing Code: no rule for format 'secret'/,
      sub {
        $_[0]{paths}{$list_path}{post}{requestBody}{content} = {
          'application/json' => {
            schema => { properties => { Code => { type => 'string', format => 'secret' } } }
          }
        };
      },
    ],
    [
      'two kinds of body',
      qr/CreateThing: no rule for a body of/,
      sub { $_[0]{paths}{$list_path}{post}{requestBody}{content}{'text/plain'} = {} },
    ],
    [
      'required query parameter on a delete',
      qr/DeleteThing Extra: no rule for a required query parameter/,
      sub {
        push @{ $_[0]{paths}{$item_path}{delete}{parameters} },
          { in => 'query', name => 'Extra', required => 1, schema => {} };
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
      'patch on a list',
      qr/PatchThings: no rule for patch on a list/,
      sub { $_[0]{paths}{$list_path}{patch} = { operationId => 'PatchThings' } },
    ],
    [
      'list on an instance',
      qr/ListThingParts: no rule for list on an instance/,
      sub { $_[0]{paths}{$item_path}{put} = { operationId => 'ListThingParts' } },
    ],
    [
      'an answer that is not an object',
      qr/FetchThing: no rule for an answer that is not an object/,
      sub { $_[0]{paths}{$item_path}{get}{responses} = { 200 => response({ type => 'string' }) } },
    ],
    [
      'one status code with two objects',
      qr/FetchThing: answers 200 with two objects/,
      sub {
        $_[0]{info} = { 'x-twilio' => { apiStandards => 'v1.0' } };
        $_[0]{paths}{$item_path}{get}{responses}{200}{content}{'application/scim+json'} =
          { schema => { properties => { message => { type => 'string' } } } };
      },
    ],
    [
      'reserved field patch',
      qr/Field patch is reserved/,
      sub { $_[0]{components}{schemas}{thing}{properties}{patch} = { type => 'string' } }
    ],
    [
      'reserved field create',
      qr/Field create is reserved/,
      sub { $_[0]{components}{schemas}{thing}{properties}{create} = { type => 'string' } }
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
      'two fields with one method',
      qr/fields friendlyName and friendly_name are both friendly_name/,
      sub {
        my $properties = $_[0]{components}{schemas}{thing}{properties};
        $properties->{friendlyName}  = { type => 'string' };
        $properties->{friendly_name} = { type => 'string' };
      }
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
        'x-twilio'  => { pathType => 'list', parent => '/Accounts/{Sid}.json' },
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
        'x-twilio' => { pathType => 'instance', parent => '/Accounts/{Sid}.json' },
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
