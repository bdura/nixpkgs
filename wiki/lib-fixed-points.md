---
summary: >-
  `fix`, `extends`, `composeExtensions` and `makeExtensible` — the handful of
  lines of Nix that underpin package-set overlays, `lib.extend`,
  `overrideScope` and `finalAttrs`. Covers `final`/`prev` semantics and the
  shallow-merge limit that causes the most common overlay surprise.
sources:
  - lib/fixed-points.nix
tags:
  - nix
  - nixpkgs
  - lib
  - overlays
---

# Fixed points and overlays

## `fix`

```nix
fix = f: let x = f x; in x;
```

That's the whole thing. Nix's laziness makes `f x` legal while `x` is still
being defined, so a function can receive its own eventual result. No
evaluator support is needed — the overlay pattern is a *library* feature,
not a language feature.

## `extends`

```nix
extends = overlay: f: final: let prev = f final; in prev // overlay final prev;
```

An overlay is a function `final: prev: { … }`. `prev` is what the
underlying set produced on its own; `final` is the fully composed result
after all overlays are applied — so an overlay can refer to an attribute
that a *later* overlay will go on to replace. That's the whole point of the
two-argument shape: `prev` for "the thing I'm layering on top of", `final`
for "the thing a consumer will actually get".

`composeExtensions` combines two overlays into one; `composeManyExtensions`
folds a list of them.

### Two limits worth remembering

- **Composition is `//`, so nested attribute sets are replaced, not
  merged.** An overlay that sets `meta.description` on a package silently
  drops the rest of that package's `meta`. This is the single most common
  overlay surprise, and worth double-checking whenever an overlay touches a
  nested attrset like `meta` or `passthru`.
- **After an overlay is applied, the base set's own notion of `final` is no
  longer its own output** — it's the composed result including everything
  layered on top. Reasoning about what `final` resolves to inside a base
  package set requires knowing what, if anything, was layered on top of it.

## `makeExtensible`

Builds a self-reproducing `extend`: it produces a `fix`ed attribute set plus
an `extend` function that re-`fix`es the set with one more overlay applied,
so extending is chainable. This is the mechanism behind:

- `lib` itself being extensible (`lib.extend`)
- package scopes via `makeScope`/`overrideScope` (see
  [[callpackage-and-override]])
- `stdenv.mkDerivation`'s `finalAttrs` pattern, where a derivation's
  attributes can refer to the final, fully-overridden derivation

## Practical relevance to packaging and overlays

An overlay does not add a package, it **replaces a name**. Everything that
reaches that name through `pkgs` gets rebuilt, and so does everything built
on top of it — replacing a widely-depended-on package like `openssl` or
`glibc` has a much larger blast radius than the size of the overlay itself
suggests. When an overlay is genuinely needed, prefer the narrowest scope
that achieves the goal (a new name rather than replacing an existing one,
or overriding only the specific package that needs it) over a global
replacement, unless the change genuinely needs to propagate everywhere.

## Related

- [[callpackage-and-override]] — `makeScope`/`overrideScope`, built on this.
