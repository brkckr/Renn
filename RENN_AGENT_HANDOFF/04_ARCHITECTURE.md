# Architecture and dependency injection

## A01 — Stack baseline

Swift 6, SwiftUI with Observation, iOS 17+ deployment baseline, SwiftData local metadata, AVFoundation capture/playback/read-write, Metal/MetalKit with Core Image rendering, Accelerate/vDSP audio analysis, PhotosUI/PhotoKit, RevenueCat Purchases, Firebase Analytics/Crashlytics, Swift Package Manager. Pin compatible stable versions at setup; this document does not claim a toolchain is installed.

Use **MVVM + unidirectional state flow + manual constructor injection**. Complex flows have explicit state machines; no application-wide MVI/TCA framework or DI library is required. One app target initially, with clear feature/domain/service boundaries. Extract packages when justified by dependency/test needs.

## A02 — Layers

| Layer | Responsibility / boundary |
|---|---|
| View | Render state, forward actions; local focus/animation/sheet presentation state is allowed |
| ViewModel | `@MainActor @Observable`, externally read-only screen state, actions and service orchestration; no frame processing or SDK ownership |
| Domain | Swift value types, recipes, snapshots, access rules; no SwiftUI, SwiftData or provider imports |
| Use case | Shared/multi-step business operation only where useful; no empty wrapper for every method |
| Services/repositories | Own I/O, SDKs and mutable subsystem state; return value snapshots |
| AppRouter | Selected tab, typed routes and presented flows; Home See all selects the existing Projects tab |

Data flow: `View action → ViewModel method → service/use case → result/state → View`. No direct camera, database, purchase or telemetry calls in View bodies. ViewModels request navigation through root-provided closures/routes rather than creating destination Views.

## A03 — Injection and lifetime

`RENNApp` has one composition root constructing live services and feature factories. Inject only dependencies needed by each initializer, never the entire container. Example conceptual signature: `ProjectsViewModel(projectStore: any ProjectStoring, onOpenProject: ...)`. Tests inject `InMemoryProjectStore` through the same boundary.

Use protocols at replaceable I/O seams: ProjectStoring, Purchasing, Exporting, TelemetryRecording, MediaPreparing. Do not abstract every helper value. No `.shared` in features or global service locator; SDK-required singleton access stays inside its adapter. Environment carries root-provided UI context such as theme/router, not hidden service lookup.

| Lifetime | Objects |
|---|---|
| App | ProjectStore, PurchaseService/access state, Telemetry, AppRouter, ExportCoordinator, shared GPU context/resources |
| Camera flow | CaptureController, SourceRecorder, transient live analysis; release mic/cameras when leaving |
| Screen | ViewModel and its observation tasks, stable across body re-evaluation |
| Export job | Immutable recipe/access snapshot, reader/writer/buffers/temp files; owned by coordinator, not a sheet |

Closing processing presentation does not implicitly destroy an active job. Explicit cancel has defined cleanup semantics. OS suspension is handled by the foreground-export interruption policy in 05.

## A04 — Ownership map

| Owner | Owns | Must not own |
|---|---|---|
| CaptureController | Permissions-derived capture graph, sample delivery, camera state/configuration | Paywall, Look catalog, analytics policy |
| SourceRecorder | Bounded clean encoding, common source timebase, finalization | Effects, entitlement queries |
| MediaPreparer | Transfer, track/color/orientation inspection, source normalization | Tier decisions or arbitrary cropping |
| BeatAnalyzer | Timestamped PCM features and immutable signal timeline | Microphone session, UI or GPU |
| RenderEngine | Frames + recipe + media time → pixels | Wall-clock randomness, purchases, capture |
| PreviewController | AVPlayer clock/frames, seeking, playback errors | Export/purchase success |
| ExportCoordinator | Policy validation/snapshot, job lifecycle, rendering/writer, output commit | Purchase transaction finishing |
| PhotosSaver | Add-only save request/result and duplicate-save guard | Re-rendering or gallery deletion |
| ProjectStore | SwiftData, source/output ownership, recipe revisions, reconciliation/migrations | Pro entitlement |
| PurchaseService | RevenueCat products/purchase/restore/customer state | Media processing |
| AccessPolicy | Pure effective output policy from entitlement/source | Independent StoreKit transaction flow |
| Telemetry | Allowlisted consented events | Feature gates/control flow |

## A05 — State and concurrency

Use associated-value enum states rather than incompatible booleans. Capture: idle/preparing/ready/countdown/recording/finalizing/failed. Export: validating/preparing/rendering/finalizing/savingToPhotos/completed/saveFailed/failed/cancelled/interrupted. Purchase: loading/ready/purchasing/pending/cancelled/failed/granted. Include job/project identity and preserved output in state where relevant.

MainActor owns UI only. Capture configuration and writer operations use explicit serialized executors/queues; storage has one actor-isolated writer. Never make unsafe media objects Sendable by annotation just to silence diagnostics. Pass immutable Sendable domain snapshots across boundaries, not SwiftData models/contexts or unowned mutable buffers.

Frame/PCM streams are bounded realtime pipelines, not Observation publishers or unbounded Tasks. Update UI progress at a modest throttled cadence. GPU textures/buffers remain alive until command completion. Parallel capture/export is outside the baseline; only one export job at a time.

Every async request carries identity/cancellation ownership. Stale results cannot replace a newer screen's state. Double taps cannot create two captures, exports or purchases. Cancel view-bound observation tasks on teardown; app-owned exports survive UI presentation changes until explicit cancel/interruption.

Screens observe one access-state source derived from PurchaseService. No independent `isPro` copies in storage/ViewModels. Snapshot access and recipe at export start; later entitlement updates affect new jobs.

## A06 — Project structure

```text
RENN/
  App/                 # entry, composition root, configuration, router
  Features/
    Home/ Looks/ Projects/ Camera/ Preview/ Export/
    Paywall/ Settings/ Onboarding/
  Domain/              # value models, recipe, policy, errors
  Services/
    Persistence/ Capture/ Rendering/ Audio/
    Purchases/ Telemetry/ Photos/
  DesignSystem/        # tokens, glass controls, typography, cassette layers
  Resources/           # catalog, licensed assets, fonts, strings
  Tests/               # pure rules, integration fixtures, UI/state tests
```

Dependency direction: presentation → domain/contracts; service adapters implement those contracts; composition root connects them. Business rules must not depend on provider DTOs.

## A07 — Testability and setup

Fake repositories/export/purchase services support UI previews and tests without real side effects. Test stale-result rejection, duplicate-start protection, cancel, rename/delete and save-retry without re-render. Pure access/recipe rules run without SDKs. Camera/GPU/Store integration still requires real-device/sandbox checks; fakes do not establish capability.

Use Swift Testing for suitable pure/integration tests and XCTest/XCUITest for UI/platform coverage. Use Instruments for memory, CPU, GPU and thermal investigation. Swift Package Manager dependencies and Package.resolved belong in version control. Keep private signing material/server credentials out of the repository. Client public configuration is not a secret authorization mechanism.

Firebase selection does not add Firestore/Auth/Storage. RevenueCat owns purchases; custom paywall UI remains SwiftUI. Initial third-party runtime SDKs are Firebase and RevenueCat; no required FFmpeg, Lottie/Rive, full 3D engine or state-management library.
