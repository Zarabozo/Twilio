use 5.016;
use warnings;

use Carp qw(croak);
use Test::More;

use lib 'tools/lib';

use Twilio::Generator;

my $SPEC = 'spec/twilio_api_v2010.json';

# The specs are downloaded, so this cannot run from a clean copy. CI fetches them first.
plan skip_all => "$SPEC is missing: run tools/fetch-specs.pl" if !-e $SPEC;

my $files = Twilio::Generator::generated_files($SPEC, '.perltidyrc');
ok(scalar keys %{$files}, 'files were generated');

for my $name (sort keys %{$files}) {
  my $same = slurp("lib/$name") eq $files->{$name};
  ok($same, "lib/$name is what the generator writes");
}

my $wire_rules = q{t/data/contract-api-v2010.json};
ok(slurp($wire_rules) eq Twilio::Generator::contract_json($SPEC),
  "$wire_rules is what the generator writes");

done_testing;

sub slurp {
  my ($file) = @_;
  open my $handle, '<:raw', $file or croak "Cannot read $file: $!";
  my $content = do { local $/ = undef; <$handle> };
  close $handle or croak "Cannot read $file: $!";
  return $content;
}
