---
summary: >-
  How a nixpkgs package that builds from source on Linux can support Darwin
  by repackaging the upstream `.app` (from a DMG or zip) instead, using a
  `darwin.nix` split selected on `hostPlatform.isDarwin`.
sources:
  - pkgs/by-name/lo/localsend/package.nix
  - pkgs/by-name/lo/localsend/darwin.nix
  - pkgs/by-name/lo/localsend/linux.nix
  - pkgs/by-name/gd/gdevelop/package.nix
  - pkgs/by-name/gd/gdevelop/darwin.nix
  - pkgs/by-name/ai/airbuddy/package.nix
tags:
  - nixpkgs
  - darwin
  - packaging
---

# Repackaging an upstream macOS binary on Darwin

Some Linux source builds use GTK, Linux-only libraries or GNU-ld flags, so
porting them to Darwin would be a lot of work. When upstream ships a macOS
`.app`, the cheaper route is to keep building from source on Linux and
repackage the upstream binary on Darwin, all under one attribute.

## The split

`package.nix` holds the shared `pname`, `version` and `meta`. It then
dispatches on the host platform to a `darwin.nix` or `linux.nix` and passes
those values in.

- **localsend** uses `import ./darwin.nix { inherit pname version meta …; }`
  and passes every dependency by hand.[^ls-pkg] Its `linux.nix` builds from
  source with `flutter341.buildFlutterApplication` and `fetchFromGitHub`.[^ls-linux]
  This is the "source on Linux, binary on Darwin" pattern.
- **gdevelop** uses `callPackage ./darwin.nix { inherit pname version meta passthru; }`,
  so each file declares its own dependencies.[^gd-pkg] Both of its sides
  are binaries.

## The Darwin side

`darwin.nix` is a `stdenvNoCC.mkDerivation` that fetches the release asset
with `fetchurl`, sets `sourceRoot = "."`, and copies the `.app` into
`$out/Applications`.[^ls-darwin][^gd-darwin] localsend also adds a
`makeBinaryWrapper` wrapper at `$out/bin/<name>` so that `mainProgram`
works.[^ls-darwin] gdevelop sets `dontPatch`/`dontConfigure`/`dontBuild`/`dontFixup`.[^gd-darwin]

The Darwin side must declare `sourceProvenance = [ lib.sourceTypes.binaryNativeCode ]`.
localsend does this by overriding the shared meta with
`meta = meta // { sourceProvenance = …; platforms = [ "aarch64-darwin" ]; }`,
which keeps the Linux side free of the binary flag.[^ls-darwin] A universal
build (x86_64 and aarch64) can use `lib.platforms.darwin`, as gdevelop
does.[^gd-pkg]

## Unpacking: `undmg` vs `_7zz`

- HFS+ DMG: `undmg` in `nativeBuildInputs` (localsend).[^ls-darwin]
- APFS-formatted DMG: `undmg` can't read these, so the convention is `_7zz`.
  airbuddy has a comment saying exactly that: "AirBuddy.dmg is APFS
  formatted, unpack with 7zz".[^airbuddy] Packages such as `aldente` carry
  the same comment.
- Zip: `unzip` (gdevelop).[^gd-darwin]

You can only tell which DMG format you have by trying to unpack it.

## Caveats

- **Two hashes, one version.** Both sides read the same `version`, so each
  bump must also refresh the Darwin asset hash. The
  [[nix-update-script]] and [[hash-update-mechanics]] pages don't yet cover
  how `nix-update` handles a second, platform-specific source. *Needs
  verification.*
- **Linux-only options** (e.g. `withSystemd`) make no sense on the binary
  side. The Darwin file should simply not accept them.
- **Review.** Reviewers sometimes prefer a separate `<name>-bin` attribute to
  a mixed source/binary attribute. localsend shows the mixed form is
  accepted. *Unsourced: based on review practice, not a written policy.*

## Related

- [[orca-slicer]] — a candidate for this pattern.
- [[callpackage-and-override]] — `callPackage` vs plain `import` for the
  split files.

[^ls-pkg]: [pkgs/by-name/lo/localsend/package.nix](../../pkgs/by-name/lo/localsend/package.nix), lines 41-55 (at `aa016d6dc7bc`)
[^ls-linux]: [pkgs/by-name/lo/localsend/linux.nix](../../pkgs/by-name/lo/localsend/linux.nix), lines 23-35
[^ls-darwin]: [pkgs/by-name/lo/localsend/darwin.nix](../../pkgs/by-name/lo/localsend/darwin.nix)
[^gd-pkg]: [pkgs/by-name/gd/gdevelop/package.nix](../../pkgs/by-name/gd/gdevelop/package.nix)
[^gd-darwin]: [pkgs/by-name/gd/gdevelop/darwin.nix](../../pkgs/by-name/gd/gdevelop/darwin.nix)
[^airbuddy]: [pkgs/by-name/ai/airbuddy/package.nix](../../pkgs/by-name/ai/airbuddy/package.nix), line 23
