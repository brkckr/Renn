# Start here — implementation brief

Build **RENN**, a native iPhone retro-video camera and processor, using the accompanying contract. Use the exact bundle identifier **`tzlapp.studio.renn`**. The documentation language is English; the app supports English and Turkish.

Read all numbered documents before making architectural or scope decisions. Inspect the included screen and motion references before implementing the corresponding UI. Do not load historical plans as additional requirements.

## First implementation turn

1. Inspect the actual repository and its applicable instructions. This handoff itself is not an existing app codebase. Preserve unrelated work.
2. Verify whether a Mac, supported stable Xcode and real iPhones are available. Pin the toolchain, deployment target and compatible SDK versions. Do not claim native iOS build/camera tests on Windows.
3. Report the current app/build state and only the missing inputs relevant to the next milestone. Use 08's owner-input ledger; do not ask again for decisions already specified here.
4. Implement M00, then the storage and one-Look vertical slice before expanding into the full effects catalog. Keep the final required 12-Look launch scope visible.
5. Keep an implementation ledger with requirement IDs, changed files, checks run, observed results, remaining blockers and artifact paths. Mark placeholders and untested device claims explicitly.

## Non-negotiable scope checks

- Four tabs: Home, Looks, Projects, Settings. Home-only + morphs the glass bar into Record video / Dual-Cam / Import video actions.
- Four onboarding pages, no name collection. No trim/crop/timeline editor and no music-adding feature.
- Twelve initial Looks, all free. Same creative tools in Free and Pro.
- Free: maximum 30 seconds, 720p ceiling, source-aware maximum 30 FPS, `shot by RENN` watermark. Pro: no commercial duration quota, supported source quality/cadence including the 4K60 target, no watermark.
- RENN capture is portrait. Imported media retains display-oriented aspect ratio.
- Dual-Cam uses two synchronized clean video sources, one microphone track and recorded main/inset swap events. It is not a premium-only feature.
- Beat uses source audio only. In-app video mute also disables Beat modulation.
- Export automatically attempts Photos saving; successful rendering and successful saving are separate states.
- Local projects display their own processed frame and name on VHS cases. Home See all opens the existing Projects tab.
- Purchase authority is RevenueCat; telemetry is Firebase. Use local SwiftData metadata and separately stored video files.

## Implementation discipline

Use MVVM, constructor injection and explicit state machines at complex boundaries. Keep media processing out of Views/ViewModels. Do not add a global service locator, redundant StoreKit purchase owner, Firestore media store, arbitrary Pro cap, hidden quality downgrade or unsupported monetization gate.

Use shared recipe-driven rendering for preview and export. Runtime camera/GPU/codec capabilities matter more than device marketing names. A progress animation or successful mock test is not evidence of actual processing or purchase success.

Use documented defaults for routine details. Ask the owner only for a real product change or required missing input; continue independent work while waiting. Do not publish the app, create paid infrastructure or claim external accounts are configured merely because the plan names them.

## Definition of a finished milestone

Implemented behavior, meaningful checks, visual evidence where relevant, and an honest list of remaining limitations. The complete app is not finished until all launch gates in 07 pass and required owner inputs in 08 are supplied. No weakened tests or fake assets may be used to mark a blocked gate complete.
