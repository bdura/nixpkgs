---
summary: >-
  How `passthru.updateScript = nix-update-script { }` actually works: the
  wrapper passes no arguments at all, the attrpath and old version arrive as
  environment variables from the caller, and everything else (which file to
  edit, which forge to query) is re-derived by nix-update at run time.
sources:
  - https://github.com/NixOS/nixpkgs/blob/master/pkgs/by-name/ni/nix-update/nix-update-script.nix
  - https://github.com/NixOS/nixpkgs/blob/master/maintainers/scripts/update.py
  - https://github.com/Mic92/nix-update/blob/0ebb0d8b522de1de00b5730d2e13307c4a0ea2e0/nix_update/update.py
  - https://github.com/Mic92/nix-update/blob/0ebb0d8b522de1de00b5730d2e13307c4a0ea2e0/README.md
tags:
  - nixpkgs
  - automation
  - passthru
---

# `passthru.updateScript` and `nix-update-script`

`passthru.updateScript` is a generic nixpkgs convention: any derivation can
expose a program (or list of program + args) under this attribute, and
tooling that walks nixpkgs looking for updatable packages — `maintainers/scripts/update.py`,
and [[r-ryantm-bot]] as one of its three discovery sources — runs it and
expects it to have rewritten the package's own file in place. The attribute
says nothing about *how* the update happens; `nix-update-script` is just the
most common implementation of it.

## The wrapper does almost nothing

`pkgs/by-name/ni/nix-update/nix-update-script.nix` is eleven lines:

```nix
{ attrPath ? null, extraArgs ? [ ] }:
[ "${lib.getExe nix-update}" ] ++ extraArgs ++ lib.optionals (attrPath != null) [ attrPath ]
```

So `nix-update-script { }` evaluates to literally `["…/bin/nix-update"]` —
no attrpath, no flags. The only thing a package can configure through this
call is `extraArgs` (e.g. `nix-update-script { extraArgs = ["--version=branch"]; }`).[^wrapper]

## Where the attrpath comes from instead: environment variables

`nix-update`'s CLI defaults its positional `attribute` argument to
`os.getenv("UPDATE_NIX_ATTR_PATH")`.[^envdefault] The caller —
`maintainers/scripts/update.py`, which is what enumerates packages and
invokes their `updateScript` — sets `UPDATE_NIX_NAME`, `UPDATE_NIX_PNAME`,
`UPDATE_NIX_OLD_VERSION`, and `UPDATE_NIX_ATTR_PATH` in the environment
before running the script.[^callerenv] This is why `nix-update-script { }`
works with zero arguments: the identity of the package is injected by
whoever runs the update script, not baked into the derivation.

Everything else — which file in the tree to edit, which forge to query for
a new version, what tag prefix to assume — is **not** configurable at this
call site at all. It's re-derived from the evaluated derivation every run;
see [[forge-detection-from-src-url]] for how that derivation is worked
back into a decision.

## The reverse direction: nix-update running someone else's updateScript

`nix-update -u`/`--use-update-script` is the same mechanism operated from
the other side: instead of nix-update doing the rewrite itself, it locates
and runs the package's `passthru.updateScript`.[^reverse] Inside a nixpkgs
checkout (non-flake) it shells out to
`nix-shell maintainers/scripts/update.nix --argstr package <attr> --argstr skip-prompt true`;
outside nixpkgs it builds the script directly
(`writeScript … (lib.escapeShellArgs (lib.toList (pkg.updateScript.command or pkg.updateScript)))`)
and runs it inside `nix develop` with `inputsFrom = [ pkg ]`, exporting the
same four `UPDATE_NIX_*` variables either way.[^reverse-env] Afterwards it
re-evaluates the attribute to learn the new version and generate a diff URL.

Concretely: `nix-update -u microcad` on a package whose own
`passthru.updateScript` is `nix-update-script { }` re-invokes nix-update a
second time, through `maintainers/scripts/update.nix` — the two directions
compose rather than being mutually exclusive.

## Worked trace: why `nix-update-script { }` is sufficient for a Codeberg package

For `pkgs/by-name/mi/microcad/package.nix` — `fetchFromCodeberg { owner =
"microcad"; repo = "microcad"; tag = "v${finalAttrs.version}"; }` plus
`cargoHash` — tracing the code (not executed) shows `nix-update-script { }`
needs no `extraArgs`:

1. `fetchFromCodeberg` is `fetchFromGitea` with a fixed `githubBase =
   "codeberg.org"`, so the evaluated `src.url` is
   `https://codeberg.org/microcad/microcad/archive/v0.5.1.tar.gz` — an
   ordinary GitHub-shaped archive URL, but on a host nix-update recognizes
   as Gitea (see [[forge-detection-from-src-url]] for the disambiguation).
2. nix-update lists `/api/v1/repos/microcad/microcad/tags` on Codeberg's
   Gitea API rather than GitHub's release API.
3. The evaluated `tag` is `"v0.5.1"`; nix-update infers the tag prefix `v`
   from that string and strips it from whatever new tag it picks, so
   `version` becomes e.g. `0.5.2` while the file's `tag` becomes `v0.5.2`.[^prefix]
4. `cargoHash` gets refreshed by the ordinary dependency-hash pass (see
   [[hash-update-mechanics]]).

Caveat: candidate tags matching a prerelease pattern (`alpha`, `beta`, `rc`,
`nightly`, etc.) are filtered out by default, so a prerelease tag like
`v0.6.0-rc1` needs `--version=unstable` to be picked up.[^prerelease]

## Related

- [[nix-update]] — the CLI this whole mechanism is built on.
- [[forge-detection-from-src-url]] — how the forge to query is chosen.
- [[hash-update-mechanics]] — how the source and dependency hashes are
  actually recomputed once a new version is chosen.
- [[r-ryantm-bot]] — the other consumer of `passthru.updateScript`, run
  with a 30-minute timeout as one of three discovery sources.

[^wrapper]: [pkgs/by-name/ni/nix-update/nix-update-script.nix](https://github.com/NixOS/nixpkgs/blob/master/pkgs/by-name/ni/nix-update/nix-update-script.nix)
[^envdefault]: [nix_update/__init__.py](https://github.com/Mic92/nix-update/blob/0ebb0d8b522de1de00b5730d2e13307c4a0ea2e0/nix_update/__init__.py), lines 119-125
[^callerenv]: [maintainers/scripts/update.py](https://github.com/NixOS/nixpkgs/blob/master/maintainers/scripts/update.py), lines 243-249
[^reverse]: [nix_update/update.py](https://github.com/Mic92/nix-update/blob/0ebb0d8b522de1de00b5730d2e13307c4a0ea2e0/nix_update/update.py), lines 137-193
[^reverse-env]: [README.md](https://github.com/Mic92/nix-update/blob/0ebb0d8b522de1de00b5730d2e13307c4a0ea2e0/README.md), lines 197-205
[^prefix]: [nix_update/update.py](https://github.com/Mic92/nix-update/blob/0ebb0d8b522de1de00b5730d2e13307c4a0ea2e0/nix_update/update.py), lines 82-89; [nix_update/version/__init__.py](https://github.com/Mic92/nix-update/blob/0ebb0d8b522de1de00b5730d2e13307c4a0ea2e0/nix_update/version/__init__.py), lines 135-157
[^prerelease]: [nix_update/version/__init__.py](https://github.com/Mic92/nix-update/blob/0ebb0d8b522de1de00b5730d2e13307c4a0ea2e0/nix_update/version/__init__.py), line 111
</content>
