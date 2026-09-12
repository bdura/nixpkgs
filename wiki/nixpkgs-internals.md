---
summary: >-
  Hub for how nixpkgs itself works underneath a `package.nix`: `stdenv`,
  dependency propagation, `callPackage`/`override`, the fixed-point/overlay
  mechanism, deprecation policy, the merge-to-channel release pipeline, and
  automated updates (the fakeHash bootstrap, the @r-ryantm bot,
  `nix-update`/`nix-update-script`, and forge auto-detection).
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

## Automated updates

- [[hash-update-mechanics]] — the `fakeHash` bootstrap: how a fixed-output
  derivation's real hash is learned by deliberately building with a wrong
  one, and why vendored hashes (`cargoHash`, `vendorHash`, `npmDepsHash`)
  need the trick run a second time. Covers two distinct implementations
  (nixpkgs-update's file-rewrite, nix-update's throwaway-expression
  override).
- [[r-ryantm-bot]] — how the `@r-ryantm` bot decides what to update, filters
  out likely false-positive PRs, and uses its fork's branch namespace as its
  only state between runs. Explored from the [[nixpkgs-update]] tool that
  implements it.
- [[nix-update-script]] — how `passthru.updateScript = nix-update-script
  { }` actually works: the wrapper passes no arguments, and the attrpath
  arrives via environment variables set by the caller. Explored from
  [[nix-update]], the CLI it wraps.
- [[forge-detection-from-src-url]] — how [[nix-update]] decides whether to
  query GitHub, GitLab, or a Gitea/Forgejo host like Codeberg for a
  package's latest version, given that the fetcher function used
  (`fetchFromGitHub` vs `fetchFromCodeberg`) is already erased by
  evaluation time.

## Known gaps

Not yet covered here (seeded from another project's wiki, which itself only
explored `lib/`, not `pkgs/`):

- `pkgs/by-name/<xx>/<name>/package.nix` layout conventions, `finalAttrs`
  style, `meta.maintainers`, common fetcher functions.
- Pre-merge CI: `nixpkgs-vet`, the `by-name` structural checks, `nixfmt`
  formatting checks, ofborg/GitHub Actions eval checks.
- `passthru.tests` as a general nixpkgs mechanism beyond how
  [[r-ryantm-bot]] and [[nix-update]] each use it as a build/check gate —
  no page yet on how a package defines one or how it's discovered outside
  those two consumers.
- The bot's actual runtime infrastructure — trigger cadence, queue, and the
  "6h timeout" referenced in some of its skiplist reasons — lives outside
  the `nixpkgs-update` codebase and hasn't been explored.
