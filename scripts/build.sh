#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
target=${1:-stm32mp157}
case "$target" in
  stm32mp157) board=stm32mp157c_dk2; name=mp157-hello ;;
  stm32f103c8) board=stm32_min_dev@blue/stm32f103xb; name=f103c8-hello ;;
  esp32s3) board=esp32s3_devkitc/esp32s3/procpu; name=esp32s3-hello ;;
  *) echo "Usage: bash scripts/build.sh [stm32mp157|stm32f103c8|esp32s3]" >&2; exit 2 ;;
esac
base=${ALLINONE_ENV_DIR:-$root/.dev}
if [ ! -f "$base/activate.sh" ]; then
  bash "$root/scripts/setup.sh"
fi
source "$base/activate.sh"
source "$root/config/zephyr-versions.env"
test "$(git -C "$ZEPHYR_BASE" rev-parse HEAD)" = "$ZEPHYR_COMMIT"
test "$(cat "$ZEPHYR_SDK_INSTALL_DIR/sdk_version")" = "$ZEPHYR_SDK_VERSION"
extra=()
if [ "$target" = stm32f103c8 ]; then
  extra=(-- "-DDTC_OVERLAY_FILE=$root/config/boards/stm32f103c8.overlay")
fi
cd "$ZEPHYR_BASE/.."
# Bash 3.2 treats an empty array as unset under nounset.
west build -b "$board" "$ZEPHYR_BASE/samples/hello_world" \
  -d "$ALLINONE_ENV_DIR/zephyr-builds/$name" "-o=-j${BUILD_JOBS:-4}" ${extra[@]+"${extra[@]}"}
