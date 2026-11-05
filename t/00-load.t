use 5.016;
use warnings;

use Test::More tests => 2;

BEGIN { use_ok('Twilio') or BAIL_OUT('Twilio failed to load') }

like(Twilio->VERSION, qr/\A\d+\.\d{6}\z/, 'version uses the six-decimal format');

diag("Testing Twilio $Twilio::VERSION on Perl $] ($^O)");
