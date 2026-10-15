#!/usr/bin/env bash
set -euo pipefail
# Dependencies live outside the application checkout. Do not create worktrees.
base=/workspace/shared
mkdir -p "$base/downloads" "$base/zephyr-onboarding" "$base/zephyr-cache/pip"
export PIP_CACHE_DIR="$base/zephyr-cache/pip"
if [ ! -x "$base/zephyr-venv/bin/python" ]; then
  python3 -m venv "$base/zephyr-venv"
fi
source "$base/zephyr-venv/bin/activate"
pip install west==1.5.0 cmake==4.4.4 ninja==1.13.2 esptool==5.5.0
if [ ! -e "$base/zephyr-workspace/zephyr" ]; then
  git clone --depth 1 --branch v4.4.2 https://github.com/zephyrproject-rtos/zephyr.git "$base/zephyr-workspace/zephyr"
fi
test "$(git -C "$base/zephyr-workspace/zephyr" rev-parse HEAD)" = dccb09599635bdff17633fa7e9dab014b91dce90
if [ ! -d "$base/zephyr-workspace/.west" ]; then
  west init -l "$base/zephyr-workspace/zephyr"
fi
cd "$base/zephyr-workspace"
west update --narrow -o=--depth=1 cmsis cmsis_6 hal_stm32 hal_espressif hal_xtensa picolibc
pip install -r zephyr/scripts/requirements-base.txt
sdk="$base/zephyr-sdk-1.0.1"
cd "$base/downloads"
cat > zephyr-sdk-1.0.1-selected.sha256 <<'HASHES'
ca9bc0ff66fafca1dac9d592a36d953cf16d096a9d09b1c0357f021cf9f6a7eb  zephyr-sdk-1.0.1_linux-x86_64_minimal.tar.xz
4d90f2d9a42802bc76bfaacd2bb52e6c30a046a425148e1ed1a7311cb66bde60  hosttools_linux-x86_64.tar.xz
21b85981cb5a1818d9bc53d82af80f208946ec038b982ff1907287572ed3a634  toolchain_gnu_linux-x86_64_arm-zephyr-eabi.tar.xz
904d42b75e4d819c58b0db640783911e508b9ee2a627eb5daffb907465a34be1  toolchain_gnu_linux-x86_64_xtensa-espressif_esp32s3_zephyr-elf.tar.xz
HASHES
while read -r checksum asset; do
  if [ ! -f "$asset" ]; then
    curl -fLsS --retry 2 "https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v1.0.1/$asset" -o "$asset"
  fi
  printf '%s  %s\n' "$checksum" "$asset" | sha256sum -c -
done < zephyr-sdk-1.0.1-selected.sha256
if [ ! -f "$sdk/sdk_version" ]; then
  tar -xf zephyr-sdk-1.0.1_linux-x86_64_minimal.tar.xz -C "$base"
fi
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
cat > "$base/zephyr-onboarding/activate.sh" <<'ACTIVATE'
source /workspace/shared/zephyr-venv/bin/activate
export ZEPHYR_BASE=/workspace/shared/zephyr-workspace/zephyr
export ZEPHYR_SDK_INSTALL_DIR=/workspace/shared/zephyr-sdk-1.0.1
export ZEPHYR_TOOLCHAIN_VARIANT=zephyr
export XDG_CACHE_HOME=/workspace/shared/zephyr-cache
export PIP_CACHE_DIR=/workspace/shared/zephyr-cache/pip
ACTIVATE
cat > "$base/zephyr-onboarding/stm32f103c8.overlay" <<'OVERLAY'
/* STM32F103C8T6: constrain upstream xB target to the rated 64 KiB flash. */
&flash0 {
    reg = <0x08000000 DT_SIZE_K(64)>;
};
OVERLAY
source "$base/zephyr-onboarding/activate.sh"
cd "$base/zephyr-workspace"
west build -b stm32mp157c_dk2 zephyr/samples/hello_world -d "$base/zephyr-builds/mp157-hello" -o=-j4
west build -b stm32_min_dev@blue/stm32f103xb zephyr/samples/hello_world -d "$base/zephyr-builds/f103c8-hello" -o=-j4 -- -DDTC_OVERLAY_FILE="$base/zephyr-onboarding/stm32f103c8.overlay"
west build -b esp32s3_devkitc/esp32s3/procpu zephyr/samples/hello_world -d "$base/zephyr-builds/esp32s3-hello" -o=-j4
west build -b qemu_cortex_m3 zephyr/tests/kernel/threads/thread_apis -d "$base/zephyr-builds/qemu-thread-tests" -o=-j4
# The Cortex-M3 guest idles after reporting ztest results. Ask the QEMU
# monitor to exit cleanly, and still require the west command's zero status.
python - <<'PY'
import os
import pathlib
import re
import signal
import subprocess
import time

log = pathlib.Path('/workspace/shared/zephyr-onboarding/qemu-verified.log')
with log.open('wb') as output:
    process = subprocess.Popen(
        ['west', 'build', '-d', '/workspace/shared/zephyr-builds/qemu-thread-tests', '-t', 'run'],
        stdin=subprocess.PIPE, stdout=output, stderr=subprocess.STDOUT,
        start_new_session=True,
    )
    try:
        deadline = time.monotonic() + 60
        while process.poll() is None:
            if b'PROJECT EXECUTION SUCCESSFUL' in log.read_bytes():
                process.stdin.write(b'\x01x')
                process.stdin.flush()
                break
            if time.monotonic() > deadline:
                raise RuntimeError('QEMU tests timed out; see ' + str(log))
            time.sleep(0.1)
        result = process.wait(timeout=10)
        text = log.read_text()
        print(text)
        if result:
            raise SystemExit(result)
        summaries = re.findall(r'SUITE PASS .*?: pass = (\d+), fail = (\d+), skip = (\d+)', text)
        assert 'PROJECT EXECUTION SUCCESSFUL' in text and summaries
        assert sum(int(passed) for passed, _, _ in summaries) > 0
        assert all(int(failed) == 0 for _, failed, _ in summaries)
    finally:
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGTERM)
            process.wait(timeout=10)
PY
