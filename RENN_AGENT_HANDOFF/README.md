# RENN — iOS coding-agent handoff

Version 1.0 · September 27, 2026 · English implementation contract

| Identity | Value |
|---|---|
| Display name | RENN |
| Bundle identifier | `tzlapp.studio.renn` |
| Platform | Native iPhone app |
| Engineering baseline | Swift 6, SwiftUI, MVVM, manual dependency injection, SwiftData, AVFoundation, Metal/Core Image, Accelerate |
| Required providers | Firebase and RevenueCat |
| Minimum OS baseline | iOS 17+, subject to dependency and real-device validation |

Use the owner-corrected identifier exactly as written above. Register the same identifier in the Xcode target, Apple developer configuration, App Store Connect, Firebase and RevenueCat app configuration. These registrations have not been performed.

## Read order

1. [Agent start instructions](00_AGENT_START.md)
2. [Product and feature contract](01_PRODUCT_CONTRACT.md)
3. [Design system and screen inventory](02_DESIGN_AND_SCREENS.md)
4. [Motion implementation contract](03_MOTION.md)
5. [Architecture and dependency injection](04_ARCHITECTURE.md)
6. [Media, rendering and persistence](05_MEDIA_AND_DATA.md)
7. [Commerce, privacy and operations](06_COMMERCE_AND_OPERATIONS.md)
8. [Implementation backlog and verification](07_IMPLEMENTATION_AND_TESTS.md)
9. [Assets and owner inputs](08_ASSETS_AND_INPUTS.md)

The files are one contract, not alternative plans. Each topic has one principal owner: product/access in 01, visual tokens/screens in 02, animation behavior in 03, code ownership in 04, media/data invariants in 05, purchase/telemetry in 06, acceptance in 07, missing inputs in 08. Future changes must update the relevant contract and its acceptance criteria together.

## Decision status

- **Product requirements:** settled owner decisions, captured in 01. Do not reopen settled choices by implementing older proposals or screenshot labels.
- **Engineering baseline / visual starting values:** specific implementation choices supplied to make the plan actionable. Use them without requesting approval for routine implementation. They are not claims of separate owner sign-off or measured performance. Record significant deviations and their evidence.
- **Owner input / release blocker:** real assets, credentials, visual approval or device results that do not exist yet. These are listed in 08. Build unaffected components using explicit test fixtures; do not pretend missing material is final.

The plan is consolidated. No unresolved historical override chain is needed to interpret it. Earlier planning history is not part of this package.

## Reference precedence

Written product requirements take precedence over text, labels, prices and feature counts visible inside the supplied images/videos. Apply RENN branding and colors to all implemented screens. Reference media may contain obsolete brand lettering; it is reference artwork, never a shipping logo or a source of product requirements.

The general screen sheet defines compositions except splash/onboarding and the explicit Home, glass-navigation, cassette-Projects and paywall-motion adaptations. The source videos are included for inspection; never play a reference video as a substitute for an interactive app component. Source references are not automatically licensed production assets.

## Delivery status

This package contains written specifications, original reference copies and prior inspection frames. It contains no production LUTs, shaders, grain assets, font files, final cassette layers, app project, account registrations or device-test evidence. Product architecture is specified; GPU throughput, HDR conversion, capture configurations and SDK behavior still require implementation verification.

No video upload, custom backend or account system is required. Core creation works offline once media is local. Store purchases, iCloud media retrieval and consented telemetry may use the network.

Package checks are recorded in [HANDOFF_VALIDATION.md](HANDOFF_VALIDATION.md). [MANIFEST.json](MANIFEST.json) records portable paths, sizes and SHA-256 hashes for package files. These checks validate the document delivery, not the future application.
