package Twilio::Generator::Contract;

use 5.016;
use warnings;

use Carp        qw(croak);
use JSON::PP    ();
use Time::Local qw(timegm);

use Twilio::Generator::Resource;
use Twilio::Generator::Spec;
use Twilio::Generator::Types qw(option_name);

our $VERSION = '2.000000';

my %IS_PAGE_PARAMETER = map { $_ => 1 } qw(Page PageSize PageToken);
my %METHOD_FOR_VERB   = (list => 'page');
my $FORM_CONTENT      = 'application/x-www-form-urlencoded';

my $DAYS_IN_A_SHORT_MONTH = 28;
my $HALF                  = 0.5;

# What each operation must do on the wire, read from the spec and not from the emitter's model,
# so that t/contract.t cannot repeat a mistake made while writing the classes.
sub entries {
  my ($spec, $tree) = @_;

  my %by_class = map { $_->{class} => $_ } @{ $tree->{resources} };
  my @root     = ([$tree->{domain}, 0], [$tree->{version}, 0]);
  my @entries;
  for my $resource (@{ $tree->{resources} }) {
    for my $type (qw(list instance)) {
      my $side  = $resource->{$type} or next;
      my $chain = _chain(\%by_class, \@root, $resource, $type);
      push @entries,
        map { _entry($spec, $tree, $resource, $side, $chain, $_) } @{ $side->{operations} };
    }
  }
  return [sort { $a->{id} cmp $b->{id} } @entries];
}

sub to_json {
  my ($entries) = @_;
  return JSON::PP->new->utf8->canonical->pretty->indent_length(1)->encode($entries);
}

# The calls that lead from the client to the object, each with whether it takes an id.
sub _chain {
  my ($by_class, $root, $resource, $type) = @_;

  my $takes_id = $type eq 'instance' && defined $resource->{instance}{key} ? 1 : 0;
  my $link     = [$resource->{mount}, $takes_id];
  return [@{$root}, $link] if !defined $resource->{parent};

  my $parent = $by_class->{ $resource->{parent} } // croak "No parent for $resource->{key}";
  return [@{ _chain($by_class, $root, $parent, $resource->{parent_side} // 'instance') }, $link];
}

sub _entry {
  my ($spec, $tree, $resource, $side, $chain, $operation) = @_;

  my $id_count = grep { $_->[1] } @{$chain};
  my $next_id  = 0;
  my $url      = $side->{path} =~ s/[{]\w+[}]/'id' . ++$next_id/ger;
  croak "$operation->{id}: $next_id parameters in the path and $id_count in the calls"
    if $next_id != $id_count;

  my $body = _body($spec, $operation);
  my $list = $operation->{verb} eq 'list';

  my %entry = (
    id       => $operation->{id},
    http     => $operation->{method},
    url      => $spec->base_url . q{/} . $spec->version_path . $url,
    chain    => $chain,
    method   => $METHOD_FOR_VERB{ $operation->{verb} } // $operation->{verb},
    required => [],
    options  => {},
    expected => [],
  );

  for my $name (@{ $body->{required} }) {
    my ($input, @wire) = _sample($spec, $name, $body->{properties}{$name});
    push @{ $entry{required} }, $input;
    push @{ $entry{expected} }, map { [$name, $_] } @wire;
  }
  for my $name (sort keys %{ $body->{properties} }) {
    next if grep { $_ eq $name } @{ $body->{required} };
    _add_option(\%entry, $spec, $name, $body->{properties}{$name});
  }
  for my $parameter (@{ $operation->{spec}{parameters} // [] }) {
    next if $parameter->{in} ne 'query' || $IS_PAGE_PARAMETER{ $parameter->{name} };
    _add_option(\%entry, $spec, $parameter->{name}, $parameter->{schema});
  }

  if ($list) {
    my $model = Twilio::Generator::Resource::build($spec, $tree, $resource);
    $entry{records_key} = $model->{records_key};
  }
  return \%entry;
}

sub _body {
  my ($spec, $operation) = @_;

  my $content = $operation->{spec}{requestBody}{content} // {};
  my $schema  = $content->{$FORM_CONTENT} ? $spec->resolve($content->{$FORM_CONTENT}{schema}) : {};
  return { properties => $schema->{properties} // {}, required => $schema->{required} // [] };
}

sub _add_option {
  my ($entry, $spec, $wire_name, $schema) = @_;

  my ($input, @wire) = _sample($spec, $wire_name, $schema);
  $entry->{options}{ option_name($wire_name) } = $input;
  push @{ $entry->{expected} }, map { [$wire_name, $_] } @wire;
  return;
}

# Stands for a date object in t/contract.t: a date given as text is sent as it is, which would
# not show whether a date is converted.
sub _moment {
  my ($day) = @_;
  return { epoch => timegm(5, 4, 3, $day, 0, 2026) };
}

# A value to pass in, and what must then appear on the wire. Each one comes from the name of its
# parameter, so that two values wired to each other's place cannot look right.
sub _sample {
  my ($spec, $wire_name, $schema) = @_;

  my $resolved = $spec->resolve($schema // {});
  my $type     = $resolved->{type}   // q{};
  my $format   = $resolved->{format} // $type;
  my $text     = 'v_' . option_name($wire_name);
  my $number   = unpack '%32C*', $wire_name;
  my $day      = $number % $DAYS_IN_A_SHORT_MONTH + 1;
  my $date     = sprintf '2026-01-%02d', $day;

  return (["${text}_1", "${text}_2"], "${text}_1", "${text}_2") if $type eq 'array';
  return (1,               'true')              if $format eq 'boolean';
  return (_moment($day),   $date)               if $format eq 'date';
  return (_moment($day),   "${date}T03:04:05Z") if $format eq 'date-time';
  return ({ a => 1 },      '{"a":1}')           if $format eq q{};
  return ($number,         "$number")           if $type eq 'integer';
  return ($number + $HALF, $number + $HALF)     if $type eq 'number';

  my @choices = @{ $resolved->{enum} // [] };
  my $value   = @choices ? $choices[$number % @choices] : $text;
  return ($value, $value);
}

1;
