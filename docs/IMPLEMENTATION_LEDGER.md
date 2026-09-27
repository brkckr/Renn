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
