# Media, effects and durable data contract

This is the implementation baseline, not measured hardware capability. Validate codec/color/capture routes in the early media prototype before building the full catalog.

## V01 — Supported media and automatic output

Launch input target: ordinary H.264/HEVC video in MOV/MP4, SDR and common iPhone HDR input through a verified SDR conversion path. Output baseline: MP4, SDR Rec.709, supported hardware encoding. Use H.264 for broadly compatible ordinary output; evaluate HEVC for high-resolution/high-FPS jobs when supported, and document the actual decision policy before production. Never silently reduce resolution/cadence to conceal an unsupported encoder. A supported-input failure needs a clear reason and preserved source.

Pro's 4K60 target means maintaining supported resolution/cadence, not HDR preservation or bit-identical re-encoding. HDR must be properly tone-mapped to SDR and disclosed in summary. HDR output, 8K and 120 FPS output are not promised. Higher-than-tested inputs must receive a truthful unsupported-format path, not an arbitrary paid upgrade suggestion. Cinematic depth/focus re-editing is not supported; use a conventional rendered representation. Unresolved Photos slow-motion time mappings require a standard exported video or a tested resolved representation; never accidentally speed up/slow down content.

Aspect is measured after the preferred transform/rotation and clean aperture. Normal RENN and final Dual-Cam capture are portrait 9:16. Imported portrait/landscape/square retain ratio. Free dimensions fit both short edge ≤720 and long edge ≤1280, never upscale. Examples: 3840×2160 →1280×720; portrait equivalent →720×1280; 1080 square →720 square. Round down to codec-compatible even dimensions with at most rounding-level aspect error, no creative crop/stretch. Pro preserves supported display dimensions with only required encoding alignment. Low-resolution inputs remain low-resolution.

Preserve asset playback duration and rational timing. Free retains source cadence up to 30 FPS; examples 24→24, 25→25, 29.97→29.97, 59.94→29.97, 60→30. Pro retains supported cadence up to the tested 60-class ceiling. Do not interpolate new motion or independently round each PTS.

For variable-frame-rate input, inspect actual timestamps rather than `nominalFrameRate` alone. First prototype must document and test an output timing policy (preserved legal VFR timestamps versus source-derived CFR sampling). Choose a supported deterministic route, show actual output summary, and preserve audio/duration within one output-frame interval. This is a technical validation gate, not permission to invent a new UI setting. Persist the resolved rational rate/time mapping in each job.

Automatic camera format selection depends on tier, actual camera combination and validated device capabilities. Start the prototype with 1080p30; this is not a commercial Pro ceiling. Production Pro selection targets the highest validated configuration up to 4K60; Dual-Cam may have a lower physical ceiling disclosed before recording. Free may capture a suitable source format for 720p/≤30 output. Do not switch formats or downgrade mid-recording without stopping/explaining.

## V02 — Capture and clock ownership

Capture records clean media, while independent GPU preview applies the recipe. App controls/countdown/real recording status are not recorded into clean source pixels. Use sample PTS/shared session time, not Date or UI timers, for synchronization. Establish one accepted capture origin, preserve audio offsets, and trim pre-origin samples correctly. Never zero video and audio independently.

SourceRecorder has bounded queues. Repeated stop/free-limit/interruption requests converge on one finalization. Accept a project as ready only after tracks/duration/readability validate. An unfinalized file after process termination may be unusable; mark interrupted rather than promising recovery. Preserve valid finalized partial media where possible.

Mic denied: offer silent capture with Beat unavailable. Camera denied: import path and relevant Settings recovery. Audio route changes/interruption/background/critical pressure: stop coherently and finalize best-effort; do not reset clocks or hide an interruption. Ordinary camera switching is pre-record only.

Free duration boundary is rational 30 seconds; stop source delivery before samples outside the allowed interval and finalize. Encoder padding must not expose a video duration over the policy boundary. Very short playable takes are allowed if the pipeline supports at least one valid video frame; there is no arbitrary one-second commercial minimum.

## V03 — Dual-Cam

Probe MultiCam support and the selected device/format pair at runtime. Two clean video tracks/files, source-specific transforms/mirror flags and common offsets plus exactly one shared audio track form one project. Record shared audio in one designated source or separate audio asset and declare ownership; never mix duplicate mic tracks.

Start/end with a valid common playable interval. Both sources must validate for readiness. Missing stream/pressure stops the take coherently; no hidden single-camera substitution. Bounded buffers and disk estimation account for both sources.

Recipe stores initial corner/main camera and ordered swap events `(sourceTime, mainCamera)`. Apply events at the same media boundary in preview/export; coalesce impossible repeated inputs, do not store only final layout. Pre-record PiP corner selection stays fixed during take. Use the same shared Beat timeline for both images.

Baseline render order: normalize each source → apply same Look/Beat to each source → compose main/PiP using timestamped layout → composite OSD → policy watermark → encode. This ensures one set of readable overlays. Validate independent orientation/mirroring so text never flips. Baseline front preview and exported front source use the same persisted mirror choice; no additional user mirror editor is added.

## V04 — Renderer and effects

Shared RenderEngine consumes immutable recipe, media time, source frames and output dimensions. Preview may use reduced rendering resolution; export does not silently drop effects. Core Image/Metal share GPU resources where possible; avoid UIImage/CPU copies per frame. Await GPU completion before writer append. Keep bounded pixel-buffer pools, initially at most three frame sets in flight; report decoder/encoder-owned memory separately.

Single-source pipeline:

```text
decode/capture buffer
→ preferred transform, clean aperture, explicit color normalization
→ persisted source mirror (no user crop)
→ LUT/tone mapping for Look
→ procedural analog texture/artifacts + effective Beat modulation
→ OSD
→ Free watermark if required
→ explicit output color encoding and encode
```

Honor color primaries, transfer function, YCbCr matrix, range and HDR metadata. Retagging HLG/PQ as SDR is not tone mapping. Prove one shared SDR conversion path and do not apply it twice. Mark untested HDR variants unsupported rather than displaying clipped footage as correct output.

Every Look definition has stable ID/version, localized name/description, actual family, LUT reference if any, shader parameter snapshot, defaultIntensity/mapping, grain definition, supported render version and reviewed fixture IDs. No tier property is needed to lock Looks: all are free. Persist resolved parameters so later catalog tuning cannot silently alter existing projects.

Procedural grain is baseline. Optional owner-supplied grain PNG/video assets may be evaluated; no external asset is required just to implement grain. Shader source is Metal; LUT import supports validated 3D `.cube`. See 08 for asset intake and licenses.

Random effects derive from project seed, source media time, spatial coordinates and render version. Use a declared fixed noise tick (baseline 60 ticks/source-second) independent of export frame count. Do not seed from wall time, task invocation or playback speed. Repeated render/seek at identical recipe/time reproduces pre-encode pixels within GPU tolerance. FPS changes must not speed up texture motion.

Look intensity 0 bypasses the Look color/artifact layer; Beat is an independent modulation layer if enabled. Beat intensity 0 must equal Beat off for the same Look/recipe. OSD/watermark are not attenuated by either. Bounded Beat effects must not introduce full-frame strobing or uncontrolled shake. Reduced-effects rendering, if used to respect reduced motion for video previews, must be represented in the effective recipe and shared with export rather than secretly showing a different result.

## V05 — Beat analysis

One capture audio sample stream feeds recorder and live analysis; no competing mic graph. After recording, analyze encoded source audio to build the canonical timeline. Live causal response may differ slightly because of compression/latency; do not promise pixel-identical live capture vs final result. Project preview and export must use the same canonical analysis.

Baseline algorithm (versioned, tunable with evidence): Float32 PCM, mono analysis downmix, 48 kHz; preserve original mono/stereo audio for playback/output. 1024-sample Hann window, 512 hop; RMS, positive spectral flux and low/mid/high energies. Bands start at 20–250 / 250–2000 / 2000–16000 Hz, clamped to available Nyquist. Timestamp each window at its ending sample, including source audio offset.

Use causal rolling two-second normalization with finite bounded denominators, initial silence gate −55 dBFS, onset threshold mean +1.5 standard deviations, refractory period 160 ms, initial envelope attack 20/release 150 ms. These are engineering starting constants, not proven DSP quality. Silence yields zero onset and decaying energy; do not amplify noise into fake beats. All outputs finite/clamped 0...1.

Preserve algorithm state across decode chunks. Cache by source fingerprint/audio track/time mapping/algorithm version/constants; intensity/mute do not invalidate analysis. Seeking samples the same source-time signal, not an independent wall-clock analyzer. Do not analyze unrelated live sound while playing old clips.

## V06 — Import and preview

Use PhotosPicker/PHPicker selected-media access; avoid requesting full Photos-library access just to import. Copy provided temporary media into app-owned staging while access is valid, then inspect/commit. Never persist only a temporary picker URL or external identifier. iCloud transfer has cancellable progress when available and indeterminate waiting otherwise.

Validate readability, tracks, duration, dimensions, actual decode/color support and disk. Free >30s is a product gate before project readiness where possible; do not silently trim or repeatedly copy known oversized-duration media. Cancellation removes only this import's staging data. No obsolete fixed 2 GiB/10-minute cap: resource feasibility determines acceptance for Pro.

AVPlayer owns canonical audio/playback clock. AVPlayerItemVideoOutput or an equivalent validated synchronized path supplies frames to RenderEngine. Seek cancels stale requests and renders correct timestamp while paused. Loop and before/after do not change recipe duration. Stall/error states must not leave unrelated audio playing behind a frozen result.

## V07 — Data model

Use local-only SwiftData with explicit schema versions/migrations; CloudKit disabled. SwiftData is metadata authority, not a competing JSON manifest database. Optional exported diagnostic manifests are non-authoritative and contain no private paths/content. There is no installed legacy database assumed by this handoff; migrations target actual schemas created during development/release.

| Record | Minimum fields |
|---|---|
| Project | UUID, schema version, created/updated dates, persisted displayName, source mode/readiness, source references, recipe revision, recipe, last successful output ID, interruption/deletion state |
| Source | Relative app path, fingerprint, rational duration/start offset, display/storage dimensions, preferred transform/mirror, color info, tracks/audio ownership, cadence metadata |
| Recipe | Render/Look versions and resolved parameters, intensity, stable seed, Beat flag/intensity/version, audioMuted, OSD version/flags/frozen date, initial dual layout + timed swaps |
| ExportJob | UUID/project/revision, immutable recipe/access/output-policy snapshots, resolved dimensions/timing/codec/color/watermark version, state, progress checkpoint, temp/final path, typed error |
| Output | Validated path/media properties, source recipe revision, render complete time, Photos save state/identifier where available, share-use lease |
| LookPreferences | Favorite IDs and ordered last-four-distinct IDs |

No trim/crop fields or editable timeline are needed. Domain rational time uses integer value/timescale with validation. Persist only relative controlled paths; reject traversal, zero timescales, nonfinite parameters and invalid date/range values. Validate catalog schema before use.

Layout: `Application Support/Projects/<UUID>/sources/`, `outputs/`; temporary job area for `.partial` files; Caches for recomputable posters/Beat. Poster cache key includes project ID, recipe revision, render version. Use a deterministic representative time (baseline near one second or midpoint for short clips); render that project's actual recipe, not unrelated demo art. No user cover-picker feature.

Names default to a localized date-based “Tape · Sep 27, 2026 · 14:35” equivalent, generated once. Baseline maximum 80 user-perceived characters, trim surrounding whitespace/reject empty, plain single-line text. Duplicate names are allowed; paths use UUID. Rename never re-renders. OSD date never renames the project.

## V08 — File transactions, recovery and storage

Database and files are not one atomic transaction. Persist preparation/job state, write temporary file, finalize and validate, atomically move within the volume, then mark DB ready. Recovery reconciles either side of a crash. Do not mark success based on file existence alone. Never wipe a database silently after migration failure; unknown future schema is read-only with update guidance.

Debounce recipe saves up to 500 ms and flush at safe navigation transitions. Running export keeps its immutable revision; new adjustments affect future jobs only. Sources are never cache-evicted. Keep latest successful output per project; retain older outputs while in a share/playback lease, then clean obsolete ones. Failed export cannot replace the previous good result.

Storage preflight estimates both sources, any normalization intermediate, output from measured bitrate/duration, 25% overhead and baseline 250 MiB reserve. Recheck during work; estimates are not guarantees. ENOSPC preserves source/recipe/previous output and cleans this job's partials. Pro “unlimited” never skips preflight.

Baseline device-backup policy excludes regenerable caches and large app-owned media from backup; metadata recovery cannot restore excluded videos. Explain local-only projects and possible loss on app deletion/device loss; restore purchases does not restore media. A future backup/sync policy is a separate product change.

Deletion requires confirmation, marks deleting state, respects active capture/export/share leases, removes only owned files (including both dual sources), then removes metadata. Either block active-project deletion with explanation or finish cancellation before deletion; never remove live files. Startup resumes partial cleanup idempotently. No PhotoKit deletion of gallery originals/outputs.

## V09 — Export state machine and saving

`validating → preparing → rendering → finalizing → local result committed → savingToPhotos → completed OR saveFailed`.

Before local commit: explicit cancel/failure/interruption retains sources and last good output, removes only job partials, permits a new job. After local commit: save failure cannot become render failure; retry only Photos saving. Reopening result uses the same output. Once PhotoKit submission begins, do not claim Cancel can undo its external save.

Resolve access before creating job; unknown access may run valid Free policy and offers restore/retry for Pro. Show actual resolved summary and obtain explicit export intent. Snapshot effective access so expiry mid-job does not secretly downgrade that authorized output. Revalidate new/retried render jobs.

Progress reflects actual decoded/rendered duration or frame count with separate finalization/saving stage; never show complete before validation. ETA only after enough measured data and labeled estimate. Long/high-quality message states source duration/resolution/FPS and asks to keep app open.

Foreground export baseline: brief system interruptions may return safely, but background/lock/suspension can interrupt work. Use available cleanup time to journal/stop safely; do not promise background completion or resume from an arbitrary frame. Restart interrupted render from source on explicit retry. No GPU job is guaranteed to complete while suspended.

Validate final file tracks, duration, dimensions, cadence, readable sample frames/audio before result commit. PhotosSaver requests add-only permission when needed. Track `notAttempted/inFlight/saved/failed/uncertain` per output. Saved output is never submitted again. If the process dies after external save but before durable confirmation, do not blindly auto-save again: show uncertain status and allow an explicit retry with duplicate risk explained. Gallery and DB cannot be made one atomic transaction by a boolean flag.

Result Share/Watch use the validated output, not source or a new recipe preview. Share-sheet completion/cancel is not proof of posting. Permission-denied save keeps Share/Watch available and explains Settings recovery. Finalized output remains available after entitlement expiry.
