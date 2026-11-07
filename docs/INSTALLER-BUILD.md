# Reproducible installer presentation

Run the installer scripts on a Mac with Xcode and Python 3.10 or newer. Set
`PACKAGING_PYTHON` when the preferred Python executable is not on `PATH`.

## Architecture-specific installers

```sh
LUMAVIEW_ARCH=arm64 ./Scripts/package-dmg.sh
LUMAVIEW_ARCH=x86_64 ./Scripts/package-dmg.sh
```

These produce `LumaView-<version>-arm64.dmg` for Apple Silicon and
`LumaView-<version>-x86_64.dmg` for Intel, each with a SHA-256 file. Both build
from the same Swift sources. Only the selected machine-code slice is shipped;
there is no duplicate architecture-specific UI or image pipeline to maintain.
`LUMAVIEW_ARCH=universal` remains available and is the default for existing
automation. The notarized release entry point accepts the same selector.

`Scripts/build-common.sh` owns the architecture list, whole-module `-Osize`
Release settings, dead-code stripping and minimum-system checks. Both the
staged app and the app remounted from the DMG must contain exactly the requested
slices, declare macOS 12.0 in Info.plist and target 12.0 in every Mach-O slice.
The remounted executable must also match the staged executable byte for byte.
Size optimization is a build policy, not a measured latency improvement.

## Validation and future SDKs

```sh
# Run on the matching hardware; core mode does not drive the desktop UI.
LUMAVIEW_ARCH=arm64 LUMAVIEW_TEST_SCOPE=core ./Scripts/validate-project.sh
LUMAVIEW_ARCH=x86_64 ./Scripts/validate-project.sh

# With a newly installed supported Xcode selected via DEVELOPER_DIR:
LUMAVIEW_STRICT_WARNINGS=1 LUMAVIEW_TEST_SCOPE=core ./Scripts/validate-project.sh
```

The default test scope is `all` (core and UI). GitHub CI uses `macos-15` for
Apple Silicon and `macos-26-intel` for Intel, as listed in the
[GitHub runner documentation](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).
Each job executes native tests and builds its corresponding single-architecture
Release app. The validation script rejects translated shells and mismatched
test hosts; cross-compilation or Rosetta execution is not Intel hardware QA.

Complete Swift concurrency checking is enabled for every scripted build, while
retaining the project's Swift language version. `LUMAVIEW_STRICT_WARNINGS=1`
additionally treats compiler warnings as errors. It is an opt-in manual CI input for
auditing new toolchains. Keep the deployment target at macOS 12.0 and put new
system APIs behind availability checks. Future macOS 28 readiness requires
rerunning these checks when an official SDK exists and testing the resulting
app on the actual system; current builds do not establish macOS 28 compatibility.

## Output safety and Finder presentation

`OUTPUT_DIR` is resolved relative to the directory where the command is run.
An existing DMG or matching `.sha256` file is never replaced: use a new version
or choose a separate QA output directory. The layout builder verifies a staged
image before atomically publishing it and cleans its temporary artwork on failure.
Run `python3 Scripts/test-packaging.py` for offline output-safety regressions;
these use stub build tools and do not replace a real DMG mount/layout check.

LumaView deliberately uses `dmgbuild` 1.6.7 to write Finder metadata directly,
rather than depending on a manually opened Finder window. The visual design is
original LumaView artwork: its colour field, title, drag arrow, capability note
and all dimensions are authored in `Scripts/create-dmg-background.swift`.
`Scripts/dmg-settings.py` supplies the app and Applications positions, icon
view and background reference.

After the image is compressed, `Scripts/verify-dmg-layout.py` remounts it and
requires all of the following before the package can succeed:

- Finder icon view and the intended 980 × 620 window;
- 128 px icons at the saved LumaView and Applications positions;
- a valid image background alias, without the legacy `pBBk` bookmark;
- the `/Applications` link and the app bundle.

The required Python packages live only in `build/dmg-tools` and are ignored by
Git. They are packaging infrastructure, not application dependencies. For a
visual acceptance check, eject any older LumaView installer volume, open the
new DMG in a fresh Finder window, and confirm that the app is dragged from left
to right into Applications.
