---
summary: >-
  How nixpkgs deprecates: `oldestSupportedRelease` gates warnings so they're
  written immediately but only fire once every currently-supported release
  has the replacement. Also what `lib/deprecated` actually is.
sources:
  - lib/trivial.nix
  - lib/deprecated/README.md
tags:
  - nix
  - nixpkgs
  - lib
---

# Deprecation policy

## Time-delayed warnings

`lib.trivial` exports `oldestSupportedRelease` and
`oldestSupportedReleaseIsAtLeast`. A deprecation is written as something
like:

```nix
warnIf (oldestSupportedReleaseIsAtLeast 2605) "…" value
```

so the warning is committed to the codebase immediately, but stays silent
until every currently-supported nixpkgs release ships the replacement. The
stated reason: out-of-tree expressions should be able to evaluate cleanly
against all supported nixpkgs versions, so a deprecation should only take
effect once every supported version can be upgraded to without losing
support.

**Practical consequence:** a deprecation warning appearing after a
`nixpkgs` bump (e.g. after moving to a new channel or flake input) usually
means a *threshold was just crossed*, not that anything in the change you
made is new or wrong. The deprecation itself may be years old and was just
waiting for `oldestSupportedRelease` to catch up.

## `lib/deprecated` is a place, not a process

The directory's README is explicit that the *location* is what's
deprecated, not necessarily the mechanism: new functions should not be added
there, but existing functions are deprecated in place with a `lib.warn` /
`lib.warnIf` wrapper, not by physically moving them.

Notably, `fakeHash` / `fakeSha256` / `fakeSha512` live in this directory
despite it being informally described as holding functions "of dubious
utility" — they remain standard, recommended practice for hash bootstrapping
(the "set a fake hash, let the build fail with the real one" workflow used
when writing or bumping a `fetchurl`/`fetchFromGitHub`-style `hash`).

## Practical takeaway for packaging work

If a package bump surfaces a new-looking deprecation warning during
evaluation, check whether it's actually new behavior from the bump versus an
old, dormant warning that just crossed its `oldestSupportedRelease`
threshold — the fix (or lack of one needed) differs accordingly.

## Related

- [[callpackage-and-override]] — `overrideDerivation` is a concrete example
  of something deprecated in favour of `overrideAttrs`.
