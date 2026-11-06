# Generator

Turns Twilio's OpenAPI specs into the classes under `lib/Twilio/Rest`. It is for
maintainers, and it isn't part of the CPAN distribution.

The specs are pinned to the `twilio-oai` release in `twilio-oai.version`, and they
aren't kept in this repository. To download them into `spec/`:

    perl tools/fetch-specs.pl

To write the generated classes into `lib/`:

    perl tools/generate.pl

Generated files start with a comment saying so, and they shouldn't be edited by
hand. `xt/generator/up-to-date.t` fails when `lib/` differs from what the generator
writes. Only the resources listed in `tools/lib/Twilio/Generator.pm` are generated
so far.

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
