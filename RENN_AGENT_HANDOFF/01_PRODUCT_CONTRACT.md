# Product contract

## P01 — Product identity and purpose

RENN turns a newly recorded or imported video into a retro-looking result using a Look, optional source-audio-driven Beat modulation and optional camcorder indicators. It is a camera/processor with simple preview adjustments, not a general video editor. Bundle ID: `tzlapp.studio.renn`.

## P02 — Navigation and creation

- Post-onboarding entry is Home. Tabs, in order: **Home / Looks / Projects / Settings**.
- A separate right-hand **+** appears only on Home. It disappears with animation on other tabs and returns when Home is selected.
- The glass capsule expands upward into three rows: **Record video**, **Record with both cameras**, **Import video**. These are one creation menu, not three system dialogs.
- Ordinary camera mode contains front/rear selection before recording. The second menu action means simultaneous front/rear Dual-Cam.
- Capture and project-preview flows hide global tab navigation. Returning preserves the originating tab/list position.

## P03 — Home and project collection

Home shows a bundled editorial recommended Look, a compact last-four-distinct-Looks row when nonempty, and recent local project cassettes with **See all**. See all selects the existing Projects tab; there is no duplicate collection screen.

Recommended Look examples are clearly demo media, never fabricated user projects. No recommendation backend or AI analysis is required. Baseline: show up to three recent project cases on Home.

Projects uses upright VHS cases/sleeves and the supplied player-insertion motion. Each case shows a frame from its own processed video and its cassette name. Dual-Cam covers show the composite. Use cached stills, not many autoplaying videos.

New projects receive a persistent date-based name. Users may rename and delete, with explicit deletion confirmation. Names are labels, never filenames. Re-export does not create another project. Deletion only removes app-owned project data; imported originals and outputs in Photos remain.

## P04 — Looks, favorites and intensity

- Launch catalog: **12 Looks**. All present and future catalog Looks are free. Final names/assets are owner inputs, not reference-image labels.
- Catalog supports All, Favorites and only real nonempty families. No paid badges or locks.
- Favorites are user-managed. Recent history contains the last four distinct Look IDs; using one again moves it to the front. Do not copy a prior project's complete recipe.
- Baseline history trigger: successful source/project creation records its chosen Look; successful export records the Look actually exported. Browsing, failed imports/capture or failed/cancelled exports never create a history event. A previous valid creation event is not removed because a later export fails.
- One Look intensity control, normalized 0...1. Zero disables the Look's color/artifact contribution; one is its catalog maximum. Each Look supplies a default and versioned parameter mapping. Switching Look loads its default; reopening retains the saved intensity.
- Look intensity does not toggle OSD or overwrite independent Beat settings. No separate grain/color/scratch sliders in V1. Look adjustments are locked during recording.

## P05 — Capture and Dual-Cam

RENN records portrait 9:16. Import preserves the source's display-oriented ratio, including landscape/square. Ordinary capture does not switch physical cameras mid-take in V1.

Dual-Cam is available to both tiers on supported hardware/configurations. Start with rear main and front rounded PiP, approximately 30% of canvas width, top-right. Users choose one of four corners before recording. A one-tap control swaps main/inset **during recording**, with timed events persisted and replayed. No PiP dragging/resizing while recording and no post-capture layout editor. Baseline swap is an immediate media-timed cut, with a subtle UI-only button response.

Retain two clean synchronized sources and one shared microphone track. Both views use the same Look/Beat. Composite indicators/watermark are drawn once. Unsupported configurations explain the reason and offer normal camera/import, not a paywall.

Capture timer: **Off / 3 s / 10 s**, both tiers and capture modes. Start only when cameras are ready; cancel on back/background/interruption. Countdown pixels/audio do not enter the recording or the Free 30-second allowance. Baseline retention: within the current camera flow, default Off on a new flow.

## P06 — Audio and Beat-Sync

Only the imported video's own audio or microphone audio recorded with a take drives Beat. Dual-Cam has one shared mic track. Preview/export never listens to the current microphone or another app.

Beat is controlled by enable + intensity. It responds to energy/transients; it does not promise exact BPM detection. Silence produces no invented beats. Missing/denied audio leaves Look-only processing usable.

In-app video mute suppresses output audio **and Beat modulation**. Unmute restores previous Beat enable/intensity; it does not auto-enable Beat if it was off. System speaker volume/silent mode does not modify the recipe. Preserve source audio and analysis cache when muted.

`effectiveBeat = beatEnabled && !audioMuted && sourceHasUsableAudio`.

## P07 — Preview and optional indicators

One simplified preview follows capture/import and opens existing projects. Allow Look/intensity, Beat enable/intensity, mute and On-screen Indicators controls. Playback seek, loop and before/after are preview controls only; they never trim, extend or otherwise edit source duration.

Indicators panel has independent **REC / PLAY / Battery / Date** switches and a custom date picker. Users may combine all four. Date uses Gregorian date-only components and frozen `YYYY.MM.DD` text; changing time zones never changes an existing stamp. Date does not alter media metadata or cassette name. Baseline: all off, static full decorative battery and static REC dot. Real recording status/timer remain separately visible even when decorative REC is off.

Use staged Apply/Cancel in indicator and Look-selection panels; Apply creates one recipe revision. Preview intensity/Beat changes can autosave with bounded debounce. No name/account question in onboarding or export.

## P08 — Access and output

| Capability | Free | Pro |
|---|---|---|
| 12 Looks and later catalog additions | All | All |
| Look intensity, Beat, indicators/custom date | Yes | Yes |
| Normal camera, supported Dual-Cam, timer, import | Yes | Yes |
| Favorites/recent Looks, local projects/rename/delete | Yes | Yes |
| Preview, share, automatic Photos save | Yes | Yes |
| Video duration | Maximum 30 seconds | No commercial cap |
| Output resolution | 720p ceiling, aspect preserved | Supported source resolution, including 4K target |
| Output FPS | Source-aware, maximum 30 | Supported source cadence, including 60 FPS target |
| Watermark | `shot by RENN` | None |
| Export count | No commercial quota | No commercial quota |

Free 60 FPS input becomes at most 30 FPS without changing duration/audio pitch. Preserve 24/25 FPS where appropriate. Pro does not upscale 24/30 to artificial 60 or invent resolution. “Unlimited” excludes commercial quotas, not disk/thermal/codec limits. No fixed arbitrary Pro duration/file-size limit; preflight real resource needs.

Free capture stops safely at 30 seconds. Free import over 30 seconds offers Pro or another source; **no automatic trim and no trim editor**. Existing longer projects remain accessible after Pro expiry; new exports revalidate current access. Previously rendered outputs remain playable/shareable.

Watermark wording is exact: `shot by RENN`. `RENN` uses Monoton with glyph colors R yellow, E amber, first N orange, second N red. Baseline placement bottom-right, layout rules in 02. No watermark toggle bypass for Free.

## P09 — Export experience

Show output summary before export. Long/high-quality jobs explain that processing may take time. Processing has real stages/progress, Cancel and “Keep the app open”; no fabricated ETA or guaranteed background completion.

Once a verified local result exists, automatically attempt Photos saving. Preserve local success independently of save failure. Result sheet has cassette cover, **Your video is ready**, verified **Saved to Photos** only when true, **Share**, **Watch in RENN**, and close to the origin. Cassette tap also plays the actual output. No normal-state extra Save/View in Gallery button. Failed Photos saving offers recovery without re-rendering. No forced post-export paywall.

## P10 — Onboarding and settings

Four animated onboarding pages: clean-to-retro transformation, 12 free Looks, source-audio Beat, and first cassette/creation. No name, account or upfront permissions/paywall. Next/Skip remain usable without waiting for scene animation. Page transition details and exact localized copy are in 02/03.

Settings is app-wide: RENN Pro card with gold crown and membership state, language System/Turkish/English, purchase restore/manage, permissions/storage/help/legal/about and optional diagnostics. It contains no Look/Beat/video-indicator controls. Supporting rows are implementation baseline, not additional creative features.

## P11 — Commerce

Monthly, annual and lifetime grant identical Pro access. Target prices: US **$2.99 / $14.99 / $29.99**; Turkey **₺49.99 / ₺249.99 / ₺599.99** respectively, subject to available Store price points. Runtime Store-localized prices are authoritative. No trial or campaign is specified. See 06 for purchase semantics and configuration.

## P12 — Explicit exclusions

No trim/crop/merge/speed/timeline tools; no music library/import/replacement audio; no name collection/login; no cloud project sync/media upload/social feed; no AI recommendations; no remote Look downloading; no project favorites; no free PiP resize or post-capture layout editor; no independent per-camera Looks; no commercial export-count limits; no mandatory paywall after valid Free export. HDR output, 8K/120 FPS export, iPad-specific UI and guaranteed background/resumable export are not promised V1 capabilities.
