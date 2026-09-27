# ADR 0001: Project foundation (M00)

Status: accepted, pending first Mac build confirmation. Date: 2026-09-27.

## Context

The contract (04 A01/A06) specifies Swift 6, SwiftUI with Observation, MVVM, manual constructor
injection, iOS 17+, SPM and one app target with clear feature/domain/service boundaries,
extracting packages "when justified by dependency/test needs". The first implementation
environment has no Mac: only a Linux container with a Swift 6.2.4 toolchain (Docker).

## Decisions

1. **Toolchain / deployment.** Swift language mode 6 (strict concurrency), iOS 17.0 deployment
   target, iPhone only, portrait only. Minimum Xcode 16 because the project uses synchronized
   folder groups (`objectVersion 77`), which keeps the hand-authored project file small and
   removes per-file project edits. The exact Xcode/SDK version is recorded in the ledger at the
   first Mac or CI build.

2. **Local package `Packages/RENNCore` (deviation from the A06 folder layout, same boundaries).**
   - `RENNDomain`: value models, product rules (access/output policy, rational time, names,
     date stamp, recent Looks, Beat mute rule, navigation rules) and service contracts. No
     SwiftUI/SwiftData/AVFoundation/SDK imports, enforced by the compiler.
   - `RENNFeatures`: `@MainActor @Observable` ViewModels and `AppRouter`. They depend only on
     `RENNDomain` and Observation, so their behavior tests run without a simulator.
   - `RENNFakes`: in-memory fakes. Separate from production adapters by module.
   Justification: the test need in A01. It lets the pure rules and presentation logic compile and
   be tested on any Swift 6 toolchain, including Linux CI and this Mac-less environment. SwiftUI
   views, the composition root and platform adapters stay in the app target as A06 describes.

3. **Composition root.** `AppComposition` builds app-lifetime services once and exposes
   ViewModel factories. Each ViewModel receives only the protocols and navigation closures it
   uses. No global service locator or `.shared` feature access. `AppRouter` owns the selected
   tab, typed flows and launch phase; ViewModels request navigation through injected closures.

4. **Unconfigured providers.** Until the owner supplies configuration:
   - Purchases use `UnconfiguredPurchaseService` (production-safe: never grants Pro, products
     unavailable, restore reports "not configured"). The fake purchase service is only used in
     Debug with an explicit launch argument, and its prices are labelled `DEV`.
   - Telemetry goes through `ConsentGatedTelemetry` into a discarding sink; consent defaults off.
   - Projects and Look preferences used in-memory fakes in M00; M01 replaced them with the
     SwiftData-backed stores (see ADR 0002).

5. **Third-party SDKs are not added in M00.** Firebase and RevenueCat packages (and their
   `Package.resolved`) are added in M06, when their configuration exists and resolution can be
   verified on a Mac. Their seams (`Purchasing`, `TelemetrySink`) are defined now. No SPM lock
   file exists yet because the only package dependency is local.

6. **Localization.** String Catalogs (`Localizable.xcstrings`, `InfoPlist.xcstrings`) with English
   source and Turkish. Semantic keys (`tab.home`). The in-app language choice sets the SwiftUI
   `locale` environment and a language-specific bundle for plain strings, and mirrors explicit
   choices to `AppleLanguages` so permission prompts follow after relaunch. Store prices are never
   localized by the app. `scripts/check_localization.py` enforces completeness.

7. **Fonts.** Brand fonts are not delivered. `Font.custom` falls back silently, so
   `FontRegistry` registers any bundled `.ttf/.otf` at launch and reports missing faces in
   Settings > Developer (Debug) and in `docs/DEVELOPMENT_ASSETS.md`.

## Consequences

- Package types used by the app are `public`.
- The app test target does not link the package products; it uses them through the host app
  (avoids duplicate static copies of the modules).
- If the Mac build shows that the hand-authored project needs adjustment, fix the project file
  and record the change here.
