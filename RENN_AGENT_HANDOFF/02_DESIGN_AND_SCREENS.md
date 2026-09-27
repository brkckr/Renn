# Design system and screen contract

Screen composition reference: [allscreen.png](references/allscreen.png). Splash and onboarding have separate references; glass navigation, Home content, Projects and paywall motion follow their explicit contracts. Do not ship the obsolete lettering, screen numbers, pricing or feature labels embedded in reference artwork.

Dimensions below are points unless explicitly output pixels. They are implementation starting values, not measurements proven on devices. Preserve hierarchy while adapting to small screens, safe areas and Dynamic Type.

## D01 — Brand tokens

| Token | Value / usage |
|---|---|
| background.base | `#403529`, opaque dark brown |
| brand.yellow | `#F8C43F`, primary CTA/active controls |
| brand.amber | `#F2A83A`, secondary brand emphasis |
| brand.orange | `#F27D3B`, effect emphasis |
| brand.red | `#F14A42`, recording/destructive accent with text/icon |
| text.primary | `#F5F5F5` |
| text.secondary | `#D0D0D0` |
| glass | Dark `.ultraThinMaterial` + `#171717` at 18% |
| glass.border | Inner 1 pt white at 12% |
| glass.shadow | Black 22%, radius 20, x 0 / y 8 |
| glass.opaqueFallback | `#292725`, Reduce Transparency |

Glass blurs content behind the surface, never the text/icons themselves. Do not replace the glass bottom bar with an opaque brown/yellow bar. Selected tab remains neutral white 12%; selected category/Look can use yellow. Increase Contrast baseline: border white 40%, selected surface white 20%, selected icon gets a 3 pt indicator dot.

Monoton: RENN branding. Press Start 2P: short retro labels/indicators only. Roboto: functional UI, headings, names, errors and purchase copy. Verify available font weights and Turkish glyphs. Use system typography inside system dialogs/pickers. Font fallback must be visible in the development asset report, not hidden as completed branding.

Standard side margin 16, spacing scale 8, touch target at least 44×44. Heading Roboto Medium 22; body 15–16; secondary 12–14, scalable. Primary button height 52, radius 16, Roboto Medium 16, yellow/dark-brown text; grow for accessibility. Secondary buttons glass/off-white. Standard card radius 12, large panel 24. Functional text does not use pixel fonts.

## D02 — Screen inventory

| ID | Surface | Entry / behavior | Reference |
|---|---|---|---|
| S01 | Splash | Every cold app entry; system launch view is static, motion starts in app | Stripe reference, M01 |
| OB01–04 | Onboarding | First use; Skip/Get started → Home | Onboarding video, M02 |
| S05 | Home | Default main tab | Sheet screen 5 composition adapted |
| S06 | Permission/error states | Contextual in the feature needing access | Native prompts + derived glass explanations |
| S07 | Camera / Dual-Cam | Home creation menu | Sheet screen 7 |
| S09 | Project preview | Capture/import/project open | Sheet screen 10, simplified controls |
| S10 | Look selector | Camera/preview | Sheet screen 8 |
| S11 | Beat controls | Camera/preview | Sheet screen 9, enable/intensity only |
| S12 | Export summary | Preview | Sheet screen 11, actual tier policy |
| S13 | Export processing | Export confirmed | Derived processing surface |
| S14 | Export result | Render/save completion | Approved glass result sheet |
| S15 | RENN Pro | Settings or explicit export upgrade intent | Sheet screen 12 + paywall video |
| S16 | Projects | Tab / Home See all | Cassette video and extracted frame |
| S17 | Settings | Main tab | Derived app-settings groups |
| S19 | Looks catalog | Main tab | Sheet screen 8 adapted to tab |
| S20 | On-screen Indicators | Camera/preview | Derived indicator panel |

No separate editor screen. The absent S08/S18 identifiers are intentional; do not infer missing features. Projects, Settings, Indicators, processing/result and error states are the additional surfaces beyond the general sheet. A Look inspection sheet is a baseline derived subview, not a new main screen. Further main-screen additions require explaining their purpose to the owner.

## D03 — Splash and onboarding

Splash: brown background with four adjacent vertical stripes in yellow/amber/orange/red order. They travel from top to bottom and bend outward toward the bottom as in [splash.jpg](references/splash.jpg). Center Monoton **RENN**, each letter centered on its own stripe. This glyph-to-stripe alignment differs from the watermark's colored glyphs. Starting geometry: combined stripe width about 40% of W, bend about 70% of H; dark-brown glyphs for contrast. These geometry/text-color choices need visual review. No slogan or unrelated accent colors.

Onboarding has a top visual scene, readable heading/supporting copy, four-dot progress, Skip and Next; final CTA Get started. Do not collect a name. Four content scenes:

| Page | English copy | Turkish localization | Scene |
|---|---|---|---|
| 1 | Capture today in another time. | Bugünü başka bir zamanda çek. | One scene changes from clean to one actual RENN Look |
| 2 | Every moment has a mood. / 12 Looks. All free. | Her anın bir havası var. / 12 Look. Hepsi ücretsiz. | Three treated versions of the same footage; selected card comes forward |
| 3 | Let sound move your video. / Effects that find rhythm in your video's sound. | Sesin görüntüyü hareketlendirsin. / Videonun sesine ritimle eşlik eden efektler. | Real demo waveform/transients with controlled distortion; optional sound |
| 4 | Your first tape is waiting. / Record or import. Let RENN do the rest. | İlk kasetin seni bekliyor. / Çek veya içe aktar. Gerisini RENN'e bırak. | Demo result becomes cassette cover, settles on shelf; Get started |

English translations are implementation copy. Turkish support-copy where not previously supplied is a localization baseline. Scene clips must be owned/licensed. Do not create fake user project records, ask for microphone access to play the demo or autoplay audible demo sound by default.

## D04 — Home and glass navigation

Home: small RENN brand; one recommended-Look hero with real sample/name/short description; last four used Look IDs when available; recent project VHS cases with See all. First use shows a create prompt without fake history. The hero is not a duplicate Start Camera button. Creation belongs in +.

For available width W and bottom safe inset B:

| Element | Geometry |
|---|---|
| Capsule | Height 64, radius 32, left 16; bottom edge B+12 above physical bottom |
| Home capsule | Width W−100 |
| Other-tab capsule | Width W−32 |
| Home + | 56×56, radius 28, 12 gap; vertically centered with capsule |
| Capsule inner padding | 8 horizontally; four equal 48-high cells |
| Selected tab pill | Cell width × 48, radius 24 |
| Reserved content bottom | B+12+64+16; count safe area only once |
| Open menu | Same left/bottom edge and width; height 256, radius 24 |
| Open rows | Three × minimum 72, padding 12, gaps 8, row radius 16 |

At accessibility sizes, expand measured panel height and allow row scrolling within available safe height. Never hide close or force clipped text into 256 pt.

Tab icons: custom consistent 24 pt vectors, 2 pt rounded strokes: house, cassette (Looks), stacked video cards (Projects), gear. Plus is two 20 pt strokes at 2.5 pt; rotate to ×. Standard layout uses icon-only tabs with proper accessible labels/selection. Final icon assets still need production.

Rows: Record video / “Record with one camera”; Record with both cameras / “Front and rear together”; Import video / “Choose a video from your library”. Roboto Medium 15/20 heading, Regular 12/16 support. Unsupported Dual-Cam stays discoverable with explanation, not a purchase CTA. Whole row tappable. Normal row white 5%, pressed 12%; selected/+ icons white. Scrim black 18%. See M03 for transitions.

## D05 — Looks and preview controls

Catalog: heading, horizontal chips, 3-column 3:4 sample grid. Side 16, column gap 10, row gap 16. Card width `(W−52)/3`, image radius 10, name gap 6, up to two lines. Selected card: 2 pt yellow inner outline + check; no colored cover over the image. Reduce to two/one columns at large text sizes.

Chips: All, Favorites, nonempty actual families; visual height 36, touch at least 44, gap 8, radius 18. Do not name families based solely on reference labels. Use the same licensed comparison scene for actual Look posters.

Catalog card opens a compact inspection sheet: example, name/description, Favorite and Create with this Look. This is a baseline interaction, not a new tab. Create returns Home with a temporary Look ID and opens creation menu. Cancel clears the pending intent without creating a project. Existing projects are never changed by catalog browsing.

Camera/preview Look selector shares the grid but has close + staged Apply/Cancel, no global tabs or Create button. One intensity slider. Beat panel has enable/intensity and audio availability information; do not implement the screenshot's extra response-speed/glitch-type controls or PRO badge.

Preview: large aspect-correct result, playback scrubber, before/after, sound, loop, Look/Beat/Indicators access and Export. No Edit button. Before/after bypasses creative Look/Beat only while held/toggled; it does not mutate the recipe or remove mandatory policy watermark. Releasing returns to the treated result. Playback controls never change export duration. A portrait app can display landscape media letterboxed in UI; output itself must not inherit those bars.

## D06 — Camera and indicators

Large portrait viewfinder, prominent record/stop control, actual REC/timer, switch-camera before capture, timer, Look/Beat/Indicators access. Controls use readable glass islands. During recording lock Look/intensity/indicator/timer changes; retain stop and approved Dual-Cam swap. No undefined FX tools.

Indicators panel: heading, aspect-correct preview up to 240 high, four glass rows (minimum 52), date picker row when date enabled, Turn all off and Apply. Cancel/back discards staged changes. Initial date is project creation date, valid Gregorian years 0001–9999. Turning date off preserves its selection.

Baseline anchors: REC top-left, battery top-right, PLAY bottom-left, date bottom-right. Use normalized margins about 5% of short edge and readable light glyphs/dark shadow. No live device-battery or wall-clock dependency. Position resolver respects actual PiP/indicator/watermark occupied rectangles; shift indicators inward/above reserved corners. Do not cover PiP content or omit a selected indicator silently. If a layout cannot fit, reduce decorative footprint within readable limits and flag the fixture for visual review.

## D07 — Watermark

Exact phrase **shot by RENN**. `shot by` Roboto Medium off-white; `RENN` Monoton with R `#F8C43F`, E `#F2A83A`, N `#F27D3B`, N `#F14A42`. Optically aligned baseline, consistent glyph size, fine dark shadow. No gradient across letters, background stripes, large card or animated watermark.

Bottom-right final-output anchor, starting inset 4% of short edge and width up to 28% of short edge. Size must be visually validated at Free output sizes, particularly Monoton's fine strokes; adjust baseline dimensions if unreadable. Date moves above this reservation in Free. For bottom-right PiP, reserve a footer gutter for watermark and shift the inset upward; do not cover its face/content. Preview reflects effective placement. Export draws one watermark after composition/effects/OSD; intensity cannot attenuate it. Pro removes only watermark reservation, not OSD preferences.

## D08 — Projects VHS shelf

Inspect [extracted reference](references/cassette-screen-reference.png) and [cassette motion](references/caset%20anim.mp4).

Top: dark rounded physical retro player, recessed slot/window, mechanical depth, thin horizontal opening, small decorative buttons with no false function. A shelf/divider separates it from a scrollable three-column collection of **upright VHS cases/sleeves**, about 2:3 front proportions, with thin side surfaces and cast shadows. They are not horizontal audio cassettes or flat generic thumbnail cards.

Starting layout: side 16, column gaps 12, row gaps 20; width `(W−56)/3`, height 1.5×width. Player region at most 28% of available height; shrink on small/large-text layouts. Bottom bar stays Projects-selected, + hidden. Omit the reference's phone frame, white presentation background, pink CTA, 60 label and music toolbar.

Print the actual processed frame and readable project name onto the case front. Preserve the frame's ratio inside the print window. Names in Roboto Medium, up to two visible lines/full accessible title. Case-print variants use the four brand colors deterministically by project ID, not random per redraw or tier. Do not copy fake manufacturer specifications. Optional tiny RENN branding is acceptable.

Expose Rename/Delete in a discoverable accessible action menu, not solely long-press. Empty collection offers a route back to Home creation. Loading covers use an empty case shell/name; failures never substitute an unrelated image.

Selection lifts/transforms a case/cassette representation into the upper player's slot behind a real occluding front layer (M05), then opens the same project preview. Home has the same case/cover/name model but uses a short dissolve to preview without inventing another player scene.

## D09 — Settings, paywall and export

Settings: crowned RENN Pro card (gold/brand yellow), active membership when applicable; System/Turkish/English; Restore Purchases, Manage Subscription where relevant, permission help, storage/cache controls, optional diagnostics, support/privacy/terms/licenses/version. No video settings or name form. System language choice follows device language with English fallback; explicit app choice persists and localizes app-owned strings without affecting Store currency.

Paywall: close, RENN brand, actual benefits (longer videos, supported higher quality, no watermark), three monthly/yearly/lifetime choices, localized price/period, fixed CTA, Restore/Terms/Privacy. All creative tools and Looks remain free. No hardcoded price, trial, fake discount or implied annual monthly charge without the actual annual total. Baseline initial selection annual when available, otherwise first available product; never auto-purchase. Third plan's motion appearance extends the reference with orange; validate original/licensed art rather than copying reference commercial claims.

Export summary: aspect-correct preview and actual duration/dimensions/FPS/watermark/audio summary. Output selection is automatic; no fake controls permitting policy violations. Explicit Pro intent can open paywall before job creation; a valid Free export proceeds without forced purchase.

Processing: preparing/processing/finalizing/saving stages, real progress where measurable, optional measured ETA, Cancel before committed output, source/quality summary and keep-open guidance. Completion sheet: dark glass, rounded top baseline 24, tappable cassette/actual output cover, Roboto “Your video is ready.”, verified save checkmark, yellow Share, glass Watch in RENN, top-right close. Photos failure keeps share/watch and offers retry/settings. No confetti. M06 defines completion motion.

All screens need loading/empty/denied/failure states where relevant, readable localized errors, safe areas and accessible control order. Do not add a generic blocking permission page before the user requests a feature.
