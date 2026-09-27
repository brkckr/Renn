# Commerce, Firebase and operational requirements

## C01 — Configuration identity

Display name **RENN**, bundle ID **`tzlapp.studio.renn`**, exact spelling. Use the same identity for the shipping iOS target, Apple app registration, Firebase iOS app and RevenueCat app. Keep development telemetry isolated from production using environment configuration. A separately signed development bundle, if needed, requires its own explicitly documented provider registration; never silently change the production ID.

Account/project identifiers, keys and Store products are not provisioned by this handoff. Pin compatible stable SDKs with Swift Package Manager, commit Package.resolved and record Xcode/Swift/deployment versions. Verify current provider/Store requirements at implementation/submission instead of relying on dated prose.

## C02 — Products and prices

| Product | Store type | US target | Turkey target |
|---|---|---|---|
| Monthly | Auto-renewing subscription | $2.99 / month | ₺49.99 / month |
| Annual | Auto-renewing subscription | $14.99 / year | ₺249.99 / year |
| Lifetime | Non-consumable | $29.99 once | ₺599.99 once |

Monthly and annual share one subscription group. All three grant RevenueCat entitlement **`pro`** with identical benefits. Prices are owner-approved targets; available Store price points and configured localized products determine runtime display. Product IDs are external configuration, not invented registered resources. Suggested suffixes monthly/annual/lifetime are naming aids only.

No trial, introductory campaign or fake discount is specified. Baseline no offer copy until a real offer is configured and eligibility handled. Show annual total clearly. Lifetime does not automatically cancel an existing Store subscription; an active subscriber choosing lifetime must see accurate guidance and a manage-subscription route.

## C03 — RevenueCat integration

RevenueCat Purchases SDK is the sole transaction owner, using its supported StoreKit integration for the pinned version. No parallel independent StoreKit purchase/finish logic. Build the custom animated paywall in SwiftUI; do not substitute a default paywall template that discards the reference design.

Products/Offerings and localized prices come from SDK/Store. If unavailable, show retry/restore/continue Free, not a hardcoded purchasable price. Public SDK app keys may be client config; secret server keys and signing credentials never enter app binaries/git.

PurchaseService owns customer information and exposes `unknown/free/pro` access state with provenance/check time. Observe entitlement changes and refresh on launch/foreground and purchase/restore. Use SDK-supported cache semantics; no custom indefinite offline grace or UserDefaults unlock. Test the pinned version with fresh install, offline cached Pro, expired/stale cache and never-loaded customer state.

Transaction states include purchasing, pending/Ask to Buy, user cancellation, failure and verified granted entitlement. Animation/button success cannot unlock Pro. Capture the selected product ID at purchase tap and keep UI aligned during the transaction. Unknown/pending does not erase a project or silently bypass limits.

Restore is always accessible in Settings/paywall. Test anonymous RevenueCat identities across reinstall/second device and the configured transfer/restore policy. Do not add a login system merely to manage purchases. Enable provider-supported Store notification configuration as required; no custom backend is necessary for the agreed V1.

After verified upgrade, return to original export intent, resolve and display policy, and continue only the user-requested operation once. Never duplicate an export from both purchase callback and entitlement observer. An authorized running job retains its snapshot. New jobs after expiry use Free policy, while prior results remain playable/shareable.

## C04 — Paywall boundaries

Entry points: crowned RENN Pro Settings card and explicit upgrade intent before export (including Free source >30 seconds). No paid gate on Looks, Beat, Dual-Cam, OSD, favorites, projects or basic sharing. No mandatory post-export interception or payment barrier on an already rendered file.

Include one clear close, actual product prices/periods, all benefits accurately, Restore, Terms and Privacy. Existing Pro state must not pretend the user needs the same access again. Lifetime is a one-time purchase; subscription disclosures are not applied to it as if it renews. Recheck current platform disclosure requirements before submission.

## C05 — Firebase scope and collection

Firebase is required; baseline modules **Analytics and Crashlytics**. No Firestore, Storage, Auth, Cloud Messaging or Remote Config is required. No raw media uploads. Core app/export must work if Firebase is offline or disabled.

Retain an explicit optional diagnostics preference in Settings; configure SDK defaults to prevent collection before the baseline consent permits it. Declining telemetry never changes features. Verify actual SDK behavior, automatic events/breadcrumbs and App Privacy declarations in the shipping binary. No advertising/cross-app tracking is part of this product scope.

Only structured allowlisted fields: app/build, coarse device/OS/capture mode, duration/quality buckets, chosen catalog Look ID, stage, typed error code, elapsed processing time and access tier. Do not send names, file paths, images/audio, waveforms, transcripts, location, purchase receipts or arbitrary raw error strings. Random event/job correlation IDs may support deduplication but must not become user content or high-cardinality reporting dimensions.

| Event | Trigger |
|---|---|
| creation_started | Capture begins or picker selection confirmed |
| source_ready | Valid source/project committed |
| look_selected / beat_changed | User commits a change, not every slider frame |
| preview_ready | First usable canonical preview per flow |
| export_started | Validated job enters preparation |
| export_completed | Valid local output committed; not Photos success |
| export_failed / cancelled / interrupted | Corresponding terminal pre-commit state |
| photos_save_finished | Actual save callback/state reconciliation |
| share_sheet_opened / finished | System presentation/callback; not proof of posting |
| paywall_shown | Visible paywall, with placement/reason |
| purchase_started / finished | Store request and pending/cancel/failure/granted outcome |
| restore_finished | SDK restore result and effective access |

Deduplicate local terminal events by job ID; transport is not assumed exactly-once. Measure failure separately from cancellation/interruption and also show completed/all-started so failures cannot be hidden by relabeling. Use provider purchase reporting as revenue authority rather than double-counting custom funnel events. Analytics metrics describe consented observed population only.

Verify Crashlytics with a controlled development/test crash and correct symbol upload; never intentionally crash production users. Telemetry adapter tests must confirm disabled means no event sending.

## C06 — Permissions, privacy and recovery

Camera/mic prompts occur when a relevant capture action is requested. Selected-media import uses system picker. Photos add permission occurs at first save need. Do not request full library access, contacts/location or microphone on onboarding. Localized usage descriptions must explain actual behavior.

| Failure | Required behavior |
|---|---|
| Camera denied/restricted | Explain; offer import and applicable Settings route |
| Microphone denied/no audio | Silent/Look-only route; no fake Beat |
| iCloud transfer offline/cancel | Retry/cancel with truthful transfer state |
| Unsupported codec/HDR/camera pair | Concrete supported alternative, no payment cure |
| Low disk | Preserve source/recipe/old output; cleanup own partials, storage guidance |
| Thermal/interruption | Coherent controlled stop, truthful recovery; no hidden quality loss |
| Missing source | Explain unavailable project; never synthesize substitute footage |
| Purchase pending/offline | Preserve draft, use effective access and retry/restore |
| Photos denied/failure | Keep local export/share/watch; retry saving only |
| Share cancelled | Keep local result and return to result sheet |

Provider networking means “no data ever leaves your phone” is inaccurate. Privacy/support/terms must describe actual diagnostics and purchase providers, local media lifecycle, configured retention and support/deletion route. No local-project recovery is implied by restore purchases. Review manifests, required-reason APIs and actual SDK disclosures before release; a consent switch alone is not legal-compliance proof.

## C07 — Localization and accessibility

English and Turkish String Catalogs cover all app strings, errors, permission descriptions and accessible labels. System/Turkish/English choice affects app UI, not Store currency. Dates for cassette names are localized; decorative stamp has fixed YYYY.MM.DD output. Validate Turkish glyphs in the actual shipped fonts and preserve required notices under Licenses.

At least 44 pt controls, Dynamic Type reflow, named/selected VoiceOver controls and adjustable sliders. Record/stop/export/close remain reachable at largest text sizes. No color-only state. Respect Reduce Motion/Transparency and readable contrast over varied footage. Do not blur functional text or use retro display type for legal explanations.

## Reference documentation

These links are implementation references, not replacements for the product contract. Revalidate against pinned versions and shipping date:

- [Apple AVFoundation](https://developer.apple.com/documentation/avfoundation/)
- [Apple SwiftData](https://developer.apple.com/documentation/swiftdata/)
- [Apple MultiCam support](https://developer.apple.com/documentation/avfoundation/avcapturemulticamsession/ismulticamsupported)
- [Apple HDR video guidance](https://developer.apple.com/videos/play/wwdc2020/10009/)
- [Apple review guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Apple subscriptions](https://developer.apple.com/app-store/subscriptions/)
- [Firebase Apple setup](https://firebase.google.com/docs/ios/setup)
- [Firebase Crashlytics](https://firebase.google.com/docs/crashlytics/ios/get-started)
- [RevenueCat iOS installation](https://www.revenuecat.com/docs/getting-started/installation/ios)
- [RevenueCat caching](https://www.revenuecat.com/docs/test-and-launch/debugging/caching)
