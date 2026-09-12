---
summary: >-
  How the @r-ryantm bot decides what to update, filters out likely
  false-positive PRs before doing any work, builds in a locked-down sandbox,
  measures rebuild count to pick a target branch, and uses its fork's branch
  namespace as its only persistent state between runs.
sources:
  - https://github.com/nix-community/nixpkgs-update/blob/57f2db992e763f64e87e6f7173fd91f120be6380/src/Update.hs
  - https://github.com/nix-community/nixpkgs-update/blob/57f2db992e763f64e87e6f7173fd91f120be6380/src/Skiplist.hs
  - https://github.com/nix-community/nixpkgs-update/blob/57f2db992e763f64e87e6f7173fd91f120be6380/src/GH.hs
  - https://github.com/nix-community/nixpkgs-update/blob/57f2db992e763f64e87e6f7173fd91f120be6380/src/Outpaths.hs
  - https://github.com/nix-community/nixpkgs-update/blob/57f2db992e763f64e87e6f7173fd91f120be6380/src/Git.hs
  - https://github.com/nix-community/nixpkgs-update/blob/57f2db992e763f64e87e6f7173fd91f120be6380/doc/nixpkgs-maintainer-faq.md
tags:
  - nixpkgs
  - automation
  - bots
---

# The @r-ryantm update bot

`@r-ryantm` is the GitHub identity behind [[nixpkgs-update]]'s `update-batch`
subcommand, run repeatedly against a queue of candidate updates by
nix-community's own infrastructure (not part of this repo). What follows is
what the tool itself does per package; the run cadence, queue, and the "6h
timeout" referenced in some skiplist reasons belong to that external
infrastructure, not to the code.

## Where candidates come from

The bot never guesses that a new version exists — it is told, by:[^intro]

- **Repology**, querying the `nix_unstable` repository for entries flagged
  `outdated=true`,[^repology] rate-limited to one request per 2 seconds with
  a custom User-Agent.
- **GitHub releases**, via the latest-release API (in production, actual
  discovery happens in a separate project,
  `synthetica9/nixpkgs-update-github-releases`; this repo's own
  `source-github` subcommand only verifies candidates against that
  API).[^github]
- **`passthru.updateScript`**, run with a 30-minute timeout.[^updatescript]

Repology's data lags behind upstream by construction: it only refreshes
when nixpkgs' own unstable channel moves, so the bot's discovery latency is
coupled to the [[nixpkgs-release-pipeline]] it is itself feeding.[^faq]

## Filtering out likely false positives, before any work happens

Given how much reviewer attention a bad automated PR wastes, most of the
code is pre-flight filtering, not rewriting:[^preflight]

- **Skiplists** on package name, attrpath, file content, and
  post-build-check behavior — each entry in `src/Skiplist.hs` is a predicate
  paired with a human-readable reason string, usually citing an issue or a
  maintainer.[^skiplist] Categories: things the tool structurally can't
  handle (Perl, `r-`, Electron), lockstep package families (mate, deepin,
  rocmPackages), known-unsafe rewrite targets (multiple fetchers/hashes in
  one file), and binaries that hang or don't exit cleanly when the bot tries
  to run them as a check.
- **An in-tree opt-out**: the literal comment
  `# nixpkgs-update: no auto update` in a package's Nix file skips it,
  deliberately keeping the decision with the package's own maintainer rather
  than in the bot's source.[^optout]
- **Version and duplication checks**: the new version must
  `builtins.compareVersions` strictly greater than the old, must respect
  attrpath "version pins" (e.g. `ruby_3_0`), must not already be present in
  the file on `master`/`staging`/`staging-next`/`staging-nixos`, and must not
  already have an open PR with the exact title `attrpath: old -> new`.[^dup]
- **Python packages are capped at 100 rebuilds** even where other packages
  are allowed up to the mass-rebuild threshold — a Python library bump fans
  out across the whole package set disproportionately.[^python]

Multi-fetcher or multi-hash files are refused by the rewriter itself (see
[[hash-update-mechanics]]) rather than by a skiplist entry.

## Sandboxed, hermetic build

Builds force `--option sandbox true` regardless of the ambient Nix config,
and evaluate with `--arg overlays "[ ]"` and `allowAliases = false` — so the
bot evaluates the same nixpkgs a reviewer would, and can't be tricked into
"updating" an alias attrpath.[^sandbox] Runtime tools it shells out to
(`nix`, `git`, `tree`, `gist`, `nixpkgs-review`) are baked in as store paths
at compile time via Template Haskell, rather than resolved from an ambient
`PATH`.[^tools]

## Choosing a target branch by measurement, not guesswork

Before and after the rewrite, the bot evaluates `pkgs/top-level/release.nix`
and `nixos/release.nix` for `x86_64-linux` only (an explicit
accuracy-vs-cost tradeoff) and diffs the resulting out-paths to get an exact
rebuild count and list of affected attrpaths — "the same mechanism OfBorg
uses to put rebuild labels on PRs," but reported as exact numbers rather than
a label.[^outpaths] ≤500 rebuilds targets `master`; above that, `staging`;
if the rebuild set includes `nixosTests.simple-container` or
`nixosTests.simple-vm`, `staging-nixos` instead. Zero rebuilds is treated as
a hard failure. See [[nixpkgs-release-pipeline]] for what happens to a PR
after it lands on one of these branches.

## Checks are evidence, not a verdict

Where possible, the bot builds `passthru.tests`, greps the built output
(and filenames) for the new version string, and uploads `tree`/`du`
listings as gists — catching the case where a package builds successfully
but silently keeps producing the old binary.[^checks] None of this proves
correctness; the PR body bundles these results, release/compare links, and
an optional `nixpkgs-review` report (180-minute timeout, degrading to a
warning rather than aborting) so that a human reviewer can verify cheaply,
not so the bot can self-certify.[^prbody]

## The fork's branch namespace is the only state

The bot is stateless between runs in every other sense: everything keys off
the branch name `auto-update/<packageName>` and the PR title
`<attrpath>: <old> -> <new>` (also used verbatim as the commit
message).[^branch] Re-running against a package with an existing branch
force-pushes and edits the existing PR rather than opening a duplicate;
`delete-done` separately garbage-collects branches whose PRs have closed or
merged.[^delete] Each package is processed in a throwaway git worktree
based on `git merge-base upstream/master upstream/staging`, so the same
commit can legitimately be proposed to either branch depending on the
measured rebuild count.[^worktree]

## Related

- [[nixpkgs-update]] — the tool this page describes the behavior of.
- [[hash-update-mechanics]] — the rewrite step this bot runs per package.
- [[nixpkgs-release-pipeline]] — what happens after the bot's PR merges;
  this page's rebuild-count table is the general policy this bot enforces
  mechanically and exactly.

[^intro]: [doc/introduction.md](https://github.com/nix-community/nixpkgs-update/blob/57f2db992e763f64e87e6f7173fd91f120be6380/doc/introduction.md)
[^repology]: [src/Repology.hs](https://github.com/nix-community/nixpkgs-update/blob/57f2db992e763f64e87e6f7173fd91f120be6380/src/Repology.hs), lines 27-28, 86-117
[^github]: [doc/batch-updates.md](https://github.com/nix-community/nixpkgs-update/blob/57f2db992e763f64e87e6f7173fd91f120be6380/doc/batch-updates.md), lines 51-52; [src/Update.hs](https://github.com/nix-community/nixpkgs-update/blob/57f2db992e763f64e87e6f7173fd91f120be6380/src/Update.hs), lines 112-133
[^updatescript]: [src/Nix.hs](https://github.com/nix-community/nixpkgs-update/blob/57f2db992e763f64e87e6f7173fd91f120be6380/src/Nix.hs), line 279 and following
[^faq]: [doc/nixpkgs-maintainer-faq.md](https://github.com/nix-community/nixpkgs-update/blob/57f2db992e763f64e87e6f7173fd91f120be6380/doc/nixpkgs-maintainer-faq.md), lines 17-25
[^preflight]: [src/Update.hs](https://github.com/nix-community/nixpkgs-update/blob/57f2db992e763f64e87e6f7173fd91f120be6380/src/Update.hs), lines 208-290
[^skiplist]: [src/Skiplist.hs](https://github.com/nix-community/nixpkgs-update/blob/57f2db992e763f64e87e6f7173fd91f120be6380/src/Skiplist.hs)
[^optout]: [src/Skiplist.hs](https://github.com/nix-community/nixpkgs-update/blob/57f2db992e763f64e87e6f7173fd91f120be6380/src/Skiplist.hs), lines 210-212; [doc/nixpkgs-maintainer-faq.md](https://github.com/nix-community/nixpkgs-update/blob/57f2db992e763f64e87e6f7173fd91f120be6380/doc/nixpkgs-maintainer-faq.md), lines 27-33
[^dup]: [src/GH.hs](https://github.com/nix-community/nixpkgs-update/blob/57f2db992e763f64e87e6f7173fd91f120be6380/src/GH.hs), lines 216-240; [src/Nix.hs](https://github.com/nix-community/nixpkgs-update/blob/57f2db992e763f64e87e6f7173fd91f120be6380/src/Nix.hs), line 89; [src/Version.hs](https://github.com/nix-community/nixpkgs-update/blob/57f2db992e763f64e87e6f7173fd91f120be6380/src/Version.hs), lines 36-106
[^python]: [src/Skiplist.hs](https://github.com/nix-community/nixpkgs-update/blob/57f2db992e763f64e87e6f7173fd91f120be6380/src/Skiplist.hs), lines 272-283
[^sandbox]: [src/Utils.hs](https://github.com/nix-community/nixpkgs-update/blob/57f2db992e763f64e87e6f7173fd91f120be6380/src/Utils.hs), lines 247-263
[^tools]: [pkgs/default.nix](https://github.com/nix-community/nixpkgs-update/blob/57f2db992e763f64e87e6f7173fd91f120be6380/pkgs/default.nix), lines 15-23
[^outpaths]: [src/Outpaths.hs](https://github.com/nix-community/nixpkgs-update/blob/57f2db992e763f64e87e6f7173fd91f120be6380/src/Outpaths.hs), lines 30-124; [doc/details.md](https://github.com/nix-community/nixpkgs-update/blob/57f2db992e763f64e87e6f7173fd91f120be6380/doc/details.md), lines 56-60
[^checks]: [src/Check.hs](https://github.com/nix-community/nixpkgs-update/blob/57f2db992e763f64e87e6f7173fd91f120be6380/src/Check.hs), lines 93-113, 179-195
[^prbody]: [src/Update.hs](https://github.com/nix-community/nixpkgs-update/blob/57f2db992e763f64e87e6f7173fd91f120be6380/src/Update.hs), lines 456-603; [src/NixpkgsReview.hs](https://github.com/nix-community/nixpkgs-update/blob/57f2db992e763f64e87e6f7173fd91f120be6380/src/NixpkgsReview.hs), lines 38-51
[^branch]: [src/Utils.hs](https://github.com/nix-community/nixpkgs-update/blob/57f2db992e763f64e87e6f7173fd91f120be6380/src/Utils.hs), lines 131, 230-234
[^delete]: [src/GH.hs](https://github.com/nix-community/nixpkgs-update/blob/57f2db992e763f64e87e6f7173fd91f120be6380/src/GH.hs), lines 77-103, 190-208
[^worktree]: [src/Update.hs](https://github.com/nix-community/nixpkgs-update/blob/57f2db992e763f64e87e6f7173fd91f120be6380/src/Update.hs), lines 726-741; [src/Git.hs](https://github.com/nix-community/nixpkgs-update/blob/57f2db992e763f64e87e6f7173fd91f120be6380/src/Git.hs), line 171
</content>
