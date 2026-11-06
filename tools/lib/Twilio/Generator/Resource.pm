package Twilio::Generator::Resource;

use 5.016;
use warnings;

use Carp qw(croak);

use Twilio::Generator::Names qw(camelize snake);
use Twilio::Generator::Types qw(field_reader option_name request_writer);

our $VERSION = '2.000000';

my $FORM_CONTENT      = 'application/x-www-form-urlencoded';
my %IS_PAGE_PARAMETER = map { $_ => 1 } qw(Page PageSize PageToken);

# Every instance has these methods, so a field with one of these names would replace them.
my %IS_RESERVED_FIELD = map { $_ => 1 } qw(DESTROY can delete fetch isa new to_hash update);

# Turns one resource of the tree into what the emitter needs, so that everything the spec
# cannot answer stops here and Emit only has to write text.
sub build {
  my ($spec, $tree, $resource) = @_;

  my @parts = @{ $resource->{class_parts} };
  my $name  = pop @parts;
  my $root  = join q{::}, 'Twilio::Rest', camelize($tree->{domain}), camelize($tree->{version});
  my $space = join q{::}, $root, @parts;

  my $model = {
    name        => $name,
    module      => "${space}::$name",
    class       => { map { $_ => "${space}::$name" . ucfirst } qw(list page context instance) },
    description => _description($spec, $resource),
  };
  $model->{list}    = _list_side($spec, $resource)    if $resource->{list};
  $model->{context} = _context_side($spec, $resource) if $resource->{instance};

  my $records = _records($spec, $resource);
  $model->{records_key} = $records->{key} if $records;
  $model->{fields}      = _fields($spec, _instance_schema($spec, $resource, $records));

  return $model;
}

sub _description {
  my ($spec, $resource) = @_;
  my $side = $resource->{list}                            // $resource->{instance};
  my $text = $spec->paths->{ $side->{path} }{description} // q{};
  return $text;
}

sub _list_side {
  my ($spec, $resource) = @_;

  my $side = _side($resource->{list});
  for my $operation (@{ $resource->{list}{operations} }) {
    my $verb = $operation->{verb};
    if    ($verb eq 'create') { $side->{create} = _body_operation($spec, $operation) }
    elsif ($verb eq 'list')   { $side->{read} = _read_operation($spec, $operation) }
    else                      { croak "$operation->{id}: no rule for $verb on a list" }
  }
  return $side;
}

sub _context_side {
  my ($spec, $resource) = @_;

  my $side = _side($resource->{instance});
  croak "$resource->{key}: no rule for a singleton yet" if !defined $resource->{instance}{key};

  for my $operation (@{ $resource->{instance}{operations} }) {
    my $verb = $operation->{verb};
    if    ($verb eq 'update') { $side->{update} = _body_operation($spec, $operation) }
    elsif ($verb eq 'delete') { $side->{delete} = _plain_operation($operation) }
    elsif ($verb eq 'fetch')  { $side->{fetch} = _plain_operation($operation) }
    else                      { croak "$operation->{id}: no rule for $verb on an instance" }
  }
  return $side;
}

sub _side {
  my ($side) = @_;

  my @tokens = split /([{]\w+[}])/, $side->{path};
  my @uri    = map { /\A[{](\w+)[}]\z/ ? { parameter => snake($1) } : { literal => $_ } }
    grep { length } @tokens;
  return { parameters => [map { $_->{parameter} // () } @uri], uri => \@uri };
}

sub _plain_operation {
  my ($operation) = @_;

  _refuse_parameters($operation, sub { 0 });
  croak "$operation->{id}: no rule for a body here" if $operation->{spec}{requestBody};
  return { method => $operation->{method} };
}

sub _read_operation {
  my ($spec, $operation) = @_;

  _refuse_parameters($operation, sub { $_[0]{in} eq 'query' });
  my @filters = grep { !$IS_PAGE_PARAMETER{ $_->{name} } && $_->{in} eq 'query' }
    @{ $operation->{spec}{parameters} // [] };

  return {
    method  => $operation->{method},
    filters => [
      map  { _argument($spec, "$operation->{id} $_->{name}", $_->{name}, $_->{schema}) }
      sort { $a->{name} cmp $b->{name} } @filters
    ],
  };
}

sub _body_operation {
  my ($spec, $operation) = @_;

  _refuse_parameters($operation, sub { 0 });
  my $content = $operation->{spec}{requestBody}{content} // {};
  my @types   = sort keys %{$content};
  if (@types > 1 || (@types && $types[0] ne $FORM_CONTENT)) {
    croak "$operation->{id}: no rule for a body of @types";
  }

  my $schema      = @types ? $spec->resolve($content->{$FORM_CONTENT}{schema}) : {};
  my $properties  = $schema->{properties} // {};
  my @required    = @{ $schema->{required} // [] };
  my %is_required = map { $_ => 1 } @required;

  my $argument =
    sub { _argument($spec, "$operation->{id} $_[0]", $_[0], $properties->{ $_[0] }) };

  return {
    method   => $operation->{method},
    required => [map { $argument->($_) } @required],
    options  => [map { $argument->($_) } sort grep { !$is_required{$_} } keys %{$properties}],
  };
}

# Parameters in the path are already in the object. Anything else needs a rule of its own, and
# it is better to stop than to drop a parameter of Twilio's API without saying so.
sub _refuse_parameters {
  my ($operation, $is_expected) = @_;

  for my $parameter (@{ $operation->{spec}{parameters} // [] }) {
    next if $parameter->{in} eq 'path' || $is_expected->($parameter);
    croak "$operation->{id}: no rule for $parameter->{in} parameter $parameter->{name}";
  }
  return;
}

sub _argument {
  my ($spec, $where, $wire_name, $schema) = @_;

  my $resolved = $spec->resolve($schema);
  return {
    wire   => $wire_name,
    name   => option_name($wire_name),
    writer => scalar request_writer($spec, $where, $schema),
    array  => ($resolved->{type} // q{}) eq 'array' ? 1 : 0,
  };
}

sub _response_schemas {
  my ($operation) = @_;

  my @schemas;
  my $responses = $operation->{spec}{responses} // {};
  for my $code (sort keys %{$responses}) {
    my $content = $responses->{$code}{content} // {};
    push @schemas, map { $content->{$_}{schema} } sort keys %{$content};
  }
  return @schemas;
}

sub _records {
  my ($spec, $resource) = @_;

  my ($operation) =
    grep { $_->{verb} eq 'list' } @{ ($resource->{list} // {})->{operations} // [] };
  return if !$operation;

  my @found;
  for my $schema (_response_schemas($operation)) {
    my $properties = $spec->resolve($schema)->{properties} // {};
    for my $key (sort keys %{$properties}) {
      my $reference = ($properties->{$key}{items} // {})->{'$ref'};
      push @found, { key => $key, reference => $reference } if defined $reference;
    }
  }
  croak "$operation->{id}: expected one list of records, found " . scalar @found if @found != 1;
  return $found[0];
}

sub _instance_schema {
  my ($spec, $resource, $records) = @_;

  my %references;
  $references{ $records->{reference} } = 1 if $records;
  for my $side (grep { $_ } @{$resource}{qw(list instance)}) {
    for my $operation (grep { $_->{verb} ne 'list' } @{ $side->{operations} }) {
      $references{ $_->{'$ref'} } = 1 for grep { $_->{'$ref'} } _response_schemas($operation);
    }
  }

  my @found = sort keys %references;
  croak "$resource->{key}: expected one instance schema, found @found" if @found != 1;
  return $spec->resolve({ '$ref' => $found[0] });
}

sub _fields {
  my ($spec, $schema) = @_;

  my @fields;
  my $properties = $schema->{properties} // {};
  for my $name (sort keys %{$properties}) {
    croak "Field $name is reserved" if $IS_RESERVED_FIELD{$name};
    my $reader = field_reader($spec, "Field $name", $properties->{$name});
    push @fields, { name => $name, reader => $reader };
  }
  return \@fields;
}

1;
