---
gate: 4
kind: implementation-audit
feature: personal-vocabulary-review
plan: dev-docs/plans/20261022-vocabulary-review-personal.md
rounds: 3
final_verdict: PASS-source-audit
auditor: independent implementation_audit agent
---

# Independent implementation audit

## Round 1
1. High H1: FoliateSpikeView loads foliate-bundle.js, while only foliate-host.js had been modified. The new context would not reach the shipped application. Fixed by rebuilding with the repository build-bundle.sh and pinned esbuild 0.28.0; bundled output and both scripts pass node --check.
2. Medium M1: VocabularyReviewView kept the same refreshed card after stale/not-due errors even if another window had already moved it into the future. Fixed by deriving eligible cards through VocabularyStudyQueue; retain the same card only if still eligible, otherwise choose the next eligible card. Added persisted two-window stale-submission regression.
3. Medium M2: Readium missing/snippet context and chunk-edge text could be presented as a complete original sentence. Fixed by requiring confirmed sentence boundaries in partial text. Unknown contexts remain empty, with term/location retained and the existing editor prompt asking the user to fill the sentence. Added exact UTF-16, emoji, truncated snippet and chunk-edge cases.

## Round 2
H1 and M1 closed. M2 chunk handling closed, but nonempty Readium before/after snippets could still be incomplete (before='ith an ', highlight='echo', after=' ret'). Further fix: build the exact selected NSRange from before/highlight UTF-16 lengths, then use boundary-required extraction. No full-text guessing.

## Round 3 focused verification
M2 closed after inspecting extraction and missing/truncated/full/emoji regressions. No new findings. Remaining Critical 0 / High 0 / Medium 0 / Low 0.

## Confirmed invariants
- SchemaV11 adds independent entities without Book cascade ownership.
- Actor mutation has no intervening await; review card and event save together, rollback uses the same operation context.
- Import validates the whole document before one save; history is replayed and UUID/normalized-term duplicates skip complete cards.
- FSRS pinned revision, FSRS-6 defaults, .9 retention and disabled fuzz match the approved configuration; MIT notice is retained.
- Existing AI consent, provider/key and feature gates are reached; draft identity prevents stale responses from overwriting edits.

## Evidence boundary
This is source review, not a build or UI pass. Swift compilation, disk migration, unit tests and actual reader/iPad UI remain mandatory cloud checks. The user explicitly allowed tests-first implementation in parallel with cloud execution on 2026-10-23.

## Targeted cloud compiler repair review
After run 39817216411, the source/review/card map-sort chains were split into explicitly typed arrays and separate sorting/loops to avoid two Swift type-inference timeouts. The independent auditor confirmed unchanged sorting keys, conversion/error order and transaction boundaries. Actual compilation remains a cloud gate.
