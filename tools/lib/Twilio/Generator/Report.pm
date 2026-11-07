package Twilio::Generator::Report;

use 5.016;
use warnings;

use Carp qw(croak);

use Twilio::Generator;
use Twilio::Generator::Contract;
use Twilio::Generator::Emit;
use Twilio::Generator::Resource;
use Twilio::Generator::Scope;

our $VERSION = '2.000000';

# Tries every spec in scope and writes nothing, to show what still stops each one. A warning
# counts as a stop, because it means the generator went on with something it did not understand.
sub dry_run {
  my ($spec_dir) = @_;

  local $SIG{__WARN__} = sub { croak "warning: $_[0]" };
  return { map { $_ => _try_spec($spec_dir, $_) } Twilio::Generator::Scope::in_scope() };
}

sub _try_spec {
  my ($spec_dir, $name) = @_;

  my %result = (resources => 0, stops => []);
  my ($spec, $tree);
  my $loaded = eval { ($spec, $tree) = Twilio::Generator::load_spec($spec_dir, $name); 1 };
  if (!$loaded) {
    push @{ $result{stops} }, _stop_text($@);
    return \%result;
  }

  for my $resource (@{ $tree->{resources} }) {
    my $built = eval {
      my $model = Twilio::Generator::Resource::build($spec, $tree, $resource);
      Twilio::Generator::Emit::module($model);
      1;
    };
    if   ($built) { $result{resources}++ }
    else          { push @{ $result{stops} }, _stop_text($@) }
  }

  # These only make sense once every resource has been built.
  if (!@{ $result{stops} }) {
    my $finished = eval {
      Twilio::Generator::top_level($spec, $tree);
      Twilio::Generator::Contract::entries($spec, $tree);
      1;
    };
    push @{ $result{stops} }, _stop_text($@) if !$finished;
  }
  return \%result;
}

sub _stop_text {
  my ($error) = @_;
  return $error =~ s/ at \S+ line \d+.*//sr;
}

sub text {
  my ($report) = @_;

  my @names = sort keys %{$report};
  my @clean = grep { !@{ $report->{$_}{stops} } } @names;

  my ($built, $stopped) = (0, 0);
  my %count;
  for my $name (@names) {
    $built   += $report->{$name}{resources};
    $stopped += @{ $report->{$name}{stops} };
    $count{ _kind($_) }++ for @{ $report->{$name}{stops} };
  }

  my @lines = (
    scalar(@names) . ' specs in scope, ' . scalar(@clean) . ' finish',
    "$built resources build, $stopped stops",
    q{},
    'Stops by kind:',
    map { sprintf '%5d  %s', $count{$_}, $_ }
      sort { $count{$b} <=> $count{$a} || $a cmp $b } keys %count,
  );
  push @lines, q{}, 'Stops by spec:', map { _spec_line($_, $report->{$_}) } @names;
  return join q{}, map { "$_\n" } @lines;
}

# What stopped, without the resource it happened in, so equal causes add up.
sub _kind {
  my ($stop) = @_;
  return $stop =~ s/\A[^:]+: //r;
}

sub _spec_line {
  my ($name, $result) = @_;
  return sprintf '%5d  %s (%d build)', scalar @{ $result->{stops} }, $name, $result->{resources};
}

1;
