# Performance baseline

This is a reproducible decode-and-navigation baseline, not a promise that all
machines will produce the same numbers. It is intentionally checked into the
project so regressions can be compared with a known run.

## 2026-10-15 — Apple M1 Pro / 16 GiB / macOS 27.0.1

Command:

```sh
./Scripts/validate-project.sh
```

The harness creates eight distinct hard-linked 5120 × 2880 JPEG paths. For
each 1 / 4 / 8 case it clears the bounded global LRU caches, loads and retains
one display-sized image per simulated document window, measures first-image
time, runs 20 adjacent-image bridge requests, and samples process RSS. The
numbers below are from `tools/StressHarness.swift` on the machine above.

| Concurrent 5K document equivalents | First image | Mean adjacent switch | Incremental RSS | Stage peak RSS |
| --- | ---: | ---: | ---: | ---: |
| 1 | 57 ms | 0.7 ms | 24.1 MiB | 148.4 MiB |
| 4 | 56 ms | 2.4 ms | 7.2 MiB | 155.5 MiB |
| 8 | 51 ms | 11.3 ms | 56.4 MiB | 211.6 MiB |

The complete harness used 371.4 MiB maximum RSS while also generating its
fixtures and exercising 1,800 catalogue entries, 320 previews, 120 adaptive
renders, and cache hot reads. Each visible LumaView window owns its navigation
and render task cancellation; the 24 MiB navigation-preview LRU and 120 MiB
render LRU remain global and bounded across windows.

## Automated real-window gate

`LumaViewLaunchTests.testRealOneFourAndEightWindowFiveKRenderingGate` is the
release gate for the user-visible multi-window path. It opens 1, 4, and 8
actual LumaView document windows from distinct 5120 × 2880 image paths, tiles
those test windows only, waits for every canvas to render at 5K, records
first-render timing and target-process RSS as XCTest attachments, and rejects a
run at or above 1.2 GiB RSS. It has deliberately broad failure limits—25 seconds
for first render and `30 + 12 × window count` seconds for all renders—so a
thermally constrained CI host is not treated as a product regression. Each
source must retain exactly one real AppKit window and accessibility scope, and
every canvas must preserve its own initial image and viewport state. The
separate Finder-style UI test covers `←` / `→` image navigation; its core
counterpart verifies that navigating one browser store never changes another
store's selection. A manual release check performs Next/Previous or rotation in
each visible window, because macOS XCTest cannot reliably target background
window toolbars after z-order changes. The UI gate is intentionally
separate from the synthetic baseline above: the latter helps isolate
decode/cache regressions; the UI gate proves the actual AppKit window lifecycle
and renderer path.

RSS results for the gate are environment-dependent and therefore kept with the
XCTest result bundle rather than presented as a misleading fixed release value.

## GUI RSS spot check

As a separate sanity check, the Debug application opened eight real, distinct
5K document paths at once. The UI gate uses physical file copies rather than
hard links, because some file-provider volumes coalesce hard-linked identities
during enumeration.
After each group of windows had settled, the LumaView process RSS was sampled
with `ps`. This is a process-wide number, so it includes SwiftUI/AppKit and
decode memory; it deliberately does not claim to be GPU memory.

| Real 5K windows | LumaView process RSS |
| --- | ---: |
| 1 | 117.5 MiB |
| 4 | 216.1 MiB |
| 8 | 309.0 MiB |

## GPU / display-memory metric

LumaView decodes through ImageIO/AppKit and creates no Metal textures itself.
Its displayed layers are allocated by Core Animation/WindowServer, so the CLI
harness cannot truthfully label RSS as “VRAM”. A three-second Metal System Trace
was captured against the one-window Debug process; this Xcode installation's
command-line exporter returns `Document Missing Template` for that trace, so it
does not expose a trustworthy per-process texture-allocation number. The GPU
baseline is therefore **not available as a numeric value**, rather than being
misreported as zero or as RSS. For a GUI regression run, open 1, 4, and 8 real
5K image windows in Instruments → **Metal System Trace** (or Core Animation)
and capture texture allocation and WindowServer memory beside the RSS numbers
above.
