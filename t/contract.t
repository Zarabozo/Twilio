use 5.016;
use warnings;

use Test::More;

use Twilio::Http::FakeClient;
use Twilio::Json;
use Twilio::Rest::Client;

# t/data/contract-api-v2010.json is written from Twilio's spec by tools/generate.pl. It says what
# each operation must send, and this test checks that the real classes send exactly that.
my $FILE = 't/data/contract-api-v2010.json';

my $operations = read_rules($FILE);
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
  push @arguments, { map { $_ => with_dates($entry->{options}{$_}) } keys %{ $entry->{options} } }
    if %{ $entry->{options} };
  $target->$method(@arguments);

  my ($request) = $http->requests;
  is($request->{method}, $entry->{http}, 'HTTP method');

  my ($url, $query) = split /[?]/, $request->{url}, 2;
  is($url, $entry->{url}, 'URL');
  is_deeply(pairs($query // $request->{content}), sorted($entry->{expected}), 'values on the wire');
  return;
}

sub with_dates {
  my ($value) = @_;
  return ref $value eq 'HASH' && exists $value->{epoch}
    ? bless { %{$value} }, 'Local::Moment'
    : $value;
}

sub object_for {
  my ($client, $chain) = @_;

  my $object  = $client->api;
  my $next_id = 0;
  for my $link (@{$chain}) {
    my ($mount, $takes_id) = @{$link};
    $object = $takes_id ? $object->$mount('id' . ++$next_id) : $object->$mount;
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
