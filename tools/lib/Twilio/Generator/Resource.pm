package Twilio::Generator::Resource;

use 5.016;
use warnings;

use Carp qw(croak);

use Twilio::Generator::Names qw(camelize snake);
use Twilio::Generator::Types qw(field_reader map_prefix option_name request_writer);

our $VERSION = '2.000000';

my $FORM_CONTENT      = 'application/x-www-form-urlencoded';
my %IS_PAGE_PARAMETER = map { $_ => 1 } qw(Page PageSize PageToken);

# These methods exist on every object of their kind, so a name from the spec would replace them.
my %IS_RESERVED_FIELD = map { $_ => 1 } qw(DESTROY can delete fetch isa new to_hash update);
my %IS_RESERVED_MOUNT = map { $_ => 1 } qw(
  DESTROY can create delete fetch get_context get_page isa new page read read_records stream
  stream_records update
);

# Turns one resource of the tree into what the emitter needs, so that everything the spec
# cannot answer stops here and Emit only has to write text.
sub build {
  my ($spec, $tree, $resource) = @_;

  croak "$resource->{key}: a level with no operations of its own"
    if !$resource->{list} && !$resource->{instance};

  my $model = _names($tree, $resource);
  $model->{description} = _description($spec, $resource);
  $model->{variable}    = snake($resource->{class_parts}[-1]);
  $model->{calls}       = _calls($tree, $resource);
  $model->{list}        = _list_side($spec, $resource)    if $resource->{list};
  $model->{context}     = _context_side($spec, $resource) if $resource->{instance};

  my $records = _records($spec, $resource);
  $model->{records_key} = $records->{key} if $records;

  my @schemas = _instance_schemas($spec, $resource, $records);
  $model->{has_instance} = @schemas ? 1 : 0;
  $model->{fields}       = _fields($spec, $resource, \@schemas);

  _add_children($spec, $tree, $resource, $model);
  return $model;
}

sub _names {
  my ($tree, $resource) = @_;

  my @parts = @{ $resource->{class_parts} };
  my $name  = pop @parts;
  my $space = join q{::}, root_class($tree), @parts;

  return {
    name   => $name,
    module => "${space}::$name",
    class  => { map { $_ => "${space}::$name" . ucfirst } qw(list page context instance) },
  };
}

# How a reader reaches a resource, for the documentation. Resources of an account have a shortcut
# on the client, so they start there.
sub _calls {
  my ($tree, $resource) = @_;

  my %by_class = map { $_->{class} => $_ } @{ $tree->{resources} };
  my $list     = _list_call($tree, \%by_class, $resource);
  my $instance = $resource->{instance} // {};
  return {
    list    => $list,
    context => defined $instance->{key} ? "$list(\$" . snake($instance->{key}) . ')' : $list
  };
}

sub _list_call {
  my ($tree, $by_class, $resource) = @_;

  my $mount = $resource->{mount};
  return _root_call($tree) . "->$mount" if !defined $resource->{parent};

  my $parent = $by_class->{ $resource->{parent} };
  return "\$client->$mount" if _is_account_shortcut($tree, $parent, $resource);

  my $from = _list_call($tree, $by_class, $parent);
  return "$from->$mount" if !_hangs_from_instance($resource);
  return "$from(\$" . _parent_id($resource) . ")->$mount";
}

# Only the main API has shortcuts, and other specs have resources called Account as well.
sub _is_account_shortcut {
  my ($tree, $parent, $resource) = @_;
  return
       $tree->{domain} eq 'api'
    && $parent->{class} eq 'Account'
    && _hangs_from_instance($resource);
}

sub _root_call {
  my ($tree) = @_;
  return '$client->api' if $tree->{domain} eq 'api';
  return "\$client->$tree->{domain}->$tree->{version}";
}

sub _hangs_from_instance {
  my ($resource) = @_;
  return ($resource->{parent_side} // q{}) ne 'list';
}

# The id of the parent is the last parameter of the child's list, or of a singleton's path.
sub _parent_id {
  my ($resource) = @_;

  my $side = $resource->{list} // $resource->{instance}
    // croak "$resource->{key}: a level with no operations of its own";
  my ($name) = $side->{path} =~ /.*[{](\w+)[}]/;
  croak "$resource->{key}: its parent needs an id that its path does not have" if !defined $name;
  return snake($name);
}

sub root_class {
  my ($tree) = @_;
  return join q{::}, 'Twilio::Rest', camelize($tree->{domain}), camelize($tree->{version});
}

sub _description {
  my ($spec, $resource) = @_;
  my $list = $resource->{list};
  my $side = $list && !$list->{implied} ? $list : $resource->{instance} // $list;
  my $text = $spec->paths->{ $side->{path} }{description}               // q{};
  return $text;
}

sub _list_side {
  my ($spec, $resource) = @_;

  my $side = _side($resource->{list});
  for my $operation (@{ $resource->{list}{operations} }) {
    my $verb = $operation->{verb};
    if    ($verb eq 'create') { $side->{create} = _body_operation($spec, $operation) }
    elsif ($verb eq 'fetch')  { $side->{fetch} = _fetch_operation($spec, $operation) }
    elsif ($verb eq 'list')   { $side->{read} = _read_operation($spec, $operation) }
    else                      { croak "$operation->{id}: no rule for $verb on a list" }
  }
  return $side;
}

sub _context_side {
  my ($spec, $resource) = @_;

  my $side = _side($resource->{instance});
  $side->{own} = $side->{parameters}[-1] if defined $resource->{instance}{key};

  for my $operation (@{ $resource->{instance}{operations} }) {
    my $verb = $operation->{verb};
    if    ($verb eq 'update') { $side->{update} = _body_operation($spec, $operation) }
    elsif ($verb eq 'delete') { $side->{delete} = _delete_operation($operation) }
    elsif ($verb eq 'fetch')  { $side->{fetch} = _fetch_operation($spec, $operation) }
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

sub _delete_operation {
  my ($operation) = @_;

  _refuse_parameters($operation, sub { 0 });
  croak "$operation->{id}: no rule for a body here" if $operation->{spec}{requestBody};
  return { method => $operation->{method}, description => $operation->{spec}{description} };
}

sub _fetch_operation {
  my ($spec, $operation) = @_;

  _refuse_parameters($operation, sub { $_[0]{in} eq 'query' });
  croak "$operation->{id}: no rule for a body here" if $operation->{spec}{requestBody};
  return {
    method      => $operation->{method},
    description => $operation->{spec}{description},
    options     => _query_arguments($spec, $operation),
  };
}

sub _read_operation {
  my ($spec, $operation) = @_;

  _refuse_parameters($operation, sub { $_[0]{in} eq 'query' });
  return {
    method      => $operation->{method},
    description => $operation->{spec}{description},
    filters     => _query_arguments($spec, $operation),
  };
}

sub _query_arguments {
  my ($spec, $operation) = @_;

  my @parameters = sort { $a->{name} cmp $b->{name} }
    grep { !$IS_PAGE_PARAMETER{ $_->{name} } && $_->{in} eq 'query' }
    @{ $operation->{spec}{parameters} // [] };

  my @arguments;
  for my $parameter (@parameters) {
    my $where = "$operation->{id} $parameter->{name}";
    croak "$where: no rule for a required query parameter" if $parameter->{required};
    push @arguments,
      _argument($spec, $where, $parameter->{name}, $parameter->{schema}, $parameter->{description});
  }
  return \@arguments;
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
    method      => $operation->{method},
    description => $operation->{spec}{description},
    required    => [map { $argument->($_) } @required],
    options     => [map { $argument->($_) } sort grep { !$is_required{$_} } keys %{$properties}],
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
  my ($spec, $where, $wire_name, $schema, $description) = @_;

  my $resolved = $spec->resolve($schema);
  my $is_array = ($resolved->{type} // q{}) eq 'array';
  return {
    wire        => $wire_name,
    name        => option_name($wire_name),
    writer      => scalar request_writer($spec, $where, $schema),
    map_prefix  => scalar map_prefix($spec, $schema),
    array       => $is_array ? 1 : 0,
    description => $description // $schema->{description},
    enum        => _enum_of($spec, $is_array ? $resolved->{items} : $schema),
  };
}

sub _enum_of {
  my ($spec, $schema) = @_;
  return $spec->resolve($schema // {})->{enum};
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

# A list and a fetch can answer with different schemas for the same object.
sub _instance_schemas {
  my ($spec, $resource, $records) = @_;

  my %references;
  $references{ $records->{reference} } = 1 if $records;
  for my $side (grep { $_ } @{$resource}{qw(list instance)}) {
    for my $operation (grep { $_->{verb} ne 'list' && $_->{verb} ne 'delete' }
      @{ $side->{operations} })
    {
      my @found = grep { $_->{'$ref'} } _response_schemas($operation);
      croak "$operation->{id}: no schema for its response" if !@found;
      $references{ $_->{'$ref'} } = 1 for @found;
    }
  }
  return map { $spec->resolve({ '$ref' => $_ }) } sort keys %references;
}

sub _fields {
  my ($spec, $resource, $schemas) = @_;

  my (%readers, %notes);
  for my $schema (@{$schemas}) {
    my $properties = $schema->{properties} // {};
    for my $name (sort keys %{$properties}) {
      croak "Field $name is reserved" if $IS_RESERVED_FIELD{$name};

      my $reader = field_reader($spec, "Field $name", $properties->{$name}) // q{};
      if (exists $readers{$name} && $readers{$name} ne $reader) {
        croak "$resource->{key}: field $name is read in two ways";
      }
      $readers{$name} = $reader;
      $notes{$name}{description} //= $properties->{$name}{description};
      $notes{$name}{enum}        //= _enum_of($spec, $properties->{$name});
    }
  }
  return [
    map { { name => $_, reader => length $readers{$_} ? $readers{$_} : undef, %{ $notes{$_} } } }
    sort keys %readers
  ];
}

# The resources with no parent hang from the version, which has no parameters of its own.
sub root_children {
  my ($spec, $tree) = @_;

  my $model = { fields => [], context => { parameters => [] } };
  _add_children($spec, $tree, { class => q{} }, $model);
  return $model->{context}{children} // [];
}

sub _add_children {
  my ($spec, $tree, $resource, $model) = @_;

  my %is_field = map { $_->{name} => 1 } @{ $model->{fields} };
  for my $child (grep { ($_->{parent} // q{}) eq $resource->{class} } @{ $tree->{resources} }) {
    my $names = _names($tree, $child);
    my $side  = _host_side($model, $child);

    my $mount = $child->{mount};
    croak "$child->{key}: method $mount is reserved"     if $IS_RESERVED_MOUNT{$mount};
    croak "$child->{key}: method $mount is also a field" if $is_field{$mount} && $side->{own};

    my $target = $child->{list} // $child->{instance};
    my $count  = () = $target->{path} =~ /[{]/g;
    if ($count != @{ $side->{parameters} }) {
      croak "$child->{key}: its path does not fit the parameters of its parent";
    }

    my $key = ($child->{instance} // {})->{key};
    push @{ $side->{children} },
      {
      mount     => $mount,
      module    => $names->{module},
      list      => $names->{class}{list},
      context   => $names->{class}{context},
      singleton => $child->{list} ? 0 : 1,
      defined $key ? (own => snake($key)) : (),
      };
  }
  return;
}

# A child hangs from the object its parent link names: /Things/{Sid} is one thing, and /Things
# is the list, which is what a section like Usage has.
sub _host_side {
  my ($model, $child) = @_;

  my $wanted = ($child->{parent_side} // q{}) eq 'list' ? 'list' : 'context';
  my $side   = $model->{$wanted} // ($child->{parent_side} ? undef : $model->{list});
  croak "$child->{key}: its parent has no $wanted" if !$side;
  return $side;
}

1;
