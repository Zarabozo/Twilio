use 5.016;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/lib";

use Getopt::Long qw(GetOptions);

use Twilio::Generator;
use Twilio::Generator::Report;
use Twilio::Generator::Spec;
use Twilio::Generator::Tree;

my $spec_dir = "$Bin/../spec";
my $out_dir  = "$Bin/../lib";
my ($tree_of, $report);
GetOptions(
  'spec-dir=s' => \$spec_dir,
  'out-dir=s'  => \$out_dir,
  'tree=s'     => \$tree_of,
  'report'     => \$report,
) or exit 2;

if (defined $tree_of) {
  my $spec = Twilio::Generator::Spec->load("$spec_dir/twilio_$tree_of.json");
  print Twilio::Generator::Tree::render(Twilio::Generator::Tree::build($spec));
  exit 0;
}

if ($report) {
  print Twilio::Generator::Report::text(Twilio::Generator::Report::dry_run($spec_dir));
  exit 0;
}

my $files = Twilio::Generator::generated_files($spec_dir, "$Bin/../.perltidyrc");
Twilio::Generator::write_files($files, $out_dir);
say for sort keys %{$files};

my $contracts = Twilio::Generator::contract_files($spec_dir);
Twilio::Generator::write_files($contracts, "$Bin/../t/data");
say "t/data/$_" for sort keys %{$contracts};
