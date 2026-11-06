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

subtest 'the generated documentation' => sub {
  my $code = emit(document());

  unlike($code, qr/C<page_size>/,  'paging is not listed among the filters');
  unlike($code, qr/C<page_token>/, 'nor the token');
  like($code, qr/E<lt>things E<gt>/,                       'description is escaped');
  like($code, qr/C<active>, C<mode>, C<tags> and C<when>/, 'options');
  like($code, qr/C<tags> takes an array reference/,        'arrays');
  like($code, qr/C<when> takes a string/,                  'dates');
  like($code, qr/create\(\$name, \$size, \\%options\)/,    'the call');
  like($code, qr/C<date_created> return L<Time::Piece>/,   'date fields');
};

subtest 'the other value types' => sub {
  my $document   = document();
  my $path       = '/v1/Accounts/{AccountSid}/Things.json';
  my $form       = 'application/x-www-form-urlencoded';
  my $body       = $document->{paths}{$path}{post}{requestBody}{content}{$form}{schema}{properties};
  my $properties = $document->{components}{schemas}{thing}{properties};

  $body->{Day}                = { type => 'string', format => 'date' };
  $body->{Parameter}          = {};
  $body->{'Parameter1.Name'}  = { type => 'string' };
  $properties->{capabilities} = { type => 'object', format => 'phone-number-capabilities' };
  $properties->{start_date}   = { type => 'string', format => 'date' };
  $properties->{tags}         = { type => 'array',  items  => { type => 'string' } };

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
    }
  );

  my $thing = $list->create(
    'one', 3,
    {
      day             => bless({}, 'Local::Date'),
      parameter       => { a => 1 },
      parameter1_name => 'first',
    }
  );

  my ($request) = $http->requests;
  like($request->{content}, qr/Day=1970-01-01(?:&|\z)/,      'date with no time');
  like($request->{content}, qr/Parameter=%7B%22a%22%3A1%7D/, 'free-form data as JSON');
  like($request->{content}, qr/Parameter1[.]Name=first/,     'a dotted wire name');

  isa_ok($thing->capabilities, 'Twilio::Base::PhoneNumberCapabilities');
  is($thing->capabilities->mms, 1,            'capabilities are read');
  is($thing->start_date->ymd,   '2026-11-06', 'a date field is read');
  is_deeply($thing->tags, ['a'], 'an array field stays as it is');

  like($code, qr/C<capabilities> return L<Twilio::Base::Phone/,            'capabilities in POD');
  like($code, qr/C<date_created> and C<start_date> return L<Time::Piece>/, 'dates in POD');
  like($code, qr/C<day> and C<when>\s+take\s+a\s+string/,                  'date option in POD');
};

subtest 'option names' => sub {
  is(option_name('StatusCallback'), 'status_callback',  'plain');
  is(option_name('DateSent<'),      'date_sent_before', 'before');
  is(option_name('DateSent>'),      'date_sent_after',  'after');

  is(option_name('Parameter1.Name'), 'parameter1_name', 'dot');

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
      'array of converted values',
      qr/no rule for an array of converted values/,
      sub {
        $_[0]{paths}{$list_path}{post}{requestBody}{content}{$form}{schema}{properties}{Tags}
          {items}{format} = 'date-time';
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
      'query parameter on fetch',
      qr/FetchThing: no rule for query parameter Extra/,
      sub {
        push @{ $_[0]{paths}{$item_path}{get}{parameters} },
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
      'singleton',
      qr/no rule for a singleton yet/,
      sub {
        my ($document) = @_;
        $document->{paths}{'/v1/Accounts/{AccountSid}/Things.json'}{'x-twilio'}{pathType} =
          'instance';
        delete $document->{paths}{$item_path};
        delete $document->{paths}{$list_path}{post};
        delete $document->{paths}{$list_path}{get};
      },
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
      'two instance schemas',
      qr/expected one instance schema, found/,
      sub {
        $_[0]{components}{schemas}{other} = { properties => {} };
        $_[0]{paths}{$item_path}{get}{responses}{200}{content}{'application/json'}{schema} =
          { '$ref' => '#/components/schemas/other' };
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
  my ($document) = @_;

  my $spec    = Twilio::Generator::Spec->new('demo', 'v1', $document);
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
            @{ path_parameters('AccountSid') },          $query->('Status'),
            $query->('Created<', format => 'date-time'), $query->('PageSize'),
            $query->('Page'),                            $query->('PageToken'),
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
