# Implementation ledger

Evidence levels used below:
- **Written**: code exists, not compiled.
- **Compiled (Linux)**: compiled with Swift 6.2.4 on Linux (Docker `swift:6.2-noble`), strict concurrency.
- **Tested (Linux)**: automated tests executed and passed on Linux.
- **Compiled (iOS)** / **Tested (Simulator)**: via CI `macos-15` runner (see run links).
- **Device-tested**: on a physical iPhone. Nothing is device-tested yet.

## M00 Foundation (2026-09-27)

CI evidence: run [36351076994](https://github.com/brkckr/Renn/actions/runs/36351076994) on commit `a467226`.
- Linux `swift:6.2-noble`: 88 package tests passed.
- `macos-15` runner, Xcode 26.3 (17C529), Swift 6.2.4: `swift test` 88 passed on the macOS host;
  `xcodebuild build` for the iOS Simulator succeeded with no warnings from project sources (only the
  generic "AppIntents metadata extraction skipped" note); `xcodebuild test` on an iPhone 17 Pro simulator,
  iOS 26.2: RENNTests 7/7 passed (bundle ID, display name, en/tr localizations, usage descriptions,
  placeholder configuration, bundled catalog, runtime language switching, unconfigured purchases).
- Not yet run: iOS 17 simulator or device (deployment target 17.0 is compiled against, not executed),
  UI/visual tests, and anything on a physical iPhone.

| Requirement | Implementation | Evidence |
|---|---|---|
| P01/A01/C01 identity | `Config/RENN.shared.xcconfig` bundle ID `tzlapp.studio.renn`, display name RENN; `AppIdentity`; `RENNTests/AppConfigurationTests.swift` | Tested (Linux) + tested (Simulator, iOS 26.2) |
| A01 toolchain / deployment | Swift 6 mode, iOS 17.0, iPhone portrait, Xcode 16+ project format; ADR 0001 | Compiled (iOS, Xcode 26.3) |
| A02/A03 MVVM + constructor DI | `RENN/App/AppComposition.swift` composition root; ViewModels in `RENNFeatures` receive only needed protocols/closures; no `.shared`/locator | ViewModels tested (Linux) with fakes |
| A06 structure | App: `App/ Features/ Services/ DesignSystem/ Resources/`; package `RENNDomain / RENNFeatures / RENNFakes` (ADR 0001 deviation) | Compiled (Linux) |
| P02 navigation | `MainNavigationState`, `AppRouter`, `GlassNavigationBar` (Home-only +, menu rows, one destination per choice, See all → Projects, Dual-Cam unsupported explanation) | Rules/router tested (Linux); UI written |
| P10 onboarding | `OnboardingPager`, `OnboardingViewModel`, `OnboardingView` (4 pages, Skip/Next/Get started, persisted once, no name/permission/paywall) | VM tested (Linux); UI written |
| P08 access rules | `AccessPolicy` (Free 30 s / 720p fit / ≤30 FPS rational / watermark; Pro supported dims and ≤60 FPS, no duration cap) | Tested (Linux) |
| P04 Looks | `LookCatalog` validation (12-Look launch gate), `LookPreferences` last-four-distinct, favorites, inspection VM | Tested (Linux) |
| C03 purchases | `Purchasing` contract, `UnconfiguredPurchaseService`, `PaywallViewModel` (annual default, last selection wins, only `.granted` unlocks) | VM tested (Linux) with fakes; no Store/RevenueCat |
| C05 telemetry | Allowlisted `TelemetryEvent`, `ConsentGatedTelemetry` (default off), discarding sink | Tested (Linux) |
| C07 localization | `Localizable.xcstrings` + `InfoPlist.xcstrings` (en, tr), `LocalizationController`, `scripts/check_localization.py` | Script passes (111 keys, en+tr); runtime tr/en switching tested (Simulator) |
| Test targets | `Packages/RENNCore/Tests/*` (Swift Testing), `RENNTests` | 88 package tests pass on Linux, 3 consecutive runs |

Placeholders introduced (all labelled): development Look catalog (1 diagnostic fixture), SF Symbol
icons, vector splash/player/case shells, onboarding scene placeholders, in-memory project and
Look-preference stores (`M00-TEMPORARY`, replaced in M01), placeholder flows for camera, import,
Dual-Cam and preview (M02/M04). See `docs/DEVELOPMENT_ASSETS.md`.

Not done in M00 (by plan): SwiftData persistence (M01), any media capture/render/export (M02+),
Firebase/RevenueCat SDKs and `Package.resolved` (M06), final motion (M07).

## M01 Durable projects (2026-09-27)

| Requirement | Implementation | Evidence |
|---|---|---|
| V07 data model | `ProjectRecord`, `Recipe`, `IndicatorSettings`, `DualCameraLayout`, `SourceReference`, `OwnedRelativePath` (RENNDomain); `RENNSchemaV1` (`ProjectEntity`, `LookPreferencesEntity`), `RENNMigrationPlan`, CloudKit off | Domain tested (Linux); SwiftData pending CI |
| V07 layout | `Application Support/RENN/Projects/<UUID>/sources|outputs`, metadata at `Application Support/RENN/Metadata/RENN.store`, per-launch `tmp/RENN/Staging|Jobs/<launch>` | Tested (Linux) with real directories |
| V08 commit / recovery | `ProjectLibrary`: `.preparing` → adopt → verify → `.ready`; reconciliation completes/interrupts, finishes deletions, flags missing sources, removes orphans only when metadata is readable | 14 crash-window and boundary tests (Linux) |
| V08 delete / leases / no external deletion | Delete refuses while leased; removes only the project directory; external files and other projects untouched; traversal paths rejected on creation and decode | Tested (Linux) |
| P03 rename / delete UI | `ProjectsViewModel.rename/requestDelete/confirmDelete`; Projects case action menu (and VoiceOver actions), rename sheet with validation, destructive confirmation, in-use error, status labels | VM tested (Linux); UI written, pending CI compile |
| P04 favorites / recents persistence | `SwiftDataLookPreferencesStore` | App test written, pending CI simulator |
| Revisions | `updateRecipe(expectedRevision:)` rejects stale and invalid recipes; concurrent writers commit once | Tested (Linux) |

Package tests: 121 passing on Linux (Swift 6.2.4), five consecutive runs stable for storage tests.
Not in M01 by plan: export jobs/outputs records (M02), poster cache (M05), debounced recipe
autosave from preview (M02/M05). Projects can only be created once M02's capture/import exists.

## M02 Media proof (2026-09-27)

Implemented (package logic tested on Linux; app code compiled by CI with Xcode 26.3):
- Import: system picker (selected-media access only) → staging → `AVMediaInspector` (display size after
  transform, rational cadence from minFrameDuration, HDR detection, audio) → Free 30 s gate → project.
- Capture: `AVCaptureController`/`CaptureGraph` (1080p30 portrait, front mirrored, session/data queues,
  interruption events) and `SourceRecorder` (clean AVAssetWriter source, shared origin, Free limit refusal,
  converging stop). `CaptureFlowViewModel` with contextual permissions, silent capture, pre-record switch,
  Off/3/10 s timer (countdown not recorded, not counted), take never discarded.
- Preview: Metal preview through the shared `RenderEngine`, scrubber, before/after, mute, loop, intensity.
- Export: `ExportCoordinator` (one job, summary, cancel before commit, render ≠ Photos save, save-only retry,
  lease), `ExportWorker` (reader → Core Image → writer, per-track media queues, cadence limiter,
  AAC re-encode, H.264/HEVC), `OutputValidator`, `PhotoLibrarySaver` (add-only).
- Decisions: ADR 0003. Device checklist: `docs/DEVICE_TEST_PLAN_M02.md`.

Bugs found by the simulator integration tests and fixed:
- Fixture generator wrote all video before audio (AVAssetWriter interleaving stall) → interleaved.
- **ExportWorker deadlock** (also a device bug): both reader outputs were drained on one thread; with the
  writer waiting to interleave, video decoding blocked forever. Fixed with per-track
  `requestMediaDataWhenReady` queues (commit f16b891).

Evidence status:
- Simulator media integration: **passed** on CI run 36357990546 (commit 943f7c6, iPhone
  simulator): import inspection, Free 720p30 with audio and same duration, muted export without audio,
  Pro 1080×1920 keeping 60 FPS, deterministic render, date indicator drawn, processed poster cached; Look
  LUT tests and SwiftData persistence also passed. Fixtures are short (CI simulators render on the CPU at
  about a second per 1080×1920 frame), so these prove correctness, not speed.
- Physical device: nothing run yet (camera, HDR route, A/V sync, performance, Photos permission flow).

## M03 Beat and render core: in progress (2026-09-27)

- `BeatAnalyzer` v1 in pure Swift per 05 V05 (tested on Linux, chunking-invariant, finite/clamped outputs,
  silence and steady-tone behavior). One added constant: 5% minimum relative flux rise.
- `BeatModulation` bounded (+0.06 brightness, 1.5% zoom); intensity 0 / mute / no audio = off.
- `AVBeatTimelineProvider`: decodes the source's own audio, cache keyed by fingerprint + constants.
- `IndicatorLayout` resolver (all 16 combinations, watermark and four PiP corners) and `IndicatorRenderer`;
  effects → OSD → watermark order; staged Indicators panel with Gregorian date-only stamp.
- Posters: `PosterPolicy` + `PosterProvider` (project's own processed frame, cached per revision).
- Catalog-driven Look graph (render version 1): each Look declares an optional bundled `.cube` LUT and
  bounded parameters (lutMix, saturation, contrast, warmth, vignette, grain). `Recipe.initial`
  snapshots the parameters; intensity scales them linearly, 0 is a passthrough. `CubeLUT` parser
  (validated, Linux-tested) + `LookLUTStore` (bundle loader, 0...1 domain, CIColorCubeWithColorSpace in
  sRGB). The hard-coded diagnostic grade is gone; the DEV Look is now one parameter set plus the
  generated `dev_warm.cube` fixture (`scripts/generate_dev_lut.py`).
- Remaining for M03: scanline/chroma/tracking artifact stages (shader work) and final per-Look tuning,
  both waiting on the owner's twelve Look briefs and assets (M08).

## M04 Dual-Cam: in progress (2026-09-27)

- Domain (Linux-tested): `DualInsetLayout` (rounded PiP, 30% width, four pre-record corners, watermark
  reservation), `DualSourceTiming` (common playable interval + per-source offsets on the shared clock),
  exact `RationalTime` +/- (bounded rounding when the common timescale exceeds Int32),
  `DualFormatSelection` (largest multi-cam format up to 1080p30 per camera), `ExportPlan.dual` with a
  single declared shared-audio owner; missing/duplicate/invalid inputs are refused, never exported as one
  camera.
- Export contract now takes `ExportSourceFiles` (URL per source role). `RenderEngine` composes main +
  inset (normalize → same Look/Beat per source → rounded inset → OSD → watermark). `ExportWorker` drives
  video from the rear file and reads the front file through a bounded frame cursor; both readers cover
  only the common interval; swap events are on the composition timeline.
- Simulator test added: two synthesized sources (red rear with audio, green front 0.1 s later), swap at
  0.5 s; asserts duration 0.9 s, one audio track and main/inset colours before and after the swap.
- Evidence: CI run 36358943585 (commit f7fefe2) passed all 24 app tests on the iPhone simulator,
  including `dualCamExportComposesBothSourcesAndReplaysTheSwap` and
  `dualPreviewCompositionPacksBothSourcesOnOneClock`; 238 package tests pass on Linux and macOS.
  Implemented since: `DualCaptureFlowViewModel` (Linux-tested with a fake), `AVDualCaptureController`
  (AVCaptureMultiCamSession, explicit connections, one mic into the rear writer, hardware-cost check;
  compiled only, device-only), `DualCameraView`, composite posters, and Dual-Cam project preview on one
  composition clock. Device plan: `docs/DEVICE_TEST_PLAN_M04.md`.
- `DeviceCaptureCapabilities` probes the real format pair. Remaining: device evidence on supported and
  unsupported hardware (nothing Dual-Cam has run on a device yet).

## M05 App flows: in progress (2026-09-27)

- Preview Look selector (02 D05 S10): catalog grid with yellow outline + check, one intensity slider,
  staged Apply/Cancel (swipe-down = Cancel); the preview renders the staged choice. `Recipe.switchingLook`
  loads the new Look's version, parameter snapshot and default intensity and keeps Beat, mute,
  indicators, seed and Dual-Cam layout; Apply writes one revision (Linux-tested).
- Camera (02 D06): Look / Beat / Indicators before recording through `RecipeDraftEditor`, locked from
  countdown until the take is finalized; the draft seeds the project for single and Dual-Cam capture.
- Look history: already recorded on successful creation and successful export only (tested).
- Settings storage (02 D09): space used by projects and by the regenerable cache, Clear cache (posters
  only; projects are removed only by deleting projects). VM tested on Linux.
- Export result cassette shows the project's own processed cover and its deterministic case variant.

## M07 Visual and motion: in progress (2026-09-27)

Motion timelines are pure functions of elapsed time in RENNDomain (frame-rate independent,
Linux-tested); SwiftUI drives them with `TimelineView(.animation)` and one identified transition
per motion so stale completions never act.
- Onboarding curved wipe (03 M02): leading edge covers by 380 ms (incl. corners), swap while covered,
  trailing edge reveals by 760 ms; copy fades per spec; Next serialized; inactivity settles; Reduce
  Motion keeps the 120 ms dissolve. Deviation: the mask draws above the navigation row (controls are
  disabled during the 760 ms) instead of below it.
- VHS insertion (03 M05): lift / curved travel / slide behind the front plate / present once at 700 ms;
  real occlusion by re-drawing the player's upper part above the travelling case; cancel on tab change,
  background, inactivity. Player art is vector development art (owner layers pending, 08 I02).
- Paywall selection stage (03 M04): passive pose → selected pose in 320 ms, halo 0.12 → 0.28 → 0.20,
  billing data independent of motion. Stage objects are RENN's own simple cassette shapes, pending review.
- Export completion (03 M06): 6 pt / opacity settle over 240 ms and one light haptic, once per output.
- Already present since M00: splash ribbons (03 M01) and the glass bar morph (03 M03).
- Not done: visual comparison against the reference videos, 60/120 Hz device recordings, final fonts and
  artwork (owner inputs).

