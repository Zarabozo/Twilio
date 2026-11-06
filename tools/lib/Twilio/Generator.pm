package Twilio::Generator;

use 5.016;
use warnings;

use Carp           qw(croak);
use File::Basename qw(dirname);
use File::Path     qw(make_path);

use Twilio::Generator::Emit;
use Twilio::Generator::Resource;
use Twilio::Generator::Spec;
use Twilio::Generator::Tree;

our $VERSION = '2.000000';

# Grows until the whole tree is generated.
my @GENERATED = ('Account::Message');

sub generated_files {
  my ($spec_file, $tidy_config) = @_;

  my $spec     = Twilio::Generator::Spec->load($spec_file);
  my $tree     = Twilio::Generator::Tree::build($spec);
  my %by_class = map { $_->{class} => $_ } @{ $tree->{resources} };

  my %files;
  for my $class (@GENERATED) {
    my $resource = $by_class{$class} // croak "No resource $class in $spec_file";
    my $model    = Twilio::Generator::Resource::build($spec, $tree, $resource);
    my $code     = Twilio::Generator::Emit::module($model);
    $files{ _file_name($model->{module}) } = tidy($code, $tidy_config);
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
