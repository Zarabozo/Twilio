package Twilio::Generator::Spec;

use 5.016;
use warnings;

use Carp           qw(croak);
use File::Basename qw(basename);
use JSON::PP       ();

our $VERSION = '2.000000';

my $VERSION_PREFIX = qr{\A/(?:[0-9]{4}-[0-9]{2}-[0-9]{2}|v[0-9][a-z0-9]*)(?=/)};

sub new {
  my ($class, $domain, $version, $document) = @_;
  return bless { domain => $domain, version => $version, document => $document }, $class;
}

sub load {
  my ($class, $file) = @_;

  my ($domain, $version) = basename($file) =~ /\Atwilio_([a-z0-9_]+)_(v[a-z0-9]+)[.]json\z/;
  croak "Not a spec file name: $file" if !defined $domain;

  open my $handle, '<:raw', $file or croak "Cannot read $file: $!";
  my $content = do { local $/ = undef; <$handle> };
  close $handle or croak "Cannot read $file: $!";

  return $class->new($domain, $version, JSON::PP->new->utf8->decode($content));
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

  my ($name) = $reference =~ m{\A#/components/schemas/(.+)\z};
  croak "Cannot follow $reference" if !defined $name;
  return $self->{document}{components}{schemas}{$name} // croak "No schema $name";
}

sub strip_version {
  my ($path) = @_;
  return $path =~ s/$VERSION_PREFIX//r;
}

1;
