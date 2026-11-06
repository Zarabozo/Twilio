use 5.016;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/lib";

use Getopt::Long qw(GetOptions);

use Twilio::Generator::Spec;
use Twilio::Generator::Tree;

my $spec_dir = "$Bin/../spec";
my $tree_of;
GetOptions('spec-dir=s' => \$spec_dir, 'tree=s' => \$tree_of) or exit 2;
die "Usage: $0 --tree api_v2010 [--spec-dir DIR]\n" if !defined $tree_of;

my $spec = Twilio::Generator::Spec->load("$spec_dir/twilio_$tree_of.json");
print Twilio::Generator::Tree::render(Twilio::Generator::Tree::build($spec));
