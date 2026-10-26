# LumaView 1.3.0 verification

Version: **1.3.0 (17)**. Universal application targeting macOS 12.0 on both Intel and Apple Silicon.

The release includes PDF page navigation and window-local reading history, seven app languages, compact Settings with explicit default-format selection, batch file opening, and the product-review fixes documented in [Product fixes](PRODUCT-FIXES-20261026.md).

- The functional source passed **74 core XCTest cases** and **8 installer-script regression tests** before the release version change.
- Pixel checks cover four print rotations and the PDF overlay appearing, fading and staying pinned. Settings renders cover both panes, English/Chinese/Russian and light/dark appearance.
- Release builds come from the tagged commit. The DMG and its SHA-256 file are published together; the mounted application is checked for version, bundle ID, both architectures, minimum OS and language resources.
- The [GitHub Verify workflow](https://github.com/ixiehao/LumaView/actions/workflows/ci.yml) runs core and UI tests on the release source. Pixel screen-capture checks can be explicitly skipped when the runner has no recording permission; these are distinct from the offscreen core pixel tests.
- Website locale pages are checked before deployment; download links and public artifacts are verified after publication.

## Remaining device coverage

macOS 12 hardware, Intel hardware, native default-application consent, multiple displays and physical keyboard delivery are not covered by the development host or hosted CI. The minimum OS is verified in the build and Mach-O metadata; this does not claim a completed Monterey hardware acceptance run. No stress test or desktop takeover was used for this release preparation.

See the localized README for first-launch instructions. Historical build-14/15/16 packages and their verification records remain separate from this release.
