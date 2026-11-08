use 5.016;
use warnings;

use Carp       qw(croak);
use File::Find qw(find);
use Test::More;

use lib 'tools/lib';

use Twilio::Generator;
use Twilio::Generator::Scope;

my $SPECS = 'spec';

# The specs are downloaded, so this cannot run from a clean copy. CI fetches them first.
plan skip_all => 'the specs are missing: run tools/fetch-specs.pl'
  if !-e "$SPECS/twilio_api_v2010.json";

my $files = Twilio::Generator::generated_files($SPECS, '.perltidyrc');
ok(scalar keys %{$files}, 'files were generated');

for my $name (sort keys %{$files}) {
  my $same = slurp("lib/$name") eq $files->{$name};
  ok($same, "lib/$name is what the generator writes");
}

# Names are compared as the disk spells them. On Windows, writing A2PBrandRegistration.pm over
# A2pBrandRegistration.pm keeps the old spelling, which Linux then cannot require.
is_deeply(
  [sort map { s{\Alib/}{}r } files_under('lib/Twilio/Rest')],
  [sort grep { m{\ATwilio/Rest/} } keys %{$files}],
  'every file under lib/Twilio/Rest is generated, under the name the generator gives it'
);

my $contracts = Twilio::Generator::contract_files($SPECS);
is_deeply(
  [sort map { s{.*/}{}r } glob 't/data/contract-*.json'],
  [sort keys %{$contracts}],
  'each spec that is ready has one contract, and no other contract is left'
);
is(scalar keys %{$contracts}, scalar(() = Twilio::Generator::Scope::ready()), 'one for each spec');

for my $name (sort keys %{$contracts}) {
  ok(slurp("t/data/$name") eq $contracts->{$name}, "t/data/$name is what the generator writes");
}

done_testing;

sub files_under {
  my ($directory) = @_;

  my @found;
  find({ wanted => sub { push @found, $File::Find::name if -f }, no_chdir => 1 }, $directory);
  return @found;
}

sub slurp {
  my ($file) = @_;
  open my $handle, '<:raw', $file or croak "Cannot read $file: $!";
  my $content = do { local $/ = undef; <$handle> };
  close $handle or croak "Cannot read $file: $!";
  return $content;
}
