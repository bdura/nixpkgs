---
summary: >-
  The path from a merged nixpkgs PR to a machine that can install it: branch
  targeting by rebuild count, the staging cycle, Hydra jobset evaluation, and
  the gating `tested` job that actually advances a channel. Explains why a
  green PR can sit unbumped for days, and why the channel is just a git
  branch a cronjob fast-forwards.
sources:
  - https://github.com/NixOS/nixpkgs/blob/master/CONTRIBUTING.md
  - https://wiki.nixos.org/wiki/Channel_branches
  - https://github.com/NixOS/nixos-channel-scripts
tags:
  - nixpkgs
  - channels
  - hydra
  - operations
---

# The nixpkgs release pipeline

How a change — a bot-authored bump or a hand-written PR like a package
version bump — travels from merge to a closure a machine can actually build.
Five stages; the latency is concentrated in two of them.

## 1. Merge

At least one committer must review and approve. Which branch a PR targets
is decided by **rebuild count**, not by the nature of the change:

| Rebuilds | Target |
|---|---|
| < 500 | `master` |
| ≥ 500 | consider `staging` |
| ≥ 1000 | mass rebuild — `staging` required |

`staging-next` is reserved for fixing Hydra breakage; anything else landing
there needs coordination with the staging maintainers.

Automated update bots always open against `master`. A bump that turns out
to cross the rebuild threshold has to be retargeted by hand — this is the
ordinary reason a green, unremarked-upon automated PR sits for weeks: it's
waiting on someone to notice and retarget it, not on CI.

## 2. The staging cycle

Only relevant if the change went to `staging`. Most of the merge schedule
is mechanical:

- `master` → `staging-next`: automated, roughly every 6h
- `staging-next` → `staging`: automated, roughly every 24h
- `staging` → `staging-next`: manual
- `staging-next` → `master`: manual PR, once Hydra is green on it

The point is batching: Hydra builds a mass rebuild once, rather than
`master` being red for the days a rebuild of that size would otherwise take.
The cost is that any single mass-rebuild change waits for the whole batch
it landed in.

## 3. Hydra builds, and the cache fills

Once a change is on `master` (or has gone through staging and landed there),
it enters Hydra's jobset evaluations. Build outputs are pushed to
`cache.nixos.org` **as they are built**, independent of channel state.

So a substitutable binary generally exists *before* the channel that would
reference it has moved. These two events — "built and cached" versus
"channel bumped" — are independent, and conflating them is the usual source
of confusion about why something seems to be "already cached but not
available yet".

## 4. The channel bump — the actual gate

A channel advances only when **both**:

1. the jobset evaluation completes with no jobs still queued, and
2. the channel's gating aggregate job (commonly named `tested`) succeeds.

| Channel | Gating job |
|---|---|
| `nixos-unstable` | includes NixOS VM tests — the strictest gate |
| `nixos-unstable-small` | a smaller, commonly-used package/test subset |
| `nixpkgs-unstable` | nixpkgs-only, no NixOS tests |

A cronjob (`nixos-channel-scripts`) polls for the newest evaluation
satisfying both conditions and performs the bump — the channel branch is
fast-forwarded to that commit. Two consequences worth internalizing:

- **A single `tested` failure anywhere blocks the whole channel for
  everyone**, not just for the package that broke. This is the single
  biggest cause of "my PR merged days ago and still isn't in the channel".
- The `*-small` channels carry the same content, gated on a smaller test
  set, so they tend to advance sooner — useful as a fallback when the large
  channel is stuck.

Typical latency from landing on `master` to a channel bump is a few days
under normal conditions; live status is tracked at status.nixos.org.

## 5. Reaching a consumer

The channel *is* a real git branch in `NixOS/nixpkgs` (e.g. `nixos-unstable`)
that the channel scripts fast-forward to the latest evaluated,
`tested`-green commit — the bump *is* the branch moving. A flake input like

```nix
nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
```

resolves to exactly the last green channel commit at the time
`flake.lock` was last updated. Nothing changes for a consumer until they run
`nix flake update` (or `nix-channel --update` in the pre-flake world) —
everything upstream of that is latency that can only be observed, not
controlled.

## Stable releases

A change does **not** reach a `release-YY.MM` channel unless it's
backported: a maintainer adds a `backport release-YY.MM` label, an
automated cherry-pick PR is opened against the release branch, and it goes
through the same review → Hydra → channel pipeline against the release
jobset. Only currently-supported releases are eligible.

## Related

- [[nixpkgs-deprecation-policy]] — `oldestSupportedRelease` is defined
  relative to which releases are currently supported, the same set this
  pipeline's backport rules reference.
