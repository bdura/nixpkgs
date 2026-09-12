# Wiki index

Knowledge base for this project. Entry point: follow a hub page to reach everything
else.

## Explored sources

- [nixpkgs-internals](nixpkgs-internals.md) — **seeded, partial.** Hub for
  build/`lib` mechanics relevant to packaging work in this repo: `stdenv`,
  dependency propagation, `callPackage`/`override`, fixed points and
  overlays, deprecation policy, the merge-to-channel release pipeline, and
  automated updates (the `fakeHash` bootstrap, the `@r-ryantm` bot, and
  `nix-update`/`nix-update-script`/forge auto-detection — from exploring
  [nixpkgs-update](nixpkgs-update.md) and [nix-update](nix-update.md)).
  Adapted from another project's wiki (which only explored `lib/`, not
  `pkgs/`) — see the hub page's "Known gaps" section for what's still
  missing.
