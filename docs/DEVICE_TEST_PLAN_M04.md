# M04 device test plan (Dual-Cam)

Dual-Cam cannot run on the Simulator (no multi-camera support), so everything below is device-only
evidence (07 test level 5). Setup is the same as `DEVICE_TEST_PLAN_M02.md`. Record the iPhone model,
iOS version and thermal state per run; write results into `docs/IMPLEMENTATION_LEDGER.md`. A step
not run stays "not run".

Simulator/CI already covers: composition rules, export of two synthesized sources with a swap
(colours checked before/after), the side-by-side preview compositor and the flow state machine.

| # | Scenario | Expected | Evidence |
|---|---|---|---|
| 1 | Supported iPhone: + → Record with both cameras | Composed live preview: rear full frame, front rounded inset top-right, DEV Look on both | Screenshot |
| 2 | Unsupported iPhone (no multi-cam) | Row stays visible; explanation, "Record with one camera" and "Import video"; no paywall | Screenshot |
| 3 | Pick each of the four corners before recording | Inset moves; picker disappears while recording | Screen recording |
| 4 | Record ~15 s, tap swap 3 times at distinct moments | Immediate cut each time; timer continues; no drag/resize possible | Screen recording |
| 5 | Open the project preview | Plays composite with one sound track; swaps happen at the same moments as during recording | Screen recording |
| 6 | Export (Free) | 720×1280, ≤30 FPS, watermark above the inset if the inset is bottom-right; swaps at the same frames as preview; sound in sync | Output file + frame grabs around each swap |
| 7 | Text held to the front camera | Readable (not mirrored twice) in preview and export, same as the live viewfinder | Frame grab |
| 8 | Let a Free take run | Stops at 0:30 by itself; project duration ≤ 30 s | Export summary |
| 9 | Deny microphone | Silent Dual-Cam take; project has no sound; Beat unavailable | Screenshot |
| 10 | Phone call / background during recording | Take stops coherently; both sources saved or neither; project opens | — |
| 11 | Heat the phone (long session) | If the system drops a camera, the take stops with an explanation; never a single-camera project | Notes + thermal state |
| 12 | Projects tab | Dual-Cam case shows the composite poster | Screenshot |
| 13 | Delete the Dual-Cam project | Both source files removed (Settings > iPhone Storage shrinks) | — |

Measurements: dropped frames per
source, and export time for a 30 s Free and a 30 s Pro Dual-Cam take.
