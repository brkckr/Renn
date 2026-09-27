# ADR 0003: Media pipeline decisions (M02)

Status: accepted for the prototype; every item marked **device** still needs physical-iPhone evidence
before it can be called validated (07 release gates). Date: 2026-09-27.

## Output container and codecs (05 V01)

- MP4, SDR Rec.709 color tags on every export.
- H.264 when the output is ≤ 1920×1080 pixels and ≤ ~30 FPS; HEVC above that (4K, 60 FPS).
  Bit rate: 0.11 bits/pixel/frame (H.264) or 0.07 (HEVC), minimum 1 Mb/s. **device:** quality,
  encode speed and hardware availability on the lowest admitted iPhone.
- Audio: decoded to 16-bit PCM and re-encoded to AAC (96 kb/s mono, 192 kb/s stereo) instead of
  passthrough, so any source audio codec produces a valid MP4. Duration and pitch are unchanged.

## Timing and cadence (05 V01)

- Output keeps the **source presentation timestamps** of kept frames; nothing is retimed or
  interpolated. `CadenceLimiter` keeps one frame per output slot (grid anchored at the first frame,
  1/8-slot tolerance), so 60→30, 59.94→29.97, 50→25 and 120→30 keep every n-th frame, and jittered
  VFR input keeps one frame per slot without bursts. VFR is therefore preserved as legal VFR at or
  below the policy ceiling (the "preserved legal VFR timestamps" option in 05 V01).
- Source cadence ceiling is read from `minFrameDuration` (actual timestamps), falling back to
  `nominalFrameRate`.
- One shared origin (video track time range start) for video and audio keeps the source A/V offset.
- Validation: output duration must match the source within one output frame + one source frame + 50 ms,
  dimensions must equal the policy, audio presence must match the plan.

## HDR (05 V01)

- HLG/PQ sources are detected from the format description and disclosed in the export summary.
- Conversion route: the reader output requests Rec.709 color properties, and rendering happens in an
  extended-linear working space with Rec.709 output. **device:** this route has not been proven to
  tone-map rather than clip on real iPhone HDR footage. Until device fixtures pass, HDR quality is
  unverified and must not be advertised.

## Rendering (05 V04)

- One `RenderEngine` (Core Image on a shared Metal device) builds the same graph for preview and
  export; preview differs only by output size. GPU work completes before the writer append.
- M02 ships a single labelled development Look (`dev.diagnostic`): desaturation/warmth, vignette and
  grain. It is a pipeline fixture, not one of the twelve RENN Looks.
- Grain is deterministic: an infinite random field offset by (project seed, media tick at
  60 ticks/second). The simulator test checks that the same recipe and time reproduce identical pixels.
- The Free watermark is drawn once, after effects, and before-after bypass never removes it.

## Capture (05 V02)

- Prototype format: 1080p30 portrait via connection rotation (90°), front camera mirrored.
  **device:** 4K/60 format selection by tier and capability is future work (07 performance targets).
- Clean samples are written by `SourceRecorder` with AVAssetWriter from `AVCaptureVideoDataOutput` /
  `AVCaptureAudioDataOutput`; the preview renders the Look on a separate path, so no UI enters the file.
- Origin is the first video sample; earlier audio is dropped. Free limit: samples at or after
  origin + 30 s are refused and one `limitReached` event stops the take. Stop, limit and
  interruption converge on one finalization. Dropped frames are counted (not yet surfaced).
- **device:** A/V sync, dropped-frame rate, camera readiness time and thermal behavior (07 targets).
