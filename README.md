# Fleksy Clone

A personal iOS keyboard extension that recreates the Fleksy typing experience:
flat colour-band keys, gesture editing, quick swapping of autocorrected words, and
Czech + English with diacritic-aware correction ("delam" → "dělám").

## Gestures

| Gesture | Action |
|---|---|
| Swipe right | space (and autocorrect the word). Swipe right again: period |
| Swipe left | delete the previous word |
| Swipe up / down | next / previous correction for the last word (down also restores what you typed) |
| Swipe on the space bar, or two-finger swipe left/right | switch Čeština ⇄ English |
| Two-finger swipe down | hide the keyboard |
| Hold a letter | accent popup (ě š č ř ž ý á í é ú ů …), slide to choose |
| Hold backspace | repeat delete |
| Double-tap shift | caps lock |
| Tap the dot left of the suggestions | settings: theme, languages, QWERTZ/QWERTY, autocorrect, key height |

## Layout

```
Packages/FleksyCore     pure Swift engine (layouts, gestures, lexicon, corrector, composer, themes) + unit tests
Keyboard/               the keyboard extension (custom-drawn UIKit view)
App/                    host app: onboarding + test field
UITests/                XCUITest that types on the real keyboard in the Simulator
Resources/Dictionaries  cs.txt / en.txt frequency lists (CC-BY-SA 4.0, see LICENSE.txt)
scripts/simulator.sh    build / install / test on the Simulator
```

## Build

Requirements: Xcode 26, `brew install xcodegen`.

```sh
xcodegen generate                       # regenerate FleksyClone.xcodeproj from project.yml
(cd Packages/FleksyCore && swift test)  # engine unit tests
scripts/simulator.sh all                # build, install in the Simulator, enable the keyboard, run UI tests
```

## Run on your iPhone

1. Open `FleksyClone.xcodeproj` in Xcode, select the `FleksyClone` target and set your
   personal team under Signing & Capabilities (do the same for `FleksyKeyboard`).
   Change the bundle identifiers if the defaults collide with something on your account.
2. Connect the phone, pick it as the run destination and press Run.
3. On the phone: Settings › General › Keyboard › Keyboards › Add New Keyboard… › Fleksy Clone.
   Full Access is *not* required; everything runs on-device.
4. In any text field hold the globe key and choose Fleksy Clone.

With a free personal team the app must be reinstalled every 7 days.

## Screenshots (iPhone 17 simulator, iOS 26.5)

| English | Czech + accent popup result | Midnight theme | Settings |
|---|---|---|---|
| ![](docs/screenshots/english.png) | ![](docs/screenshots/czech-accent.png) | ![](docs/screenshots/midnight.png) | ![](docs/screenshots/settings.png) |
