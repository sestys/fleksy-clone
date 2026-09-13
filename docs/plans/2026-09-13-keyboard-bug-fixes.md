# Keyboard bug fixes

Approved direction: implement the fixes described in the implementation review, preserving the core/UIKit split. Use focused patches rather than a broad engine rewrite.

- [x] Add failing regression tests for Enter replay, Unicode deletion, mid-word completion, stale document state, language-scoped learning, recovered-word accounting and current personal frequency.
- [x] Add document snapshots (optional contexts, selection and identity), invalidate pending state after external edits, and suppress replacement inside words/selections. Enter ends correction eligibility. Delete by grapheme count and normalize lookup independently.
- [x] Give commits their originating language and learning ownership. Read current personal frequencies when ranking cached vocabulary.
- [x] Extract touch lifecycle decisions into a small tested core type; cancel holds on movement, make simultaneous lift order deterministic, and wire accessible activation.
- [x] Fix candidate notice interaction, redundant rendering, onboarding directions and emoji accessibility labels. Respect field correction/capitalization traits.
- [x] Exercise runner failure paths with command stubs, preserve real build/test failures, and make runner executable.
- [x] Run all core tests, build and full simulator tests. Inspect final diff and record any environment limitations.

Validation: SwiftPM regression tests, shell runner integration tests, Xcode build and the full existing XCUITest suite. No feature expansion, dictionary replacement, or persistence redesign is required for this bug-fix pass.

## Verification

- 142 FleksyCore tests passed.
- Full simulator run passed 10 of 11 UI tests and all 3 accessibility tests. The remaining UI test still looked for the learning notice as a button; after changing that query to a static text label, its complete learn/forget flow passed on rerun. No production code changed after the full run.
- Runner failure-propagation tests, shell syntax checks and git diff whitespace checks passed.
- Independent read-only review found no blocking issues.
- Validation used iPhone 17 / iOS 26.5 Simulator; physical-device VoiceOver was not exercised.
