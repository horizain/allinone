# 本地编译环境

## 文件组织

```text
config/
  zephyr-versions.env          # Zephyr、SDK、开发工具的固定版本
  zephyr-sdk.sha256            # 官方 SDK 下载校验和
  boards/stm32f103c8.overlay   # 将 Flash 限制为 64 KiB
scripts/
  setup.sh                    # 下载并初始化本地依赖
  build.sh                    # 首次自动初始化，再构建指定目标
  test.sh                     # 构建并运行官方 QEMU 测试
  test-qemu.py                # 测试结果验证、超时和 QEMU 退出处理
  cloud/setup-zephyr.sh        # 旧云环境入口，转调 setup.sh
.dev/                         # 自动生成，已被 Git 忽略
  activate.sh
  zephyr-venv/
  zephyr-workspace/
  zephyr-sdk-1.0.1/
  zephyr-builds/
  zephyr-onboarding/           # 测试日志
  zephyr-cache/
  downloads/
```

仓库保存配置、脚本和文档。Zephyr 源码、SDK、虚拟环境、构建缓存与固件产物
在需要编译时下载或生成，不纳入 Git。尚未初始化自有应用或 west manifest。
Zephyr 模块版本由固定 Zephyr 提交中的上游 manifest 决定。

## 初始化

支持 Linux x86_64；Windows 使用 WSL2。需要 Bash、Python 3.12（含 venv/pip）、
Git、curl、tar、xz、make。Ubuntu 可先安装系统依赖：

```bash
sudo apt-get update
sudo apt-get install -y python3 python3-venv python3-pip git curl tar xz-utils make
```

需要至少 6 GiB 可用空间，以及 GitHub（包括下载重定向域名）和 PyPI 网络访问。
脚本不安装系统软件，不需要以 root 身份运行。

在仓库根目录执行：

```bash
bash scripts/setup.sh
```

脚本安装 ARM 与 ESP32-S3 工具链及所需模块，验证 SDK SHA-256，生成激活脚本。
初始化本身不执行构建或测试；重复运行会刷新 Python/模块依赖并复用已下载文件。
Python 顶层工具版本固定，Zephyr Python 依赖按上游 requirements 约束解析。
不会自动追踪最新稳定版。升级时应一并核对 `config/zephyr-versions.env`、
`config/zephyr-sdk.sha256` 及三目标验证结果。

默认保存至仓库的 `.dev/`。可指定外部目录，后续构建与测试也使用同一个变量：

```bash
export ALLINONE_ENV_DIR="$HOME/.cache/allinone"
bash scripts/setup.sh
bash scripts/build.sh
```

已有 Zephyr 检出必须匹配固定提交；脚本不自动切分支、重置或覆盖本地修改。
不要并发执行多个安装或 QEMU 测试。使用已有隔离检出，无需创建 Git worktree。
虚拟环境与构建缓存含绝对路径，移动仓库或环境目录后应使用新目录重新初始化。

## 构建与测试

`build.sh` 在环境尚未初始化时自动执行 `setup.sh`，默认构建 STM32MP157 M4。
脚本会核对 Zephyr 提交及 SDK 版本；默认使用 4 个编译任务，可用 `BUILD_JOBS` 调整。

```bash
bash scripts/build.sh stm32mp157
bash scripts/build.sh stm32f103c8
bash scripts/build.sh esp32s3
bash scripts/test.sh
```

| 参数 | 上游参考板 | 构建目录（相对环境目录） |
| --- | --- | --- |
| `stm32mp157` | `stm32mp157c_dk2` | `zephyr-builds/mp157-hello` |
| `stm32f103c8` | `stm32_min_dev@blue/stm32f103xb` | `zephyr-builds/f103c8-hello` |
| `esp32s3` | `esp32s3_devkitc/esp32s3/procpu` | `zephyr-builds/esp32s3-hello` |

当前构建官方 `samples/hello_world`，ELF 位于各构建目录下的 `zephyr/zephyr.elf`。
STM32F103C8T6 使用本地 overlay，将 Flash 限为标称 64 KiB，RAM 为 20 KiB。
ESP32-S3 实际模块的 Flash、PSRAM 和引脚待确认，当前未准备或验证 Wi-Fi/Bluetooth blobs。

`test.sh` 在 `qemu_cortex_m3` 上运行官方 `tests/kernel/threads/thread_apis`。
检查真实测试汇总及 west 退出状态，在成功后通过 QEMU monitor 正常退出；
测试运行超时为 60 秒，日志位于环境目录的 `zephyr-onboarding/qemu-verified.log`。
此前固定版本验证为三目标构建通过、QEMU 41 项通过、0 项失败、2 项跳过
（`test_thread_name_user_get_set`、`test_threads_cpu_mask`）。
QEMU 测试不代表三款芯片的真机行为。

## STM32MP157 M4 调试

使用默认环境时，每个新 shell 可执行：

```bash
source .dev/activate.sh
cd "$ZEPHYR_BASE/.."
west attach -d "$ALLINONE_ENV_DIR/zephyr-builds/mp157-hello" --context
```

`--context` 只检查 runner 配置。确认设备连接后，去掉此选项即可附加调试器。
SDK 已提供 ARM GDB 和 OpenOCD。

目前以 STM32MP157C-DK2 为参考，该构建只针对 M4，不构建 A7 Linux。
实际板型尚未确认，其他 STM32MP157 板需核对时钟、引脚和设备树。
M4 固件通常由 A7/Linux remoteproc 加载到 RAM 并启动，再附加调试器；
不能直接套用其他 STM32 的片上 Flash 烧录流程。
上游 DK2 默认 RAM console，不能假定 UART 会输出日志。
板级文档位于 `$ZEPHYR_BASE/boards/st/stm32mp157c_dk2/doc/stm32mp157_dk2.rst`。
真机烧录、remoteproc、串口和调试连接尚未验证。
