# Generator

Turns Twilio's OpenAPI specs into the classes under `lib/Twilio/Rest`. It is for
maintainers, and it isn't part of the CPAN distribution.

The specs are pinned to the `twilio-oai` release in `twilio-oai.version`, and they
aren't kept in this repository. To download them into `spec/`:

    perl tools/fetch-specs.pl

To write the generated classes into `lib/`:

    perl tools/generate.pl

To see what still stops each spec, without writing anything:

    perl tools/generate.pl --report

Generated files start with a comment saying so, and they shouldn't be edited by
hand. `xt/generator/up-to-date.t` fails when `lib/` differs from what the generator
writes.

It also writes a `t/data/contract-*.json` for each spec, which holds what each operation
must send, taken straight from the spec. `t/contract.t` checks the real classes against
them.

Besides the resources, it writes a class for each domain and version, and
`Twilio::Rest::Client`. Only the main API offers a shortcut to each resource of an
account: `$client->messages` is `$client->api->v2010->account->messages`. Elsewhere the
path has the version in it, as in `$client->frontline_api->v1->users`.

## Which specs become code

`Twilio::Generator::Scope` holds three lists, and every spec of `twilio-oai` belongs to
exactly one:

- **Ready** specs are generated. If one stops, generation stops.
- **Pending** specs still have something the generator cannot do. They are named because
  skipping whatever fails would let a spec sync silently delete a whole product.
  `xt/generator/scope.t` fails when a pending spec starts to work, so the list only
  shrinks. Phase 4 ends when it's empty.
- **Excluded** specs are never downloaded, and each one says why. The scope follows what
  twilio-php ships, so check this at each spec sync.

A domain takes twilio-php's name, which isn't always the spec's: `flex` is `flex_api`.

To print the resource tree of an API:

    perl tools/generate.pl --tree api_v2010

Each line shows a resource, the method that reaches it from its parent, and its
operations:

    Account::Message [messages] list(create list) instance:Sid(delete fetch update)

## How resources are found

- The `parent` in `x-twilio` places a resource, not its path: `SMS/ShortCodes` is a
  direct child of `Account`.
- `className` in `x-twilio` overrides the name built from the last path segment.
- A key in `dependentProperties` overrides the method name built from the path.
- One path can hold two resources: `POST` on `Keys` creates a `NewKey`. An operation
  whose noun isn't the resource's own moves to a sibling resource.
- An instance path with no parameter at the end is a singleton.

The generator stops on anything it can't place, because a guess would become
wrong public API.

## Test vectors

`tools/vectors/generate.php` runs real twilio-php and writes what it produces into
`t/data/vectors-*.json`, so the tests compare against twilio-php without needing
PHP. The cases that both languages build are in `tools/vectors/`, and the release
of twilio-php they were last written with is in `tools/twilio-php.version`.

    php tools/vectors/generate.php /path/to/twilio-php

Attributes are sorted in the vectors, because this library sorts them. The text
is otherwise exactly what twilio-php wrote, with two corrections.

## TwiML

`twilio-oai` has no TwiML spec, so the names of elements and attributes come from
the source of twilio-php, in `tools/twiml-elements.json`:

    perl tools/extract-twiml.pl /path/to/twilio-php

Run it again when updating `tools/twilio-php.version`, then run the generator. It
stops on any PHP it doesn't recognize, because a skipped element would simply go
missing.

Two attribute names are corrected there, because twilio-php writes them wrongly
and its tests don't cover them: `for_` becomes `for`, and `xml:Lang` becomes
`xml:lang`. twilio-python uses the corrected names.
