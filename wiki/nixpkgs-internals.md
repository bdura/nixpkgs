---
summary: >-
  Hub for how nixpkgs itself works underneath a `package.nix`: `stdenv`,
  dependency propagation, `callPackage`/`override`, the fixed-point/overlay
  mechanism, deprecation policy, and the merge-to-channel release pipeline.
sources: []
tags:
  - nixpkgs
  - hub
---

# nixpkgs internals

Hub page for mechanics that matter when packaging or updating something in
nixpkgs, as opposed to project-specific knowledge (a particular package, a
particular PR).

## Build mechanics

- [[stdenv-demystified]] — what `stdenv` and `mkDerivation` actually are:
  a shell script and a manifest, with phases as plain bash functions.
- [[stdenv-dependency-propagation]] — `buildInputs`, `propagatedBuildInputs`,
  setup hooks and env hooks, and how the `nativeBuildInputs`/`buildInputs`/
  `depsBuild*` split supersedes the older "buildInputs for everything" model.

## The `lib` layer

- [[callpackage-and-override]] — how `callPackage` auto-wires a package
  function's arguments from `pkgs`, and how `override`/`overrideAttrs` differ.
- [[lib-fixed-points]] — `fix`/`extends`/`makeExtensible`: the mechanism
  behind overlays, `lib.extend`, `overrideScope` and `finalAttrs`, including
  the shallow-merge overlay gotcha.
- [[nixpkgs-deprecation-policy]] — why a deprecation warning is written years
  before it starts firing, and what `lib/deprecated` actually means.

## Getting a change out

- [[nixpkgs-release-pipeline]] — merge → staging → Hydra → channel bump →
  consumer; why a green PR can sit unbumped for days.

## Known gaps

Not yet covered here (seeded from another project's wiki, which itself only
explored `lib/`, not `pkgs/`):

- `pkgs/by-name/<xx>/<name>/package.nix` layout conventions, `finalAttrs`
  style, `meta.maintainers`, common fetcher functions.
- Pre-merge CI: `nixpkgs-vet`, the `by-name` structural checks, `nixfmt`
  formatting checks, ofborg/GitHub Actions eval checks.
- Hash-update mechanics in practice: recomputing `hash`/`cargoHash`/
  `npmDepsHash`, the `fakeHash` bootstrap workflow end to end.
- The `@r-ryantm` update bot's behavior in detail (queueing, retry cadence,
  what blocks it from picking up a new version).
