---
summary: >-
  How a fixed-output derivation's real hash is learned by deliberately
  building with a wrong one and parsing the true hash out of the failure —
  the `fakeHash` bootstrap, with two different concrete implementations
  (nixpkgs-update, nix-update) — and why vendored-dependency hashes
  (`cargoHash`, `vendorHash`, `npmDepsHash`) need the trick run a second time.
sources:
  - https://github.com/nix-community/nixpkgs-update/blob/57f2db992e763f64e87e6f7173fd91f120be6380/src/Nix.hs
  - https://github.com/nix-community/nixpkgs-update/blob/57f2db992e763f64e87e6f7173fd91f120be6380/src/Rewrite.hs
  - https://github.com/nix-community/nixpkgs-update/blob/57f2db992e763f64e87e6f7173fd91f120be6380/src/Skiplist.hs
  - https://github.com/Mic92/nix-update/blob/0ebb0d8b522de1de00b5730d2e13307c4a0ea2e0/nix_update/dependency_hashes.py
  - https://github.com/Mic92/nix-update/blob/0ebb0d8b522de1de00b5730d2e13307c4a0ea2e0/nix_update/hashes.py
tags:
  - nixpkgs
  - hashes
  - fixed-output-derivations
---

# The fakeHash bootstrap

A fixed-output derivation (FOD) — `fetchurl`, `fetchFromGitHub`,
`fetchCargoVendor`, and the like — is the only authority on its own output
hash. There is no way to ask Nix "what would this hash be" without actually
fetching the content, so both [[nixpkgs-update]] and [[nix-update]] learn a
new hash the same conceptual way: deliberately cause a hash-mismatch build
failure and read the correct hash out of Nix's own error message. They
implement that idea differently enough to be worth reading side by side.

## Implementation A: rewrite the file with a matching-algorithm fake hash (nixpkgs-update)

`Rewrite.srcVersionFix` does, in order:[^rewrite]

1. Read the *current* `outputHash` via `nix eval` (exposed as
   `drvAttrs.outputHash`).[^gethash]
2. Substitute the version string in the package file.
3. Replace the old hash with an all-`A` fake hash of the *same SRI
   algorithm* — `sha256-AAA…` or `sha512-AAA…`. The algorithm has to match,
   or Nix rejects the fake hash before it ever attempts the build.[^fakehash]
4. Run `nix-build`, expecting it to fail with a hash mismatch.
5. Parse the real hash out of stderr by splitting on the literal string
   `"got:    "` in Nix's FOD-mismatch message.[^parse]
6. If the new hash equals the old one, abort with "Hashes equal; no update
   necessary" — nothing to do.

This is the same class of trick a human does by hand when bumping a
`fetchFromGitHub` hash with a placeholder and copying the "got:" line out of
the build error; nixpkgs-update just automates the substitution and the
parsing. The cost of this approach: the fake hash is briefly present in the
actual file on disk, and its algorithm must be guessed correctly up front.

## Implementation B: override `outputHash` in a throwaway expression (nix-update)

`nix-update`'s `nix_prefetch` never edits the file at all.[^nixprefetch] It
runs:

```
nix-build --expr 'let src = <pkg-expr>.<attr>; in
  (src.overrideAttrs or (f: src // f src)) (_: { outputHash = ""; outputHashAlgo = "sha256"; })'
```

— overriding `outputHash` to the *empty string* on a throwaway copy of the
attribute, in a `--expr` that is never written to disk, then letting that
build fail and parsing stderr with a regex tolerant of several formats
(`got: <hex>`, `got: sha256:...`, `got: sha256-...=`, `blake3-...`, and
`expected 'x' but got 'y'`).[^extractregex] The result is normalized via
`nix hash to-sri`, guessing the algorithm from the hex length (32→md5,
40→sha1, else sha256).[^tosri] The old and new hashes are compared
post-normalization, and the write is skipped entirely if they match.

Consequences of not touching the file: no risk of a fake hash surviving an
interrupted run, and no need to pre-guess the original algorithm (it's
forced to `sha256` for the override attempt regardless of what's actually
in the file). The tradeoff: the attribute has to be reachable as an
evaluable sub-expression that supports `overrideAttrs` (hence the
`(src.overrideAttrs or (f: src // f src))` fallback for non-derivation
values like a plain fetched tarball).

## Vendored hashes need a second (and sometimes third) pass

`cargoHash`, `npmDepsHash`, and Go's `vendorHash` are each an independent
FOD from the main `src` — one build cannot reveal both hashes at once. Both
tools handle this, differently:

**nixpkgs-update**: each vendor-hash attribute gets its own rewriter that
runs the ordinary `srcVersionFix` first, then repeats the fake-hash-and-parse
cycle for the vendor hash, then does a real build to confirm the
result.[^vendor] Its Go rewriter is the special case: it first tries setting
`vendorHash = null` — i.e., assuming the package vendors its dependencies
in-tree and needs no separate hash at all — and only falls back to the
fake-hash cycle if that build fails, restoring the original file contents in
between.[^golang] A code comment notes the vendor hash "may not actually
change if go.sum did not," i.e. small version bumps often leave the
dependency lock untouched. Only these three ecosystems get this treatment;
`buildRustCrate`, `buildRubyGem`, `bundlerEnv`, and `buildPerlPackage` are
skiplisted outright rather than attempted.[^skiplist]

**nix-update** dispatches every ecosystem it supports (`cargoHash`,
`vendorHash`, `npmDepsHash`, `pnpmDeps`, `yarnOfflineCache`, `mvnHash`,
`mixFodDeps`, `zigDeps`, `nugetDeps`, `composerVendor`, Gradle `mitmCache`,
and arbitrary `--custom-dep` attributes) from one ordered registry, with a
comment explaining *why the order is load-bearing*: some frameworks like
Go's `goModules` derive their FOD from the whole derivation, so an earlier
edit to an unrelated hash (say, an npm hash) can invalidate a Go hash
computed before it — hence Go-related entries are placed last in the
dict.[^ordering] Notably, nix-update does **not** replicate nixpkgs-update's
`vendorHash = null` probe for Go — no attempt to detect in-tree vendoring.

## Limits

- The hash-parsing step in both tools is tied to the exact wording of Nix's
  error output — a Nix error-message format change could break either,
  though nix-update's regex is markedly more tolerant of format variation
  (hex, `algo:`, SRI, blake3, and the `expected 'x' but got 'y'` phrasing)
  than nixpkgs-update's single fixed split string.
- nixpkgs-update refuses outright, by design, any package with more than
  one fetcher or more than one hash attribute in its file (counted by naive
  substring search for things like `fetchurl {` or `sha256 =`) — correct-
  looking textual substitution across ambiguous hashes is judged worse than
  not updating at all.[^multihash]
- nix-update's ordered-registry fix for the Go hash-invalidation hazard is
  a silent convention: adding a new ecosystem in the wrong position in the
  dict would reintroduce the bug it exists to prevent.[^ordering]

## Related

- [[nixpkgs-update]] and [[nix-update]] — the two tools this page compares.
- [[r-ryantm-bot]] — how this rewrite step fits into the bot's overall
  discover → rewrite → build → check → PR pipeline.
- [[nix-update-script]] — how nix-update's variant of this mechanism gets
  invoked from a package's `passthru.updateScript`.

[^rewrite]: [src/Rewrite.hs](https://github.com/nix-community/nixpkgs-update/blob/57f2db992e763f64e87e6f7173fd91f120be6380/src/Rewrite.hs), lines 247-257
[^gethash]: [src/Nix.hs](https://github.com/nix-community/nixpkgs-update/blob/57f2db992e763f64e87e6f7173fd91f120be6380/src/Nix.hs), line 148
[^fakehash]: [src/Nix.hs](https://github.com/nix-community/nixpkgs-update/blob/57f2db992e763f64e87e6f7173fd91f120be6380/src/Nix.hs), lines 230-234
[^parse]: [src/Nix.hs](https://github.com/nix-community/nixpkgs-update/blob/57f2db992e763f64e87e6f7173fd91f120be6380/src/Nix.hs), lines 236-258
[^vendor]: [src/Rewrite.hs](https://github.com/nix-community/nixpkgs-update/blob/57f2db992e763f64e87e6f7173fd91f120be6380/src/Rewrite.hs), lines 130-222
[^golang]: [src/Rewrite.hs](https://github.com/nix-community/nixpkgs-update/blob/57f2db992e763f64e87e6f7173fd91f120be6380/src/Rewrite.hs), lines 173-189
[^skiplist]: [src/Skiplist.hs](https://github.com/nix-community/nixpkgs-update/blob/57f2db992e763f64e87e6f7173fd91f120be6380/src/Skiplist.hs), lines 208-221
[^multihash]: [src/Rewrite.hs](https://github.com/nix-community/nixpkgs-update/blob/57f2db992e763f64e87e6f7173fd91f120be6380/src/Rewrite.hs), line 83; [src/Nix.hs](https://github.com/nix-community/nixpkgs-update/blob/57f2db992e763f64e87e6f7173fd91f120be6380/src/Nix.hs), lines 198-209
[^nixprefetch]: [nix_update/dependency_hashes.py](https://github.com/Mic92/nix-update/blob/0ebb0d8b522de1de00b5730d2e13307c4a0ea2e0/nix_update/dependency_hashes.py), lines 57-94
[^extractregex]: [nix_update/dependency_hashes.py](https://github.com/Mic92/nix-update/blob/0ebb0d8b522de1de00b5730d2e13307c4a0ea2e0/nix_update/dependency_hashes.py), lines 34-54
[^tosri]: [nix_update/hashes.py](https://github.com/Mic92/nix-update/blob/0ebb0d8b522de1de00b5730d2e13307c4a0ea2e0/nix_update/hashes.py), lines 12-32
[^ordering]: [nix_update/dependency_hashes.py](https://github.com/Mic92/nix-update/blob/0ebb0d8b522de1de00b5730d2e13307c4a0ea2e0/nix_update/dependency_hashes.py), lines 209-234, citing nixpkgs issue #358844
</content>
