use 5.016;
use warnings;

use FindBin qw($Bin);

use File::Path qw(make_path);
use HTTP::Tiny;

# Pinned to a release, so the same input always generates the same code. The specs stay out of
# the repository: the license of the Voice specs is an open question, and they can always be
# downloaded again.
my @SPECS    = qw(twilio_api_v2010.json);
my $BASE_URL = 'https://raw.githubusercontent.com/twilio/twilio-oai';

my $tag = read_tag("$Bin/twilio-oai.version");
my $dir = "$Bin/../spec";
make_path($dir);

my $http = HTTP::Tiny->new(agent => 'twilio-perl-generator', verify_SSL => 1);
for my $name (@SPECS) {
  my $response = $http->get("$BASE_URL/$tag/spec/json/$name");
  die "$name: $response->{status} $response->{reason}\n" if !$response->{success};

  open my $handle, '>:raw', "$dir/$name" or die "Cannot write $name: $!\n";
  print {$handle} $response->{content};
  close $handle or die "Cannot write $name: $!\n";
  say "$name from $tag";
}

sub read_tag {
  my ($file) = @_;

  open my $handle, '<', $file or die "Cannot read $file: $!\n";
  my $line = <$handle>;
  close $handle or die "Cannot read $file: $!\n";

  my ($found) = ($line // q{}) =~ /\A(\S+)/;
  die "No tag in $file\n" if !defined $found;
  return $found;
}
