package Twilio::Generator::Names;

use 5.016;
use warnings;

use Exporter qw(import);

our @EXPORT_OK = qw(camelize segment_class singular snake);

our $VERSION = '2.002';

# A letter after a digit starts a word, as in Twilio's generator: TrustHub's a2p_brand_registrations
# are A2PBrandRegistration in twilio-php, twilio-python and twilio-node.
sub camelize {
  my ($name) = @_;
  return join q{}, map { ucfirst =~ s/([0-9])([a-z])/$1\u$2/gr } split /_/, $name;
}

sub snake {
  my ($name) = @_;
  $name =~ s/([a-z0-9])([A-Z])/$1_$2/g;
  return lc $name;
}

# Twilio's own generators use a full inflector. These rules are enough for the words in the
# specs, and the comparison with twilio-php shows when one stops being enough.
sub singular {
  my ($word) = @_;

  # The inflector reads the word Bases as the plural of basis, so twilio-php and twilio-python
  # both have KnowledgeBasis, which this keeps. Databases is still a Database.
  return $word =~ s/ases\z/asis/r if $word =~ /(?:\A[Bb]|B)ases\z/;
  return $word =~ s/ies\z/y/r     if $word =~ /[^aeiou]ies\z/;
  return $word =~ s/es\z//r       if $word =~ /(?:ss|us|x|ch|sh)es\z/;
  return $word if $word =~ /(?:ss|us)\z/;
  return $word =~ s/s\z//r;
}

sub segment_class {
  my ($segment) = @_;

  # An acronym like SIP is a class named Sip in the official libraries.
  return ucfirst lc $segment if $segment =~ /\A[A-Z]+\z/;

  # A few paths are lowercase, like OAuth's /v1/token.
  return ucfirst singular($segment);
}

1;
