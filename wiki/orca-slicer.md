---
summary: >-
  Why `orca-slicer` is Linux-only in nixpkgs: the restriction was inherited
  from `bambu-studio` without a stated reason, and the source build depends
  on GTK/Linux. Upstream ships a universal macOS DMG that could be
  repackaged.
sources:
  - pkgs/by-name/or/orca-slicer/package.nix
  - git commit 98a73e1caf11 (orca-slicer: init at 1.8.1, #275638)
  - Homebrew cask `orcaslicer` (pasted by the user, 2026-10-20)
tags:
  - package
  - orca-slicer
  - darwin
---

# orca-slicer

OrcaSlicer is a G-code generator for 3D printers. In nixpkgs it is built
from source with `clangStdenv`, because GCC runs out of memory on this code
base.[^pkg]

## Why it is Linux-only

**History.** The package was added in `98a73e1caf11` (Dec 2023, #275638) as
an override of `bambu-studio`, which already had `platforms = platforms.linux`.
orca-slicer copied that line, and nobody gave a reason.[^init] Upstream
itself supports macOS and Windows.

**The source build is Linux-specific:**[^pkg]

- wxWidgets is built on GTK (`withWebKit`, `withEGL`, `--enable-secretstore`),
  together with `gtk3`, `webkitgtk_4_1`, `libx11` and `SLIC3R_GTK=3`.
  On macOS, OrcaSlicer uses Cocoa wxWidgets and the system WebKit instead.
- `CMAKE_EXE_LINKER_FLAGS = -Wl,--no-as-needed` is a GNU-style linker flag
  that Apple `ld64` rejects.
- `SLIC3R_FHS=true`, an `LD_LIBRARY_PATH` wrapper and `/run/opengl-driver`
  paths (the `withNvidiaGLWorkaround` option) are Linux/NixOS conventions.
- `dbus`, gstreamer and `binutils` are listed unconditionally. Only systemd
  is optional (`withSystemd`).

So adding Darwin is real porting work, not just a `meta.platforms` change.

## Upstream macOS binary

The Homebrew cask installs `OrcaSlicer_Mac_universal_V${version}.dmg` from
the GitHub release, which contains `OrcaSlicer.app`. At 2.4.2 the same tag is
packaged in nixpkgs.[^cask] The bundle id is `com.softfever3d.orca-slicer`.

That makes orca-slicer a candidate for [[darwin-binary-repackaging]]:
universal, so `platforms = lib.platforms.darwin`. Whether the DMG is HFS+
(`undmg`) or APFS (`_7zz`) has not been checked yet.

[^pkg]: [pkgs/by-name/or/orca-slicer/package.nix](../../pkgs/by-name/or/orca-slicer/package.nix) (at `aa016d6dc7bc`)
[^init]: `git show 98a73e1caf11`
[^cask]: Homebrew cask `orcaslicer`, version 2.4.2, as pasted in session on 2026-10-20 (not stored under `sources/`)
