# LumaView release procedure

LumaView supports **Intel and Apple Silicon Macs** on macOS 13+. Every release script requires both `arm64` and `x86_64` slices.

There are two deliberately distinct paths:

- **Transparent public preview (current v1.2.2):** the ShotMap pattern—an
  ad-hoc-signed DMG plus its SHA-256 file, with the Release and README clearly
  saying that it is not Apple-notarized and explaining the one-time Gatekeeper
  recovery action. This is useful for early open-source testing, but must never
  be presented as a notarized stable release.
- **Formal stable release:** the MP4Flow pattern—re-sign the exact final app
  with Developer ID, notarize the final DMG, staple its ticket, validate
  Gatekeeper, and publish its checksum.

## Internal QA package

```sh
./Scripts/package-dmg.sh
```

This produces `dist/LumaView-<version>-universal.dmg` and its SHA-256 file. The
installer has an original LumaView background, clear drag-to-install guidance,
and only `LumaView.app` plus an `Applications` shortcut. The script writes its
Finder presentation deterministically (window, icon locations and image alias),
then validates it after mounting the compressed DMG. It also validates the app
signature, checksum and architecture. Build-only Python dependencies are held
in `build/dmg-tools` and are never included in the app. This package will not
satisfy Gatekeeper on a clean Mac by itself. It can stay internal, or may be
published only through the transparent preview procedure below.

See [INSTALLER-BUILD.md](INSTALLER-BUILD.md) for the installer-artwork and
Finder-layout guarantees.

## Transparent public preview (ShotMap-compatible)

Use this only when the project owner explicitly chooses a public preview before
Developer ID/notarization is available. Run the full test and packaging gate
from a clean `main` checkout, then upload exactly these two generated files to
the matching GitHub Release:

- `LumaView-<version>-universal.dmg`
- `LumaView-<version>-universal.dmg.sha256`

The release title and bilingual notes must state all of the following:

1. macOS 13+ on both **Intel and Apple Silicon** Macs; the package contains `x86_64` and `arm64` slices.
2. The DMG is ad-hoc signed and **not Apple-notarized**.
3. If macOS cannot verify the developer: copy the app to Applications,
   Control-click it, select **Open**, then select **Open** once more. Never
   ask users to disable system-wide security.
4. The SHA-256 file is attached and matches the DMG. The source commit and
   annotated `vX.Y.Z` tag identify the build.

Keep existing stable assets available. Do not replace a released preview DMG
without a clearly recorded packaging correction; when formal signing becomes
available, publish a new version rather than rewriting the old artifact.

## Public notarized release

Prerequisites:

- Apple Developer Program membership and a `Developer ID Application` certificate in Keychain.
- An App Store Connect API-key Keychain profile configured for `xcrun notarytool`.
- No certificate, private key, API key, app-specific password, or profile committed to this repository.

```sh
export DEVELOPER_ID_APPLICATION='Developer ID Application: Your Name (TEAMID)'
export NOTARYTOOL_PROFILE='lumaview-notary'
./Scripts/release-notarized-dmg.sh
```

The script signs with hardened runtime and a secure timestamp, submits the exact final DMG, staples it after acceptance, runs `spctl` Gatekeeper assessment, re-mounts the final image, verifies the contained app and Applications shortcut, and writes a matching SHA-256 file. Do not rebuild or modify the bundle after submission.

It preflights the exact Developer ID identity and the named Keychain
`notarytool` profile before building anything. A missing identity or profile is
a release blocker; the script never falls back to an ad-hoc signature.

Before publishing, test the resulting DMG on clean Intel and Apple Silicon Macs with Gatekeeper enabled and retain the notarization submission ID and validation record privately.

## Auditable source identity

The repository must have an initial reviewable commit before any public build.
For every public release, build from a clean checkout of one commit and attach
an annotated tag to that exact commit; do not create the commit or tag from a
packaging script.

```sh
git status --short                 # must be empty before the release build
git log --oneline -1               # record the source commit SHA
git tag -a vX.Y.Z -m 'LumaView X.Y.Z'
git show --no-patch --format=fuller vX.Y.Z
git verify-tag vX.Y.Z              # when the release team uses signed tags
```

Record the source commit SHA, annotated-tag object ID, DMG SHA-256, notarization
submission ID, and Gatekeeper assessment alongside the release notes. This is a
procedure for an authorized release operator; it intentionally does not create
a commit, tag, signing identity, or notarization credential on their behalf.

## Update feed

LumaView follows ShotTessera's lightweight update model: it reads only the
latest public GitHub release metadata at most once every 12 hours, including
across app launches. Before the first public release, create the repository at the configured
slug or update `LumaViewProjectLinks.repositorySlug` in
`LumaView/UpdateChecker.swift`. The expected release link is strictly limited
to that repository's HTTPS `/releases/` path, and draft or prerelease tags are
ignored. The release tag must be `vX.Y.Z` and newer than
`MARKETING_VERSION`; do not publish a tag that violates this relation.
