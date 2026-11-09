use 5.016;
use warnings;

use Pod::Simple::PullParser;
use Test::More;

use lib 'tools/lib';

use Twilio::Generator::Emit;
use Twilio::Generator::Pod;

subtest 'text' => sub {
  my @cases = (
    ['plain text stays',      'A message.',                     'A message.'],
    ['nothing given',         undef,                            q{}],
    ['spaces collapse',       "  One\n\ntwo   three\n",         'One two three'],
    ['code',                  'Use `status` here',              'Use C<status> here'],
    ['code with brackets',    'As `<=YYYY-MM-DD` here',         'As C<< <=YYYY-MM-DD >> here'],
    ['empty code',            'A `` here',                      'A C<> here'],
    ['a raw tag',             'The <Pay> verb',                 'The E<lt>PayE<gt> verb'],
    ['less than',             'When a < b',                     'When a E<lt> b'],
    ['bold',                  'See **this** now',               'See B<this> now'],
    ['code inside bold',      '**Use `a`**',                    'B<Use C<a>>'],
    ['a single star stays',   'Use * or %',                     'Use * or %'],
    ['stars in code stay',    'Meta `*` here',                  'Meta C<*> here'],
    ['a link',                'An [Account](https://a.test/b)', 'An L<Account|https://a.test/b>'],
    ['a relative link',       '[Docs](/docs/x)',       'L<Docs|https://www.twilio.com/docs/x>'],
    ['code inside a link',    '[`a`](https://a.test)', 'L<C<a>|https://a.test>'],
    ['a bar in a link',       '[a|b](https://a.test)', 'L<aE<verbar>b|https://a.test>'],
    ['a link with no target', '[text]()',              'text'],
    ['two of them',           '`a` and [b](https://a.test)', 'C<a> and L<b|https://a.test>'],
    ['non-ASCII stays',       "Fetch a Recording\x{2019}s",  "Fetch a Recording\x{2019}s"],
  );

  for my $case (@cases) {
    my ($name, $input, $expected) = @{$case};
    is(Twilio::Generator::Pod::text($input), $expected, $name);
  }
};

subtest 'a document' => sub {
  my $pod = Twilio::Generator::Pod::document(model());

  like($pod, qr/\$client = Twilio::Rest::Client->new/, 'the synopsis starts with a client');
  like($pod, qr/my \$thing = \$client->things->create\(\$name, \\%options\);/, 'create');
  like($pod, qr/for my \$thing \(\$client->things->read\(\{\}, 20\)\)/,        'read');
  like($pod, qr/my \$thing = \$client->things\(\$sid\)->fetch;/,               'fetch');
  like($pod, qr/\$client->things\(\$sid\)->update\(\\%options\);/,             'update');
  like($pod, qr/\$client->things\(\$sid\)->delete;/,                           'delete');

  like($pod, qr/=head1 ThingList/,      'list');
  like($pod, qr/=head1 ThingPage/,      'page');
  like($pod, qr/=head2 records_key/,    'its method');
  like($pod, qr/=head2 build_instance/, 'and the other');
  like($pod, qr/=head1 ThingContext/,   'context');
  like($pod, qr/=head1 ThingInstance/,  'instance');
  like($pod, qr/=head2 new/,            'the constructors');

  like($pod, qr/Make a thing[.] Returns a C<ThingInstance>[.]/, 'the description of the operation');
  like($pod, qr/Removes it[.] Returns true[.]/,                 'and a full stop is not doubled');
  like($pod, qr/=item C<\$name>\n\nIts name[.]/,                'a required value');
  like($pod, qr/The mode[.] One of C<fast>, C<slow> or C<safe>[.]/,        'choices');
  like($pod, qr/=item C<kind>\n\nMust be C<one>[.]/,                       'one choice');
  like($pod, qr/=item C<tags>\n\nThe tags[.] An array reference[.]/,       'an array');
  like($pod, qr/=item C<when>\n\nA string, or an object with/,             'a date');
  like($pod, qr/L<Twilio::Serialize\/iso8601_date_time>/,                  'linked');
  like($pod, qr/=item C<data>\n\nA hash or array reference/,               'free-form data');
  like($pod, qr/=item C<blank>\n\nNo description in the specification[.]/, 'nothing to say');

  like($pod, qr/=item sid\n\nThe id[.]/, 'a field');
  like($pod, qr/=item friendly_name\n/,  'a field is listed by its method, not its wire name');
  like($pod, qr/=item status\n\nOne of C<on> or C<off>[.]/, 'a field with choices');
  my %passages = (
    'a date field' => "=item date_created\n\nCreated. A L<Time::Piece> object in UTC",
    'capabilities' => "=item capabilities\n\nA L<Twilio::Base::PhoneNumberCapabilities> object",
    'a child'      =>
      "=head2 parts\n\n  my \$list = \$object->parts;\n\n  my \$context = \$object->parts(\$sid);",
  );
  ok(index($pod, $passages{$_}) >= 0, $_) for sort keys %passages;

  like($pod, qr/=head2 data\n\n  my \$context = \$object->data;\n/, 'a singleton');
  like(
    $pod,
    qr/It has C<fetch>, C<update>, C<delete>, C<parts> and C<data>/,
    'what an instance offers'
  );
  like($pod, qr/=head2 get_context/, 'get_context');
  like($pod, qr/=head1 LICENSE/,     'license');

  my $parser = Pod::Simple::PullParser->new;
  $parser->set_source(\$pod);
  1 while $parser->get_token;
  ok(!$parser->any_errata_seen, 'valid POD');
};

subtest 'optional parts are left out' => sub {
  my $model = model();
  delete $model->{context};
  delete $model->{records_key};
  $model->{has_instance} = 0;
  delete $model->{list}{read};
  delete $model->{list}{create};
  delete $model->{list}{children};
  $model->{description} = q{};

  my $pod = Twilio::Generator::Pod::document($model);

  unlike($pod, qr/=head1 SYNOPSIS/,      'nothing to show');
  unlike($pod, qr/=head1 ThingContext/,  'no context');
  unlike($pod, qr/=head1 ThingPage/,     'no page');
  unlike($pod, qr/=head1 ThingInstance/, 'no instance');
  like($pod, qr/This file holds C<ThingList>[.]/, 'what is left');
};

done_testing;

sub argument {
  my ($name, %details) = @_;
  return { name => $name, wire => ucfirst $name, array => 0, %details };
}

sub model {
  my $instance = { instance => 1, others => [] };
  my $create   = {
    method      => 'POST',
    result      => $instance,
    description => 'Make a thing',
    required    => [argument('name', description => 'Its name.')],
    options     => [
      argument('mode', description => 'The mode.', enum => [qw(fast slow safe)]),
      argument('kind', enum        => ['one']),
      argument('tags', description => 'The tags.', array => 1),
      argument('when', writer      => 'iso8601_date_time'),
      argument('data', writer      => 'json_object'),
      argument('blank'),
    ],
  };

  return {
    name         => 'Thing',
    module       => 'Demo::Thing',
    variable     => 'thing',
    description  => 'A thing.',
    class        => { map { $_ => 'Demo::Thing' . ucfirst } qw(list page context instance) },
    calls        => { list => '$client->things', context => '$client->things($sid)' },
    records_key  => 'things',
    has_instance => 1,
    list         => {
      create => $create,
      read   => { method => 'GET', description => 'List things', filters => [argument('status')] },
    },
    context => {
      own    => 'sid',
      fetch  => { method => 'GET', options => [], result => $instance },
      update =>
        { method => 'POST', required => [], options => [argument('mode')], result => $instance },
      delete   => { method => 'DELETE', description => 'Removes it.' },
      children => [
        { mount => 'parts', module => 'Demo::Part', own => 'sid', singleton => 0 },
        { mount => 'data',  module => 'Demo::Data', singleton => 1 },
      ],
    },
    fields => [
      { name => 'capabilities', method => 'capabilities', reader => 'phone_number_capabilities' },
      {
        name        => 'date_created',
        method      => 'date_created',
        reader      => 'date_time',
        description => 'Created.'
      },
      { name => 'sid',          method => 'sid',    description => 'The id.' },
      { name => 'status',       method => 'status', enum        => [qw(on off)] },
      { name => 'friendlyName', method => 'friendly_name' },
    ],
  };
}
