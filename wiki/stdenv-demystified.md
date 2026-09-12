---
summary: >-
  `stdenv` is one derivation containing two files, with the toolchain hardcoded
  as text inside a shell script. `mkDerivation` wires a builder around it.
  Phases are bash functions; Nix itself knows nothing about any of it.
sources:
  - pkgs/stdenv/generic/setup.sh
  - pkgs/stdenv/generic/make-derivation.nix
  - pkgs/stdenv/generic/default-builder.sh
tags:
  - nix
  - nixpkgs
  - stdenv
  - fundamentals
---

# `stdenv` demystified

`nix-build '<nixpkgs>' -A stdenv` yields a derivation whose output is, at
bottom, a shell script (`setup`) plus a propagated-inputs manifest. That is
the thing every nixpkgs package is built with.

## How the toolchain gets in

By having the store paths for the standard toolchain **hardcoded as text
inside `setup`**. That is delightful, because it means the toolchain becomes
a runtime dependency of `stdenv` through the ordinary closure-scanning
mechanism nixpkgs uses everywhere else — the scanner finds the paths by
searching the file's text. No special case is needed for `stdenv` itself.

## What `mkDerivation` actually contributes

At its simplest, the pipeline `mkDerivation` sets up is:

```sh
source $stdenv/setup
genericBuild
```

i.e. `nix-build` → run a builder shell → `source $stdenv/setup` →
`genericBuild`. Modern `pkgs/stdenv/generic/make-derivation.nix` is far more
elaborate than this (structured attrs, `finalAttrs`, cross-compilation
splicing, `__structuredAttrs`, etc.), but the core shape is unchanged: a
builder script sources `setup`, which defines `genericBuild` and the phase
functions, and then runs it.

## Nix knows nothing about it

`stdenv`, `mkDerivation`, phases, hooks and `buildInputs` are **convention
all the way down** — a large bash library (`setup.sh`, now ~1800 lines) that
the community agreed to use, sitting on top of the plain `derivation`
primitive. Nothing in Nix requires any of it: a `derivation` call with a
hand-written builder is just as valid, and phases can be reordered or
replaced with arbitrary shell because they are just bash functions, nothing
more.

This is why `unpackPhase`, `configurePhase` and friends can be overridden
with arbitrary shell, and why failures in them surface as ordinary bash
errors rather than anything Nix-specific.

## Why the build environment and the setup script are separate concerns

`nix develop` (formerly `nix-shell`) can source the *environment* `setup.sh`
sets up without running a full build — and `set -e` is deliberately **not**
set for interactive use, because it would kill your shell on a typo. The
split serves the development workflow, not just the build: an environment a
human can enter halfway.

## Related

- [[stdenv-dependency-propagation]] — what `setup` does with `buildInputs`.
- [[callpackage-and-override]] — how a package function becomes a derivation
  with `override`/`overrideAttrs`.

## Provenance

Adapted from a page written against the `nix-pills` tutorial (pills 10 and 19)
in another project's wiki; re-verified here against this repo's actual
`pkgs/stdenv/generic/setup.sh` and `make-derivation.nix`, which are
considerably more elaborate than the pills' teaching example but share the
same core mechanism.
