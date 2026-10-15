#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/config/zephyr-versions.env"
if [[ $(uname -s) != Linux || $(uname -m) != x86_64 ]]; then
  echo "Supported host: Linux x86_64 (use WSL2 on Windows)." >&2
  exit 1
fi
for prerequisite in python3 git curl tar xz make; do
  command -v "$prerequisite" >/dev/null || { echo "Missing prerequisite: $prerequisite" >&2; exit 1; }
done
# Keep generated dependencies and build outputs out of Git.
mkdir -p "${ALLINONE_ENV_DIR:-$root/.dev}"
base=$(cd -- "${ALLINONE_ENV_DIR:-$root/.dev}" && pwd)
mkdir -p "$base/downloads" "$base/zephyr-onboarding" "$base/zephyr-cache/pip"
export PIP_CACHE_DIR="$base/zephyr-cache/pip"
if [ ! -x "$base/zephyr-venv/bin/python" ]; then
  python3 -m venv "$base/zephyr-venv"
fi
source "$base/zephyr-venv/bin/activate"
pip install "west==$WEST_VERSION" "cmake==$CMAKE_VERSION" "ninja==$NINJA_VERSION" "esptool==$ESPTOOL_VERSION"
if [ ! -e "$base/zephyr-workspace/zephyr" ]; then
  git clone --depth 1 --branch "v$ZEPHYR_VERSION" https://github.com/zephyrproject-rtos/zephyr.git "$base/zephyr-workspace/zephyr"
fi
test "$(git -C "$base/zephyr-workspace/zephyr" rev-parse HEAD)" = "$ZEPHYR_COMMIT"
test "$(cat "$base/zephyr-workspace/zephyr/SDK_VERSION")" = "$ZEPHYR_SDK_VERSION"
if [ ! -d "$base/zephyr-workspace/.west" ]; then
  west init -l "$base/zephyr-workspace/zephyr"
fi
cd "$base/zephyr-workspace"
west update --narrow -o=--depth=1 cmsis cmsis_6 hal_stm32 hal_espressif hal_xtensa picolibc
pip install -r zephyr/scripts/requirements-base.txt
sdk="$base/zephyr-sdk-$ZEPHYR_SDK_VERSION"
cd "$base/downloads"
while read -r checksum asset; do
  if [ ! -f "$asset" ]; then
    curl -fLsS --retry 2 "https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v$ZEPHYR_SDK_VERSION/$asset" -o "$asset"
  fi
  printf '%s  %s\n' "$checksum" "$asset" | sha256sum -c -
done < "$root/config/zephyr-sdk.sha256"
if [ ! -f "$sdk/sdk_version" ]; then
  tar -xf "zephyr-sdk-${ZEPHYR_SDK_VERSION}_linux-x86_64_minimal.tar.xz" -C "$base"
fi
test "$(cat "$sdk/sdk_version")" = "$ZEPHYR_SDK_VERSION"
mkdir -p "$sdk/gnu"
for target in arm-zephyr-eabi xtensa-espressif_esp32s3_zephyr-elf; do
  if [ ! -d "$sdk/gnu/$target" ]; then
    tar -xf "toolchain_gnu_linux-x86_64_${target}.tar.xz" -C "$sdk/gnu"
  fi
done
if [ ! -x "$sdk/hosttools/sysroots/x86_64-pokysdk-linux/usr/bin/dtc" ]; then
  tar -xf hosttools_linux-x86_64.tar.xz -C "$sdk"
  "$sdk/setup.sh" -h
fi
# Store shell-escaped absolute paths so activation works from any directory.
{
  printf 'source %q\n' "$base/zephyr-venv/bin/activate"
  printf 'export ALLINONE_ENV_DIR=%q\n' "$base"
  printf 'export ZEPHYR_BASE=%q\n' "$base/zephyr-workspace/zephyr"
  printf 'export ZEPHYR_SDK_INSTALL_DIR=%q\n' "$sdk"
  printf 'export ZEPHYR_TOOLCHAIN_VARIANT=zephyr\n'
  printf 'export XDG_CACHE_HOME=%q\n' "$base/zephyr-cache"
  printf 'export PIP_CACHE_DIR=%q\n' "$base/zephyr-cache/pip"
} > "$base/activate.sh"
echo "Environment initialized. Activate with:"
printf 'source %q\n' "$base/activate.sh"
