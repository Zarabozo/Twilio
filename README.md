# Twilio for Perl

[![CI](https://github.com/Zarabozo/Twilio/actions/workflows/ci.yml/badge.svg)](https://github.com/Zarabozo/Twilio/actions/workflows/ci.yml)

A community Perl library for the [Twilio](https://www.twilio.com/) API, designed
to feel like Twilio's official helper libraries.

**Status: under development.** Version 2 is a rewrite from scratch. So far it
covers the main REST API (`api.twilio.com`), and it has not been released. The
`Twilio-1.000` release on CPAN is the old, unrelated codebase.

```perl
use Twilio;

my $client = Twilio->new($account_sid, $auth_token);    # a Twilio::Rest::Client

my $message = $client->messages->create('+15558675309', {
  from => '+15017250604',
  body => 'Hello',
});
```

TwiML is built the same way:

```perl
use Twilio::TwiML::VoiceResponse;

my $response = Twilio::TwiML::VoiceResponse->new;
$response->say('Hola', { language => 'es-MX', voice => 'alice' });
my $dial = $response->dial(q{}, { timeout => 20 });
$dial->number('+15551234567', { send_digits => 'ww1' });

print $response;
```

The interface mirrors `twilio-php`, so a Twilio documentation example translates
to Perl with a few simple rules.

Accounts that enforce Public Key Client Validation (a setting in the Twilio
Console) need `Twilio::Http::ValidationClient` as the HTTP client, which signs
every request. It uses the optional module `Crypt::OpenSSL::RSA` (0.38 or later,
or before 0.35). Leave it out for other accounts: Twilio refuses signed requests
to an account without that setting.

## Development

```sh
perl Makefile.PL
make test        # nmake on Windows with MSVC
```

The tests need no Twilio account and no network. Author checks are in `xt/`:

```sh
prove -lr xt
```

They need the modules listed as `develop` prerequisites in `Makefile.PL`.

## Issues and contributions

Bug reports and pull requests are welcome through
[GitHub issues](https://github.com/Zarabozo/Twilio/issues).

## License

[MIT](LICENSE). This is an independent project. It is not written, endorsed or
supported by Twilio Inc., and "Twilio" is a trademark of Twilio Inc.
