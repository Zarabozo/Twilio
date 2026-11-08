use 5.016;
use warnings;

use JSON::PP ();
use Test::More;

use Twilio::Http::FakeClient;
use Twilio::Json;
use Twilio::Rest::Client;

# The t/data/contract-*.json files are written from Twilio's specs by tools/generate.pl. They say
# what each operation must send, and this test checks that the real classes send exactly that.
my @FILES = glob 't/data/contract-*.json';

my $operations = [map { @{ read_rules($_) } } @FILES];
ok(@{$operations} > 190, 'the contract covers the API');

for my $entry (@{$operations}) {
  subtest $entry->{id} => sub { check($entry) };
}

done_testing;

sub check {
  my ($entry) = @_;

  my $http = Twilio::Http::FakeClient->new;
  my $client =
    Twilio::Rest::Client->new('ACxx', 'token', { http_client => $http, environment => {} });
  $http->mock(200, $entry->{records_key} ? { $entry->{records_key} => [], meta => {} } : {});

  my $target = object_for($client, $entry->{chain});
  my $method = $entry->{method};
  ok($target->can($method), "the object has $method") or return;

  my @arguments = map { with_dates($_) } @{ $entry->{required} };
  push @arguments, { map { $_ => with_dates($entry->{body}{$_}) } keys %{ $entry->{body} } }
    if $entry->{body};
  push @arguments, { map { $_ => with_dates($entry->{options}{$_}) } keys %{ $entry->{options} } }
    if %{ $entry->{options} };
  $target->$method(@arguments);

  my ($request) = $http->requests;
  is($request->{method}, $entry->{http}, 'HTTP method');

  # Values can arrive in the query string and in a form body at once.
  my ($url, $query) = split /[?]/, $request->{url}, 2;
  is($url, $entry->{url}, 'URL');
  my $form = $entry->{json} ? undef : $request->{content};
  is_deeply(
    sorted([@{ pairs($query) }, @{ pairs($form) }]),
    sorted($entry->{expected}),
    'values on the wire'
  );

  # As text, because 1 and true are equal to is_deeply, and not to Twilio.
  is(
    canonical(Twilio::Json::decode($request->{content})),
    canonical($entry->{json}),
    'the JSON body'
  ) if $entry->{json};
  is($request->{headers}{$_}, $entry->{headers}{$_}, "header $_")
    for sort keys %{ $entry->{headers} // {} };
  return;
}

sub canonical {
  my ($data) = @_;
  return JSON::PP->new->canonical->encode($data);
}

sub with_dates {
  my ($value) = @_;
  return ref $value eq 'HASH' && exists $value->{epoch}
    ? bless { %{$value} }, 'Local::Moment'
    : $value;
}

sub object_for {
  my ($client, $chain) = @_;

  my $object  = $client;
  my $next_id = 0;

  # Each link says how many ids its call takes. Most take none or one, and a few take more, like
  # archived_calls($date, $sid).
  for my $link (@{$chain}) {
    my ($mount, $ids) = @{$link};
    $object = $object->$mount(map { 'id' . ++$next_id } 1 .. $ids);
  }
  return $object;
}

sub pairs {
  my ($encoded) = @_;

  my @pairs = map {
    [map { decoded($_) } split /=/, $_, 2]
  } split /&/, $encoded // q{};
  return sorted(\@pairs);
}

sub decoded {
  my ($text) = @_;
  $text =~ tr/+/ /;
  $text =~ s/%([0-9A-Fa-f]{2})/chr hex $1/ge;
  return $text;
}

sub sorted {
  my ($pairs) = @_;
  return [sort { $a->[0] cmp $b->[0] || $a->[1] cmp $b->[1] } @{$pairs}];
}

sub read_rules {
  my ($file) = @_;

  open my $handle, '<:raw', $file or die "Cannot read $file: $!\n";
  my $content = do { local $/ = undef; <$handle> };
  close $handle or die "Cannot read $file: $!\n";
  return Twilio::Json::decode($content);
}

package Local::Moment;

sub epoch { return $_[0]{epoch} }
