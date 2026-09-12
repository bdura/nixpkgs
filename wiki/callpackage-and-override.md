---
summary: >-
  `callPackage` wires a package function's named arguments automatically from
  a scope (`pkgs`); `makeOverridable` is what puts `override` and
  `overrideAttrs` on the result. Covers the `functionArgs` mechanism, the
  deliberate `abort` on a missing argument, and package scopes.
sources:
  - lib/customisation.nix
tags:
  - nix
  - nixpkgs
  - lib
---

# `callPackage`, `makeOverridable` and scopes

## `callPackage`

The mechanism, roughly:

```nix
allArgs = intersectAttrs (functionArgs f) autoArgs // args;
```

`builtins.functionArgs` reads the formal argument names of a package
function, and **only those names** are pulled automatically from the scope
(typically `pkgs`); explicit `args` passed to `callPackage` win over the
auto-supplied ones. The consequence for how you write a `package.nix`: the
function's argument list *is* its dependency declaration. Adding a new
input means adding a new formal argument, nothing else.

A missing argument produces a "did you mean" suggestion built with a bounded
Levenshtein distance (a deliberate performance trade-off, not an attempt at
perfect suggestions).

### Why `abort` and not `throw`

The missing-argument failure is an `abort`, not a `throw`, specifically so
it **cannot** be caught with `builtins.tryEval` — which tools like `nix-env`
and CI evaluation checks use to filter out packages that fail to evaluate.
This forces such errors to be fixed in nixpkgs itself rather than silently
skipped, which matters in particular with `allowAliases = false`. The
trade-off: a packaging mistake here cannot be worked around from user code —
it has to be fixed at the source.

### The `functionArgs` limit

`functionArgs` only reports argument names for functions written with a
formal set pattern (`{ foo, bar, ... }: …`). A function written as
`args: …` or `args@{ foo, ... }: …` defeats auto-wiring — its declared
argument list is incomplete from `callPackage`'s point of view. This is the
concrete, mechanical reason nixpkgs' contribution guidelines forbid
`args: with args; …` in package functions: it isn't just a style
preference, it silently breaks dependency auto-wiring.

## `makeOverridable`

Wraps a package function so its result carries `.override`, and — when the
result is a derivation — `.overrideAttrs` (and the deprecated
`.overrideDerivation`). A few details that matter in practice:

- It mirrors the function's argument names onto the wrapper, so calling
  `callPackage` on an *already-overridden* package function still auto-wires
  correctly.
- `override` changes the **arguments passed to the package function** (the
  formal parameters above); `overrideAttrs` changes the **attribute set
  passed to `mkDerivation`**. These are different layers, and conflating
  them is the most common source of confusion when overriding a package.
- `overrideDerivation` is deprecated in favour of `overrideAttrs`, with a
  documented limitation: to preserve evaluation errors, the new
  derivation's `outPath` depends on the old one's `outPath`, so it cannot be
  used in circular situations.

## `makeScope`

The mechanism behind interdependent package sets like `python3Packages`:
each scope gets its own `callPackage` and its own `overrideScope`, built as
a fixed point (see [[lib-fixed-points]]) over the scope's own package set.
`makeScopeWithSplicing'` is the cross-compilation-aware variant used more
widely in nixpkgs today.

## Related

- [[stdenv-demystified]] and [[stdenv-dependency-propagation]] — what the
  attributes passed through `mkDerivation` actually do.
- [[lib-fixed-points]] — the `fix`/`extends` machinery `makeScope` and
  `overrideScope` build on.
