---
title: "feat(orca-slicer): support Darwin by repackaging the upstream macOS DMG"
---

`orca-slicer` (`pkgs/by-name/or/orca-slicer/package.nix`) currently has
`meta.platforms = lib.platforms.linux`. The user asked why. It turns out the
restriction was inherited from `bambu-studio` when the package was created
(`98a73e1caf11`, #275638) and nobody gave a reason. Upstream ships macOS
builds. See wiki [orca-slicer](../wiki/orca-slicer.md).

Porting the source build to Darwin would be real work: it is GTK-bound
(wxGTK, webkitgtk, gstreamer, dbus) and uses `-Wl,--no-as-needed`. The user
pasted the Homebrew cask, which installs
`OrcaSlicer_Mac_universal_V${version}.dmg` from the GitHub release
(containing `OrcaSlicer.app`). The proposal is to repackage that DMG on
Darwin and keep building from source on Linux, following the
localsend/gdevelop `darwin.nix` pattern described in
[darwin-binary-repackaging](../wiki/darwin-binary-repackaging.md).

What is already known:

- The DMG is universal (x86_64 and aarch64), so `lib.platforms.darwin` would
  cover both architectures.
- The Darwin side would carry `sourceProvenance = [ binaryNativeCode ]`.
- The Linux build and its options (`withSystemd`, `withNvidiaGLWorkaround`)
  must not change.
- Testing the Darwin side needs a Mac. From the user's Linux machine, the
  most we can do is `nix eval` and fetch the DMG to get its hash.

Open questions:

- One attribute with a source/binary split, or a separate `orca-slicer-bin`?
- Is the DMG HFS+ (`undmg`) or APFS (`_7zz`)?
- How do version bumps refresh both the source hash and the DMG hash (update
  script / `nix-update` behaviour)?
- Is there a maintainer or contributor with a Mac who can confirm the app
  launches?
