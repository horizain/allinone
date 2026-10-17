#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/config/zephyr-versions.env"
case "$(uname -s)-$(uname -m)" in
  Linux-x86_64) host=linux-x86_64 ;;
  Darwin-arm64) host=macos-aarch64 ;;
  *)
    echo "Supported hosts: Linux x86_64 and macOS Apple Silicon (native arm64 shell). Use WSL2 on Windows." >&2
    exit 1 ;;
esac
for prerequisite in git curl tar xz make; do
  command -v "$prerequisite" >/dev/null || { echo "Missing prerequisite: $prerequisite" >&2; exit 1; }
done
if command -v sha256sum >/dev/null; then
  sha256=(sha256sum)
elif command -v shasum >/dev/null; then
  sha256=(shasum -a 256)
else
  echo "Missing prerequisite: sha256sum or shasum" >&2
  exit 1
fi
if [[ $host == macos-* ]]; then
  xcode-select -p >/dev/null 2>&1 || { echo "Install Apple Command Line Tools: xcode-select --install" >&2; exit 1; }
  command -v dtc >/dev/null || { echo "Missing prerequisite: dtc (brew install dtc)" >&2; exit 1; }
fi
# Apple's system Python may be too old; prefer a versioned interpreter.
python_bin=${PYTHON_BIN:-}
if [ -z "$python_bin" ]; then
  for candidate in python3.12 python3.13 python3.14 python3; do
    if command -v "$candidate" >/dev/null && "$candidate" -c 'import sys; sys.exit(sys.version_info < (3, 12))'; then
      python_bin=$candidate
      break
    fi
  done
fi
if [ -z "$python_bin" ] || ! "$python_bin" -c 'import sys; sys.exit(sys.version_info < (3, 12))'; then
  echo "Python 3.12+ is required. On macOS: brew install python@3.12; or set PYTHON_BIN to a suitable interpreter." >&2
  exit 1
fi
# Keep generated dependencies and build outputs out of Git.
mkdir -p "${ALLINONE_ENV_DIR:-$root/.dev}"
base=$(cd -- "${ALLINONE_ENV_DIR:-$root/.dev}" && pwd)
mkdir -p "$base/downloads" "$base/zephyr-onboarding" "$base/zephyr-cache/pip"
export PIP_CACHE_DIR="$base/zephyr-cache/pip"
if [ ! -x "$base/zephyr-venv/bin/python" ]; then
  "$python_bin" -m venv "$base/zephyr-venv"
fi
source "$base/zephyr-venv/bin/activate"
python -c 'import sys; sys.exit(sys.version_info < (3, 12))' || {
  echo "Existing virtual environment needs Python 3.12+. Reinitialize with a new ALLINONE_ENV_DIR." >&2
  exit 1
}
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
  # The manifest includes all supported hosts; download only this host's assets.
  [[ $asset == *"_${host}"* ]] || continue
  if [ ! -f "$asset" ]; then
    curl -fLsS --retry 2 "https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v$ZEPHYR_SDK_VERSION/$asset" -o "$asset.part"
    mv "$asset.part" "$asset"
  fi
  printf '%s  %s\n' "$checksum" "$asset" | "${sha256[@]}" -c -
done < "$root/config/zephyr-sdk.sha256"
if [ ! -f "$sdk/sdk_version" ]; then
  tar -xf "zephyr-sdk-${ZEPHYR_SDK_VERSION}_${host}_minimal.tar.xz" -C "$base"
fi
test "$(cat "$sdk/sdk_version")" = "$ZEPHYR_SDK_VERSION"
mkdir -p "$sdk/gnu"
for target in arm-zephyr-eabi xtensa-espressif_esp32s3_zephyr-elf; do
  if [ ! -d "$sdk/gnu/$target" ]; then
    tar -xf "toolchain_gnu_${host}_${target}.tar.xz" -C "$sdk/gnu"
  fi
done
if [[ $host == linux-* ]]; then
  if [ ! -x "$sdk/hosttools/sysroots/x86_64-pokysdk-linux/usr/bin/dtc" ]; then
    tar -xf "hosttools_${host}.tar.xz" -C "$sdk"
    "$sdk/setup.sh" -h
  fi
fi
# The macOS minimal bundle already contains ready-to-run QEMU and OpenOCD.
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
