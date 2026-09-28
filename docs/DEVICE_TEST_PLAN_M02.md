# M02 device test plan (first media vertical slice)

Purpose: turn M02's simulator evidence into physical-iPhone evidence (07 test level 5).
Record the iPhone model, iOS version, Xcode version and thermal state for every run, and write
the results into `docs/IMPLEMENTATION_LEDGER.md`. A step not run stays "not run".

## Setup (owner)

1. Mac with the Xcode version CI uses (26.x) or newer; open `RENN.xcodeproj`.
2. Copy `Config/Secrets.example.xcconfig` to `Config/Secrets.xcconfig` and set only
   `RENN_DEVELOPMENT_TEAM` (Apple Developer Team ID). Other values may stay empty.
3. Select the RENN scheme, your iPhone as destination, Run. Automatic signing with a personal or
   paid team is enough for development; no App Store Connect, Firebase or RevenueCat setup is needed
   for M02 (purchases stay "not configured": Free policy applies).

## Checks

| # | Scenario | Expected | Evidence to capture |
|---|---|---|---|
| 1 | First launch | Splash → 4 onboarding pages → Home; no permission prompt | Screen recording |
| 2 | + → Record video, allow camera + mic | Portrait live preview with the DEV Look; REC pill with real timer | Screenshot |
| 3 | Record ~10 s, stop | Preview opens; the take plays with sound; Look visible | Note A/V sync by eye |
| 4 | Record and let it run | Stops by itself at 0:30 (Free); preview opens | Recorded duration in export summary |
| 5 | Front camera, record | Mirrored like the viewfinder; text in the scene not flipped in the export | Exported file |
| 6 | Deny microphone, record | "Recording without sound"; project has no sound; export has no audio track | Screenshot |
| 7 | Deny camera | Explanation + Import / Settings; no paywall | Screenshot |
| 8 | + → Import video (SDR, ≤30 s, e.g. 1080p 60 FPS) | Picker without full-library permission; preview opens | — |
| 9 | Import > 30 s | "RENN Free videos can be up to 30 seconds"; no trim; another video works | Screenshot |
| 10 | Export from preview | Summary 720p / ≤30 FPS / watermark; progress; "Your video is ready"; Photos permission (add-only) asked once; "Saved to Photos" only after it is really saved | Output in Photos |
| 11 | Open exported video in Photos | Watermark `shot by RENN` bottom-right, readable; duration equals source; sound in sync | Frame grab of the watermark |
| 12 | Deny Photos add access, export | Result sheet keeps Share / Watch in RENN; Retry saving; no re-render | Screenshot |
| 13 | Cancel during processing | Returns cleanly; project unchanged; a new export works | — |
| 14 | Mute in preview, export | Output has no audio track; unmute restores sound | — |
| 15 | Kill the app during export, relaunch | Project still opens; no half-written output appears as a result | — |
| 16 | Import an iPhone HDR (Dolby Vision/HLG) clip | Summary says HDR is converted; compare highlights vs. Photos app (clipping = fail) | Side-by-side screenshots |
| 17 | Rename and delete a project | Name updates on Home and Projects; delete asks for confirmation; Photos copy remains | — |
| 19 | Pro (DEBUG `-RENNUseFakePurchases YES` or sandbox Pro): record ~10 s | Recorded source is the highest format up to 4K60 the device offers (check the export summary: Pro 3840×2160, 60 FPS when supported); Free records 1080p30 | Export summary + file info |
| 18 | Switch language to Türkçe in Settings | All app text Turkish; permission prompts Turkish after relaunch | Screenshots |

## Measurements (07 performance targets, initial evidence only)

- 30 s 1080p SDR import → Free export: elapsed time (target ≤ 60 s on the floor device, ≤ 30 s mainstream).
- Camera readiness: time from + → Record video to live preview (target p95 ≤ 2–3 s).
- Instruments (Allocations) during one export: peak memory (initial target ≤ 350 MiB at 1080p).
- Pro 4K60 cannot be tested until purchases are configured (M06) or a Debug build uses
  `-RENNUseFakePurchases` with the fake set to Pro. Treat that only as a pipeline check, never purchase evidence.

## Known limitations going in

- The Look is the labelled development fixture `dev.diagnostic`, not a RENN Look.
- Fonts fall back to system fonts; icons are SF Symbols; case/player art are placeholders.
- No capture timer, Beat, indicators, Dual-Cam, paywall motion or final Look catalog yet (M03–M08).
