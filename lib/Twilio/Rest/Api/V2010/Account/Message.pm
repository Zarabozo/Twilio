package Twilio::Rest::Api::V2010::Account::Message;

use 5.016;
use warnings;

our $VERSION = '2.000000';

package Twilio::Rest::Api::V2010::Account::MessageList;

use parent 'Twilio::ListResource';

use Twilio::Serialize;

sub new {
  my ($class, $version, $account_sid) = @_;
  my $self = $class->SUPER::new($version);
  $self->{solution} = { account_sid => $account_sid };
  $self->{uri} = '/Accounts/' . Twilio::Serialize::path_segment($account_sid) . '/Messages.json';
  return $self;
}

sub create {
  my ($self, $to, $options) = @_;
  $options //= {};

  my $data = {
    To                  => $to,
    StatusCallback      => $options->{status_callback},
    ApplicationSid      => $options->{application_sid},
    MaxPrice            => $options->{max_price},
    ProvideFeedback     => Twilio::Serialize::boolean_to_string($options->{provide_feedback}),
    Attempt             => $options->{attempt},
    ValidityPeriod      => $options->{validity_period},
    ForceDelivery       => Twilio::Serialize::boolean_to_string($options->{force_delivery}),
    ContentRetention    => $options->{content_retention},
    AddressRetention    => $options->{address_retention},
    SmartEncoded        => Twilio::Serialize::boolean_to_string($options->{smart_encoded}),
    PersistentAction    => $options->{persistent_action},
    TrafficType         => $options->{traffic_type},
    ShortenUrls         => Twilio::Serialize::boolean_to_string($options->{shorten_urls}),
    ScheduleType        => $options->{schedule_type},
    SendAt              => Twilio::Serialize::iso8601_date_time($options->{send_at}),
    SendAsMms           => Twilio::Serialize::boolean_to_string($options->{send_as_mms}),
    ContentVariables    => $options->{content_variables},
    MessageIntent       => $options->{message_intent},
    RiskCheck           => $options->{risk_check},
    From                => $options->{from},
    FallbackFrom        => $options->{fallback_from},
    MessagingServiceSid => $options->{messaging_service_sid},
    Body                => $options->{body},
    MediaUrl            => $options->{media_url},
    ContentSid          => $options->{content_sid},
  };

  my $version  = $self->{version};
  my $response = $version->handle_request('POST', $self->{uri}, 'create', { data => $data });
  return Twilio::Rest::Api::V2010::Account::MessageInstance->new($version, $response->get_content,
    $self->{solution}{account_sid});
}

sub read {
  my ($self, @arguments) = @_;
  return $self->read_records(@arguments);
}

sub stream {
  my ($self, @arguments) = @_;
  return $self->stream_records(@arguments);
}

sub page {
  my ($self, $options, $page_size, $page_token, $page_number) = @_;
  $options //= {};

  my $params = {
    To          => $options->{to},
    From        => $options->{from},
    'DateSent<' => Twilio::Serialize::iso8601_date_time($options->{date_sent_before}),
    DateSent    => Twilio::Serialize::iso8601_date_time($options->{date_sent}),
    'DateSent>' => Twilio::Serialize::iso8601_date_time($options->{date_sent_after}),
    PageToken   => $page_token,
    Page        => $page_number,
    PageSize    => $page_size,
  };

  my $response = $self->{version}->page('GET', $self->{uri}, { params => $params });
  return $self->_build_page($response);
}

sub get_page {
  my ($self, $target_url) = @_;
  my $client = $self->{version}->get_domain->get_client;
  return $self->_build_page($client->request('GET', $target_url));
}

sub get_context {
  my ($self, $sid) = @_;
  return Twilio::Rest::Api::V2010::Account::MessageContext->new($self->{version},
    $self->{solution}{account_sid}, $sid);
}

sub _build_page {
  my ($self, $response) = @_;
  return Twilio::Rest::Api::V2010::Account::MessagePage->new($self->{version}, $response,
    $self->{solution});
}

package Twilio::Rest::Api::V2010::Account::MessagePage;

use parent 'Twilio::Page';

sub records_key { return 'messages' }

sub build_instance {
  my ($self, $payload) = @_;
  return Twilio::Rest::Api::V2010::Account::MessageInstance->new($self->{version}, $payload,
    $self->{solution}{account_sid});
}

package Twilio::Rest::Api::V2010::Account::MessageContext;

use parent 'Twilio::InstanceContext';

use Twilio::Serialize;

sub new {
  my ($class, $version, $account_sid, $sid) = @_;
  my $self = $class->SUPER::new($version);
  $self->{solution} = { account_sid => $account_sid, sid => $sid };
  $self->{uri}      = join q{}, '/Accounts/', Twilio::Serialize::path_segment($account_sid),
    '/Messages/', Twilio::Serialize::path_segment($sid), '.json';
  return $self;
}

sub delete {
  my ($self) = @_;
  $self->{version}->handle_request('DELETE', $self->{uri}, 'delete');
  return 1;
}

sub fetch {
  my ($self) = @_;
  my $response = $self->{version}->handle_request('GET', $self->{uri}, 'fetch');
  return $self->_build_instance($response);
}

sub update {
  my ($self, $options) = @_;
  $options //= {};

  my $data = { Body => $options->{body}, Status => $options->{status} };

  my $response =
    $self->{version}->handle_request('POST', $self->{uri}, 'update', { data => $data });
  return $self->_build_instance($response);
}

sub _build_instance {
  my ($self, $response) = @_;
  my $solution = $self->{solution};
  return Twilio::Rest::Api::V2010::Account::MessageInstance->new($self->{version},
    $response->get_content, $solution->{account_sid},
    $solution->{sid});
}

package Twilio::Rest::Api::V2010::Account::MessageInstance;

use parent 'Twilio::InstanceResource';

use Twilio::Deserialize;

sub new {
  my ($class, $version, $payload, $account_sid, $sid) = @_;
  my $self = $class->SUPER::new($version, $payload);
  $self->{solution} = { account_sid => $account_sid, sid => $sid // $self->{properties}{sid} };
  return $self;
}

sub delete {
  my ($self) = @_;
  return $self->_context->delete;
}

sub fetch {
  my ($self) = @_;
  return $self->_context->fetch;
}

sub update {
  my ($self, $options) = @_;
  return $self->_context->update($options);
}

sub account_sid           { return $_[0]{properties}{account_sid} }
sub api_version           { return $_[0]{properties}{api_version} }
sub body                  { return $_[0]{properties}{body} }
sub direction             { return $_[0]{properties}{direction} }
sub error_code            { return $_[0]{properties}{error_code} }
sub error_message         { return $_[0]{properties}{error_message} }
sub from                  { return $_[0]{properties}{from} }
sub messaging_service_sid { return $_[0]{properties}{messaging_service_sid} }
sub num_media             { return $_[0]{properties}{num_media} }
sub num_segments          { return $_[0]{properties}{num_segments} }
sub price                 { return $_[0]{properties}{price} }
sub price_unit            { return $_[0]{properties}{price_unit} }
sub sid                   { return $_[0]{properties}{sid} }
sub status                { return $_[0]{properties}{status} }
sub subresource_uris      { return $_[0]{properties}{subresource_uris} }
sub to                    { return $_[0]{properties}{to} }
sub uri                   { return $_[0]{properties}{uri} }

sub date_created { return Twilio::Deserialize::date_time($_[0]{properties}{date_created}) }
sub date_sent    { return Twilio::Deserialize::date_time($_[0]{properties}{date_sent}) }
sub date_updated { return Twilio::Deserialize::date_time($_[0]{properties}{date_updated}) }

sub _context {
  my ($self) = @_;
  my $solution = $self->{solution};
  return Twilio::Rest::Api::V2010::Account::MessageContext->new($self->{version},
    $solution->{account_sid},
    $solution->{sid});
}

1;

__END__

=encoding UTF-8

=head1 NAME

Twilio::Rest::Api::V2010::Account::Message - Send and read messages

=head1 SYNOPSIS

  my $client = Twilio::Rest::Client->new($account_sid, $auth_token);

  my $message = $client->messages->create('+15558675309', {
    from => '+15017250604',
    body => 'Hello',
  });
  say $message->sid;

  for my $message ($client->messages->read({ to => '+15558675309' }, 20)) {
    say $message->body;
  }

  my $stream = $client->messages->stream({}, 100, 50);
  while (my $message = $stream->next) {
    say $message->status;
  }

  $client->messages('SMxxxx')->update({ body => q{} });
  $client->messages('SMxxxx')->delete;

=head1 DESCRIPTION

The Message resource of the 2010 API. This file holds four classes:
C<MessageList>, C<MessagePage>, C<MessageContext> and C<MessageInstance>, all under
C<Twilio::Rest::Api::V2010::Account>.

Options use the snake_case form of the names in Twilio's documentation, so
C<statusCallback> in a PHP example is C<status_callback> here. Options this version
does not know about are ignored, as in Twilio's own libraries.

All these methods throw L<Twilio::Exceptions::RestException> on an error response.

=head1 MessageList

Returned by C<< $client->messages >>. See also L<Twilio::ListResource>.

=head2 create

  my $message = $client->messages->create($to, \%options);

Sends a message and returns a C<MessageInstance>. The options are C<from>,
C<messaging_service_sid>, C<body>, C<media_url>, C<content_sid>,
C<status_callback>, C<application_sid>, C<max_price>, C<provide_feedback>,
C<attempt>, C<validity_period>, C<force_delivery>, C<content_retention>,
C<address_retention>, C<smart_encoded>, C<persistent_action>, C<traffic_type>,
C<shorten_urls>, C<schedule_type>, C<send_at>, C<send_as_mms>,
C<content_variables>, C<message_intent>, C<risk_check> and C<fallback_from>.

C<media_url> and C<persistent_action> take an array reference. C<send_at> takes a
string, or an object with an C<epoch> method such as L<Time::Piece>.

=head2 read

  my @messages = $client->messages->read(\%options, $limit, $page_size);

Returns the messages as a list, fetching as many pages as it needs. Without a
C<$limit>, that is every message in the account. The options are C<to>, C<from>,
C<date_sent>, C<date_sent_before> and C<date_sent_after>, and the dates take the
same values as C<send_at>.

=head2 stream

  my $stream = $client->messages->stream(\%options, $limit, $page_size);

Takes the same arguments as L</read>, and returns a L<Twilio::Stream> that fetches
each page when it is needed.

=head2 page

  my $page = $client->messages->page(\%options, $page_size, $page_token, $page_number);

Fetches one page, and returns a L<Twilio::Page>.

=head2 get_page

  my $page = $client->messages->get_page($url);

Fetches the page at a URL given by Twilio, such as C<< $page->get_next_page_url >>.

=head2 get_context

  my $context = $client->messages->get_context($sid);

Returns a C<MessageContext>, as C<< $client->messages($sid) >> does.

=head1 MessageContext

Returned by C<< $client->messages($sid) >>. Using it makes no request until one of
these methods is called.

=head2 fetch

  my $message = $client->messages($sid)->fetch;

Returns a C<MessageInstance>.

=head2 update

  my $message = $client->messages($sid)->update({ body => q{} });

Changes a message and returns it. The options are C<body>, where an empty string
redacts the text of a message, and C<status>, where C<canceled> cancels a scheduled
one.

=head2 delete

  $client->messages($sid)->delete;

Deletes a message and returns true.

=head1 MessageInstance

A message, as returned by L</create> and L</read>. See also
L<Twilio::InstanceResource>. It has L</fetch>, L</update> and L</delete> too, which
work the same way. L</fetch> and L</update> return a new object.

Its fields are C<account_sid>, C<api_version>, C<body>, C<direction>,
C<error_code>, C<error_message>, C<from>, C<messaging_service_sid>, C<num_media>,
C<num_segments>, C<price>, C<price_unit>, C<sid>, C<status>, C<subresource_uris>,
C<to> and C<uri>.

C<date_created>, C<date_sent> and C<date_updated> return L<Time::Piece> objects in
UTC. See L<Twilio::Deserialize/date_time>.

=head1 LICENSE

Copyright (c) 2026 Francisco Zarabozo. Released under the MIT License.

=cut
