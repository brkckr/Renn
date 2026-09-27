# Implementation backlog and acceptance

Execute in dependency order. Independent design previews can progress while platform integration waits, but they do not establish working media capability. Record actual results; none of the tests below have been run on an app during planning.

## Milestones

| ID | Depends on | Deliverable and completion evidence |
|---|---|---|
| M00 Foundation | Handoff | Repository/toolchain audit, exact bundle ID, iOS deployment strategy, app target, SPM locks, MVVM/DI composition, English/Turkish catalogs, test target; build on Mac or mark build blocked |
| M01 Durable projects | M00 | SwiftData schema, owned file store, recipe/snapshots, migration/reconciliation, rename/delete/leases, fake stores; tested interrupted commits and no external deletion |
| M02 Media proof | M00–01 | One clearly labeled diagnostic Look: import and ordinary capture → shared preview → export → verified file → Photos; prove clocks/aspect/SDR/HDR route/FPS policy and profile 4K60 before catalog expansion |
| M03 Beat and render core | M02 | Deterministic LUT/artifact/grain engine, canonical audio analysis, mute rule, intensity semantics, OSD/date/watermark/collision resolver; actual file integration tests |
| M04 Dual-Cam | M02–03 | Runtime capability/formats, two clean sources/one audio, common clock, persisted live swap events, interruption handling and actual supported-device evidence |
| M05 App flows | M01–04 | Home/catalog/favorites/recent/preview/indicators/timer/export/result/settings, all empty/error paths; no editor/music/name scope creep |
| M06 Commerce/telemetry | M00–02, integrates M05 | RevenueCat products/access policy/restore/offline/pending, Firebase consent/events/crash verification, exact app configs; sandbox evidence |
| M07 Visual and motion | UI shells from M00; final integration M05–06 | Brand fonts/tokens, splash/onboarding, glass bar, 3-plan paywall, VHS project insertion/result motion; recordings vs references and accessibility |
| M08 Final Look catalog | M03 + licensed owner assets | Twelve reviewed Looks with stable versions and parameter snapshots, real posters/demos, license inventory; no fake final presets |
| M09 Hardening/release candidate | M01–08 | Device/format/long-video matrix, storage/interruption/purchase regressions, performance report, accessibility/localization review, production configuration audit and TestFlight-ready build |

M02's diagnostic Look is a development fixture, not one of twelve automatically approved artistic Looks. Missing final art should not block basic media engineering. Final public catalog and advertised quality cannot ship without review.

## Acceptance matrix

| Requirement | Meaningful checks |
|---|---|
| P01 / A01 / C01 | Display name RENN; production bundle ID exactly tzlapp.studio.renn in build settings and provider checklist; no alternate brand text in app code/resources |
| P02 / D04 / M03 | Four tabs in correct order; Home-only + absent from hit-testing elsewhere; growing glass surface; repeated taps cause one destination; unsupported Dual-Cam is explanatory |
| P03 / D08 / M05 | Correct processed poster/name, composite dual cover, deterministic case variant, See all same collection, rename reflects both surfaces, insertion truly occludes and opens correct media |
| P04 | Twelve release entries all free; favorites survive restart; four distinct recents updated only by valid events; catalog browsing never mutates projects; intensity/version persistence |
| P05 / V02–03 | Portrait capture, supported dual configuration, one shared audio track, replay every swap at correct source time, pre-record corners, no recording-time drag; timer Off/3/10 excludes countdown from media/limit |
| P06 / V05 | Imported/recorded source sound only; mute disables audio/Beat but preserves choice/cache; no-audio/silence behavior; no accidental live mic in preview |
| P07 / D06 | All 16 indicator combinations, staged Apply/Cancel, date leap-year/timezone persistence, real REC unaffected, no editor scope, playback seek doesn't trim |
| P08 / V01 | 30-second Free boundary and >30 import response; aspect-aware 720p cap, rational rates, no upscaling; supported Pro 4K60; no artificial 180-second/10-minute/2-GiB restrictions |
| P09 / V09 | Valid local output before success, truthful progress, save failed vs render failed, retry Photos only, no normal repeated save, uncertain crash window, cancel/interruption preserves source |
| P10 / M01–02 | Four pages/no name/upfront permission, usable Next/Skip, final route once, no duplicate fake project, static launch vs animated app splash |
| P11 / C02–04 | Three real products same entitlement, localized prices, restore/expiry/refund/offline/pending and rapid selection correct; no forced post-export gate |
| A02–05 | Services injected; no feature singleton/global locator, no SwiftData objects across actors, stale results/duplicate actions rejected, frame queues bounded |
| C05–07 | Consent-disabled providers silent, no media/path/name in events, local failures don't depend on network, permissions contextual, accessibility and both languages functional |

## Test levels

1. **Pure rules:** access resolution, dimension/rational-time mapping, recipe validation, date/name validation, seeded effect parameters, state transitions and cache keys.
2. **State/service tests:** fake storage/purchases/export; cancellation, stale replies, duplicate starts, save-only retry, project deletion with active leases and interrupted recovery. Do not merely assert mocks return supplied values.
3. **Media integration:** decode actual output files and inspect tracks/timing/colors/dimensions/audio/overlays. Same-size pre-encode preview/export comparison and deterministic seeking.
4. **UI/motion:** real navigation, VoiceOver controls, large text, 320/375/390/430 layouts, Reduce Motion/Transparency, frame recordings for reference comparison.
5. **Physical devices:** camera/GPU/Dual-Cam/long-video/thermal/storage interruptions and actual performance. Simulator checks do not substitute.
6. **Commerce:** local StoreKit test configuration as development aid, then RevenueCat sandbox/TestFlight purchase/restore/renewal/expiry/refund/pending paths with real product configuration.

## Fixtures and devices

Use owned/licensed or synthetic fixtures: known audio pulse/visual flash, silence, speech, steady music, irregular percussion, skin tones, gradients, night/noisy footage and fast movement. Include 24/25/29.97/30/50/59.94/60 FPS and VFR; portrait/landscape/square/rotation/mirror; H.264/HEVC SDR and representative iPhone HDR; no audio/delayed audio/stereo; corrupt/truncated; low resolution; >2 GiB and >10-minute feasible inputs, plus a long 4K60 Pro case. Rejection cases test actual unsupported capability/resource limits, not removed commercial caps.

Boundary fixtures: just below/exactly/just above 30 seconds, output duration within one frame, mute/unmute, all indicator combinations with four PiP corners, light/dark footage under watermark, catalog revision stability, app kill during file/DB/Photos stages.

Test lowest actually admitted supported device, small-screen SE-class layout, mainstream mid-generation and current mainstream/Pro; identify exact OS/model. iOS deployment may admit older devices than a desired test floor, so runtime capability checks and actual admitted-device coverage are required. iPhone 11-class/A13 is an initial profiling target, not an App Store model-exclusion mechanism. Dual-Cam has its own supported/unsupported matrix.

## Engineering performance targets

These are initial acceptance targets, not measured guarantees. Run Release builds, record fixture/device/OS/thermal state and sample counts. Report p95 with at least 20 runs for short operations. If unmet, investigate and document evidence; do not silently weaken the gate.

| Area | Target / evidence |
|---|---|
| Camera readiness | p95 ≤2 s warm / ≤3 s cold with permissions already granted |
| Look response | p95 input-to-visible ≤100 ms on minimum test device |
| Preview | 30 FPS baseline, average ≥29 over 60 s and <1% intervals >66.7 ms at nominal thermal state; document adaptive preview resolution |
| Capture timing | Monotonic PTS, ≤1% unexpected dropped frames, no unreported gap >100 ms on validated configuration |
| A/V sync | Start/end absolute offset ≤50 ms; drift change ≤20 ms over a 3-minute timing fixture; repeat marker checks throughout longer fixtures |
| Dual alignment | ≤1 output-frame inter-camera skew on a documented shared visual timing fixture |
| Standard export | 30 s 1080p SDR fixture ≤60 s on floor device and ≤30 s mainstream; measure HDR preparation separately |
| 4K60/long export | Publish real elapsed time, throughput, peak memory/disk/thermal behavior; no fabricated universal speed promise; bounded memory independent of duration |
| Memory | Initial 1080p app-resident target ≤350 MiB, drift ≤20 MiB after five cycles; profile 4K/dual separately against real jetsam margin, no unbounded queues |
| Cancel | UI acknowledgment ≤200 ms, worker cleanup within 2 s unless already suspended; next launch reconciles remnants |
| Determinism/parity | Same recipe/time reproducible pre-encode output; same-size preview/export max channel difference target ≤2/255 on SDR fixtures; compressed outputs reviewed separately |
| Reliability | At least 200 valid attempts across device matrix, ≥99% success excluding explicit cancel/fault injection; interruptions reported separately and all-start completion rate also shown |

Three-minute and long endurance fixtures are test durations, not Pro limits. Add at least a 15-minute representative Pro processing run where test hardware/storage permits; a longer owner's real workflow must be validated before advertising it specifically.

## Release gates

Block release for source loss/corruption, entitlement bypass, missing restore behavior, unsupported advertised format, unsafe unbounded memory, significant A/V drift, incorrect preview/export effects, wrong project playback, inaccessible stop/export, missing required asset licenses or incomplete 12-Look visual review. Compile success alone clears none of these.

Record exact defaults chosen for codec/VFR/HDR/device formats in short architecture decision records with fixture evidence. These resolve engineering validation items in 08. Product changes require owner discussion; routine implementation choices do not.

Release candidate needs owner-provided accounts/legal/support/brand assets, configured real products and prices, provider privacy disclosures, app icon/screenshots/metadata, current platform requirement review and actual TestFlight evidence. Do not publish as part of merely preparing this handoff.

## Implementation report template

```text
Milestone / requirement IDs:
Implemented behavior and changed files:
Toolchain / dependencies / device configurations:
Checks run and observed results:
Visual/media evidence paths:
Known limitations and placeholders:
Owner inputs or external blockers:
Next dependency:
```
