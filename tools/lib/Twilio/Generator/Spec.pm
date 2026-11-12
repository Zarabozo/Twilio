package Twilio::Generator::Spec;

use 5.016;
use warnings;

use Carp           qw(croak);
use File::Basename qw(basename);
use JSON::PP       ();

use Twilio::Generator::Scope;

our $VERSION = '2.001';

my $VERSION_PREFIX = qr{\A/(?:[0-9]{4}-[0-9]{2}-[0-9]{2}|v[0-9][a-z0-9]*)(?=/)};

sub new {
  my ($class, $domain, $version, $document) = @_;

  my $self = bless { domain => $domain, version => $version, document => $document }, $class;
  $self->_resolve_shared;
  return $self;
}

# Some specs share parameters under components/parameters, and Memory shares its redirects under
# components/responses. Each operation gets them in place, so that nothing after this has to tell
# a reference from what it names.
sub _resolve_shared {
  my ($self) = @_;

  for my $item (values %{ $self->{document}{paths} // {} }) {
    for my $operation (grep { ref eq 'HASH' } values %{$item}) {
      my $listed = $operation->{parameters};
      $operation->{parameters} = [map { $self->resolve($_) } @{$listed}] if ref $listed eq 'ARRAY';

      my $responses = $operation->{responses};
      next if ref $responses ne 'HASH';
      $responses->{$_} = $self->resolve($responses->{$_}) for keys %{$responses};
    }
  }
  return;
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

# A spec with no version in its name holds several, and twilio-oai-generator makes each first
# path segment one: preview's /HostedNumbers/... is Preview::HostedNumbers. Each is a spec of
# its own from here on.
sub versions {
  my ($self) = @_;
  return ($self) if defined $self->{version};

  my %paths_of;
  for my $path (sort keys %{ $self->{document}{paths} // {} }) {
    my ($first) = $path =~ m{\A/([^/]+)} or croak "No version in path $path";
    $paths_of{$first}{$path} = $self->{document}{paths}{$path};
  }
  return map { $self->_version_spec($_, $paths_of{$_}) } sort keys %paths_of;
}

# A version named apart from its segment keeps the segment in its paths and has no URL of its
# own, as twilio-php's PreviewIam::Versionless keeps /Organizations.
sub _version_spec {
  my ($self, $segment, $paths) = @_;

  my $named = Twilio::Generator::Scope::version_name($self->{domain}, $segment);
  my $class = ref $self;
  my $spec  = $class->new(
    $self->{domain},
    $named // _version_id($segment),
    { %{ $self->{document} }, paths => $paths }
  );
  $spec->{version_path} = defined $named ? q{} : $segment;
  return $spec;
}

sub _version_id {
  my ($segment) = @_;
  return lc $segment =~ s/([a-z0-9])([A-Z])/$1_$2/gr;
}

# The first path segment, which is the version in Twilio's URLs.
sub version_path {
  my ($self) = @_;
  return $self->{version_path} if exists $self->{version_path};

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

# Twilio's newer APIs follow its v1.0 standard: errors of another shape, and pages that move by
# token. twilio-php uses ApiV1Version and TokenPaginationPage for exactly these specs.
sub follows_v1_standard {
  my ($self) = @_;
  return (($self->{document}{info}{'x-twilio'} // {})->{apiStandards} // q{}) eq 'v1.0' ? 1 : 0;
}

# The parent links in x-twilio are written without the version.
sub paths {
  my ($self) = @_;
  my $paths = $self->{document}{paths} // {};
  return { map { $self->strip($_) => $paths->{$_} } keys %{$paths} };
}

# A path without this spec's version, which is not always one like v1: preview has HostedNumbers.
sub strip {
  my ($self, $path) = @_;
  return strip_version($path) if !exists $self->{version_path};

  my $segment = $self->{version_path};
  return length $segment ? $path =~ s{\A/\Q$segment\E(?=/)}{}r : $path;
}

# An enum lives in components, and what matters here is the type it has there.
sub resolve {
  my ($self, $schema) = @_;

  my $reference = $schema->{'$ref'};
  return $schema if !defined $reference;

  # Parameters and responses can be shared too.
  my ($kind, $name) = $reference =~ m{\A#/components/(schemas|parameters|responses)/(.+)\z};
  croak "Cannot follow $reference" if !defined $name;
  my $noun = $kind =~ s/s\z//r;
  return $self->{document}{components}{$kind}{$name} // croak "No $noun $name";
}

sub strip_version {
  my ($path) = @_;
  return $path =~ s/$VERSION_PREFIX//r;
}

1;
