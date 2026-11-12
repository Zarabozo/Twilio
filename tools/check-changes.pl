use 5.016;
use warnings;

# Checks that the newest entry of Changes is the version being released, with its date.
# make dist runs it on the copy it is about to pack, because ExtUtils::MakeMaker leaves
# {{NEXT}} as it is, and 2.000000 went to CPAN with it. xt/author/changes.t runs it with
# --allow-next, since {{NEXT}} heads the entry being written between releases.
#
#   perl tools/check-changes.pl [--allow-next] VERSION FILE

my $allow_next = @ARGV && $ARGV[0] eq '--allow-next' ? shift @ARGV : 0;
my ($version, $file) = @ARGV;
die "Usage: $0 [--allow-next] VERSION FILE\n" if !defined $file;

my $heading = newest_heading($file);
my $wanted  = "'$version  YYYY-MM-DD'";
if ($heading eq '{{NEXT}}') {
  exit 0 if $allow_next;
  die "$file still starts with {{NEXT}}: replace it with $wanted before making the dist\n";
}
my ($found, $date) = $heading =~ /\A(\S+)\s+(\S+)/;
die "$file starts with '$heading', not $wanted\n"
  if !defined $date || $found ne $version || $date !~ /\A\d{4}-\d{2}-\d{2}\z/;
exit 0;

# An entry starts at a line with no indent, after the title line.
sub newest_heading {
  my ($path) = @_;
  open my $handle, '<', $path or die "Cannot read $path: $!\n";
  my @headings = grep { /\A\S/ } map { s/\s+\z//r } <$handle>;
  close $handle or die "Cannot read $path: $!\n";
  die "$path has no entry\n" if @headings < 2;
  return $headings[1];
}
