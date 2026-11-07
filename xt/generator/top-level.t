use 5.016;
use warnings;

use Test::More;

use lib 'tools/lib';

use Twilio::Generator;
use Twilio::Generator::Emit;
use Twilio::Generator::Report;
use Twilio::Generator::Resource;
use Twilio::Generator::Spec;
use Twilio::Generator::Tree;

my $HOST = 'https://other.test';

my $COMPONENTS =
  { schemas => { record => { type => 'object', properties => { sid => { type => 'string' } } } } };

subtest 'a domain with several versions' => sub {
  my $domain = Twilio::Generator::domain_model('other', [version('v2'), version('v1')]);

  is($domain->{class}, 'Twilio::Rest::Other', 'the class');
  is_deeply([map { $_->{version_method} } @{ $domain->{versions} }], ['v1', 'v2'], 'in order');
  ok(!$domain->{main}, 'it is not the main API');

  my $code = Twilio::Generator::Emit::domain($domain);
  like($code, qr/sub v1 .*sub v2 /s, 'both versions');
  unlike($code, qr/sub accounts/, 'no forwarders');
  like($code, qr/=head2 v1.*=head2 v2/s, 'both documented');
  my $compiled = eval "no warnings qw(redefine); $code";    ## no critic (ProhibitStringyEval)
  ok($compiled, 'it compiles') or diag($@);
};

subtest 'versions of a domain must share a host' => sub {
  my $elsewhere = version('v2');
  $elsewhere->{base_url} = 'https://elsewhere.test';

  my $ok    = eval { Twilio::Generator::domain_model('other', [version('v1'), $elsewhere]); 1 };
  my $error = $@;
  ok(!$ok, 'refused');
  like($error, qr/other: its versions live on different hosts/, 'says why');
};

subtest 'names on the client' => sub {
  my $main      = { method => 'api', main => { shortcuts => [{ mount => 'calls' }] } };
  my $other     = { method => 'other' };
  my $clash     = { method => 'calls' };
  my $same_name = { method => 'account' };

  my $distinct = eval { Twilio::Generator::check_client_names([$main, $other]); 1 };
  ok($distinct, 'distinct names pass');

  for my $case ([calls => $clash], [account => $same_name]) {
    my ($name, $domain) = @{$case};
    my $ok    = eval { Twilio::Generator::check_client_names([$main, $domain]); 1 };
    my $error = $@;
    ok(!$ok, "$name: refused");
    like($error, qr/$name is both a domain and a shortcut/, "$name: says why");
  }

  my $ok    = eval { Twilio::Generator::check_client_names([$other]); 1 };
  my $error = $@;
  ok(!$ok, 'no main API: refused');
  like($error, qr/No domain has the account/, 'says why');
};

subtest 'an Account outside the main API has no shortcuts' => sub {
  my ($spec, $tree) = account_spec('other');
  my %by_class = map { $_->{class} => $_ } @{ $tree->{resources} };

  my $account = Twilio::Generator::Resource::build($spec, $tree, $by_class{Account});
  my $top     = Twilio::Generator::top_level($spec, $tree, $account);
  ok(!$top->{account_context}, 'it is not the account of the client');
  is_deeply($top->{shortcuts},                        [],           'no shortcuts');
  is_deeply([map { $_->{mount} } @{ $top->{roots} }], ['accounts'], 'it hangs from the version');

  my $part = Twilio::Generator::Resource::build($spec, $tree, $by_class{'Account::Part'});
  like($part->{calls}{list}, qr/\A\$client->other->v1->accounts\(\$\w+\)->parts\z/, 'a full path');
};

subtest 'an Account in the main API has them' => sub {
  my ($spec, $tree) = account_spec('api');
  my %by_class = map { $_->{class} => $_ } @{ $tree->{resources} };

  my $account = Twilio::Generator::Resource::build($spec, $tree, $by_class{Account});
  my $top     = Twilio::Generator::top_level($spec, $tree, $account);
  ok($top->{account_context}, 'it is the account of the client');
  is_deeply([map { $_->{mount} } @{ $top->{shortcuts} }], ['parts'], 'a shortcut');

  my $part = Twilio::Generator::Resource::build($spec, $tree, $by_class{'Account::Part'});
  is($part->{calls}{list}, '$client->parts', 'documented through the shortcut');
};

subtest 'an implied list keeps the description of the instance' => sub {
  my $document = {
    components => $COMPONENTS,
    servers    => [{ url => $HOST }],
    paths      => {
      '/v1/Things/{Sid}' => {
        description => 'A thing',
        'x-twilio'  => { pathType => 'instance' },
        get         => operation('FetchThing'),
      },
    },
  };
  my $spec  = Twilio::Generator::Spec->new('other', 'v1', $document);
  my $tree  = Twilio::Generator::Tree::build($spec);
  my $model = Twilio::Generator::Resource::build($spec, $tree, $tree->{resources}[0]);

  is($model->{description}, 'A thing', 'the description');
};

subtest 'a level with no resource of its own is named' => sub {
  my $document = {
    components => $COMPONENTS,
    servers    => [{ url => $HOST }],
    paths      => {
      '/v1/Things/{Sid}' =>
        { 'x-twilio' => { pathType => 'instance' }, get => operation('FetchThing') },
      '/v1/Things' =>
        { 'x-twilio' => { pathType => 'list' }, get => listing('ListThing', 'things') },
      '/v1/Things/Parts' =>
        { 'x-twilio' => { pathType => 'list' }, get => listing('ListPart', 'parts') },
    },
  };
  my $spec   = Twilio::Generator::Spec->new('other', 'v1', $document);
  my $tree   = Twilio::Generator::Tree::build($spec);
  my ($part) = grep { $_->{class} eq 'Thing::Part' } @{ $tree->{resources} };

  my $ok    = eval { Twilio::Generator::Resource::build($spec, $tree, $part); 1 };
  my $error = $@;
  ok(!$ok, 'a child with no id for its parent: refused');
  like($error, qr/its parent needs an id/, 'says why');
};

subtest 'the report' => sub {
  my $text = Twilio::Generator::Report::text(
    {
      ready   => { resources => 5, stops => [] },
      blocked => {
        resources => 1,
        stops => ['Field one: no rule for x', 'Field two: no rule for x', 'Other: no rule for y'],
      },
    }
  );

  like($text, qr/^2 specs in scope, 1 finish$/m,     'the specs');
  like($text, qr/^6 resources build, 3 stops$/m,     'the resources');
  like($text, qr/^\s+2  no rule for x$/m,            'equal causes add up');
  like($text, qr/^\s+1  no rule for y$/m,            'the others too');
  like($text, qr/^\s+3  blocked \(1 build\)$/m,      'by spec');
  like($text, qr/\A.*no rule for x.*no rule for y/s, 'the most common first');
};

done_testing;

sub version {
  my ($method) = @_;
  return {
    base_url       => $HOST,
    domain_class   => 'Twilio::Rest::Other',
    shortcuts      => [],
    version_class  => 'Twilio::Rest::Other::' . ucfirst $method,
    version_method => $method,
  };
}

sub account_spec {
  my ($domain) = @_;

  my $parts    = '/v1/Accounts/{AccountSid}/Parts';
  my $document = {
    components => $COMPONENTS,
    servers    => [{ url => $HOST }],
    paths      => {
      '/v1/Accounts/{Sid}' => {
        'x-twilio' => { pathType => 'instance' },
        get        => operation('FetchAccount'),
      },
      '/v1/Accounts' =>
        { 'x-twilio' => { pathType => 'list' }, get => listing('ListAccount', 'accounts') },
      $parts => {
        'x-twilio' => { pathType => 'list', parent => '/Accounts/{Sid}' },
        get        => listing('ListPart', 'parts'),
      },
    },
  };
  my $spec = Twilio::Generator::Spec->new($domain, 'v1', $document);
  return ($spec, Twilio::Generator::Tree::build($spec));
}

sub operation {
  my ($id) = @_;
  return {
    operationId => $id,
    responses   => {
      200 => {
        content => {
          'application/json' => { schema => { '$ref' => '#/components/schemas/record' } }
        }
      }
    },
  };
}

sub listing {
  my ($id, $key) = @_;

  my $schema = {
    type       => 'object',
    properties => {
      $key => { type => 'array', items => { '$ref' => '#/components/schemas/record' } },
      meta => { type => 'object' }
    },
  };
  return {
    operationId => $id,
    responses   => { 200 => { content => { 'application/json' => { schema => $schema } } } }
  };
}
