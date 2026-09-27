# Motion implementation contract

The included videos are visual references, not executable UI or licensed shipping artwork. Timings below are selected implementation baselines, not measured reference timings. Do not infer exact easing from sampled contact sheets.

| Motion | Reference |
|---|---|
| M01 Splash stripes | [splash.jpg](references/splash.jpg) |
| M02 Onboarding wipe | [video](references/onboarding.mp4), [inspection frames](references/onboarding-contact-sheet.png) |
| M03 Glass creation bar | [video](references/bottom%20bar.mp4), [inspection frames](references/bottom-bar-contact-sheet.png) |
| M04 Paywall selection | [video](references/paywall.mp4), [inspection frames](references/paywall-contact-sheet.png) |
| M05 Project insertion | [video](references/caset%20anim.mp4), [inspection frames](references/cassette-projects-contact-sheet.png) |

## Shared implementation rules

Use SwiftUI animatable shapes, measured geometry and layered artwork; Core Animation bridges are acceptable where needed. No full 3D engine or Lottie dependency is required by this contract. One state owner per motion; business selection and visual progress are separate. Animation completion never proves a purchase, export or source load succeeded.

Use one cancellable coordinator/task with a transition identity. Invalidate stale completions on dismissal/navigation/inactivity. Do not chain unowned delayed callbacks. Preserve view identity and layout space. Moving duplicates have no independent hit-testing/VoiceOver presence. Use elapsed time, not frame counts, for 60/120 Hz consistency.

Reduce Motion removes translation/rotation/scale/pulses: immediate final geometry or at most 120 ms dissolve. Reduce Transparency follows the opaque glass fallback. Decorative scenes stop on hidden tabs/background. No required sound. Any haptic occurs once per valid event, never as the only feedback.

## M01 — Splash

Separate static iOS launch presentation from the animated in-app splash. Static view uses the brown background and compatible centered branding; do not attempt to execute animation in the system launch screen.

Four adjacent brand-color ribbons descend from offscreen top along a continuous path that bends outward near the bottom, matching the reference composition. The leading edge follows the bend, rather than moving a precomposed poster down the screen. Center Monoton RENN so each glyph belongs to its corresponding vertical stripe. Measure glyph cells and stripe centers together; do not use arbitrary text tracking that misaligns them.

Baseline total 1,100 ms: 0–800 ms reveal ribbons top-to-bottom along their bent shapes, 300–700 ms introduce centered logo, 800–1,100 ms settle/transition. Curves and bend geometry are tuned to the reference, without bounce. Text color is the dark-brown baseline from 02, subject to contrast review. This is not the colored-glyph watermark.

Route to onboarding if incomplete, otherwise Home. Do not replay on foreground return. Do not wait for remote analytics/products to exit splash. Reduce Motion shows final composition then dissolves. App inactivity invalidates delayed routing and resumes into the correct destination once.

## M02 — Onboarding curved wipe

Four user-controlled pages, one-shot content scenes and resting poses. Scenes from 02 run independently of Next/Skip; no required wait or automatic page advancement. A transition in progress may temporarily serialize navigation to avoid double-advancing.

Back-to-front: brown background → current/target scene and copy → moving curved color mask → navigation where appropriate. States `idle(index) → covering(from,to) → revealing(to) → idle(to)`.

| Time | Behavior |
|---|---|
| 0–100 ms | Old copy fades out; stop old scene playback |
| 0–380 ms | Broad curved leading edge sweeps right-to-left, completely covering viewport |
| 380 ms | Replace page while covered; update indicator |
| 380–760 ms | Trailing edge continues left, exposing new brown page |
| 520–760 ms | New copy fades in; restore controls at completion |

Starting curve `(0.22,1,0.36,1)`. Use an animatable Shape/Path with top/middle/bottom control points, middle deflection about 0.22W; clip to viewport. Verify corner coverage at midpoint for every supported layout. Do not assume one moving circle covers all corners.

Page 1 clean-to-treated sample; page 2 three actual Look cards come forward in turn; page 3 recorded demo-audio transients animate waveform/controlled artifacts; page 4 sample becomes VHS case and settles on shelf. The sample sound is opt-in and no microphone prompt is needed. No endless bright flashing or simultaneous competing scene and page wipes.

On inactivity settle to the intended target page, removing partial masks. Skip and final completion persist onboarding completion and route Home once. Move VoiceOver focus to target heading. Reduce Motion uses a 120 ms content dissolve and static scene examples.

## M03 — Glass capsule to creation menu

One continuous bottom-left-anchored material surface morphs; do not place a separate system sheet above an unchanged bar. Geometry and colors are in D04. States `closed/opening/open/closing`, selected tab and latest pending tab request.

| Event | Baseline timing |
|---|---|
| Selection pill | 220 ms, `(0.22,1,0.36,1)`; icon color 140 ms |
| Leave Home | 280 ms total; + fades/scales 1→0 / 1→0.75 in first 160; capsule expands at 60–280 |
| Return Home | Capsule narrows 0–220; + appears 120–280 |
| Open | 360 ms surface height 64→256/radius 32→24; tabs fade 0–80 |
| Rows enter | 100–260 / 130–290 / 160–320 ms, opacity 0→1 and y 8→0 |
| + to × | 240 ms, rotation 0→45°; center fixed |
| Scrim | 180 ms to black 18% |
| Close | 260 ms `(0.4,0,0.2,1)`; rows exit first 80, tabs return 160–260 |
| × to + / scrim out | 220 / 160 ms |
| + press | Scale to 0.94 in 70 ms, return in 120 ms |

Left/bottom anchor and + center remain fixed as the panel grows up. Content opacity layers differ but material/mask identity stays stable; no opaque flash. Row text/icons remain sharp.

Disable + immediately on leaving Home and until returning animation completes. Hidden + is absent from accessibility/hit-testing. Ignore repeated transition taps; queue only the latest tab request. Capture a chosen action once, close, then present its destination once. Outside tap/×/accessible dismiss closes without changing projects. Focus first row on open; restore visible control focus on close. One light haptic on open, none on every tab/close.

## M04 — Paywall plan selection

Three products: monthly, annual, lifetime. `selectedProductID` is authoritative; selection atomically updates localized price/period/semantic state at t=0. Decoration cannot change billing data. Proposed accents: monthly amber, annual yellow, lifetime orange. All products grant the same entitlement.

Layers: brown → bounded halo → glass plan panel → fixed decorative object stage → price/copy/CTA. Stage max 120 pt, compact 80. CTA/disclosures remain stationary and reachable. Extend the supplied two-object visual language to a third object without copying unapproved product art.

- 0–320 ms `(0.22,1,0.36,1)`: selected object scale 0.92→1, y −8→0, passive tilt (about ±6°)→0; foreground z-order. Old object returns passive.
- 0–240 ms: old/new halo crossfade.
- 180–480 ms: selected halo opacity 0.12→0.28→0.20, peak about 330 ms. Outline 1.5 pt; blur 16; spill at most 16. No perpetual pulse.
- Entrance at most 400 ms opacity/8 pt motion; close and payment controls do not wait.

New selection cancels/redirects old presentation, last selection wins. Purchase snapshots selected product and locks selection while Store transaction is active. Pending/cancel/failure/granted are purchase states independent of animation. No number tween, fake countdown, automatic plan cycling or synthetic success.

Reduce Motion: at most 120 ms opacity/color change. No audio; optional one selection haptic. Validate ten rapid selections and purchase mid-animation: displayed and purchased product must agree.

## M05 — VHS case/cassette insertion

Inspect the upright case/upper player in [the original extracted frame](references/cassette-screen-reference.png). Build separate player rear/front/slot mask, case front/side, travelling cassette representation and shadow. Do not flatten the screenshot into a background or turn the collection into audio cassettes.

State `idle → lifting(projectID) → travelling → inserting → presentingPreview`. Snapshot project ID/poster; use one screen overlay and a named coordinate space for source/target anchors. Keep grid-cell space while hiding its visual; prevent scroll from moving the source during transition.

| Time | Behavior |
|---|---|
| 0–150 ms | Lift 8 pt, scale 1→1.05, spread shadow |
| 150–500 ms | Curved travel/rotate toward slot, scale to slot entrance |
| 500–700 ms | Slide behind player front mask; shadow fades |
| 700 ms | Present correct project preview once, if media ready |

Use one normalized progress value. Starting quadratic path endpoints source/slot centers, control point above midpoint by `min(80pt,0.12H)` clamped to visible bounds. Starting rotation 0→−8°→0; final asset geometry may need adjustment to expose thin side as in reference. Layer ordering at insertion is rear player → travelling object → front player. Actual occlusion, not simple shrinking-away, is required.

Grid objects are VHS sleeves; travelling object may expose a cassette carrying the same project identity. Prototype this transformation with layered art and compare to reference. Do not invent elaborate unapproved mechanics.

Prepare media in parallel. If not ready at insertion end, hold inserted pose with preparing state; never navigate to black. Missing source gives recoverable error. Tab/back/inactivity cancels, removes overlay/restores card and prevents stale navigation. Only one project opens at a time. Home has no slot target and uses a short dissolve to the same preview. Reduce Motion: no travel, 120 ms dissolve.

## M06 — Export completion

Only verified render completion triggers the result presentation. Cassette settles by a small 6 pt / opacity transition over 240 ms, one light haptic. Photos save checkmark is separately driven by actual save success; never animate a false check. No confetti. Reopening the sheet does not replay the completion haptic. Reduce Motion uses opacity only.

## Visual acceptance

Record interactive start/middle/end and rapid-repeat behavior at widths 320/375/390/430, large text, both accessibility reductions and actual 60/120 Hz devices where available. Verify surface continuity, full wipe coverage, cassette occlusion, correct route/product identity, cancellation and accessible focus. Inspection frames are a comparison aid, not evidence that the app matches the reference. Report placeholders and untested performance explicitly.
