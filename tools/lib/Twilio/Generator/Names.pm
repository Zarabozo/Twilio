package Twilio::Generator::Names;

use 5.016;
use warnings;

use Exporter qw(import);

our @EXPORT_OK = qw(camelize segment_class singular snake);

our $VERSION = '2.000000';

sub camelize {
  my ($name) = @_;
  return join q{}, map { ucfirst } split /_/, $name;
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
  return $word =~ s/ies\z/y/r if $word =~ /[^aeiou]ies\z/;
  return $word =~ s/es\z//r   if $word =~ /(?:ss|x|ch|sh)es\z/;
  return $word if $word =~ /ss\z/;
  return $word =~ s/s\z//r;
}

sub segment_class {
  my ($segment) = @_;

  # An acronym like SIP is a class named Sip in the official libraries.
  return ucfirst lc $segment if $segment =~ /\A[A-Z]+\z/;
  return singular($segment);
}

1;
