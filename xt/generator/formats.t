use 5.016;
use warnings;

use JSON::PP ();
use Test::More;

use lib 'tools/lib';

use Twilio::Generator::Scope;
use Twilio::Generator::Spec;
use Twilio::Generator::Types
  qw(field_reader header_option_name json_rule option_name request_writer);

my $SPECS = 'spec';
my $FORM  = 'application/x-www-form-urlencoded';
my $JSON  = 'application/json';

my @files =
  map { "$SPECS/" . Twilio::Generator::Scope::spec_file($_) } Twilio::Generator::Scope::in_scope();

# The specs are downloaded, so this cannot run from a clean copy. CI fetches them first.
my @missing = grep { !-e } @files;
plan skip_all => "$missing[0] is missing: run tools/fetch-specs.pl" if @missing;

# Every spec in scope, and not only the ones that finish: a value with no rule should show up
# here first, and not hide behind whatever else stops its spec today.
for my $file (@files) {
  my $spec = Twilio::Generator::Spec->load($file);
  my @failures;
  for my $item (values %{ $spec->paths }) {
    for my $operation (grep { ref eq 'HASH' && $_->{operationId} } values %{$item}) {
      push @failures, check_operation($spec, $operation);
    }
  }
  push @failures, check_fields($spec);
  is_deeply([sort @failures], [], "every value in $file has a rule");
}

done_testing;

sub check_operation {
  my ($spec, $operation) = @_;

  my @failures;
  for my $listed (@{ $operation->{parameters} // [] }) {

    # Ids in the URL have rules too, like the date in Voice's /Archives/{Date}, and so do headers.
    my $parameter = $spec->resolve($listed);
    push @failures,
      check_request($spec, $operation, $parameter->{name}, $parameter->{schema}, $parameter->{in});
  }

  # Only the top-level fields of a JSON body have rules.
  if (my $json = ($operation->{requestBody}{content} // {})->{$JSON}) {
    my $properties = $spec->resolve($json->{schema} // {})->{properties} // {};
    push @failures,
      check(sub { json_rule($spec, "$operation->{operationId} $_", $properties->{$_}) })
      for keys %{$properties};
  }

  my $form       = ($operation->{requestBody}{content} // {})->{$FORM} or return @failures;
  my $properties = $spec->resolve($form->{schema})->{properties} // {};
  push @failures, check_request($spec, $operation, $_, $properties->{$_}) for keys %{$properties};
  return @failures;
}

sub check_request {
  my ($spec, $operation, $name, $schema, $place) = @_;
  return check(
    sub {
      ($place // q{}) eq 'header' ? header_option_name($name) : option_name($name);
      request_writer($spec, "$operation->{operationId} $name", $schema);
    }
  );
}

# The fields of each schema that an operation answers with.
sub check_fields {
  my ($spec) = @_;

  my $schemas = $spec->{document}{components}{schemas} // {};
  my @failures;
  for my $name (sort keys %{ response_schema_names($spec) }) {
    my $properties = ($schemas->{$name} // {})->{properties} // {};
    push @failures, check(sub { field_reader($spec, "$name.$_", $properties->{$_}) })
      for keys %{$properties};
  }
  return @failures;
}

sub response_schema_names {
  my ($spec) = @_;

  my $json = JSON::PP->new->canonical;
  my %names;
  for my $item (values %{ $spec->paths }) {
    for my $operation (grep { ref eq 'HASH' && $_->{operationId} } values %{$item}) {
      my $text = $json->encode($operation->{responses} // {});
      $names{$_}++ for $text =~ m{"#/components/schemas/([^"]+)"}g;
    }
  }
  return \%names;
}

sub check {
  my ($rule) = @_;

  my $ok = eval { $rule->(); 1 };
  return $ok ? () : $@ =~ s/\s+at\s.*//sr;
}
