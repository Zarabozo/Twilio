use 5.016;
use warnings;

use Test::More;

use lib 'tools/lib';

use Twilio::Generator::Spec;
use Twilio::Generator::Types qw(field_reader option_name request_writer);

my $FILE = 'spec/twilio_api_v2010.json';

# The specs are downloaded, so this cannot run from a clean copy. CI fetches them first.
plan skip_all => "$FILE is missing: run tools/fetch-specs.pl" if !-e $FILE;

my $spec = Twilio::Generator::Spec->load($FILE);

my @failures;
for my $item (values %{ $spec->paths }) {
  for my $operation (grep { ref eq 'HASH' && $_->{operationId} } values %{$item}) {
    check_operation($operation);
  }
}
for my $name (grep { /\Aapi[.]/ } sort keys %{ $spec->{document}{components}{schemas} }) {
  my $schema     = $spec->resolve({ '$ref' => "#/components/schemas/$name" });
  my $properties = $schema->{properties} // {};
  check(sub { field_reader($spec, "$name.$_[0]", $properties->{ $_[0] }) }, $_)
    for keys %{$properties};
}

is_deeply([sort @failures], [], 'every value in the spec has a rule');

done_testing;

sub check_operation {
  my ($operation) = @_;

  for my $parameter (@{ $operation->{parameters} // [] }) {
    next if $parameter->{in} eq 'path';
    check_request($operation, $parameter->{name}, $parameter->{schema});
  }

  my $content = $operation->{requestBody}{content} // {};
  for my $type (values %{$content}) {
    my $properties = $spec->resolve($type->{schema})->{properties} // {};
    check_request($operation, $_, $properties->{$_}) for keys %{$properties};
  }
  return;
}

sub check_request {
  my ($operation, $name, $schema) = @_;
  check(
    sub {
      option_name($_[0]);
      request_writer($spec, "$operation->{operationId} $_[0]", $schema);
    },
    $name
  );
  return;
}

sub check {
  my ($rule, $name) = @_;

  my $ok = eval { $rule->($name); 1 };
  push @failures, $@ =~ s/\s+at\s.*//sr if !$ok;
  return;
}
