package Twilio::Generator::Tree;

use 5.016;
use warnings;

use Carp qw(croak);

use Twilio::Generator::Names qw(camelize segment_class singular snake);
use Twilio::Generator::Spec;

our $VERSION = '2.000000';

my @HTTP_METHODS = qw(get post put patch delete);
my %IS_HTTP      = map { $_ => 1 } @HTTP_METHODS;
my %IS_PATH_NOTE = map { $_ => 1 } qw(description parameters servers summary x-maturity x-twilio);
my %IS_VERB      = map { $_ => 1 } qw(create delete fetch list update);

# A resource's place comes from the parent in x-twilio, not from its path: SMS/ShortCodes is a
# direct child of Account, with no Sms level, in every official library.
sub build {
  my ($spec) = @_;

  croak 'a spec with several versions in it' if !defined $spec->version;

  my %nodes;
  my $paths = $spec->paths;
  _add_path(\%nodes, $_, $paths->{$_}) for sort keys %{$paths};
  _link_parents(\%nodes);
  _split_by_noun(\%nodes);
  _add_missing_lists(\%nodes);

  my $mounts = _dependent_mounts($paths);
  my @ordered =
    sort { @{ $a->{segments} } <=> @{ $b->{segments} } || $a->{key} cmp $b->{key} } values %nodes;
  _name_node(\%nodes, $_, $mounts) for @ordered;
  _check_unique(\@ordered);

  return {
    domain    => $spec->domain,
    version   => $spec->version,
    resources => [sort { $a->{class} cmp $b->{class} } @ordered],
  };
}

sub render {
  my ($tree) = @_;
  return map { _render_resource($_) . "\n" } @{ $tree->{resources} };
}

sub _render_resource {
  my ($resource) = @_;

  my @parts = ($resource->{class}, "[$resource->{mount}]");
  push @parts, 'list(' . _verbs($resource->{list}) . ')' if $resource->{list};
  if (my $instance = $resource->{instance}) {
    my $key = $instance->{key} // 'singleton';
    push @parts, "instance:$key(" . _verbs($instance) . ')';
  }
  return join q{ }, @parts;
}

sub _verbs {
  my ($side) = @_;
  return join q{ }, sort map { $_->{verb} } @{ $side->{operations} };
}

sub _add_path {
  my ($nodes, $path, $item) = @_;

  my $notes = $item->{'x-twilio'} // {};
  my $type  = $notes->{pathType}  // q{};
  croak "$path: unknown path type '$type'" if $type ne 'list' && $type ne 'instance';

  # An instance with no parameter at the end is a singleton, like a payload's Data.
  my $key = _instance_key($path);
  croak "$path: a list cannot end in a parameter" if $type eq 'list' && defined $key;

  my @segments    = _segments($path);
  my $key_of_node = join q{/}, @segments;
  my $node        = $nodes->{$key_of_node} //= { key => $key_of_node, segments => \@segments };
  croak "$path: a second $type for $node->{key}" if $node->{$type};

  _set_parent($node, $path, $notes->{parent});

  $node->{$type} = { path => $path, operations => _operations($path, $item) };
  $node->{$type}{key} = $key if defined $key;
  _set_class_name($node, $path, $notes->{className});
  _set_mount_name($node, $path, $notes->{mountName});
  return;
}

# twilio-php names a class after its mount when the spec gives one: a user's channels are
# user_channels, so the class is UserChannel and not Channel.
sub _set_mount_name {
  my ($node, $path, $name) = @_;
  return if !defined $name;

  if (defined $node->{mount_name} && $node->{mount_name} ne $name) {
    croak "$path: mount name $name conflicts with $node->{mount_name}";
  }
  $node->{mount_name} = $name;
  return;
}

sub _instance_key {
  my ($path) = @_;
  my ($key)  = $path =~ m{/[{](\w+)[}](?:[.]json)?\z};
  return $key;
}

sub _segments {
  my ($path)   = @_;
  my $plain    = $path =~ s/[.]json\z//r;
  my @segments = grep { length && !/\A[{]/ } split m{/}, $plain;
  return @segments;
}

sub _set_parent {
  my ($node, $path, $parent) = @_;
  return if !defined $parent;

  my @own    = @{ $node->{segments} };
  my @theirs = _segments($parent);
  my $key    = join q{/}, @theirs;
  if (@theirs >= @own || $key ne join q{/}, @own[0 .. $#theirs]) {
    croak "$path: parent $parent does not contain it";
  }
  if (defined $node->{parent_key} && $node->{parent_key} ne $key) {
    croak "$path: parent $key conflicts with $node->{parent_key}";
  }
  $node->{parent_key}  = $key;
  $node->{parent_side} = defined _instance_key($parent) ? 'instance' : 'list';
  return;
}

# Only the path around a resource can place a section that no path declares, like a parent
# with no operations of its own.
sub _link_parents {
  my ($nodes) = @_;

  my @pending = map { $nodes->{$_} } sort keys %{$nodes};
  while (my $node = shift @pending) {
    my @segments = @{ $node->{segments} };
    next if @segments == 1;

    pop @segments;
    my $key = $node->{parent_key} //= join q{/}, @segments;
    next if $nodes->{$key};

    $nodes->{$key} = { key => $key, segments => [split m{/}, $key] };
    push @pending, $nodes->{$key};
  }
  return;
}

# A list is what turns an id into a context, so an instance with an id needs one even when no
# path declares it. twilio-php generates the same empty class.
sub _add_missing_lists {
  my ($nodes) = @_;

  for my $node (values %{$nodes}) {
    my $instance = $node->{instance} or next;
    next if $node->{list} || !defined $instance->{key};

    my $path = $instance->{path} =~ s{/[{]\w+[}]((?:[.]json)?)\z}{$1}r;
    $node->{list} = { path => $path, operations => [], implied => 1 };
  }
  return;
}

sub _operations {
  my ($path, $item) = @_;

  for my $name (keys %{$item}) {
    croak "$path: unknown path entry '$name'" if !$IS_HTTP{$name} && !$IS_PATH_NOTE{$name};
  }
  return [map { _operation($path, $_, $item->{$_}) } grep { $item->{$_} } @HTTP_METHODS];
}

sub _operation {
  my ($path, $method, $operation) = @_;

  my $id = $operation->{operationId} // q{};
  my ($verb, $noun) = $id =~ /\A([A-Z][a-z]+)([A-Z]\w*)\z/;
  $verb = lc($verb // q{});
  croak "$path: cannot read a verb from operation '$id'" if !$IS_VERB{$verb};

  return { verb => $verb, noun => $noun, method => uc $method, id => $id, spec => $operation };
}

sub _set_class_name {
  my ($node, $path, $name) = @_;
  return if !defined $name;

  if (defined $node->{class_name} && $node->{class_name} ne $name) {
    croak "$path: class name $name conflicts with $node->{class_name}";
  }
  $node->{class_name} = $name;
  return;
}

# One path can hold two resources: POST on /Keys creates a NewKey, and GET lists Key objects.
# Twilio's libraries give each its own classes, so an operation with a noun that is not the
# resource's own moves to a sibling.
sub _split_by_noun {
  my ($nodes) = @_;

  for my $key (sort keys %{$nodes}) {
    my $node = $nodes->{$key};
    my %nouns =
      map { $_->{noun} => 1 } map { @{ $_->{operations} } } grep { $_ } @{$node}{qw(list instance)};
    next if keys %nouns < 2;

    my $own = segment_class($node->{segments}[-1]);
    croak "$key: no operation is named after $own" if !$nouns{$own};
    _move_operations($nodes, $node, $_) for sort grep { $_ ne $own } keys %nouns;
  }
  return;
}

sub _move_operations {
  my ($nodes, $node, $noun) = @_;

  my %sibling = (
    key         => "$node->{key}:$noun",
    segments    => $node->{segments},
    parent_key  => $node->{parent_key},
    parent_side => $node->{parent_side},
    class_name  => snake($noun),
  );
  for my $type (qw(list instance)) {
    my $side  = $node->{$type} or next;
    my @moved = grep { $_->{noun} eq $noun } @{ $side->{operations} };
    next if !@moved;

    $side->{operations} = [grep { $_->{noun} ne $noun } @{ $side->{operations} }];
    $sibling{$type} = { %{$side}, operations => \@moved };
  }
  $nodes->{ $sibling{key} } = \%sibling;
  return;
}

# When Twilio names the method that reaches a child, that name wins over one built from the
# path. Names are kept by class because resources split by noun share a URL.
sub _dependent_mounts {
  my ($paths) = @_;

  my %mounts;
  for my $path (sort keys %{$paths}) {
    my $dependents = $paths->{$path}{'x-twilio'}{dependentProperties} // {};
    for my $mount (sort keys %{$dependents}) {
      my $url = Twilio::Generator::Spec::strip_version($dependents->{$mount}{resource_url} // q{});
      my $key = join q{/}, _segments($url);
      $mounts{$key}{ singular(camelize($mount)) } = $mount;
    }
  }
  return \%mounts;
}

sub _name_node {
  my ($nodes, $node, $mounts) = @_;

  my $final_segment = $node->{segments}[-1];
  my $class =
      defined $node->{class_name} ? camelize($node->{class_name})
    : defined $node->{mount_name} ? singular(camelize($node->{mount_name}))
    :                               segment_class($final_segment);

  my @parents;
  if (defined $node->{parent_key}) {
    my $parent = $nodes->{ $node->{parent_key} };
    @parents = @{ $parent->{class_parts} };
    $node->{parent} = $parent->{class};
  }
  $node->{class_parts} = [@parents, $class];
  $node->{class}       = join q{::}, @{ $node->{class_parts} };
  $node->{mount}       = _mount($node, $mounts->{ join q{/}, @{ $node->{segments} } }, $class);
  return;
}

sub _mount {
  my ($node, $names, $class) = @_;

  my @all = sort values %{ $names // {} };
  return $node->{mount_name} // snake($node->{segments}[-1]) if !@all;
  return $all[0]                                             if @all == 1;
  return $names->{$class} // croak "$node->{key}: called both $all[0] and $all[1]";
}

sub _check_unique {
  my ($resources) = @_;

  my (%classes, %mounts);
  for my $resource (@{$resources}) {
    my $class = $resource->{class};
    croak "$resource->{key} and $classes{$class} are both $class" if $classes{$class};
    $classes{$class} = $resource->{key};

    my $mount = join q{.}, $resource->{parent} // q{}, $resource->{mount};
    croak "$resource->{key} and $mounts{$mount} are both $mount" if $mounts{$mount};
    $mounts{$mount} = $resource->{key};
  }
  return;
}

1;
