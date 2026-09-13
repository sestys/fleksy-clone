#!/bin/bash
# Exercise the real runner's exit codes without booting a simulator.
set -euo pipefail
cd "$(dirname "$0")/.."
task_tmp=$(mktemp -d)
trap 'rm -rf "$task_tmp"' EXIT
mkdir -p "$task_tmp/bin"
cat > "$task_tmp/bin/xcrun" <<'STUB'
#!/bin/bash
if [[ "$*" == *'list devices'* ]]; then
  echo '{"devices":{"iOS 26":[{"name":"iPhone 17","udid":"test-device"}]}}'
elif [[ "$*" == *'install'* ]]; then
  echo installed >> "$RUNNER_MARKER"
fi
STUB
cat > "$task_tmp/bin/swift" <<'STUB'
#!/bin/bash
echo 'Executed 1 tests'
STUB
cat > "$task_tmp/bin/xcodebuild" <<'STUB'
#!/bin/bash
if [[ "$*" == *build-for-testing* ]]; then
  exit "${BUILD_STATUS:-0}"
fi
exit "${TEST_STATUS:-0}"
STUB
cat > "$task_tmp/bin/open" <<'STUB'
#!/bin/bash
exit 0
STUB
cat > "$task_tmp/bin/find" <<'STUB'
#!/bin/bash
echo '/test/FleksyClone.app'
STUB
chmod +x "$task_tmp/bin/"*
export PATH="$task_tmp/bin:$PATH"
export RUNNER_MARKER="$task_tmp/installed"
check() {
  local expected=$1 mode=$2 status=0
  bash scripts/simulator.sh "$mode" > "$task_tmp/output" 2>&1 || status=$?
  if [ "$status" != "$expected" ]; then
    cat "$task_tmp/output"
    echo "$mode: expected exit $expected, got $status" >&2
    exit 1
  fi
}
export BUILD_STATUS=23 TEST_STATUS=0
check 23 build
check 23 smoke
[ ! -e "$RUNNER_MARKER" ] || { echo 'Installed stale app after failed build' >&2; exit 1; }
export BUILD_STATUS=0 TEST_STATUS=27
check 27 smoke
export TEST_STATUS=0
check 0 smoke
echo 'Runner failure propagation passed'
