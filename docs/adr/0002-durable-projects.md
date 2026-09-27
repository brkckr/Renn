# ADR 0002: Durable projects (M01)

Status: accepted. Date: 2026-09-27.

## Decisions

1. **Split of responsibilities.**
   - `RENNDomain`: `ProjectRecord`, `Recipe` (Look, intensity, seed, Beat, mute, indicators with
     frozen stamp date, Dual-Cam corner + ordered swap events), `SourceReference`,
     `OwnedRelativePath`, and the backend contracts `ProjectMetadataStoring` / `OwnedFileStoring`.
   - `RENNStorage` (new package module): `ProjectLibrary` (the `ProjectStoring` authority that
     orders commits, deletions, leases and reconciliation) and `FileSystemOwnedFileStore`.
     Both use only Foundation, so the crash-window tests run on Linux with real directories.
   - App: SwiftData adapters (`SwiftDataProjectMetadataStore`, `SwiftDataLookPreferencesStore`),
     `RENNSchemaV1` + `RENNMigrationPlan`, CloudKit disabled.

2. **SwiftData stores domain JSON for recipe and sources.** Domain types validate themselves on
   decode (no traversal paths, positive timescales, finite parameters). A row that cannot be
   decoded makes the whole metadata read fail, so reconciliation never mistakes that project's
   files for orphans. The database is never wiped; a store that cannot be opened (e.g. created
   by a newer app) shows "projects unavailable" and nothing is deleted.

3. **Commit order (05 V08).** Insert `.preparing` → move staged sources (same volume) →
   verify fingerprints → `.ready`. A failure after media moved keeps the media and marks the
   project `.interrupted`; recorded takes are never deleted by a failed commit.
   Reconciliation completes a `.preparing` project only when every source fingerprint matches
   (file existence alone is not success).

4. **Delete order.** Refuse while leased → `.deleting` (hidden) → remove the project directory
   → remove metadata. An interrupted deletion finishes on next launch. Only the project's own
   directory can be removed; photo-library originals and exported videos in Photos are never
   touched.

5. **Per-launch temporary directories.** Staging and job partials live in
   `tmp/RENN/Staging/<launch>/` and `tmp/RENN/Jobs/<launch>/`. Reconciliation removes other
   launches' directories. An mtime cutoff was tried first and rejected: file timestamps use a
   coarse clock and swept a file staged in the current launch (found by the Linux tests).

6. **Fingerprint.** Byte size + FNV-1a over the first and last 1 MiB. Change detection only,
   not security; avoids hashing multi-GB 4K sources.

7. **Serialization.** `ProjectLibrary` serializes operations across suspension points with an
   internal async lock (actor reentrancy guard); concurrent writers at the same recipe revision
   commit exactly once (tested).

8. **Backup.** The `Projects` directory is excluded from device backup (baseline policy);
   Settings already explains projects are local to the iPhone.
