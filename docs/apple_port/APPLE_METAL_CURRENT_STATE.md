# Apple Metal Current State

Snapshot date: 2026-09-29 (upstream sync). The 2026-09-04 snapshot is kept
below as history.

## 2026-09-29 upstream sync

| Repository | Branch | Upstream merged |
|---|---|---|
| Hesiod | `macos/upstream-sync-2026-09-29` (from `macos/metal-on-dev`) | `upstream/dev` `47754242` (243 commits) |
| HighMap (submodule) | `feature/apple-metal-backend` | `upstream/dev` `7f439892f` (103 commits), contains upstream Hesiod's pin `89f329403` |

What changed for macOS:

* HighMap's Metal thermal kernels now follow upstream's new border rule.
  New Metal routes: `smooth_cpulse`, `local_max`/`local_min` (DISK, SQUARE,
  OCTAGON, and so all morphology), `morphological_gradient` and `noise_fbm`.
  The synchronous wrappers reuse their buffers. Details are in HighMap's
  `docs/apple_port/UPSTREAM_SYNC_2026-09-29.md`.
* Upstream removed the `MorphologicalGradient` node; legacy graphs are
  converted to `MorphologicalOperators`. That node no longer has a resident
  path, but its min/max passes now run natively on Metal through HighMap.
* The Metal graph code was ported to the current GNode API (`gnode::PortType`,
  typed `get_value_ref`) and to upstream's const input pointers.
* The Meta `<sstream>` workaround is now attached to the `meta` target as a
  PUBLIC option, so it reaches upstream's renamed `hesiod_core` target.
* `Thermal` still only requests a deposition map when that port is
  connected, which keeps it on the Metal path.

Validation (Apple M3, 8 GB, Release, `--phase4-benchmark` on
`Hesiod/data/examples/SpectralEqualizer.hsd`, tiling 1×1):

| Size | Resident nodes | Uploads / readbacks | Resident wall | Host fallback wall | Parity (max abs) |
|---|---:|---:|---:|---:|---|
| 512² | 4 | 0 / 1 | 14.7 ms | (includes first-run init) | 0.00902 PASS |
| 1024² | 4 | 0 / 1 | 93.2 ms | 145.0 ms | 0.00459 PASS |
| 2048² | 4 | 0 / 1 | 677.1 ms | 852.3 ms | 0.00233 PASS |

The upstream `bench_local_min_max.hsd` and `bench_coherent_noise.hsd` graphs
and 19 example graphs that use the routed node types (CoherentNoise,
MorphologicalOperators, legacy MorphologicalGradient, SmoothCpulse, Thermal,
SelectSlope, ExpandShrink, Jagged, RecastCliff, …) run in `--batch` mode at
512² without errors.

## Full macOS validation (later on 2026-09-29)

Upstream `dev` was re-synced (`fed61165`, TWI node). Everything below ran
against the final build on the Apple M3 (8 GB, macOS 27.2).

* **Hesiod tests:** 4/4 ctest suites pass (unit build/run, graph editor,
  autosave). 102 of 119 hsd-tooling pytest tests pass; the other 17 still use
  nodes upstream removed (`NoiseFbm`, `NoiseIq`) or an old docs layout.
* **All 258 example graphs, headless at their own resolution:** 255 run
  cleanly. The other 3 (`CloudFromCsv`, `PathFromCsv`, `ImportHeightmap`)
  point at input files that only exist on the upstream author's machine. There
  were no crashes or hangs (earlier: 8 crashes and 1 hang, from the HighMap
  tile-storage race).
* **Metal vs OpenCL A/B:** `--phase4-benchmark` with `HESIOD_PHASE4_DUMP_DIR`,
  once with Metal and once with `HIGHMAP_DISABLE_METAL=1`, 1106 node outputs;
  see HighMap `UPSTREAM_SYNC_2026-09-29.md`. This found that resident runs
  left intermediate node outputs zero on the host, which would have shown
  blank previews/viewers in the GUI. Fixed: `flush()` now writes every
  resident output back.
* **Export chain:** a 16-bit PNG, 8-bit PNG, 32-bit EXR and 16-bit RAW
  heightmap, a 16-bit normal map, a 16-bit RGBA texture and a glTF asset
  (1M vertices + texture + normal map) were exported from one graph. All are
  valid; the 16-bit outputs use 62,678 distinct levels and contain no NaN.
* **SpectralEqualizer resident chain:** parity passes at 512²/1024², untiled
  and 2×2. At 1024² it takes 115 ms, with 0 uploads and 4 readbacks (all
  node outputs are now on the host).
* **Install:** `scripts/macos/install_macos_app.sh` builds
  `~/Applications/Hesiod.app`. The app starts from Finder with every resource
  loaded from the bundle, and logs to `~/Library/Logs/Hesiod/hesiod.log`.

# Snapshot 2026-09-04 (history)

## Repository state

| Repository | Personal remote | Branch | Implementation HEAD at snapshot | Upstream base |
|---|---|---|---|---|
| Hesiod | `Leonhardmaster2/Hesiod` | `feature/apple-metal-integration` | `ac11110a7ea25c3364b4d1f7f9525af8456c6aca` before this documentation refresh | `b44dfe8203ab827c9f76b84dacd18a4f25922d19` |
| HighMap | `Leonhardmaster2/HighMap` | `feature/apple-metal-backend` | `d335ec051f7c7d5cb241e80baa5e4139cf4361de` | `aa57b8e7638f68bafd2b9fc595c682ec9204cd4e` |

Both feature histories are linear from the actual fetched upstream `dev` bases
and contain zero merge commits in the feature-only range. The Hesiod submodule
is pinned to the published personal HighMap feature revision
`d335ec051f7c7d5cb241e80baa5e4139cf4361de`. Existing local build directories,
generated images, logs, and other untracked artifacts were preserved. The
pre-sync states are also retained on personal backup branches.

## What has been done

### HighMap backend

* Added a capability-gated native Metal backend with a portable no-Metal stub.
* Added explicit GPU-resident `DeviceArray` and ordered `DeviceSession`
  ownership/synchronization.
* Added resident noise, spectral, thermal, blend, Gabor, and supporting
  operations across the previous phases.
* Added the Phase 7 `morphological_gradient` Metal kernel and synchronous
  wrapper.
* Added Phase 8 focused DeviceArray tests (7 tests) for residency, hybrid
  boundaries, fallback exception, repeated execution, and cache-handoff
  discipline.

### Hesiod integration

* Phases 5–7 established the four-node `SpectralEqualizer.hsd` resident chain
  (CoherentNoise FBM → SpectralEqualizer → Thermal/Linear → Blend ADD) with
  one terminal readback.
* Phase 7 added explicit `MorphologicalGradient` eligibility and lifecycle
  guards, plus `texturing_101.hsd` Graph D coverage.
* Phase 8 tightens hybrid execution: the two remaining host-only fallbacks
  now explicitly materialize (`prepare_host_node`) before their CPU/OpenCL
  path reads a resident input, and `SpectralEqualizer` reports
  `multi-tile halo fallback` rather than a silent host mismatch.

## Validation summary (2026-09-04, Apple M3, Release)

* HighMap Metal-focused suite: 39/39 passed (32 MetalBackend + 7 MetalPhase8).
* HighMap full suite: 433 passed, 2 intentional portability skips, and 1
  pre-existing `PathSplines.PreservePathShape` failure.
* HighMap no-Metal full suite: 385 passed, 50 expected backend skips, and the
  same pre-existing spline failure. The no-Metal focused Metal/Phase 8 tests
  skip cleanly because no Metal device is available.
* HighMap isolated 1024² resident Chain A: 1.477 ms, 0 uploads, 1 readback,
  1 command buffer, and 1 final synchronization.
* HighMap isolated 1024² hydraulic VPipes: 172.811 ms, with the expected
  explicit hydraulic pass allocations and transfer accounting.
* Hesiod `SpectralEqualizer.hsd` parity `1e-2` PASS at 512²/1024²/2048²/4096².
  The current resident legs report 4 resident nodes, 0 uploads, and 1 terminal
  readback at every tested size.
* Current resident wall times: 19.727 ms (512²), 99.458 ms (1024²),
  747.170 ms (2048²), and 13,058.750 ms (4096²). The 4096² peak resident
  allocation is 1,073,741,836 bytes.
* Current 1024² parity maxima are `0.00459123` for Metal and `0.00065053`
  for the no-Metal reference run; both pass.

The historical Phase 5 and Phase 8 benchmark tables retain their original
measurement dates and are not silently replaced by this post-sync smoke
qualification.

## Current limitations and next work

The `SpectralEqualizer` global-frequency/blurs remain single-logical-tile only;
tiled graphs fall back with seam checks. The persistent cache is opt-in. The
OpenCL settings API is explicitly guarded so the no-Metal/optional-OpenCL
build remains compilable. See `PHASE8_REVIEW.md` for the full benchmark and
transfer table, and for the suggested next steps.
