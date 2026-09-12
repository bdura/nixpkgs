---
summary: >-
  Why nix-update decides which forge (GitHub, GitLab, Gitea/Codeberg,
  Sourcehut...) to query for a new version by matching the evaluated `src`
  URL, not the fetcher function used in the package file — because by
  evaluation time the fetcher function is already gone.
sources:
  - https://github.com/Mic92/nix-update/blob/0ebb0d8b522de1de00b5730d2e13307c4a0ea2e0/nix_update/eval.nix
  - https://github.com/Mic92/nix-update/blob/0ebb0d8b522de1de00b5730d2e13307c4a0ea2e0/nix_update/eval.py
  - https://github.com/Mic92/nix-update/blob/0ebb0d8b522de1de00b5730d2e13307c4a0ea2e0/nix_update/version/github.py
  - https://github.com/Mic92/nix-update/blob/0ebb0d8b522de1de00b5730d2e13307c4a0ea2e0/nix_update/version/gitea.py
  - https://github.com/Mic92/nix-update/blob/0ebb0d8b522de1de00b5730d2e13307c4a0ea2e0/nix_update/version/gitlab.py
tags:
  - nixpkgs
  - automation
  - fetchers
---

# Forge detection from the evaluated `src` URL

[[nix-update]] never inspects which Nix fetcher function a package used
(`fetchFromGitHub`, `fetchFromCodeberg`, `fetchgit`, ...). It can't: by the
time the package attribute is evaluated, the fetcher call has already been
reduced to a plain derivation with a `url`/`urls` attribute — the function
name is gone. `nix_update/eval.nix` exports only `pkg.src.urls`/`.url`/
`.rev`/`.tag`/`.outputHash`, nothing about how they were produced.[^eval]
Every "which forge is this" decision is made by matching that one URL
string.[^post-init]

## Why this matters for Codeberg/Forgejo specifically

`fetchFromCodeberg` is implemented as `fetchFromGitea` with a fixed
`githubBase = "codeberg.org"`, which is itself implemented in terms of
`fetchFromGitHub`'s URL shape.[^fetchgitea] So a Codeberg package and a
GitHub package produce **the same URL shape**:
`https://<host>/<owner>/<repo>/archive/<rev>.tar.gz`. The only thing that
distinguishes them post-evaluation is the hostname.

nix-update's GitHub backend therefore contains an explicit guard: if a URL
matches the GitHub archive-URL regex but the host is a known Gitea/Forgejo
host, the GitHub backend declines and lets the Gitea backend handle
it.[^guard] The Gitea backend matches a hardcoded list —
`codeberg.org`, `gitea.com`, `akkoma.dev` — and, for any *other* host,
probes it live: a GET to `https://<host>/api/v1/settings/api`, which is why
this backend is tried last (it costs a network request).[^gitea-detect]
GitLab is matched separately by its distinctive
`/api/v4/projects/<id>/repository/archive.tar.gz?sha=` URL shape.[^gitlab]

## Tags vs. releases is a second, independent forge difference

Beyond *which* API to call, different forges are asked for different kinds
of thing:

- **GitHub** defaults to parsing the repo's `releases.atom` feed (no token,
  no rate-limit budget needed); `--use-github-releases` switches to the
  paginated REST `/releases` API, which understands the `prerelease` flag
  and honours `$GITHUB_TOKEN`.[^github-releases]
- **Gitea/Codeberg** is queried for **tags**
  (`/api/v1/repos/{owner}/{repo}/tags`), not releases.[^gitea-tags]
- **GitLab** is queried for tags, preferring ones that carry an attached
  release but falling back to plain tags if none do.[^gitlab-tags]

This distinction is load-bearing, not cosmetic: Codeberg also serves a
GitHub-shaped `releases.atom` that lists only *releases*. A regression test
(`tests/test_gitea.py`, tracking issue #636) exists specifically because
consulting that feed for a Codeberg package would have silently
**downgraded** it — the newest tag had no attached release, so the release
feed's newest entry was older than the newest tag.[^regression] The
GitHub-vs-Gitea host guard described above is the fix.

## Limits

- A package whose `src` points at a vendor download mirror rather than a
  forge archive URL (the README's example is Signal Desktop) is
  undetectable by any backend; `--url` is the manual override.[^undetectable]
- Non-URL sources — a bare `fetchgit` URL, a local path — fail outright
  with "Could not find a url in the derivations src attribute".[^nourl]
- A GitHub project that tags releases but never *publishes* a GitHub
  Release is not handled symmetrically to the Codeberg case: there's a
  `# TODO fallback to tags?` at the point where the ATOM-feed parse would
  need one.[^todo-fallback]
- Documentation drift: the README lists "Codeberg" as a forge distinct from
  Gitea; in the code there is no separate Codeberg backend, only
  `gitea.py` with `codeberg.org` in its list of known hosts. The commit
  message's `Diff:` trailer generator (`diff_urls.py`) separately hardcodes
  only `codeberg.org`/`gitea.com`, narrower than the live-probe detection
  above — a self-hosted Forgejo instance gets its version bumped correctly
  but no `Diff:` trailer, and this gap isn't documented anywhere.[^diffgap]

## Related

- [[nix-update]] — the tool this mechanism belongs to.
- [[nix-update-script]] — the `passthru.updateScript` integration point;
  includes a worked trace of this detection for a `fetchFromCodeberg`
  package.

[^eval]: [nix_update/eval.nix](https://github.com/Mic92/nix-update/blob/0ebb0d8b522de1de00b5730d2e13307c4a0ea2e0/nix_update/eval.nix), lines 120-124
[^post-init]: [nix_update/eval.py](https://github.com/Mic92/nix-update/blob/0ebb0d8b522de1de00b5730d2e13307c4a0ea2e0/nix_update/eval.py), lines 91-93; [nix_update/version/__init__.py](https://github.com/Mic92/nix-update/blob/0ebb0d8b522de1de00b5730d2e13307c4a0ea2e0/nix_update/version/__init__.py), lines 66-78
[^fetchgitea]: [pkgs/build-support/fetchgitea/default.nix](https://github.com/NixOS/nixpkgs/blob/master/pkgs/build-support/fetchgitea/default.nix), lines 1-22
[^guard]: [nix_update/version/github.py](https://github.com/Mic92/nix-update/blob/0ebb0d8b522de1de00b5730d2e13307c4a0ea2e0/nix_update/version/github.py), lines 23-45
[^gitea-detect]: [nix_update/version/gitea.py](https://github.com/Mic92/nix-update/blob/0ebb0d8b522de1de00b5730d2e13307c4a0ea2e0/nix_update/version/gitea.py), lines 16-37
[^gitlab]: [nix_update/version/gitlab.py](https://github.com/Mic92/nix-update/blob/0ebb0d8b522de1de00b5730d2e13307c4a0ea2e0/nix_update/version/gitlab.py), lines 14-16
[^github-releases]: [nix_update/version/github.py](https://github.com/Mic92/nix-update/blob/0ebb0d8b522de1de00b5730d2e13307c4a0ea2e0/nix_update/version/github.py), lines 107-169
[^gitea-tags]: [nix_update/version/gitea.py](https://github.com/Mic92/nix-update/blob/0ebb0d8b522de1de00b5730d2e13307c4a0ea2e0/nix_update/version/gitea.py), lines 46-48
[^gitlab-tags]: [nix_update/version/gitlab.py](https://github.com/Mic92/nix-update/blob/0ebb0d8b522de1de00b5730d2e13307c4a0ea2e0/nix_update/version/gitlab.py), lines 43-51
[^regression]: [tests/test_gitea.py](https://github.com/Mic92/nix-update/blob/0ebb0d8b522de1de00b5730d2e13307c4a0ea2e0/tests/test_gitea.py), lines 48-59
[^undetectable]: [README.md](https://github.com/Mic92/nix-update/blob/0ebb0d8b522de1de00b5730d2e13307c4a0ea2e0/README.md), lines 127-137
[^nourl]: [nix_update/update.py](https://github.com/Mic92/nix-update/blob/0ebb0d8b522de1de00b5730d2e13307c4a0ea2e0/nix_update/update.py), lines 78-80
[^todo-fallback]: [nix_update/version/github.py](https://github.com/Mic92/nix-update/blob/0ebb0d8b522de1de00b5730d2e13307c4a0ea2e0/nix_update/version/github.py), line 156
[^diffgap]: [README.md](https://github.com/Mic92/nix-update/blob/0ebb0d8b522de1de00b5730d2e13307c4a0ea2e0/README.md), line 10, vs. [nix_update/version/gitea.py](https://github.com/Mic92/nix-update/blob/0ebb0d8b522de1de00b5730d2e13307c4a0ea2e0/nix_update/version/gitea.py); [nix_update/diff_urls.py](https://github.com/Mic92/nix-update/blob/0ebb0d8b522de1de00b5730d2e13307c4a0ea2e0/nix_update/diff_urls.py), line 93
</content>
