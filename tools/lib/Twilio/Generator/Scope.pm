package Twilio::Generator::Scope;

use 5.016;
use warnings;

our $VERSION = '2.000000';

my $NOT_SHIPPED = 'No official Twilio library ships it yet, and the scope follows them';
my $PROPRIETARY = 'The spec says "Proprietary and protected", so it stays out until Twilio '
  . 'authorizes it, although twilio-oai is MIT and twilio-php ships these classes';

# Each spec left out, and why. Users can still reach these with $client->request.
my %EXCLUDED = (monitor_v2 => $NOT_SHIPPED, voice_v2 => $PROPRIETARY, voice_v3 => $PROPRIETARY);

# twilio-php's name for a domain, where it is not the name of the spec.
my %DOMAIN_NAME =
  (flex => 'flex_api', frontline => 'frontline_api', iam_organizations => 'preview_iam');

my @READY = qw(
  api_v2010 bulkexports_v1 chat_v1 content_v2 events_v1 frontline_v1 insights_v1 ip_messaging_v1
  lookups_v1 monitor_v1 notify_v1 numbers_v3 oauth_v1 pricing_v1 pricing_v2 proxy_v1 routes_v2
  routes_v3 serverless_v1 studio_v1 supersim_v1 trunking_v1 voice_v1 wireless_v1
);

# Specs the generator cannot finish yet. They are named, and not skipped when they fail, because
# then a spec sync that broke one resource would silently delete a whole product from the
# library. xt/generator/scope.t fails when a spec here starts to work, so this list only shrinks.
my @PENDING = qw(
  accounts_v1 chat_v2 chat_v3 content_v1 conversations_v1 conversations_v2 flex_v1 flex_v2
  iam_organizations iam_v1 insights_v2 insights_v3 intelligence_v2 intelligence_v3 ip_messaging_v2
  knowledge_v1 knowledge_v2 lookups_v2 marketplace_v1 memory_v1 messaging_v1 messaging_v2
  messaging_v3 numbers_v1 numbers_v2 oauth_v2 preview studio_v2 sync_v1 taskrouter_v1 trusthub_v1
  verify_v2 video_v1 webhooks_v1
);

sub ready    { return @READY }
sub pending  { return @PENDING }
sub excluded { return {%EXCLUDED} }

sub in_scope {
  my @names = sort @READY, @PENDING;
  return @names;
}

sub spec_file {
  my ($name) = @_;
  return "twilio_$name.json";
}

sub domain_name {
  my ($name) = @_;
  return $DOMAIN_NAME{$name} // $name;
}

1;
