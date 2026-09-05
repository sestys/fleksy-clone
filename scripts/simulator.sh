#!/bin/bash
# Build, install and exercise the Fleksy Clone keyboard in the iOS Simulator.
#
#   scripts/simulator.sh build     # build app + keyboard extension (+ UI test bundle)
#   scripts/simulator.sh install   # boot simulator, install app, enable the keyboard
#   scripts/simulator.sh test      # run the XCUITest suite against the simulator
#   scripts/simulator.sh all       # build + install + test
#   scripts/simulator.sh shot out.png   # screenshot the simulator
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

run_tests() {
  local id=$1
  xcodebuild -project FleksyClone.xcodeproj -scheme FleksyClone \
    -destination "platform=iOS Simulator,id=$id" -derivedDataPath "$DERIVED" \
    -resultBundlePath "build/TestResults-$(date +%s).xcresult" \
    CODE_SIGNING_ALLOWED=NO test-without-building 2>&1 | grep -E "error:|Test Case|Executing|passed|failed|BUILD|TEST" | grep -v "^$" || true
}

cmd=${1:-all}
ID=$(ensure_device)
case "$cmd" in
  build) build "$ID" ;;
  install) boot "$ID"; install "$ID" ;;
  test) boot "$ID"; run_tests "$ID" ;;
  all) build "$ID"; boot "$ID"; install "$ID"; run_tests "$ID" ;;
  shot) boot "$ID"; xcrun simctl io "$ID" screenshot "${2:-screenshot.png}" ;;
  udid) echo "$ID" ;;
  *) echo "unknown command $cmd"; exit 1 ;;
esac
