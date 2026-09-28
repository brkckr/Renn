# M06 owner setup: RevenueCat and Firebase

The app contains the RevenueCat and Firebase adapters but no credentials, products or
accounts. Until the items below exist it runs with the Free policy, shows "purchases not
configured" and sends no telemetry. Nothing here needs to be committed to git.

## RevenueCat (purchases)

1. In App Store Connect, for bundle ID `tzlapp.studio.renn`: create the subscription group with
   the monthly and annual auto-renewing subscriptions, and the lifetime non-consumable (06 C02
   prices). Product IDs are yours to choose.
2. In RevenueCat: add the iOS app with the same bundle ID, create the entitlement **`pro`** and
   attach all three products to it, and make the **current offering** contain three packages of
   type **Monthly**, **Annual** and **Lifetime** (the app maps plans by package type).
3. Copy the **public** Apple SDK key (starts with `appl_`) into `Config/Secrets.xcconfig`:
   `RENN_REVENUECAT_API_KEY = appl_...` (the file is git-ignored). Never put a secret/server key
   in the app.
4. Enable App Store server notifications as RevenueCat recommends.

The app then loads the offering, shows Store-localized prices, purchases through RevenueCat only,
grants Pro only from the active `pro` entitlement and restores from Settings and the paywall.

## Firebase (optional diagnostics)

1. In the Firebase console, add an iOS app with bundle ID `tzlapp.studio.renn` and enable
   Analytics and Crashlytics only.
2. Download `GoogleService-Info.plist` and place it in `RENN/Resources/` (any folder under `RENN/`
   is bundled automatically). Keep a separate Firebase project or app for development builds if
   you want development telemetry isolated (06 C01).
3. Collection is off by default (Info.plist) and turns on only when the user enables
   "Share diagnostics" in Settings.
4. Crashlytics symbol upload: add the Firebase `run` script build phase before the first
   TestFlight build (it needs the plist, so it is not in the project yet).

## Evidence still to collect (on a device, with sandbox accounts)

Fresh install, purchase each plan, Ask to Buy / pending, cancel, restore on a second device,
offline with cached Pro, expired subscription, and a controlled development crash visible in
Crashlytics with symbols (never crash production users).
