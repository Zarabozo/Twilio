package Twilio::Generator;

use 5.016;
use warnings;

use Carp           qw(croak);
use File::Basename qw(dirname);
use File::Path     qw(make_path);

use Twilio::Generator::Contract;
use Twilio::Generator::Emit;
use Twilio::Generator::Resource;
use Twilio::Generator::Scope;
use Twilio::Generator::Spec;
use Twilio::Generator::Tree;
use Twilio::Generator::TwiML;

our $VERSION = '2.000000';

my $TWIML_ELEMENTS = dirname(dirname(dirname(__FILE__))) . '/twiml-elements.json';

sub generated_files {
  my ($spec_dir, $tidy_config) = @_;

  my %files;
  my %versions_of;
  for my $version (map { load_versions($spec_dir, $_) } Twilio::Generator::Scope::ready()) {
    my ($spec, $tree) = @{$version};

    my %models;
    for my $resource (@{ $tree->{resources} }) {
      my $model = Twilio::Generator::Resource::build($spec, $tree, $resource);
      $models{ $resource->{class} } = $model;
      $files{ _file_name($model->{module}) } =
        tidy(Twilio::Generator::Emit::module($model), $tidy_config);
    }

    my $top = top_level($spec, $tree, $models{Account});
    $files{ _file_name($top->{version_class}) } =
      tidy(Twilio::Generator::Emit::version($top), $tidy_config);
    push @{ $versions_of{ $spec->domain } }, $top;
  }

  my @domains = map { domain_model($_, $versions_of{$_}) } sort keys %versions_of;
  check_client_names(\@domains);
  $files{ _file_name($_->{class}) } = tidy(Twilio::Generator::Emit::domain($_), $tidy_config)
    for @domains;
  $files{'Twilio/Rest/Client.pm'} = tidy(Twilio::Generator::Emit::client(\@domains), $tidy_config);

  my $twiml = Twilio::Generator::TwiML::modules(Twilio::Generator::TwiML::load($TWIML_ELEMENTS));
  $files{$_} = tidy($twiml->{$_}, $tidy_config) for keys %{$twiml};
  return \%files;
}

# Each version in a spec, with its tree. Most specs hold one.
sub load_versions {
  my ($spec_dir, $name) = @_;

  my $file = "$spec_dir/" . Twilio::Generator::Scope::spec_file($name);
  my $spec = Twilio::Generator::Spec->load($file);
  return map { [$_, Twilio::Generator::Tree::build($_)] } $spec->versions;
}

# What the version and its domain need. Only the main API has an account to offer shortcuts of.
sub top_level {
  my ($spec, $tree, $account) = @_;

  my %top = (
    base_url       => $spec->base_url,
    domain_class   => Twilio::Generator::Resource::root_class($tree) =~ s/::\w+\z//r,
    roots          => Twilio::Generator::Resource::root_children($spec, $tree),
    shortcuts      => [],
    version_class  => Twilio::Generator::Resource::root_class($tree),
    version_method => $tree->{version},
    version_path   => $spec->version_path,
    v1_standard    => $spec->follows_v1_standard,
  );
  return \%top if !$account || $tree->{domain} ne 'api';

  $top{account_context} = $account->{class}{context};
  $top{account_module}  = $account->{module};
  $top{shortcuts}       = [sort { $a->{mount} cmp $b->{mount} } @{ $account->{context}{children} }];
  return \%top;
}

sub domain_model {
  my ($name, $versions) = @_;

  my ($first) = @{$versions};
  my @hosts = grep { $_->{base_url} ne $first->{base_url} } @{$versions};
  croak "$name: its versions live on different hosts" if @hosts;

  my ($main) = grep { $_->{account_context} } @{$versions};
  return {
    method    => $name,
    class     => $first->{domain_class},
    base_url  => $first->{base_url},
    versions  => [sort { $a->{version_method} cmp $b->{version_method} } @{$versions}],
    shortcuts => [_host_shortcuts($name, $versions)],
    defined $main ? (main => $main) : (),
  };
}

# twilio-php writes these by hand on each host, and marks all but this one deprecated, besides
# the main API's, which come from its account. A version they name must have the resource.
my %HOST_SHORTCUTS = (preview_iam => { versionless => ['organization'] });

sub _host_shortcuts {
  my ($name, $versions) = @_;

  my $wanted     = $HOST_SHORTCUTS{$name} or return;
  my %version_of = map { $_->{version_method} => $_ } @{$versions};
  my @shortcuts;
  for my $method (sort keys %{$wanted}) {
    my $version = $version_of{$method} or croak "$name: no version $method for its shortcuts";
    for my $mount (@{ $wanted->{$method} }) {
      my ($root) = grep { $_->{mount} eq $mount } @{ $version->{roots} };
      croak "$name: no $mount in $method for a shortcut" if !$root;
      push @shortcuts, { %{$root}, version_method => $method };
    }
  }
  return @shortcuts;
}

# A domain and a shortcut of the account would be two methods with one name on the client.
sub check_client_names {
  my ($domains) = @_;

  my ($main) = map { $_->{main} // () } @{$domains};
  croak 'No domain has the account of the client' if !$main;

  my %is_shortcut = map { $_->{mount} => 1 } @{ $main->{shortcuts} }, { mount => 'account' };
  for my $domain (@{$domains}) {
    croak "$domain->{method} is both a domain and a shortcut" if $is_shortcut{ $domain->{method} };
  }
  return;
}

sub contract_files {
  my ($spec_dir) = @_;

  my %files;
  for my $name (Twilio::Generator::Scope::ready()) {
    my $entries = [
      sort { $a->{id} cmp $b->{id} }
      map  { @{ Twilio::Generator::Contract::entries(@{$_}) } } load_versions($spec_dir, $name)
    ];
    $files{ 'contract-' . ($name =~ tr/_/-/r) . '.json' } =
      Twilio::Generator::Contract::to_json($entries);
  }
  return \%files;
}

sub write_files {
  my ($files, $directory) = @_;

  for my $name (sort keys %{$files}) {
    my $path = "$directory/$name";
    make_path(dirname($path));
    open my $handle, '>:raw', $path or croak "Cannot write $path: $!";
    print {$handle} $files->{$name};
    close $handle or croak "Cannot write $path: $!";
  }
  return;
}

# Loaded here because only the generator needs it, and it is slow to load.
sub tidy {
  my ($code, $config) = @_;
  require Perl::Tidy;

  # The descriptions from the spec are characters, and files hold bytes.
  utf8::encode($code);

  my ($tidied, $errors);
  my $failed = Perl::Tidy::perltidy(
    source      => \$code,
    destination => \$tidied,
    perltidyrc  => $config,
    argv        => [],
    stderr      => \$errors,
    errorfile   => \$errors,
  );
  croak 'perltidy refused the generated code: ' . ($errors // q{}) if $failed;
  return $tidied;
}

sub _file_name {
  my ($module) = @_;
  return ($module =~ s{::}{/}gr) . '.pm';
}

1;
