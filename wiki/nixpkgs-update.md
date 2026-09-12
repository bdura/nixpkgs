---
summary: >-
  Exploration of nixpkgs-update, the Haskell tool that discovers outdated
  packages, rewrites their version and hashes, builds and checks the result,
  and opens a nixpkgs PR — the engine behind the @r-ryantm bot.
url: https://github.com/nix-community/nixpkgs-update
commit-hash: 57f2db992e763f64e87e6f7173fd91f120be6380
tags:
  - nixpkgs
  - automation
  - external-project
---

# nixpkgs-update

A Haskell CLI that, given `(package, oldVersion, newVersion)`, edits the
version string and fetcher hashes in a package's Nix file, runs quality
checks, commits, and optionally opens a PR against `NixOS/nixpkgs`. Its
stated mission is "to make nixpkgs the most up-to-date repository of
software in the world by the most ridiculous margin possible."[^intro] It is
the code behind the `@r-ryantm` bot that files most automated nixpkgs
version-bump PRs.

The two mechanisms most worth understanding on their own are covered in
dedicated pages, both linked from the [[nixpkgs-internals]] hub:

- [[hash-update-mechanics]] — how it learns a fixed-output derivation's real
  hash by deliberately building with a wrong one, for both the main `src`
  hash and vendored-dependency hashes (`cargoHash`, `vendorHash`,
  `npmDepsHash`).
- [[r-ryantm-bot]] — how it decides what to update, filters out likely
  false-positive PRs, and treats its fork's branch namespace as its only
  persistent state.

## Where this fits versus `nix-update`

This repo never mentions `nix-update` (the separate, single-package,
interactive CLI by Mic92) — a full-tree grep found no reference.[^grep]
**Verified** by directly exploring [[nix-update]]: the reference is
one-directional, not absent both ways — nix-update's own README does link
to nixpkgs-update, under "Related projects" (using the pre-rename
`ryantm/nixpkgs-update` URL, mildly stale), while `@r-ryantm` itself is
never named there either.

The two projects are not the same thing, and nix-update's README confirms
the contrast almost verbatim: nixpkgs-update owns the whole pipeline
(discover → rewrite → build → check → git → PR) and is built for unattended
batch operation with heavy false-positive suppression, whereas `nix-update`
is a human-in-the-loop tool for updating one package interactively, and is
not limited to nixpkgs. The overlap is wider than just the
fakeHash-and-parse-the-error trick (see [[hash-update-mechanics]] for both
tools' distinct implementations of that): both also treat
`passthru.updateScript` as an update source (see [[nix-update-script]]),
and both integrate `nixpkgs-review` — unsurprising, since that's also a
Mic92 project.

## Other things in the repo, not yet written up

- A CVE/security report built from a local NVD SQLite mirror
  (`src/NVD.hs`, `src/CVE.hs`, `src/NVDRules.hs`), explicitly designed to
  "avoid false negatives... expect to generate many false positives," with
  hand-written suppression rules.[^cve]
- An optional `nixpkgs-review` run embedded in the PR body, with a 180-minute
  timeout that degrades to a warning rather than aborting.[^review]
- A half-finished Rust rewrite ("nu") in `rust/`: a Diesel/SQLite tracker of
  per-package versions across `master`/`staging`/`staging-next`/Repology/
  GitHub, documented in `doc/nu.md` but not fully implemented.[^nu]

## Documentation/code drift found while reading

- The docs (`doc/batch-updates.md`, `doc/details.md`) describe an
  `update-list` subcommand that no longer exists; the actual subcommands are
  `update`, `update-batch`, `delete-done`, `version`,
  `update-vulnerability-db`, `check-vulnerable`, `check-all-vulnerable`,
  `source-github`, `fetch-repology`.[^cli] Per-package batch iteration now
  lives in the bot's external infrastructure, calling `update-batch` once
  per package.
- The docs still lead with "Setup hub" (the old GitHub CLI); the code path
  is the `github` Haskell library over the REST API, and a comment notes
  nixpkgs-update "reads credentials from the files hub uses but no longer
  uses hub itself."[^hub]
- The docs describe three update-discovery sources (Repology, GitHub
  releases, `passthru.updateScript`), but the production GitHub-releases
  source is actually a separate external project
  (`synthetica9/nixpkgs-update-github-releases`); this repo's own
  `source-github` subcommand only verifies candidate versions against the
  GitHub latest-release API rather than discovering them.[^sources]

## Not read

`src/CVE.hs`/`src/NVDRules.hs` in depth, `src/OurPrelude.hs`/`src/Process.hs`/
`src/File.hs` (plumbing), `test/`, and most of `rust/`. No git history was
read, so the drift above cannot be dated. The bot's actual runtime
infrastructure (trigger cadence, queue, the "6h timeout" referenced in
skiplist reasons) is not in this repo — see `doc/r-ryantm.md`, which points
at nix-community's own infrastructure rather than describing it here.

[^intro]: [doc/introduction.md](https://github.com/nix-community/nixpkgs-update/blob/57f2db992e763f64e87e6f7173fd91f120be6380/doc/introduction.md)
[^grep]: repo-wide search for `nix-update`/`Mic92`, no matches, at commit `57f2db9`.
[^cve]: [doc/details.md](https://github.com/nix-community/nixpkgs-update/blob/57f2db992e763f64e87e6f7173fd91f120be6380/doc/details.md), around lines 26-29
[^review]: [src/NixpkgsReview.hs](https://github.com/nix-community/nixpkgs-update/blob/57f2db992e763f64e87e6f7173fd91f120be6380/src/NixpkgsReview.hs), lines 38-51
[^nu]: [doc/nu.md](https://github.com/nix-community/nixpkgs-update/blob/57f2db992e763f64e87e6f7173fd91f120be6380/doc/nu.md), [rust/src/main.rs](https://github.com/nix-community/nixpkgs-update/blob/57f2db992e763f64e87e6f7173fd91f120be6380/rust/src/main.rs)
[^cli]: [app/Main.hs](https://github.com/nix-community/nixpkgs-update/blob/57f2db992e763f64e87e6f7173fd91f120be6380/app/Main.hs), lines 72-116, vs. [doc/batch-updates.md](https://github.com/nix-community/nixpkgs-update/blob/57f2db992e763f64e87e6f7173fd91f120be6380/doc/batch-updates.md)
[^hub]: [doc/interactive-updates.md](https://github.com/nix-community/nixpkgs-update/blob/57f2db992e763f64e87e6f7173fd91f120be6380/doc/interactive-updates.md), [src/GH.hs](https://github.com/nix-community/nixpkgs-update/blob/57f2db992e763f64e87e6f7173fd91f120be6380/src/GH.hs)
[^sources]: [doc/batch-updates.md](https://github.com/nix-community/nixpkgs-update/blob/57f2db992e763f64e87e6f7173fd91f120be6380/doc/batch-updates.md), lines 51-52, vs. [src/Update.hs](https://github.com/nix-community/nixpkgs-update/blob/57f2db992e763f64e87e6f7173fd91f120be6380/src/Update.hs), lines 112-133
</content>
