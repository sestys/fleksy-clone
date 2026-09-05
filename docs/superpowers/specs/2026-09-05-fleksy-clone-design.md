# Fleksy clone for iOS — design

Personal-use iOS custom keyboard that reproduces the Fleksy typing feel:
flat, borderless colourful keys, gesture-driven editing, easy swapping of
autocorrected words, and quick Czech/English switching. Not in scope:
context-aware (n-gram / neural) prediction, emoji keyboard, cloud sync.

## Assumptions (made without user confirmation)

- Czech layout is QWERTZ; diacritics via long-press accent popups and via
  diacritic-insensitive autocorrect ("delam" -> "dělám").
- Autocorrect is dictionary based (edit distance + keyboard proximity +
  word frequency), not contextual. The user said this is acceptable.
- Settings live inside the keyboard (no App Group needed, works with a free
  personal signing team). Host app only carries onboarding + a test field.
- Word lists: hermitdave/FrequencyWords (OpenSubtitles 2018, CC-BY-SA 4.0),
  top 50k for cs and en.

## Gestures (Fleksy semantics)

| Gesture | Action |
|---|---|
| Tap key | insert character |
| Swipe right (1 finger) | insert space; commits autocorrect of the current word |
| Swipe right again immediately after a space | replace the space with ". " (period) |
| Swipe left | delete previous word (or trailing whitespace + word) |
| Swipe up | cycle the last corrected/typed word forward through candidates |
| Swipe down | cycle backward (first swipe down returns to what was typed) |
| Swipe left/right on the space bar, or 2-finger horizontal swipe | switch language cs <-> en |
| 2-finger swipe down | dismiss keyboard |
| Long-press letter | accent popup (slide to choose) |
| Hold backspace | repeat delete |
| Double-tap shift | caps lock |

## Architecture

```
Packages/FleksyCore   pure Swift, no UIKit, `swift test` on macOS
  KeyboardLayout      keys, rows, per-language layouts, accent variants
  GestureClassifier   (start, end, duration, fingers) -> tap/swipe/longPress
  Lexicon             word -> frequency, prefix completions
  Corrector           candidate generation and ranking
  Composer            editing state machine over a TextDocument protocol
  Theme               colour presets as plain RGBA values
Keyboard/             UIInputViewController + custom-drawn KeyboardView,
                      CandidateBar, AccentPopup, SettingsPanel
App/                  SwiftUI onboarding + test text field
UITests/              XCUITest driving the keyboard on the Simulator
```

The Composer is the only place that mutates text. It receives high-level
events (`.character`, `.space`, `.swipe(.up)`, ...) and talks to the
document through `TextDocument` (insert / deleteBackward / contextBefore),
so the whole typing model is unit-tested with a fake document.

## Correction model

On word commit (space / punctuation / swipe right):
1. If the typed word is in the lexicon (case-insensitive) keep it.
2. Else rank lexicon words within length +/-2 by
   `score = -editCost(typed, w) + log10(freq) * 0.35`, where substitutions
   between keyboard-adjacent keys cost 0.6, a diacritic-only difference
   costs 0.15, other edits cost 1.0. Only replace when the best candidate's
   edit cost <= 1.2 (short words) or <= 2.0 (>= 6 letters).
3. Remember `(typedWord, candidates, index)` so swipe up/down and the
   candidate bar can swap the committed word in place by deleting
   `current.count + trailing` characters and re-inserting.

Candidate bar shows, while typing: the raw word plus top completions;
after commit: the candidate list with the chosen one highlighted.

## Testing

- `swift test` in Packages/FleksyCore covers layouts, gesture classification,
  correction ranking, and the Composer event model.
- XCUITest on the iPhone simulator: enable keyboard via simctl
  `defaults write -g AppleKeyboards`, type with coordinate taps + swipes,
  assert the host text field content. Screenshots via `simctl io screenshot`.
