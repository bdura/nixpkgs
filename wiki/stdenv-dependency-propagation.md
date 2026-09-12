---
summary: >-
  `buildInputs`, `propagatedBuildInputs`, setup hooks and env hooks are all
  implemented in bash at build time, not in Nix at evaluation time. Why
  `nix-support/` exists, why setup hooks are an escape hatch around Nix's own
  isolation guarantees, and how the `nativeBuildInputs`/`buildInputs`/`depsBuild*`
  family superseded the pills-era "buildInputs for everything" model.
sources:
  - pkgs/stdenv/generic/setup.sh
tags:
  - nix
  - nixpkgs
  - stdenv
  - fundamentals
---

# Dependency propagation and hooks

The thing to know first: **none of this is implemented in Nix.** It is
bash, run at build time, inside `setup.sh`.

## `buildInputs`

`findInputs` (in `setup.sh`) accumulates dependencies into a list; each
dependency's `bin` directory is added to the build's `PATH`. That is the
whole mechanism, and it is why a deliberately minimal starting `PATH` is
survivable — everything you need gets added back by this process.

On the Nix side there's one coercion rule involved: a list coerces to a
space-separated string, so `buildInputs = [ a b c ]` becomes the argument to
a shell `for` loop.

## `propagatedBuildInputs`

`fixupPhase` writes the propagated list to
`$out/nix-support/propagated-build-inputs`. Then `findInputs`, running in a
**downstream** package's build, reads that file and recurses into it.

So propagation is a file written into a build's output, later read by a
shell function in a *different* build. That is what the `nix-support/`
directory is for. For the package being built, it doesn't matter whether one
of its own dependencies is propagated or not — that only matters to whatever
depends on it in turn.

## Setup hooks

`$pkg/nix-support/setup-hook` is sourced by any `stdenv` build that depends
on `$pkg`. They exist because propagation only covers one hard-coded kind of
influence (adding to `PATH`/build inputs), but a dependency might need to
affect a consuming build in genuinely arbitrary ways — you cannot enumerate
those in `setup.sh` in advance, so you let the dependency ship its own shell
code instead.

This is worth stating plainly because it's easy to forget: a dependency in
nixpkgs is **not inert**. It can execute arbitrary code inside a build that
depends on it. The isolation Nix provides is between the build and the host
system, not between a build and its own dependencies. Setup hooks should
therefore be used sparingly — they're explicitly an escape hatch around
Nix's normal isolation guarantees, not a routine extension point.

## Env hooks

Functions pushed onto `envHooks` run against *every sibling dependency* in a
build. The canonical example is a compiler learning about `-I`/`-L` flags for
its sibling dependencies — that's the compiler's business, not `stdenv`'s, so
the hook lives with the compiler package rather than being hardcoded into
`setup.sh`. This is what lets `stdenv` stay language-agnostic: language- or
toolchain-specific propagation logic lives in the toolchain's own setup hook.

## What changed since the pills-era model

Older teaching material (the `nix-pills` tutorial) describes `buildInputs`
as the answer for everything, toolchain included. Modern nixpkgs
distinguishes:

- `nativeBuildInputs` — build-time tools, built for the build platform
  (compilers, code generators, `pkg-config`, etc.)
- `buildInputs` — runtime/link-time dependencies, built for the host platform
- the `depsBuild*` / `depsHost*` / `depsTarget*` family, for cross-compilation

Putting a compiler in plain `buildInputs` today would be a review comment.
The underlying propagation *mechanism* described above is unchanged — only
the number of buckets it's split across grew, mainly to support
cross-compilation.

## Related

- [[stdenv-demystified]] — where `setup.sh` and `genericBuild` come from.
- [[callpackage-and-override]] — how these attributes reach a derivation in
  the first place, through a package function's arguments.

## Provenance

Adapted from a page written against the `nix-pills` tutorial in another
project's wiki; the mechanism described (`findInputs`, `nix-support/`, setup
hooks, env hooks) matches this repo's `pkgs/stdenv/generic/setup.sh`.
