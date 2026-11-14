package Twilio::Generator::Resource;

use 5.016;
use warnings;

use Carp     qw(croak);
use JSON::PP ();

use Twilio::Generator::Names qw(camelize snake);
use Twilio::Generator::Types
  qw(field_reader header_option_name json_rule map_prefix option_name request_writer);

our $VERSION = '2.002';

my $FORM_CONTENT      = 'application/x-www-form-urlencoded';
my $JSON_CONTENT      = 'application/json';
my $SCIM_CONTENT      = 'application/scim+json';
my %IS_PAGE_PARAMETER = map { $_ => 1 } qw(Page PageSize PageToken);

# The v1.0 standard pages with these. A list sends them from page, and any other operation
# takes them as options, as twilio-php does with Insights v3's FetchQueryJobResults.
my %IS_TOKEN_PAGE_PARAMETER = map { $_ => 1 } qw(pageSize pageToken);

# These methods exist on every object of their kind, so a name from the spec would replace them.
my %IS_RESERVED_FIELD =
  map { $_ => 1 } qw(DESTROY can create delete fetch isa new patch to_hash update);

# Records whose own id the spec names only in words. Memory's TraitGroups/{traitGroupName} is the
# displayName, "a unique and addressable name", and twilio-php reads a traitGroupName field that
# the records do not have, so a listed trait group builds a URL with no name in it there.
my %OWN_FIELD_OF = ('ControlPlane/Stores/TraitGroups' => 'display_name');

my %IS_RESERVED_MOUNT = map { $_ => 1 } qw(
  DESTROY can create delete fetch get_context get_page isa new page patch read read_records stream
  stream_records update
);

# Turns one resource of the tree into what the emitter needs, so that everything the spec
# cannot answer stops here and Emit only has to write text.
sub build {
  my ($spec, $tree, $resource) = @_;

  croak "$resource->{key}: a level with no operations of its own"
    if !$resource->{list} && !$resource->{instance};

  my $model = _names($tree, $resource);
  $model->{v1_standard} = $spec->follows_v1_standard;
  $model->{description} = _description($spec, $resource);
  $model->{variable}    = snake($resource->{class_parts}[-1]);
  $model->{calls}       = _calls($tree, $resource);
  $model->{list}        = _list_side($spec, $resource)    if $resource->{list};
  $model->{context}     = _context_side($spec, $resource) if $resource->{instance};

  my $records = _records($spec, $resource);
  $model->{records_key} = $records->{key} if $records;

  my $shapes = _shapes($spec, $resource, $records);
  $model->{has_instance} = @{ $shapes->{instance} } ? 1 : 0;
  $model->{fields}       = _fields($spec, $resource, $shapes->{instance});
  _add_plain_id($spec, $model, $records) if $records && $records->{plain};
  _add_answer_classes($spec, $resource, $model, $shapes);

  # Only a list builds an instance without its context, which knows the id already.
  if (defined(my $own = ($model->{context} // {})->{own})) {
    my $listed =
      $records || grep { $_->{kind} eq 'list' && !defined $_->{class} } @{ $shapes->{answered} };
    $model->{context}{own_field} = _own_field($model->{fields}, $own, $resource->{key}, $listed);
  }

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
  my ($method, @ids) = _reach($tree, \%by_class, $resource);
  my $instance = $resource->{instance} // {};
  my @own      = defined $instance->{key} ? '$' . _id_name($instance->{key}) : ();
  return { list => _call($method, @ids), context => _call($method, @ids, @own) };
}

# Every class takes the API version as $version, so Intelligence's /Versions/{version} is
# $path_version, as twilio-php's $pathVersion.
my %IS_TAKEN_NAME = map { $_ => 1 } qw(class payload self version);

sub _id_name {
  my ($name) = @_;
  my $snake = snake($name);
  return $IS_TAKEN_NAME{$snake} ? "path_$snake" : $snake;
}

sub _call {
  my ($method, @ids) = @_;
  return @ids ? "$method(" . join(q{, }, @ids) . ')' : $method;
}

# The method that reaches a resource, and the ids it takes before the resource's own.
sub _reach {
  my ($tree, $by_class, $resource) = @_;

  my $mount = $resource->{mount};
  if (!defined $resource->{parent}) {
    return (_root_call($tree) . "->$mount", map { "\$$_" } @{ extra_ids($resource, 0) });
  }

  my $parent = $by_class->{ $resource->{parent} };
  return "\$client->$mount" if _is_account_shortcut($tree, $parent, $resource);

  my $from_instance = _hangs_from_instance($resource) && !_is_singleton($parent);
  my $host      = $from_instance || _is_singleton($parent) ? $parent->{instance} : $parent->{list};
  my $host_path = ($host // {})->{path} // q{};
  my $held      = () = $host_path =~ /[{]/g;
  my ($method, @ids) = _reach($tree, $by_class, $parent);
  push @ids, '$' . _parent_id($resource, $parent, $held) if $from_instance;
  return (_call($method, @ids) . "->$mount", map { "\$$_" } @{ extra_ids($resource, $held) });
}

sub _is_singleton {
  my ($resource) = @_;
  return $resource->{instance} && !$resource->{list} && !defined $resource->{instance}{key};
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

# The id of the parent is the last one it holds in the child's list, or in a singleton's path. The
# child's name for it reads better than the parent's own Sid: $call_sid, not $sid. A child whose
# URL does not use it gets the parent's own name.
sub _parent_id {
  my ($resource, $parent, $held) = @_;

  my $side = $resource->{list} // $resource->{instance}
    // croak "$resource->{key}: a level with no operations of its own";
  my @names = $side->{path} =~ /[{](\w+)[}]/g;
  return _id_name($names[$held - 1]) if $held && @names >= $held;

  my $key = ($parent->{instance} // {})->{key};
  croak "$resource->{key}: its parent needs an id that its path does not have" if !defined $key;
  return _id_name($key);
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

# Each verb a side can have: the method it becomes, and how its operation is read. twilio-php
# has a patch method of its own, next to update, for the APIs that have both.
my %LIST_VERB = (
  create => [create => \&_body_operation],
  delete => [delete => \&_delete_operation],
  fetch  => [fetch  => \&_fetch_operation],
  list   => [read   => \&_read_operation],
  update => [update => \&_body_operation],
);
my %INSTANCE_VERB = (
  create => [create => \&_body_operation],
  delete => [delete => \&_delete_operation],
  fetch  => [fetch  => \&_fetch_operation],
  patch  => [patch  => \&_body_operation],
  update => [update => \&_body_operation],
);

sub _list_side {
  my ($spec, $resource) = @_;

  my $side = _side($spec, $resource, $resource->{list});
  _add_operations($spec, $side, $resource->{list}{operations}, \%LIST_VERB, 'a list');
  return $side;
}

sub _context_side {
  my ($spec, $resource) = @_;

  my $side = _side($spec, $resource, $resource->{instance});
  $side->{own} = $side->{parameters}[-1] if defined $resource->{instance}{key};
  _add_operations($spec, $side, $resource->{instance}{operations}, \%INSTANCE_VERB, 'an instance');
  return $side;
}

sub _add_operations {
  my ($spec, $side, $operations, $rules, $where) = @_;

  for my $operation (@{$operations}) {
    my $rule = $rules->{ $operation->{verb} }
      or croak "$operation->{id}: no rule for $operation->{verb} on $where";
    my ($method, $reader) = @{$rule};
    $side->{$method} = $reader->($spec, $operation);
  }
  return;
}

# An id in a URL has a rule like any other value: Voice's /Archives/{Date} takes a date, which
# twilio-php writes as 2026-11-07. The rules come from both sides of the resource, because a list
# with no operations of its own still builds its URL.
sub _side {
  my ($spec, $resource, $side) = @_;

  my %writer = _path_writers($spec, $resource);
  my @tokens = split /([{]\w+[}])/, $side->{path};
  my @uri    = map {
    /\A[{](\w+)[}]\z/
      ? { parameter => _id_name($1), defined $writer{$1} ? (writer => $writer{$1}) : () }
      : { literal   => $_ }
  } grep { length } @tokens;
  return { parameters => [map { $_->{parameter} // () } @uri], uri => \@uri };
}

sub _path_writers {
  my ($spec, $resource) = @_;

  my %writer;
  for my $operation (map { @{ $_->{operations} } } grep { $_ } @{$resource}{qw(list instance)}) {
    for my $listed (@{ $operation->{spec}{parameters} // [] }) {
      my $parameter = $spec->resolve($listed);
      next if ($parameter->{in} // q{}) ne 'path';
      my $where = "$operation->{id} $parameter->{name}";
      $writer{ $parameter->{name} } = request_writer($spec, $where, $parameter->{schema} // {});
    }
  }
  return %writer;
}

# A delete returns true, or the object it answers with, as twilio-php returns it.
sub _delete_operation {
  my ($spec, $operation) = @_;

  croak "$operation->{id}: no rule for a body here" if $operation->{spec}{requestBody};
  my $parameters = _parameters($spec, $operation, 'no required');
  return {
    method      => $operation->{method},
    description => $operation->{spec}{description},
    options     => $parameters->{optional},
    _accept($operation),
  };
}

sub _fetch_operation {
  my ($spec, $operation) = @_;

  croak "$operation->{id}: no rule for a body here" if $operation->{spec}{requestBody};
  my $parameters = _parameters($spec, $operation, 'no required');
  return {
    method      => $operation->{method},
    description => $operation->{spec}{description},
    options     => $parameters->{optional},
    _accept($operation),
  };
}

# A required query parameter comes before the options, as in twilio-php's read($channel, ...).
sub _read_operation {
  my ($spec, $operation) = @_;

  my $parameters = _parameters($spec, $operation);
  return {
    method      => $operation->{method},
    description => $operation->{spec}{description},
    required    => $parameters->{required},
    filters     => $parameters->{optional},
    _accept($operation),
  };
}

# What an operation takes besides its body and its path: query parameters, and headers, which
# twilio-php takes as options too, like X-Twilio-Webhook-Enabled.
sub _parameters {
  my ($spec, $operation, $no_required) = @_;

  my (@required, @optional);
  for my $parameter (sort { $a->{name} cmp $b->{name} } @{ $operation->{spec}{parameters} // [] }) {
    my $place = $parameter->{in};
    next if $place eq 'path' || ($place eq 'query' && $IS_PAGE_PARAMETER{ $parameter->{name} });
    croak "$operation->{id}: no rule for $place parameter $parameter->{name}"
      if $place ne 'query' && $place ne 'header';

    my $paging = _is_token_page_parameter($spec, $parameter);
    next if $paging && $operation->{verb} eq 'list';
    my $required = $parameter->{required} && !$paging;

    my $where = "$operation->{id} $parameter->{name}";
    croak "$where: no rule for a required $place parameter"
      if $required && ($no_required || $place eq 'header');
    my $argument = _argument($spec, $where, $parameter->{name}, $parameter->{schema},
      $parameter->{description}, $place);
    push @{ $required ? \@required : \@optional }, $argument;
  }
  return { required => \@required, optional => \@optional };
}

sub _is_token_page_parameter {
  my ($spec, $parameter) = @_;
  return
       $spec->follows_v1_standard
    && $parameter->{in} eq 'query'
    && $IS_TOKEN_PAGE_PARAMETER{ $parameter->{name} };
}

# twilio-php asks for what an operation answers in. Only SCIM differs from the JSON every other
# operation gets.
sub _accept {
  my ($operation) = @_;

  my %types;
  for my $response (_successes($operation)) {
    $types{$_}++ for keys %{ $response->{content} // {} };
  }
  my @types = sort keys %types;
  return @types == 1 && $types[0] eq $SCIM_CONTENT ? (accept => $SCIM_CONTENT) : ();
}

sub _body_operation {
  my ($spec, $operation) = @_;

  my $content    = $operation->{spec}{requestBody}{content} // {};
  my @types      = sort keys %{$content};
  my $parameters = _parameters($spec, $operation);
  my %operation  = (
    method      => $operation->{method},
    description => $operation->{spec}{description},
    _accept($operation),
  );

  # A body that can also be SCIM is sent as JSON, as twilio-php sends it.
  if ($content->{$JSON_CONTENT} && !grep { $_ ne $JSON_CONTENT && $_ ne $SCIM_CONTENT } @types) {
    return {
      %operation,
      required => $parameters->{required},
      options  => $parameters->{optional},
      json     => _json_body($spec, $operation, $content->{$JSON_CONTENT}{schema}),
    };
  }
  if (@types > 1 || (@types && $types[0] ne $FORM_CONTENT)) {
    croak "$operation->{id}: no rule for a body of @types";
  }

  my $schema      = @types ? $spec->resolve($content->{$FORM_CONTENT}{schema}) : {};
  my $properties  = $schema->{properties} // {};
  my @required    = @{ $schema->{required} // [] };
  my %is_required = map { $_ => 1 } @required;

  my $argument =
    sub { _argument($spec, "$operation->{id} $_[0]", $_[0], $properties->{ $_[0] }, undef, 'body') };

  my @options = map { $argument->($_) } sort grep { !$is_required{$_} } keys %{$properties};
  return {
    %operation,
    required => [(map { $argument->($_) } @required), @{ $parameters->{required} }],
    options  => [@options,                            @{ $parameters->{optional} }],
  };
}

# The caller writes a JSON body as a hash reference, with the names Twilio's documentation uses.
# Only its top-level fields have rules, and they are listed for the documentation.
sub _json_body {
  my ($spec, $operation, $schema) = @_;

  my $resolved    = $spec->resolve($schema // {});
  my $properties  = $resolved->{properties} // {};
  my %is_required = map { $_ => 1 } @{ $resolved->{required} // [] };
  my (%rules, @fields);
  for my $name (sort keys %{$properties}) {
    my $rule = json_rule($spec, "$operation->{id} $name", $properties->{$name});
    $rules{$name} = $rule if defined $rule;
    push @fields,
      {
      name        => $name,
      required    => $is_required{$name} ? 1 : 0,
      description => $properties->{$name}{description},
      enum        => _enum_of($spec, $properties->{$name}),
      };
  }
  return {
    required => $operation->{spec}{requestBody}{required} ? 1 : 0,
    rules    => \%rules,
    fields   => \@fields,
  };
}

sub _argument {
  my ($spec, $where, $wire_name, $schema, $description, $place) = @_;

  my $resolved = $spec->resolve($schema);
  my $is_array = ($resolved->{type} // q{}) eq 'array';
  return {
    wire        => $wire_name,
    place       => $place,
    name        => $place eq 'header' ? header_option_name($wire_name) : option_name($wire_name),
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

# An error, from 400 up, dies before any object is built, so only the other answers count: SCIM's
# ScimError would otherwise give every user an always-empty scim_type, as twilio-python's has.
# A redirect counts, because Bulk Exports' FetchDay describes its answer only under 307.
sub _successes {
  my ($operation) = @_;
  my $responses = $operation->{spec}{responses} // {};
  return map { $responses->{$_} } grep { !/\A[45]/ } sort keys %{$responses};
}

# Each answer with a body, with its status code.
sub _answers {
  my ($operation) = @_;

  my $responses = $operation->{spec}{responses} // {};
  my @answers;
  for my $code (grep { !/\A[45]/ } sort keys %{$responses}) {
    my $content = $responses->{$code}{content} // {};
    push @answers,
      map { { code => $code, schema => $content->{$_}{schema} // {} } } sort keys %{$content};
  }
  return @answers;
}

# Records are the one array of objects in a list's answer, by reference or written in place.
# Memory's ListStores has ids instead, which TokenPaginationPage turns into { id => ... }.
sub _records {
  my ($spec, $resource) = @_;

  my ($operation) =
    grep { $_->{verb} eq 'list' } @{ ($resource->{list} // {})->{operations} // [] };
  return if !$operation;

  my (@found, @plain);
  for my $answer (_answers($operation)) {
    my $properties = $spec->resolve($answer->{schema})->{properties} // {};
    for my $key (sort keys %{$properties}) {
      my $items = $properties->{$key}{items} or next;
      my $array = defined $items->{'$ref'} || _is_object($items) ? \@found : \@plain;
      push @{$array}, { key => $key, items => $items };
    }
  }
  @found = @plain if !@found;

  croak "$operation->{id}: expected one list of records, found " . scalar @found if @found != 1;

  my $records = $found[0];
  my @names   = _field_names($spec, $records->{items});
  $records->{plain} = @names ? 0 : 1;
  croak "$operation->{id}: no rule for records that are plain values, outside the v1.0 standard"
    if $records->{plain} && !$spec->follows_v1_standard;
  return $records;
}

sub _is_object {
  my ($schema) = @_;
  return 1 if grep { $schema->{$_} } qw(properties allOf anyOf oneOf);
  return ($schema->{type} // q{}) eq 'object' ? 1 : 0;
}

# The objects a schema can be. A oneOf gets the fields of every variant, as twilio-php's
# UsAppToPerson has the 30 fields of its two.
sub _objects {
  my ($spec, $schema) = @_;

  my $resolved = $spec->resolve($schema // {});
  my @parts    = map { @{ $resolved->{$_} // [] } } qw(allOf anyOf oneOf);
  return $resolved if !@parts;
  return (%{ $resolved->{properties} // {} } ? $resolved : ()), map { _objects($spec, $_) } @parts;
}

sub _field_names {
  my ($spec, $schema) = @_;
  my %names = map { %{ $_->{properties} // {} } } _objects($spec, $schema);
  my @names = sort keys %names;
  return @names;
}

my $CANONICAL = JSON::PP->new->canonical;

# Which object each answer is. Most share fields with the resource's records, or with its fetch
# when it has no list, and are the resource's instance. Under the v1.0 standard, one that shares
# none is another object, like Memory's { message, statusUrl } after a write, and gets a class of
# its own, as in twilio-php. Older APIs have one object per resource, and twilio-php gives every
# answer of theirs the resource's class: Bulk Exports' redirect is a Day.
sub _shapes {
  my ($spec, $resource, $records) = @_;

  my @answered;
  for my $kind (grep { $resource->{$_} } qw(list instance)) {
    for my $operation (grep { $_->{verb} ne 'list' } @{ $resource->{$kind}{operations} }) {
      push @answered,
        map { +{ %{$_}, kind => $kind, operation => $operation } } _answers($operation);
    }
  }

  my %base =
    $spec->follows_v1_standard ? map { $_ => 1 } _base_names($spec, $records, \@answered) : ();
  my (%instance_schema, %own, @own_keys);
  $instance_schema{ _schema_key($records->{items}) } = $records->{items} if $records;
  for my $answer (@answered) {
    my $schema = $answer->{schema};
    croak "$answer->{operation}{id}: no rule for an answer that is not an object"
      if !defined $schema->{'$ref'} && !_is_object($schema);

    my @names = _field_names($spec, $schema);
    my $key   = _schema_key($schema);
    if (!%base || !@names || grep { $base{$_} } @names) {
      $instance_schema{$key} = $schema;
      next;
    }
    push @own_keys, $key if !$own{$key};
    $own{$key} //= { name => _answer_class_name($answer), schema => $schema };
    $answer->{class} = $own{$key}{name};
  }

  # Sorted, so that the first description of a field is always the same one.
  my @instance = map { _objects($spec, $instance_schema{$_}) } sort keys %instance_schema;
  return { instance => \@instance, own => [@own{@own_keys}], answered => \@answered };
}

sub _schema_key {
  my ($schema) = @_;
  return $schema->{'$ref'} // $CANONICAL->encode($schema);
}

# What the resource's own object has: its records' fields, or an id when they are plain values,
# or else what its fetch answers with first.
sub _base_names {
  my ($spec, $records, $answered) = @_;

  if ($records) {
    my @names = _field_names($spec, $records->{items});
    return @names ? @names : 'id';
  }
  my ($fetch) = grep { $_->{operation}{verb} eq 'fetch' } @{$answered};
  return $fetch ? _field_names($spec, $fetch->{schema}) : ();
}

# twilio-php's names: the schema's, or the operation's and the status code's for one written in
# place, like CreateStore202ResponseInstance.
sub _answer_class_name {
  my ($answer) = @_;

  my $reference = $answer->{schema}{'$ref'};
  my $name =
    defined $reference
    ? ($reference =~ s{.*/}{}r) . 'Instance'
    : "$answer->{operation}{id}$answer->{code}ResponseInstance";
  croak "$answer->{operation}{id}: no rule for a class named $name" if $name !~ /\A[A-Za-z]\w*\z/;
  return ucfirst $name;
}

# An id the records hold as plain values, as Memory's ListStores does.
sub _add_plain_id {
  my ($spec, $model, $records) = @_;

  return if grep { $_->{name} eq 'id' } @{ $model->{fields} };
  my $description = $spec->resolve($records->{items})->{description};
  $model->{fields} = [
    sort { $a->{name} cmp $b->{name} } @{ $model->{fields} },
    { name => 'id', method => 'id', reader => undef, description => $description }
  ];
  return;
}

# Each object that is not the resource's gets its class, and each operation says what it returns
# for each status code.
sub _add_answer_classes {
  my ($spec, $resource, $model, $shapes) = @_;

  my $space = $model->{module} =~ s/::[^:]+\z//r;
  my %taken = map { $_ => 1 } values %{ $model->{class} };
  my %class_of;
  for my $own (@{ $shapes->{own} }) {
    my $class = "${space}::$own->{name}";
    croak "$resource->{key}: two objects are both $own->{name}" if $taken{$class}++;
    $class_of{ $own->{name} } = $class;
    push @{ $model->{answer_classes} },
      {
      name   => $own->{name},
      class  => $class,
      fields => _fields($spec, $resource, [_objects($spec, $own->{schema})]),
      };
  }

  my %answers_of;
  for my $answer (@{ $shapes->{answered} }) {
    my $operation = $answer->{operation};
    push @{ $answers_of{ $answer->{kind} }{ $operation->{verb} } }, $answer;
  }
  for my $kind (sort keys %answers_of) {
    my $side  = $model->{ $kind eq 'list' ? 'list' : 'context' };
    my $rules = $kind eq 'list' ? \%LIST_VERB : \%INSTANCE_VERB;
    for my $verb (sort keys %{ $answers_of{$kind} }) {
      $side->{ $rules->{$verb}[0] }{result} = _result(\%class_of, $answers_of{$kind}{$verb});
    }
  }

  for my $answer_class (@{ $model->{answer_classes} // [] }) {
    $answer_class->{methods} = [_methods_returning($model, $answer_class->{class})];
  }
  return;
}

# What an operation returns: the resource's instance, or another object, chosen by status code
# when it answers with both, as Knowledge's UpdateKnowledge does with 200 and 202.
sub _result {
  my ($class_of, $answers) = @_;

  my (%codes_of, %class_at);
  my $operation = $answers->[0]{operation};
  for my $answer (@{$answers}) {
    my $class = defined $answer->{class} ? $class_of->{ $answer->{class} } : q{};
    croak "$operation->{id}: answers $answer->{code} with two objects"
      if exists $class_at{ $answer->{code} } && $class_at{ $answer->{code} } ne $class;
    $class_at{ $answer->{code} } = $class;
    push @{ $codes_of{$class} }, $answer->{code}
      if !grep { $_ eq $answer->{code} } @{ $codes_of{$class} // [] };
  }

  my @others = grep { length } sort keys %codes_of;
  if (@others && keys %codes_of > 1) {
    my @codes = map { @{$_} } values %codes_of;
    croak "$operation->{id}: no rule for choosing an object by status @codes"
      if grep { !/\A\d+\z/ } @codes;
  }
  return {
    instance => exists $codes_of{q{}} ? 1 : 0,
    others   => [map { { class => $_, codes => $codes_of{$_} } } @others],
  };
}

sub _methods_returning {
  my ($model, $class) = @_;

  my @methods;
  for my $side (grep { $_ } @{$model}{qw(list context)}) {
    for my $method (qw(create fetch update patch delete)) {
      my $result = ($side->{$method} // {})->{result} or next;
      push @methods, $method if grep { $_->{class} eq $class } @{ $result->{others} };
    }
  }
  my %seen;
  return grep { !$seen{$_}++ } @methods;
}

sub _fields {
  my ($spec, $resource, $schemas) = @_;

  my (%readers, %notes);
  for my $schema (@{$schemas}) {
    my $properties = $schema->{properties} // {};
    for my $name (sort keys %{$properties}) {
      croak "Field $name is reserved" if $IS_RESERVED_FIELD{ snake($name) };

      my $reader = field_reader($spec, "Field $name", $properties->{$name}) // q{};
      if (exists $readers{$name} && $readers{$name} ne $reader) {
        croak "$resource->{key}: field $name is read in two ways";
      }
      $readers{$name} = $reader;
      $notes{$name}{description} //= $properties->{$name}{description};
      $notes{$name}{enum}        //= _enum_of($spec, $properties->{$name});
    }
  }

  # Newer APIs answer in camelCase, like Routes v3's friendlyName, and the method is still
  # friendly_name, as in every other resource and in twilio-python.
  my %by_method;
  for my $name (sort keys %readers) {
    my $method = snake($name);
    croak "$resource->{key}: fields $by_method{$method} and $name are both $method"
      if $by_method{$method};
    $by_method{$method} = $name;
  }
  return [
    map {
      {
        name   => $_,
        method => snake($_),
        reader => length $readers{$_} ? $readers{$_} : undef,
        %{ $notes{$_} }
      }
    } sort keys %readers
  ];
}

# The field that holds an instance's own id: sid, or phoneNumber when the API answers in
# camelCase and the URL calls it {PhoneNumber}. When no field has the URL's name, the record's
# sid or id holds it, as in twilio-php and twilio-python: IAM's {UserSid} is a SCIM user's id.
# Without a list, its context gives the id, as for Lookups' Overrides/{Field}.
sub _own_field {
  my ($fields, $own, $key, $listed) = @_;

  my %by_method = map { $_->{method} => $_->{name} } @{$fields};
  return $own if !@{$fields};
  for my $method ($own, $OWN_FIELD_OF{$key} // (), qw(sid id)) {
    return $by_method{$method} if defined $by_method{$method};
  }
  return $own if !$listed;
  croak "$key: no field holds its own id $own";
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

  my %is_field = map { $_->{method} => 1 } @{ $model->{fields} };
  for my $child (grep { ($_->{parent} // q{}) eq $resource->{class} } @{ $tree->{resources} }) {
    my $names = _names($tree, $child);
    my $side  = _host_side($model, $child);

    my $mount = $child->{mount};
    croak "$child->{key}: method $mount is reserved"     if $IS_RESERVED_MOUNT{$mount};
    croak "$child->{key}: method $mount is also a field" if $is_field{$mount} && $side->{own};

    my $key = ($child->{instance} // {})->{key};
    push @{ $side->{children} },
      {
      mount     => $mount,
      module    => $names->{module},
      list      => $names->{class}{list},
      context   => $names->{class}{context},
      singleton => $child->{list} ? 0 : 1,
      extra_ids => extra_ids($child, scalar @{ $side->{parameters} }),
      used_ids  => used_ids($child, scalar @{ $side->{parameters} }),
      defined $key ? (own => _id_name($key)) : (),
      };
  }
  return;
}

# The ids in a child's list URL, or in a singleton's, beyond the ones its parent holds. These come
# after the parent's in every URL. The order is the URL's, though twilio-php sorts them by name:
# lookup_overrides($phone_number, $field) reads like the URL it builds.
sub extra_ids {
  my ($child, $held) = @_;

  my @ids = _ids_of($child);
  return [@ids > $held ? @ids[$held .. $#ids] : ()];
}

# How many of its parent's ids a child's URL uses. Usually all of them, but TaskRouter's
# Workers/CumulativeStatistics hangs from a worker, as in twilio-php, and has no worker id.
sub used_ids {
  my ($child, $held) = @_;

  my @ids = _ids_of($child);
  return @ids < $held ? scalar @ids : $held;
}

sub _ids_of {
  my ($child) = @_;
  my $target = $child->{list} // $child->{instance};
  return map { _id_name($_) } $target->{path} =~ /[{](\w+)[}]/g;
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
