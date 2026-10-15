#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
base=${ALLINONE_ENV_DIR:-$root/.dev}
if [ ! -f "$base/activate.sh" ]; then
  bash "$root/scripts/setup.sh"
fi
source "$base/activate.sh"
source "$root/config/zephyr-versions.env"
test "$(git -C "$ZEPHYR_BASE" rev-parse HEAD)" = "$ZEPHYR_COMMIT"
test "$(cat "$ZEPHYR_SDK_INSTALL_DIR/sdk_version")" = "$ZEPHYR_SDK_VERSION"
cd "$ZEPHYR_BASE/.."
west build -b qemu_cortex_m3 "$ZEPHYR_BASE/tests/kernel/threads/thread_apis" \
  -d "$ALLINONE_ENV_DIR/zephyr-builds/qemu-thread-tests" "-o=-j${BUILD_JOBS:-4}"
python "$root/scripts/test-qemu.py"
