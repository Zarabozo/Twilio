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

# twilio-php has a patch method of its own, next to update. Building it is a resource's job.
my %IS_VERB = map { $_ => 1 } qw(create delete fetch list patch update);

# A resource's place comes from the parent in x-twilio, not from its path: SMS/ShortCodes is a
# direct child of Account, with no Sms level, in every official library.
sub build {
  my ($spec) = @_;

  croak 'a spec with several versions in it' if !defined $spec->version;

  my %nodes;
  my $paths = $spec->paths;
  _add_path(\%nodes, $_, $paths->{$_}) for sort keys %{$paths};
  _link_parents(\%nodes);
  _split_by_names(\%nodes);
  _key_inner_ids(\%nodes);
  _add_missing_lists(\%nodes);
  _hang_on_singletons(\%nodes);

  my $mounts = _dependent_mounts($spec, $paths);
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

  # An instance with no parameter at the end is a singleton, like a payload's Data. A path that
  # does not say what it is ends in a parameter when it is an instance, as twilio-php reads it.
  my $key  = _instance_key($path);
  my $type = $notes->{pathType} // (defined $key ? 'instance' : 'list');
  croak "$path: unknown path type '$type'" if $type ne 'list' && $type ne 'instance';

  # A list can end in an id, as Insights' /Voice/Reports/PhoneNumbers/Inbound/{reportId} does:
  # the id is part of where the list is, and the list's records have none of their own.
  undef $key if $type eq 'list';

  my @segments    = _segments($path);
  my $declared    = _declared_class($notes);
  my $key_of_node = _node_key($nodes, join(q{/}, @segments), $declared);
  my $node        = $nodes->{$key_of_node} //=
    { key => $key_of_node, segments => \@segments, declared => $declared };
  croak "$path: a second $type for $node->{key}" if $node->{$type};

  # A parent written with the version, like IAM's /v1/Roles/{Sid}, is not one twilio-php finds,
  # so its child hangs from the version: RolePermission, not Role::Permission.
  my $parent = $notes->{parent};
  undef $parent if defined $parent && Twilio::Generator::Spec::strip_version($parent) ne $parent;
  _set_parent($node, $path, $parent);

  $node->{$type} = { path => $path, operations => _operations($path, $item) };
  $node->{$type}{key} = $key if defined $key;
  _set_class_name($node, $path, $notes->{className});

  # Most mount names are in snake case, but a few are not, like Lookups' lookupOverrides.
  _set_mount_name($node, $path, defined $notes->{mountName} ? snake($notes->{mountName}) : undef);
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

  # The parent is usually part of the path, but not always: Voice's /Settings belongs to
  # /DialingPermissions in twilio-php. Only a parent at or below the path itself is refused.
  my @own    = @{ $node->{segments} };
  my @theirs = _segments($parent);
  my $key    = join q{/}, @theirs;
  if (@theirs >= @own && join(q{/}, @theirs[0 .. $#own]) eq join q{/}, @own) {
    croak "$path: parent $parent does not contain it";
  }
  if (defined $node->{parent_key} && $node->{parent_key} ne $key) {
    croak "$path: parent $key conflicts with $node->{parent_key}";
  }
  $node->{parent_key}  = $key;
  $node->{parent_path} = $parent;
  $node->{parent_side} = defined _instance_key($parent) ? 'instance' : 'list';
  return;
}

# A path that declares no parent hangs from the version, wherever it is: twilio-php has
# /Configuration/Addresses as AddressConfiguration, next to Configuration and not below it. Only
# a declared parent that no path describes, like v2010's SIP, becomes a section, and the path
# around a section is all that can place it.
sub _link_parents {
  my ($nodes) = @_;

  my @pending = map { $nodes->{$_} } sort keys %{$nodes};
  while (my $node = shift @pending) {
    my @segments = @{ $node->{segments} };
    next if @segments == 1 || (!defined $node->{parent_key} && !$node->{section});

    pop @segments;
    my $key = $node->{parent_key} //= join q{/}, @segments;
    next if $nodes->{$key};

    $nodes->{$key} = _section($key, $node->{parent_path});
    push @pending, $nodes->{$key};
  }
  return;
}

# An instance's own id need not end its path: TrustHub's /ComplianceInquiries/Customers/Initialize
# lists, and /ComplianceInquiries/Customers/{CustomerId}/Initialize is one inquiry. twilio-php
# gives a context every id its list does not hold, so that id is the instance's own. A singleton
# has no list, and every id in its path belongs to a parent.
sub _key_inner_ids {
  my ($nodes) = @_;

  for my $node (values %{$nodes}) {
    my ($list, $instance) = @{$node}{qw(list instance)};
    next if !$list || !$instance || defined $instance->{key};

    my @ids  = $instance->{path}  =~ /[{](\w+)[}]/g;
    my $held = () = $list->{path} =~ /[{]/g;
    next                                                          if @ids <= $held;
    croak "$instance->{path}: more than one id beyond its list's" if @ids > $held + 1;
    $instance->{key} = $ids[-1];
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

    # twilio-php names a resource after the end of its list's URL, even an id: Routes v3's
    # /ShortCodes/{IsoCountryCode}/{ShortCode} is IsoCountryCode.
    my ($id) = $path =~ m{/[{](\w+)[}](?:[.]json)?\z};
    $node->{named_by_id} = $id if defined $id;
  }
  return;
}

# A parent path with no id, like /Configuration, reads as a list, but when only a singleton
# lives there its children go on the singleton. twilio-php puts them on a list class that only
# offers getContext, and calls read the same: configuration->webhooks and configuration->fetch.
# A parent that no path describes. When the child's link ends in an id, as iam_organizations'
# /Organizations/{OrganizationSid} does, it is an instance with no operations, so that the id has
# a place: organizations($organization_sid)->users, as in twilio-php.
sub _section {
  my ($key, $parent_path) = @_;

  my $section = { key => $key, segments => [split m{/}, $key], section => 1 };
  my $id      = defined $parent_path ? _instance_key($parent_path) : undef;
  return $section if !defined $id;

  # Its method is named after its class, as twilio-php and twilio-python have organization.
  $section->{instance}       = { path => $parent_path, operations => [], key => $id };
  $section->{mount_by_class} = 1;
  return $section;
}

sub _hang_on_singletons {
  my ($nodes) = @_;

  for my $node (values %{$nodes}) {
    next if ($node->{parent_side} // q{}) ne 'list';
    my $parent = $nodes->{ $node->{parent_key} } or next;
    next if $parent->{list} || !$parent->{instance} || defined $parent->{instance}{key};
    $node->{parent_side} = 'instance';
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
  my ($verb) = $id =~ /\A([A-Z][a-z]+)[A-Z]/;
  $verb = lc($verb // q{});
  croak "$path: cannot read a verb from operation '$id'" if !$IS_VERB{$verb};

  my $notes = $operation->{'x-twilio'} // {};
  return {
    verb   => $verb,
    method => uc $method,
    id     => $id,
    spec   => $operation,
    class  => scalar _declared_class($notes),
    notes  => $notes,
  };
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
# The spec says so by naming a class or a mount on the operation itself, and twilio-oai-generator
# groups operations by those names, so an operation that names another resource moves to it.
sub _split_by_names {
  my ($nodes) = @_;

  for my $key (sort keys %{$nodes}) {
    my $node = $nodes->{$key};
    my $own  = $node->{declared} // segment_class($node->{segments}[-1]);
    my %elsewhere;
    for my $operation (map { @{ $_->{operations} } } grep { $_ } @{$node}{qw(list instance)}) {
      my $class = $operation->{class} // next;
      $elsewhere{$class} = $operation->{notes} if $class ne $own;
    }
    _move_operations($nodes, $node, $_, $elsewhere{$_}) for sort keys %elsewhere;
  }
  return;
}

sub _move_operations {
  my ($nodes, $node, $class, $notes) = @_;

  my %sibling = (
    key         => "$node->{key}:$class",
    segments    => $node->{segments},
    parent_key  => $node->{parent_key},
    parent_side => $node->{parent_side},
    class_name  => $notes->{className} // snake($class),
    mount_name  => defined $notes->{mountName} ? snake($notes->{mountName}) : undef,
  );
  my $is_moved = sub { ($_[0]{class} // q{}) eq $class };
  for my $type (qw(list instance)) {
    my $side  = $node->{$type} or next;
    my @moved = grep { $is_moved->($_) } @{ $side->{operations} };
    next if !@moved;

    $side->{operations} = [grep { !$is_moved->($_) } @{ $side->{operations} }];
    $sibling{$type} = { %{$side}, operations => \@moved };
  }
  $nodes->{ $sibling{key} } = \%sibling;

  # Verify's /Passkeys/Challenges holds only NewChallenge's create, and twilio-php has no
  # Challenge left there: nothing would reach it but an object with no methods.
  my @remaining = map  { @{ $_->{operations} } } grep { $_ } @{$node}{qw(list instance)};
  my $is_parent = grep { ($_->{parent_key} // q{}) eq $node->{key} } values %{$nodes};
  delete $nodes->{ $node->{key} } if !@remaining && !$is_parent;
  return;
}

# The class that a path or an operation names: className, or else mountName made singular, as
# twilio-oai-generator does.
sub _declared_class {
  my ($notes) = @_;
  return camelize($notes->{className})                  if defined $notes->{className};
  return singular(camelize(snake($notes->{mountName}))) if defined $notes->{mountName};
  return;
}

# A list and an instance on the same segments are one resource when they agree on its name.
# When they do not, twilio-php makes two, like IAM's GetApiKeys list and ApiKey instance.
sub _node_key {
  my ($nodes, $key, $declared) = @_;

  my $node = $nodes->{$key} or return $key;
  return $key if ($node->{declared} // q{}) eq ($declared // q{});
  return "$key#" . ($declared // 'plain');
}

# When Twilio names the method that reaches a child, that name wins over one built from the
# path. Names are kept by class because resources split by noun share a URL, and by the shape of
# the URL, ids included, because two resources can share their segments: Bulk Exports names the
# jobs of an export, /Exports/{ResourceType}/Jobs, and /Exports/Jobs/{JobSid} is another one.
sub _dependent_mounts {
  my ($spec, $paths) = @_;

  my %mounts;
  for my $path (sort keys %{$paths}) {
    my $dependents = $paths->{$path}{'x-twilio'}{dependentProperties} // {};
    for my $mount (sort keys %{$dependents}) {
      my $url = $spec->strip($dependents->{$mount}{resource_url} // q{});
      $mounts{ _shape($url) }{ singular(camelize($mount)) } = $mount;
    }
  }
  return \%mounts;
}

# A list's URL, or an instance's without its own id, with every id the same.
sub _list_shape {
  my ($node) = @_;

  return _shape($node->{list}{path}) if $node->{list};
  my $instance = $node->{instance} or return q{};
  my $path     = $instance->{path};
  $path =~ s{/[{]\w+[}]((?:[.]json)?)\z}{$1} if defined $instance->{key};
  return _shape($path);
}

sub _shape {
  my ($path) = @_;
  return $path =~ s/[.]json\z//r =~ s/[{]\w+[}]/{}/gr;
}

# A parent is named first, because its name starts the child's. It can come later in the order,
# since a parent need not be part of the path, as Voice's /Settings shows.
sub _name_node {
  my ($nodes, $node, $mounts) = @_;
  return if $node->{class_parts};

  my $final_segment = $node->{segments}[-1];
  my $class =
      defined $node->{class_name}  ? camelize($node->{class_name})
    : defined $node->{mount_name}  ? singular(camelize($node->{mount_name}))
    : defined $node->{named_by_id} ? ucfirst $node->{named_by_id}
    :                                segment_class($final_segment);

  my @parents;
  if (defined $node->{parent_key}) {
    my $parent = $nodes->{ $node->{parent_key} };
    _name_node($nodes, $parent, $mounts);
    @parents = @{ $parent->{class_parts} };
    $node->{parent} = $parent->{class};
  }
  $node->{class_parts} = [@parents, $class];
  $node->{class}       = join q{::}, @{ $node->{class_parts} };
  $node->{mount}       = _mount($node, $mounts->{ _list_shape($node) }, $class);
  return;
}

sub _mount {
  my ($node, $names, $class) = @_;

  # A name the parent gives this very class wins. Otherwise the resource's own mount name does,
  # because two resources can share the segments: TaskRouter's queue statistics hang from both a
  # queue and the list of queues.
  my @all = sort values %{ $names // {} };
  return $names->{$class}             if defined $names->{$class};
  return $node->{mount_name}          if defined $node->{mount_name};
  return snake($class)                if $node->{mount_by_class};
  return snake($node->{named_by_id})  if defined $node->{named_by_id} && !@all;
  return snake($node->{segments}[-1]) if !@all;
  return $all[0]                      if @all == 1;
  croak "$node->{key}: called both $all[0] and $all[1]";
}

sub _check_unique {
  my ($resources) = @_;

  my (%classes, %mounts);
  for my $resource (@{$resources}) {
    my $class = $resource->{class};
    croak "$resource->{key} and $classes{$class} are both $class" if $classes{$class};
    $classes{$class} = $resource->{key};

    # A list and its instances can each have a child by the same name, as TaskRouter's queues
    # and each queue have their own statistics.
    my $side  = $resource->{parent_side} // 'instance';
    my $mount = join q{.}, $resource->{parent} // q{}, $resource->{mount};
    $mount .= " on the $side"                                    if defined $resource->{parent};
    croak "$resource->{key} and $mounts{$mount} are both $mount" if $mounts{$mount};
    $mounts{$mount} = $resource->{key};
  }
  return;
}

1;
