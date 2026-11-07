use 5.016;
use warnings;

use Test::More;

use lib 'tools/lib';

use Twilio::Generator::Report;
use Twilio::Generator::Resource;
use Twilio::Generator::Scope;
use Twilio::Generator::Spec;

my $SPECS = 'spec';

my $excluded = Twilio::Generator::Scope::excluded();

subtest 'a spec has one place' => sub {
  my %seen;
  $seen{$_}++
    for Twilio::Generator::Scope::ready(), Twilio::Generator::Scope::pending(),
    keys %{$excluded};

  is_deeply([grep { $seen{$_} > 1 } sort keys %seen], [], 'none is listed twice');
};

# Spelled out here, so that letting one of these in takes a deliberate change in two places.
# Voice v2 and v3 wait for Twilio's answer about their license.
subtest 'what stays out' => sub {
  is_deeply([sort keys %{$excluded}], [qw(monitor_v2 voice_v2 voice_v3)], 'the list');
};

subtest 'each exclusion says why' => sub {
  ok(length $excluded->{$_}, "$_ has a reason") for sort keys %{$excluded};
};

subtest 'names follow twilio-php' => sub {
  my %expected = (
    frontline         => 'frontline_api',
    flex              => 'flex_api',
    iam_organizations => 'preview_iam',
    ip_messaging      => 'ip_messaging',
  );
  is(Twilio::Generator::Scope::domain_name($_), $expected{$_}, $_) for sort keys %expected;
};

subtest 'a spec file name' => sub {
  is(Twilio::Generator::Scope::spec_file('api_v2010'), 'twilio_api_v2010.json', 'with a version');
  is(Twilio::Generator::Scope::spec_file('preview'),   'twilio_preview.json',   'without one');
};

# The rest needs the specs, which are downloaded. CI fetches them first.
if (!-e "$SPECS/twilio_api_v2010.json") {
  diag('the specs are missing: run tools/fetch-specs.pl');
  done_testing;
  exit 0;
}

subtest 'the specs on disk are the ones in scope' => sub {
  my %known =
    map { Twilio::Generator::Scope::spec_file($_) => 1 } Twilio::Generator::Scope::in_scope();

  opendir my $handle, $SPECS or die "Cannot read $SPECS: $!\n";
  my @files = sort grep { /[.]json\z/ } readdir $handle;
  closedir $handle or die "Cannot read $SPECS: $!\n";

  is_deeply([grep { !$known{$_} } @files],               [], 'no spec is unknown');
  is_deeply([grep { !-e "$SPECS/$_" } sort keys %known], [], 'no spec is missing');
};

my $report = Twilio::Generator::Report::dry_run($SPECS);

subtest 'what is ready finishes' => sub {
  for my $name (Twilio::Generator::Scope::ready()) {
    is_deeply($report->{$name}{stops}, [], "$name has no stops");
  }
};

subtest 'what is pending still has a reason to be' => sub {
  for my $name (Twilio::Generator::Scope::pending()) {
    ok(scalar @{ $report->{$name}{stops} }, "$name still stops");
  }
};

subtest 'every stop is named' => sub {
  my @stops   = map  { @{ $report->{$_}{stops} } } sort keys %{$report};
  my @unnamed = grep { /\Awarning:|Can't use|uninitialized|Not a [A-Z]+ reference/ } @stops;

  is_deeply(\@unnamed, [], 'none is a crash or a warning');
};

subtest 'a warning counts as a stop' => sub {
  local *Twilio::Generator::Resource::build = sub { warn "something odd\n"; return {} };
  my $result = Twilio::Generator::Report::dry_run($SPECS);

  like($result->{frontline_v1}{stops}[0], qr/\Awarning: something odd/, 'it is reported');
};

done_testing;
