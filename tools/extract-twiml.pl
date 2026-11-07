use 5.016;
use warnings;

use FindBin qw($Bin);

use File::Find qw(find);
use JSON::PP   ();

# twilio-oai has no TwiML spec, so the names of elements and attributes are read once from the
# source of twilio-php into tools/twiml-elements.json, which the generator uses. Anything this
# script does not recognize stops it, because a skipped element would simply be missing.
#
# Usage: perl tools/extract-twiml.pl /path/to/twilio-php

# Attribute names that twilio-php writes wrongly, and its tests do not cover. twilio-python and
# Twilio's documentation use the names on the right.
my %CORRECT_ATTRIBUTE = ('for_' => 'for', 'xml:Lang' => 'xml:lang');

my %IS_LIST = map { $_ => 1 } qw(string[] int[]);

# The parts of a method in the PHP source.
my $COMMENT_END = qr{[*]/\s*};
my $METHOD      = qr/public\s+function\s+(\w+)\(([^)]*)\)[^{]*[{]\s*/;
my $NEST        = qr/return\s+\$this->nest\(new\s+([\w\\]+)\(([^)]*)\)\);/;
my $CHILD       = qr{/[*][*]\s*[*]\s*([^\n]*)\n(?:(?![*]/).)*?$COMMENT_END$METHOD$NEST}s;

my $PARAMETER = qr/[*]\s*\@param\s+(\S+)\s+\$\w+\s*((?:(?![*]\/).)*?)/s;
my $SETTER    = qr/public\s+function\s+(set\w+)\(\$(\w+)\):\s*self\s*[{]\s*/;
my $SET       = qr/return\s+\$this->setAttribute\('([^']+)',\s*\$\w+\);/;
my $ATTRIBUTE = qr/$PARAMETER$COMMENT_END$SETTER$SET/s;

my $root = shift // die "Usage: $0 /path/to/twilio-php\n";
my $dir  = "$root/src/Twilio/TwiML";

my %elements;
find(
  sub {
    return if !/[.]php\z/ || /\A(?:TwiML|GenericNode)[.]php\z/;
    my $class = $File::Find::name =~ s{\A\Q$dir\E/}{}r =~ s{[.]php\z}{}r =~ s{/}{::}gr;
    $elements{ perl_class($class) } = read_element($File::Find::name, $class);
  },
  $dir
);

for my $class (sort keys %elements) {
  for my $child (@{ $elements{$class}{children} }) {
    die "$class: unknown child $child->{class}\n" if !$elements{ $child->{class} };
  }
}

open my $handle, '>:raw', "$Bin/twiml-elements.json" or die "Cannot write: $!\n";
print {$handle} JSON::PP->new->utf8->canonical->pretty->indent_length(1)->encode(\%elements);
close $handle or die "Cannot write: $!\n";
say scalar(keys %elements), ' elements';

# PHP adds an underscore to names it reserves, like Echo_ and break_.
sub perl_class {
  my ($class) = @_;
  return $class =~ s/_\z//r;
}

sub snake {
  my ($name) = @_;
  $name =~ s/_+\z//;
  $name =~ s/([a-z0-9])([A-Z])/$1_$2/g;
  return lc $name;
}

sub read_element {
  my ($file, $class) = @_;

  open my $source, '<:encoding(UTF-8)', $file or die "Cannot read $file: $!\n";
  my $text = do { local $/ = undef; <$source> };
  close $source or die "Cannot read $file: $!\n";

  my ($space) = $class =~ /\A(\w+)::/;
  my %element = (php_class => $class, read_constructor($file, $text));
  $element{children}   = read_children($file, $text, $space);
  $element{attributes} = read_setters($file, $text);

  my @methods = $text =~ /public function (\w+)\(/g;
  my $known   = 1 + @{ $element{children} } + @{ $element{attributes} };
  die "$file: found " . scalar(@methods) . " methods and understood $known\n" if @methods != $known;
  return \%element;
}

sub read_constructor {
  my ($file, $text) = @_;

  my ($arguments) = $text =~ /public function __construct\(([^)]*)\)/;
  my ($tag, $value) = $text =~ /parent::__construct\('([^']+)',\s*(\$\w+|null)/;
  die "$file: no constructor\n" if !defined $tag;

  my $has_attributes = $arguments =~ /\$attributes/ ? 1 : 0;
  return (tag => $tag, has_attributes => $has_attributes, value => scalar value_name($value));
}

sub value_name {
  my ($value) = @_;
  return if $value eq 'null';
  return snake($value =~ s/\A\$//r);
}

sub read_children {
  my ($file, $text, $space) = @_;

  my @children;
  while ($text =~ /$CHILD/g) {
    my ($about, $method, $arguments, $class) = ($1, $2, $5, $4);
    my @names = $arguments =~ /\$(\w+)/g;
    my $value = (grep { $_ ne 'attributes' } @names)[0];

    push @children,
      {
      php_method     => $method,
      method         => snake($method),
      class          => perl_class(qualified($class, $space)),
      value          => defined $value                       ? snake($value) : undef,
      has_attributes => (grep { $_ eq 'attributes' } @names) ? 1             : 0,
      about          => $about,
      };
  }
  return [sort { $a->{method} cmp $b->{method} } @children];
}

sub qualified {
  my ($class, $space) = @_;

  my $name = $class =~ s/\\/::/gr;
  return $name if $name =~ /::/ || !defined $space;
  return "${space}::$name";
}

sub read_setters {
  my ($file, $text) = @_;

  my @attributes;
  while ($text =~ /$ATTRIBUTE/g) {
    my ($type, $note, $setter, $parameter, $wire) = ($1, $2, $3, $4, $5);

    # A description can run over several lines of the comment, and @return follows it.
    my $about = $note =~ s/\s*[*]?\s*\@return.*//sr =~ s/\s*\n\s*[*]\s*/ /gr =~ s/\s+\z//r;

    push @attributes,
      {
      setter   => $setter,
      method   => 'set_' . snake($parameter),
      name     => snake($parameter),
      wire     => $CORRECT_ATTRIBUTE{$wire} // $wire,
      php_wire => $wire,
      type     => $type eq 'bool' ? 'boolean' : $IS_LIST{$type} ? 'list' : 'text',
      php_type => $type,
      about    => $about,
      };
  }
  return [sort { $a->{name} cmp $b->{name} } @attributes];
}
