# Vocabulary and spaced review personal fork implementation

Goal: iPad reading selection -> vocabulary -> offline FSRS review -> JSON restore -> unsigned device IPA.
Approved by the user 2026-10-22. UI may be designed for this personal fork using existing VReader styling (explicit exception to upstream rule 51). Work only under D:\AI. Public fork: murphyevergarden528-eng/vreader. No Anki, OCR, WebDAV vocabulary integration, stemming, notifications, or whole-book vocabulary coloring.

## Deliverables and interfaces
- SchemaV11 adds VocabularyEntry, VocabularyOccurrence, VocabularyReviewEvent. Book deletion never cascades into vocabulary. PersistenceActor owns all mutations and returns Sendable records.
- VocabularySelectionSnapshot captures selected term, exact available context, book identity/title, location and reader identity before selection cleanup. Readium, legacy EPUB, TXT/MD, PDF independent confirmationDialog, and native Foliate independent confirmationDialog must each expose the action.
- English key: NFC + whitespace normalization + fixed-locale lowercase. Repeated collection preserves definition and FSRS state, adding distinct sources. Term edit conflicts never merge review histories.
- swift-fsrs revision 4fbaf20184d62f82a9f44f343337c61a2c5483e9: explicit FSRS-6 default weights, retention .9, fuzz false, pinned default learning/relearning steps. Save card state and review event atomically. Duplicate/stale review submission rejected. No definition means not reviewable.
- Offline JSON version 1 includes entries, occurrences, algorithm configuration, state and review events; no keys or book files. Validate fully before one save; duplicate UUID/key skips the complete incoming card. Invalid version/data leaves storage untouched.
- UI: library vocabulary entry, search/all/due, editor/manual or explicit AI definition, flip/review four ratings, empty/done/error states, JSON importer/exporter. Chinese new UI, iPad rotation/split view/Dynamic Type.
- AI reuses AIService vocabulary requests with resolved provider and existing consent/key gates. No auto network on collection; cancellation/stale response never overwrites draft.

## Execution sequence
1. Restore GitHub CLI authorization, fork, branch codex/vocabulary-review. Add macOS cloud baseline unit tests and unsigned iphoneos build. Checkout current fork SHA, not upstream fixed SHA.
2. Independent plan audit (rule 47), then red tests, minimal core persistence/FSRS/backup implementation, targeted cloud test execution.
3. Reading adapters and UI, targeted end-to-end tests, independent implementation audit.
4. Regress migration/reading annotations, run iPad UI verification sequentially after unit tests, build Release IPA from tested SHA and check arm64/Info.plist/archive.
5. Download IPA, SHA256, revision and logs to D:\AI\vreader-build. Signing and real-device installation are separate verified milestones.

## Mandatory verification
- Save/relaunch/duplicates/multiple sources/book deletion/rename conflict.
- Four FSRS grades/due boundaries/stale and duplicate submissions/save failure atomicity.
- V10 actual pre-change store -> V11 retains old records.
- Export -> empty store restore equality/repeat import/corrupt and future backup/orphan refs.
- AI disabled/missing key/error/cancel/draft edited before response.
- EPUB both engines/layouts, PDF, TXT chunked/plain, MD, Foliate and converted Kindle; actual selection context and no cross-book/window capture.
- iPad portrait/landscape/split view/large type, highlights/notes/translation/position regression.

## Current evidence
- Clean upstream base b996ab4d828a180ae4b23d0b07d045b3d318c34f.
- Existing baseline build file incorrectly checks out upstream; will replace in personal fork workflow.
- GitHub CLI device authorization completed for murphyevergarden528-eng; personal fork and codex/vocabulary-review branch created. Connector lacks fork/dispatch, so authorized CLI is used.
- Local host Windows cannot run xcodebuild; missing cloud execution is a blocker, never counted as passing tests.

## Gate 2 audit corrections
- PDF and Foliate use their real independent confirmation dialogs; shared menu only covers other paths.
- Freeze context before menu dismissal; async DOM context is captured before enabling the action. Bind request to per-reader instance UUID, not only book key. TXT bilingual uses existing display-to-source offset mapping.
- Review mutation receives expected revision and unique operation UUID. Within the actor, perform fetch/check/schedule/write without await, save card plus event once; failed save rolls back. Duplicate operation returns unchanged; stale revision rejects.
- Register SchemaV11 in VReaderMigrationPlan and VReaderApp, update latest-version assertions without editing historical model sets. Actual V10 disk fixture includes book, annotation and position and is reopened as V11.
- Existing AI gates/readiness remain required; local save is independent of AI availability.

## Execution update 2026-10-22
- Plan audit passed round 2; test sources prepared before feature implementation.
- Cloud bootstrap corrected stdout/watchdog pipe lifetime and selected Xcode 26 for the existing Readium Swift 6.2 requirement.
- ARM64 runner run 39751000289 never acquired a runner and ended after 15 minutes; this is not feature RED evidence.
- Switched to the standard macos-15-intel runner (commit 9757dae); run 39754332012 has started and reached simulator boot.
- Feature production code and IPA remain pending actual test execution; no passing claim.
