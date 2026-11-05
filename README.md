# Twilio for Perl

[![CI](https://github.com/Zarabozo/Twilio/actions/workflows/ci.yml/badge.svg)](https://github.com/Zarabozo/Twilio/actions/workflows/ci.yml)

A community Perl library for the [Twilio](https://www.twilio.com/) API, designed
to feel like Twilio's official helper libraries.

**Status: under development.** Version 2 is a rewrite from scratch and has no
usable API client yet. The `Twilio-1.000` release on CPAN is the old, unrelated
codebase.

```perl
my $client = Twilio::Rest::Client->new($account_sid, $auth_token);

my $message = $client->messages->create('+15558675309', {
  from => '+15017250604',
  body => 'Hello',
});
```

This is the planned interface. It mirrors `twilio-php`, so a Twilio documentation
example translates to Perl with a few simple rules.

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
