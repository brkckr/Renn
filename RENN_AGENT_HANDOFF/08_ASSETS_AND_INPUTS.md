# Asset intake and outstanding inputs

The owner will source Look-related material. No production LUT/shader/grain pack has been delivered in this handoff. Do not turn missing assets into invented final Looks or stall unrelated engineering.

## I01 — Owner effect asset checklist

| Asset | Preferred delivery | Validation |
|---|---|---|
| Color LUT | 3D `.cube`, preferably 33³ or 64³ | Declared input/output color space and range, valid dimensions/data, identity/skin/gradient tests; Rec.709/SDR preferred |
| Shader source, if supplied | `.metal` plus helper includes/config/docs | Compiles on target, inspect resource/buffer assumptions, bounded GPU cost, deterministic timing; source license required |
| Non-Metal shader reference | `.glsl`, `.frag`, `.hlsl` plus license | Reference/porting input only; never treat it as drop-in iOS code |
| Grain still, if used | High-quality `.png`, preferably grayscale/seamless | Document bit depth, intended blend/range/scale; no baked watermark; alpha optional |
| Grain motion, if used | `.mov` or `.mp4` | Extension is only container: inspect codec, bit depth, FPS/duration, compression, loop seam, alpha if intended and blend rule |
| Visual target | Short reference clip, ideally paired original/treated | Identify desired color/texture/motion and what should not be reproduced |
| Rights | License text, author/source, proof of purchase where applicable | Must cover commercial application embedding/distribution of the asset/code, not only exported-video use |

Procedural shader grain is the default; a grain file is optional. Agent-authored Metal shaders are expected if suitable shader source is not supplied. LUT is a color transform, not tracking/grain/glitch by itself. Twelve Looks can share shaders/LUTs with different reviewed parameter presets; twelve independent shader programs or LUTs are not inherently required.

Do not feed Log-specific LUTs directly with SDR frames; they require an explicitly correct input conversion or replacement. Reject malformed `.cube` size/domain/nonfinite values with actionable errors. Do not assume `.metallib` from another build/device is a portable editable source; prefer `.metal` and compile with the pinned toolchain. The `.metallib` is a build artifact, not a required owner deliverable.

Suggested delivery structure per Look:

```text
look-stable-id/
  brief.md             # intended appearance, intensity, Beat behavior
  color.cube           # if needed
  shader/              # optional licensed source and includes
  grain/               # optional texture/video
  reference/           # target and original clips, if available
  LICENSE.txt
  source-info.txt      # author, source, allowed usage, color/blend metadata
```

Use a stable ID independent of localized display name. Create a catalog manifest with asset hashes, versions, color-space contract, default intensity, parameter ranges, grain mode, Beat mapping, licensed thumbnails and renderer compatibility. Agent controls schema; owner controls final artistic selection. Missing material can be replaced only by clearly labeled development fixtures until reviewed.

## I02 — Bundled design references

| Included path | Role |
|---|---|
| [allscreen.png](references/allscreen.png) | General non-onboarding/non-splash compositions, with explicit overrides in 02 |
| [splash.jpg](references/splash.jpg) | Vertical ribbon/bend geometry; apply four RENN colors |
| [onboarding.mp4](references/onboarding.mp4) | Curved page-transition language |
| [bottom bar.mp4](references/bottom%20bar.mp4) | Capsule expansion/morph into tools menu |
| [paywall.mp4](references/paywall.mp4) | Selected object/halo movement, adapted to three plans |
| [caset anim.mp4](references/caset%20anim.mp4) | Physical player, upright VHS collection and insertion |
| [cassette-screen-reference.png](references/cassette-screen-reference.png) | Extracted original frame at 2.75 seconds |
| Four `*-contact-sheet.png` images in references | Prior sampled-frame inspection, not exact easing measurements |

References are included as unmodified inspection copies, not licensed production layers. Embedded obsolete lettering is not app branding. No absolute external desktop path is required to use this package. If video playback is unavailable, contact sheets support initial structure inspection but do not prove a final motion match.

Final art still needed: original/licensed player rear/front/slot, case front/side/travelling cassette/shadow, icon family, onboarding demo clips, three paywall object variants and app icon. Simple vector placeholders can unblock prototypes; do not report them as final approved visuals. Existing uninspected external art archives are not assumed approved.

## I03 — Fonts

Monoton, Press Start 2P and Roboto actual font files (`.ttf`/`.otf`, with supported weights) and their license notices must be bundled correctly. Monoton's previously reviewed upstream license is SIL OFL 1.1; recheck the license accompanying the delivered font and preserve notices. Verify actual files for Turkish glyphs and allowed embedding. Styling glyphs in four colors does not require editing the font binary. No font files or license texts are included yet.

## I04 — Input / readiness ledger

| Item | Status | Who / next action |
|---|---|---|
| App name / bundle ID | Settled: RENN / tzlapp.studio.renn | Agent uses exactly; owner provisions corresponding accounts |
| Product scope and Free/Pro | Settled in 01 | Implement; do not reopen legacy alternatives |
| Stack/MVVM/DI | Specified engineering baseline | Agent implements and validates with pinned toolchain |
| 12 final Looks/names/parameters | Missing artistic deliverables | Owner supplies candidates; agent integrates; visual review before release |
| LUT/shader/grain packs | Owner sourcing; not delivered | Intake/license/compatibility checks; agent can build diagnostic shader/grain first |
| Final fonts/icon/cassette layers/demo footage | Not delivered as production assets | Source/create licensed materials and obtain visual review |
| Motion geometry/timing | Concrete starting values supplied | Agent prototypes/reference-compares; report adjustments |
| Watermark legibility/collision fixtures | Specified, not visually validated | Agent produces actual 720p results for review |
| Mac/Xcode/real-device access | Not verified by this package | Required for native build/device tests |
| Signing/Apple Developer/App Store Connect | Not configured here | Owner supplies access/configuration through appropriate secure setup |
| Firebase app/config | Required provider, not configured here | Register exact bundle ID; supply client config; separate environments |
| RevenueCat app/products/entitlement | Required provider, not configured here | Map real monthly/annual/lifetime products to pro and test sandbox |
| Product prices | Target values settled | Validate available Store price points; runtime localized Store prices |
| Codec/HDR/VFR/capture configuration | Technical proof required | M02 ADR and actual media fixtures; no untested quality claims |
| Dual-Cam capability/performance | Required, not tested | Supported/unsupported device matrix at M04 |
| 4K60/long-video performance | Required target, not tested | Bounded-memory M02/M09 measurements |
| Support/privacy/terms URLs and disclosures | Not supplied | Owner-specific documents/hosting; verify shipping providers |
| Store metadata/screenshots/age rating | Not prepared | Build-dependent release assets and owner review |

No account secret, dummy purchase price, placeholder Look or screenshot brand may be presented as production-ready. This ledger is the remaining implementation/release dependency list, not an unresolved product-design questionnaire.
