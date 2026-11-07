package Twilio::Generator::Spec;

use 5.016;
use warnings;

use Carp           qw(croak);
use File::Basename qw(basename);
use JSON::PP       ();

use Twilio::Generator::Scope;

our $VERSION = '2.000000';

my $VERSION_PREFIX = qr{\A/(?:[0-9]{4}-[0-9]{2}-[0-9]{2}|v[0-9][a-z0-9]*)(?=/)};

sub new {
  my ($class, $domain, $version, $document) = @_;
  return bless { domain => $domain, version => $version, document => $document }, $class;
}

sub load {
  my ($class, $file) = @_;

  # Two specs have no version in their name, because each holds several versions.
  my ($domain, $version) = basename($file) =~ /\Atwilio_([a-z0-9_]+?)(?:_(v[a-z0-9]+))?[.]json\z/;
  croak "Not a spec file name: $file" if !defined $domain;

  open my $handle, '<:raw', $file or croak "Cannot read $file: $!";
  my $content = do { local $/ = undef; <$handle> };
  close $handle or croak "Cannot read $file: $!";

  my $name = Twilio::Generator::Scope::domain_name($domain);
  return $class->new($name, $version, JSON::PP->new->utf8->decode($content));
}

# The first path segment, which is the version in Twilio's URLs.
sub version_path {
  my ($self) = @_;

  my ($first)   = sort keys %{ $self->{document}{paths} // {} };
  my ($segment) = ($first // q{}) =~ $VERSION_PREFIX ? $first =~ m{\A/([^/]+)} : ();
  return $segment // croak 'No version in the paths of the spec';
}

sub base_url {
  my ($self) = @_;
  return $self->{document}{servers}[0]{url} // croak 'No server in the spec';
}

sub domain  { return $_[0]{domain} }
sub version { return $_[0]{version} }

# The parent links in x-twilio are written without the version.
sub paths {
  my ($self) = @_;
  my $paths = $self->{document}{paths} // {};
  return { map { strip_version($_) => $paths->{$_} } keys %{$paths} };
}

# An enum lives in components, and what matters here is the type it has there.
sub resolve {
  my ($self, $schema) = @_;

  my $reference = $schema->{'$ref'};
  return $schema if !defined $reference;

  # Parameters can be shared too, under components/parameters.
  my ($kind, $name) = $reference =~ m{\A#/components/(schemas|parameters)/(.+)\z};
  croak "Cannot follow $reference" if !defined $name;
  my $noun = $kind eq 'schemas' ? 'schema' : 'parameter';
  return $self->{document}{components}{$kind}{$name} // croak "No $noun $name";
}

sub strip_version {
  my ($path) = @_;
  return $path =~ s/$VERSION_PREFIX//r;
}

1;
