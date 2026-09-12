---
summary: >-
  Exploration of nix-update, the single-package interactive CLI (by Mic92)
  that bumps a package's version, refetches its source hash, and recomputes
  derived dependency hashes — the tool most `passthru.updateScript`s in
  nixpkgs actually run.
url: https://github.com/Mic92/nix-update
commit-hash: 0ebb0d8b522de1de00b5730d2e13307c4a0ea2e0
tags:
  - nixpkgs
  - automation
  - external-project
---

# nix-update

A Python CLI that updates **one** attribute in a Nix expression tree: it
evaluates the attribute, works out the latest upstream version from the
*URL* of its `src`, rewrites the version string and source hash, then
recomputes every derived fixed-output hash it can find (`cargoHash`,
`vendorHash`, `npmDepsHash`, `pnpmDeps`, `yarnOfflineCache`, `mvnHash`, and
others).[^readme] It works on nixpkgs and on other package sets, including
flakes (`--flake`).[^flake-support]

Two pages cover the parts most worth understanding on their own, both
linked from [[nixpkgs-internals]]:

- [[nix-update-script]] — how nixpkgs' `passthru.updateScript = nix-update-script
  { }` actually invokes this CLI (no arguments — everything comes from
  environment variables set by the caller), and the reverse direction:
  `nix-update -u` delegating to a package's own `updateScript`.
- [[forge-detection-from-src-url]] — how it decides whether to query
  GitHub, GitLab, or a Gitea/Forgejo instance like Codeberg for a package's
  latest version, given that by evaluation time the fetcher function used
  (`fetchFromGitHub` vs `fetchFromCodeberg`) has already been erased.

See [[hash-update-mechanics]] for how it learns a fixed-output hash — a
second, distinct implementation of the same trick [[r-ryantm-bot]] uses.

## Where this fits versus nixpkgs-update

A prior exploration of [[nixpkgs-update]] (the engine behind the `@r-ryantm`
bot) found no mention of nix-update anywhere in that repo, and treated the
obvious contrast between the two tools as an unverified inference. Having
now read nix-update itself, that contrast is confirmed almost verbatim by
its own README: nixpkgs-update "is optimized for mass-updates in nixpkgs
while nix-update is better suited for interactive usage that might require
user-intervention i.e. fixing the build and testing the result. nix-update
is also not limited to nixpkgs."[^contrast]

Two things the prior page got wrong or overstated, now corrected:

- **The reference is one-directional, not absent both ways.** nix-update's
  README does mention nixpkgs-update, in a "Related projects" section — it
  just links the pre-rename `ryantm/nixpkgs-update` GitHub URL rather than
  the current `nix-community/nixpkgs-update`, so it's mildly stale.
  `@r-ryantm` itself is never named.[^related]
- **The overlap is wider than "just the fakeHash trick."** Both tools also
  treat `passthru.updateScript` as an update source, and both integrate
  `nixpkgs-review` (nix-update runs `nixpkgs-review wip` locally via
  `--review`; nixpkgs-update embeds a review in the PR body) — unsurprising
  since `nixpkgs-review` is also a Mic92 project.[^review-overlap]

The fakeHash mechanism itself is *not* the same implementation in both
tools, only the same underlying idea — see [[hash-update-mechanics]] for
both variants side by side.

## Design posture: teach the operator, don't auto-resolve

Where nixpkgs-update suppresses ambiguous candidates via skiplists to avoid
false-positive bot PRs (see [[r-ryantm-bot]]), nix-update surfaces ambiguity
to a human with the flag that resolves it: an unstable/prerelease version
found upstream produces an error naming `--version=unstable` as the
fix,[^teach] and a version bump that can't be distinguished from "no actual
change" opens a commit template in an editor rather than auto-committing a
message.[^template] It also re-checks `git diff` after the update and skips
build/test/commit entirely if nothing changed.[^diff-check] Consistent with
being human-in-the-loop: there is no branch creation or PR support —
`README.md` lists "create pull requests" under **TODO**.[^todo]

## Known doc/code drift

- The README lists "Codeberg" as a forge distinct from Gitea; in the code
  there is only a Gitea backend, with `codeberg.org` in a hardcoded list of
  known Gitea hosts (see [[forge-detection-from-src-url]]).[^codeberg-doc]
- The commit-message "Diff:" trailer only covers `codeberg.org` and
  `gitea.com` (hardcoded), narrower than version-detection coverage, which
  also probes arbitrary self-hosted Forgejo instances at runtime. A package
  on a self-hosted Forgejo gets its version bumped correctly but no `Diff:`
  trailer, undocumented.[^diffurl-gap]
- `README.md` says `--update-script-args` only passes args to the nixpkgs
  `update.nix` shell invocation; the code also appends them to the
  non-nixpkgs `nix develop` path.[^argdrift]

## Not read

Most of the per-forge backends beyond GitHub/GitLab/Gitea
(`bitbucket.py`, `crate.py`, `npm.py`, `pypi.py`, `rubygems.py`,
`savannah.py`) — assumed by symmetry to match on URL netloc, not verified.
`nix_update/lockfile.py`, `version_compare.py`, `version_info.py`,
`http.py`, `errors.py` — read only by reference from call sites, so exact
version-comparison semantics are unverified. Most of `tests/` (≈60 files,
network-dependent integration tests) beyond `test_gitea.py`. No git history
was read, so none of the drift above can be dated. On the nixpkgs side, only
`pkgs/by-name/ni/nix-update/nix-update-script.nix`,
`pkgs/build-support/fetchgitea/default.nix`, and a grep of
`maintainers/scripts/update.py` were read — not `maintainers/scripts/update.nix`
itself, which is what actually enumerates packages for `nix-update -u`.

[^readme]: [README.md](https://github.com/Mic92/nix-update/blob/0ebb0d8b522de1de00b5730d2e13307c4a0ea2e0/README.md), line 3-4 and the dependency-hash attribute list
[^flake-support]: [nix_update/options.py](https://github.com/Mic92/nix-update/blob/0ebb0d8b522de1de00b5730d2e13307c4a0ea2e0/nix_update/options.py), lines 101-128, 169-188
[^contrast]: [README.md](https://github.com/Mic92/nix-update/blob/0ebb0d8b522de1de00b5730d2e13307c4a0ea2e0/README.md), lines 333-337
[^related]: repo-wide grep for `r-ryantm|ryantm|nixpkgs-update` at commit `0ebb0d8`, one hit, in the README's "Related projects" section
[^review-overlap]: [README.md](https://github.com/Mic92/nix-update/blob/0ebb0d8b522de1de00b5730d2e13307c4a0ea2e0/README.md), line 141
[^teach]: [nix_update/version/__init__.py](https://github.com/Mic92/nix-update/blob/0ebb0d8b522de1de00b5730d2e13307c4a0ea2e0/nix_update/version/__init__.py), lines 205-216
[^template]: [nix_update/__init__.py](https://github.com/Mic92/nix-update/blob/0ebb0d8b522de1de00b5730d2e13307c4a0ea2e0/nix_update/__init__.py), lines 284-317
[^diff-check]: [nix_update/__init__.py](https://github.com/Mic92/nix-update/blob/0ebb0d8b522de1de00b5730d2e13307c4a0ea2e0/nix_update/__init__.py), lines 485-495
[^todo]: [README.md](https://github.com/Mic92/nix-update/blob/0ebb0d8b522de1de00b5730d2e13307c4a0ea2e0/README.md), lines 315-317
[^codeberg-doc]: [README.md](https://github.com/Mic92/nix-update/blob/0ebb0d8b522de1de00b5730d2e13307c4a0ea2e0/README.md), line 10, vs. [nix_update/version/gitea.py](https://github.com/Mic92/nix-update/blob/0ebb0d8b522de1de00b5730d2e13307c4a0ea2e0/nix_update/version/gitea.py), lines 16-37
[^diffurl-gap]: [nix_update/diff_urls.py](https://github.com/Mic92/nix-update/blob/0ebb0d8b522de1de00b5730d2e13307c4a0ea2e0/nix_update/diff_urls.py), line 93
[^argdrift]: [README.md](https://github.com/Mic92/nix-update/blob/0ebb0d8b522de1de00b5730d2e13307c4a0ea2e0/README.md), lines 191-195, vs. [nix_update/update.py](https://github.com/Mic92/nix-update/blob/0ebb0d8b522de1de00b5730d2e13307c4a0ea2e0/nix_update/update.py), line 190
</content>
