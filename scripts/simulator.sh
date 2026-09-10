#!/bin/bash
# Build, install and exercise the Fleksy Clone keyboard in the iOS Simulator.
#
# Three tiers, because driving the real keyboard is slow and most changes do not need
# it. Every tier runs the unit tests first: they are two orders of magnitude cheaper
# and catch anything that is wrong with the engine rather than the wiring.
#
#   scripts/simulator.sh unit      # FleksyCore unit tests only, no simulator  (~10s, default)
#   scripts/simulator.sh smoke     # + the UI tests that cover each wiring path (~50s)
#   scripts/simulator.sh full      # + the whole XCUITest suite                (~2min)
#
#   scripts/simulator.sh build     # build app + keyboard extension (+ UI test bundle)
#   scripts/simulator.sh install   # boot simulator, install app, enable the keyboard
#   scripts/simulator.sh shot out.png   # screenshot the simulator
#
# Run `unit` while working, `smoke` before committing, `full` before pushing or after
# touching anything in Keyboard/.
set -euo pipefail
cd "$(dirname "$0")/.."

DEVICE_NAME="${SIM_DEVICE:-iPhone 17}"
DERIVED=build/DerivedData
APP_BUNDLE=com.matejsestak.fleksyclone
KB_BUNDLE=com.matejsestak.fleksyclone.keyboard

udid() {
  xcrun simctl list devices available -j | python3 -c '
import json,sys,os
name=os.environ["DEVICE_NAME"]
d=json.load(sys.stdin)["devices"]
best=None
for rt,devs in d.items():
    if "iOS" not in rt: continue
    for dev in devs:
        if dev["name"]==name: best=(rt,dev)
if not best:
    for rt,devs in d.items():
        if "iOS" not in rt: continue
        for dev in devs:
            if dev["name"].startswith("iPhone"): best=(rt,dev)
print(best[1]["udid"] if best else "")'
}

ensure_device() {
  local id
  id=$(DEVICE_NAME="$DEVICE_NAME" udid)
  if [ -z "$id" ]; then
    local rt
    rt=$(xcrun simctl list runtimes -j | python3 -c 'import json,sys; r=[x for x in json.load(sys.stdin)["runtimes"] if x["platform"]=="iOS" and x["isAvailable"]]; print(r[-1]["identifier"])')
    id=$(xcrun simctl create "$DEVICE_NAME" "$DEVICE_NAME" "$rt")
  fi
  echo "$id"
}

boot() {
  local id=$1
  xcrun simctl bootstatus "$id" -b >/dev/null 2>&1 || true
  open -a Simulator --args -CurrentDeviceUDID "$id" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$id" >/dev/null
}

build() {
  local id=$1
  xcodebuild -project FleksyClone.xcodeproj -scheme FleksyClone \
    -destination "platform=iOS Simulator,id=$id" -derivedDataPath "$DERIVED" \
    CODE_SIGNING_ALLOWED=NO build-for-testing 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" || true
}

enable_keyboard() {
  local id=$1
  # Register the extension as an enabled keyboard, ahead of the system one.
  xcrun simctl spawn "$id" defaults write -g AppleKeyboards -array "$KB_BUNDLE" "en_US@sw=QWERTY;hw=Automatic" "emoji@sw=Emoji"
  xcrun simctl spawn "$id" defaults write -g AppleKeyboardsExpanded -int 1
  xcrun simctl spawn "$id" defaults write com.apple.Preferences KeyboardLastUsed -string "$KB_BUNDLE" 2>/dev/null || true
  xcrun simctl spawn "$id" defaults write com.apple.Preferences KeyboardLastChosen -string "$KB_BUNDLE" 2>/dev/null || true
}

install() {
  local id=$1
  local app
  app=$(find "$DERIVED/Build/Products" -name "FleksyClone.app" -path "*iphonesimulator*" | head -1)
  xcrun simctl install "$id" "$app"
  enable_keyboard "$id"
  xcrun simctl launch "$id" "$APP_BUNDLE" >/dev/null
}

# Between them these cover every path from a touch to the app: typing and gestures,
# the settings panel reaching the keyboard, and the emoji picker. Enough to catch a
# broken connection - the full suite is what checks behaviour.
SMOKE_TESTS=(
  testTypingAndAutocorrectAndSwipes
  testKeyboardHeightIsAdjustableFromSettings
  testRecentEmojiKeepTheirPlaceWhileBeingTapped
)

unit_tests() {
  local out status=0
  echo "== FleksyCore unit tests =="
  out=$(swift test --package-path Packages/FleksyCore 2>&1) || status=$?
  echo "$out" | grep -E "error:|XCTAssert|failed \(" || true
  echo "$out" | grep -E "Executed [0-9]+ tests" | tail -1
  return $status
}

# Any test names given are run on their own; with none, the whole suite runs.
run_tests() {
  local id=$1; shift
  local only=()
  local t
  for t in "$@"; do only+=(-only-testing:FleksyCloneUITests/FleksyCloneUITests/"$t"); done
  echo "== UI tests (${#only[@]:-0} selected, 0 means all) =="
  xcodebuild -project FleksyClone.xcodeproj -scheme FleksyClone \
    -destination "platform=iOS Simulator,id=$id" -derivedDataPath "$DERIVED" \
    -resultBundlePath "build/TestResults-$(date +%s).xcresult" \
    ${only[@]+"${only[@]}"} \
    CODE_SIGNING_ALLOWED=NO test-without-building 2>&1 | grep -E "error:|Test Case|Executing|passed|failed|BUILD|TEST" | grep -v "^$" || true
}

# Prepares the simulator and returns its id. Only the tiers that need one call this,
# so `unit` never boots anything.
with_simulator() {
  local id
  id=$(ensure_device)
  build "$id" >&2
  boot "$id" >&2
  install "$id" >&2
  echo "$id"
}

cmd=${1:-unit}
case "$cmd" in
  unit)  unit_tests ;;
  smoke) unit_tests && run_tests "$(with_simulator)" "${SMOKE_TESTS[@]}" ;;
  full|test|all) unit_tests && run_tests "$(with_simulator)" ;;
  build) build "$(ensure_device)" ;;
  install) ID=$(ensure_device); boot "$ID"; install "$ID" ;;
  shot) ID=$(ensure_device); boot "$ID"; xcrun simctl io "$ID" screenshot "${2:-screenshot.png}" ;;
  udid) ensure_device ;;
  *) echo "unknown command $cmd"; exit 1 ;;
esac
