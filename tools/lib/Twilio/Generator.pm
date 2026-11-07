package Twilio::Generator;

use 5.016;
use warnings;

use Carp           qw(croak);
use File::Basename qw(dirname);
use File::Path     qw(make_path);

use Twilio::Generator::Contract;
use Twilio::Generator::Emit;
use Twilio::Generator::Resource;
use Twilio::Generator::Spec;
use Twilio::Generator::Tree;
use Twilio::Generator::TwiML;

our $VERSION = '2.000000';

my $TWIML_ELEMENTS = dirname(dirname(dirname(__FILE__))) . '/twiml-elements.json';

sub generated_files {
  my ($spec_file, $tidy_config) = @_;

  my $spec = Twilio::Generator::Spec->load($spec_file);
  my $tree = Twilio::Generator::Tree::build($spec);

  my %files;
  my %models;
  for my $resource (@{ $tree->{resources} }) {
    my $model = Twilio::Generator::Resource::build($spec, $tree, $resource);
    $models{ $resource->{class} } = $model;
    $files{ _file_name($model->{module}) } =
      tidy(Twilio::Generator::Emit::module($model), $tidy_config);
  }

  my $top = _top_level($spec, $tree, $models{Account} // croak "No Account in $spec_file");
  $files{ _file_name($top->{version_class}) } =
    tidy(Twilio::Generator::Emit::version($top), $tidy_config);
  $files{ _file_name($top->{domain_class}) } =
    tidy(Twilio::Generator::Emit::domain($top), $tidy_config);
  $files{'Twilio/Rest/Client.pm'} = tidy(Twilio::Generator::Emit::client($top), $tidy_config);

  my $twiml = Twilio::Generator::TwiML::modules(Twilio::Generator::TwiML::load($TWIML_ELEMENTS));
  $files{$_} = tidy($twiml->{$_}, $tidy_config) for keys %{$twiml};
  return \%files;
}

# What the client, the domain and the version need: each offers the resources of an account.
sub _top_level {
  my ($spec, $tree, $account) = @_;

  my $domain_class = Twilio::Generator::Resource::root_class($tree) =~ s/::\w+\z//r;
  return {
    account_context => $account->{class}{context},
    account_list    => $account->{class}{list},
    account_module  => $account->{module},
    base_url        => $spec->base_url,
    domain_class    => $domain_class,
    shortcuts       => [sort { $a->{mount} cmp $b->{mount} } @{ $account->{context}{children} }],
    version_class   => Twilio::Generator::Resource::root_class($tree),
    version_method  => $tree->{version},
    version_path    => $spec->version_path,
  };
}

sub contract_json {
  my ($spec_file) = @_;

  my $spec = Twilio::Generator::Spec->load($spec_file);
  my $tree = Twilio::Generator::Tree::build($spec);
  return Twilio::Generator::Contract::to_json(Twilio::Generator::Contract::entries($spec, $tree));
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
