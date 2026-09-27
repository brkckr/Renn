# RENN

Native iPhone retro-video camera and processor. Bundle identifier `tzlapp.studio.renn`.

The implementation contract is in [`RENN_AGENT_HANDOFF/`](RENN_AGENT_HANDOFF/README.md) and is the
source of truth for scope, Free/Pro rules, design, architecture and milestones.
Progress, checks and open items are tracked in [`docs/IMPLEMENTATION_LEDGER.md`](docs/IMPLEMENTATION_LEDGER.md).

## Requirements

- macOS with Xcode 16 or newer (Swift 6 language mode, iOS 17 deployment target).
  The project uses Xcode 16 synchronized folders (`objectVersion 77`); older Xcode cannot open it.
- A physical iPhone for camera, Dual-Cam, Metal, audio sync and export validation.
  The Simulator cannot establish those capabilities.

## Layout

```text
RENN.xcodeproj           App project (one app target + RENNTests)
RENN/                    App target: SwiftUI views, composition root, platform adapters, resources
  App/                   Entry point, composition root, configuration, root view
  Features/              SwiftUI screens per feature
  Services/              Platform adapters (preferences, purchases, capture, localization, fonts)
  DesignSystem/          Tokens, glass surfaces, typography, placeholders
  Resources/             Asset catalog, String Catalogs (en, tr), Look catalog manifest
RENNTests/               App-bundle tests (bundle identity, localization, configuration)
Packages/RENNCore/       Swift package, platform independent
  RENNDomain             Value models, product rules, service contracts
  RENNFeatures           @MainActor @Observable ViewModels and the app router
  RENNFakes              In-memory fakes for tests, previews and development only
Config/                  xcconfig files and Info.plist additions
scripts/                 Repository checks (String Catalog completeness)
docs/                    Ledger, architecture decisions, development-asset report
```

## Build and test

```sh
# Pure layers: runs on macOS or Linux with Swift 6
swift test --package-path Packages/RENNCore

# Localization completeness (en + tr)
python3 scripts/check_localization.py

# App (macOS + Xcode)
open RENN.xcodeproj            # select the RENN scheme, then Run or Test
```

CI (`.github/workflows/ci.yml`) runs the package tests on Linux, the localization check, and on
macOS builds the app for the iOS Simulator and runs the tests.

## Owner configuration

Nothing account-related is committed. Copy `Config/Secrets.example.xcconfig` to
`Config/Secrets.xcconfig` (git-ignored) and fill in the development team, the RevenueCat public
SDK key and the support/privacy/terms URLs. Firebase uses `GoogleService-Info.plist` (added in M06).
Without these values the app runs in a truthful unconfigured mode: no purchases, telemetry off, links disabled.

For UI work only, Debug builds can use scripted fake purchases with the launch argument
`-RENNUseFakePurchases` (listed, disabled, in the RENN scheme). Its products are labelled `DEV`.
