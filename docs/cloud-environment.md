# Zephyr 云开发环境

环境以 STM32MP157 Cortex-M4 开发为主，使用官方板配置验证工具链。
当前应用仓库只有说明和环境脚本，尚未初始化自有应用或 west manifest。

## 安装与启用

脚本面向 Linux x86_64 Codex 云环境，需要 Bash、Python 3.12（含 venv/pip）、
Git、curl、tar、xz、make，以及可写的 `/workspace/shared`。
网络需要访问 GitHub（含下载重定向域名）和 PyPI；安装保留 TLS 和 SDK SHA-256 校验。
预留至少 6 GiB 可用磁盘。使用当前隔离检出，无需创建 Git worktree。

在仓库根目录执行：

```bash
bash scripts/cloud/setup-zephyr.sh
```

脚本固定 Zephyr v4.4.2（`dccb09599635bdff17633fa7e9dab014b91dce90`）与 SDK 1.0.1，
安装 west、CMake、Ninja、esptool 及指定版本的 HAL 依赖。
这是一组已验证的版本，不会在每次启动时自动追踪最新发布。
脚本不修改应用源码；重复执行会复用下载、依赖和构建目录。
已存在的 Zephyr 检出必须匹配上述提交，否则停止，不会重置本地工作。
不要并行运行多个安装或测试实例。

每个新 shell 启用环境：

```bash
source /workspace/shared/zephyr-onboarding/activate.sh
cd /workspace/shared/zephyr-workspace
```

| 路径 | 内容 |
| --- | --- |
| `/workspace/shared/zephyr-venv` | Python 开发工具 |
| `/workspace/shared/zephyr-workspace` | Zephyr 与所需模块 |
| `/workspace/shared/zephyr-sdk-1.0.1` | ARM、ESP32-S3 工具链及主机工具 |
| `/workspace/shared/zephyr-builds` | 构建产物 |
| `/workspace/shared/zephyr-onboarding` | 环境激活脚本、C8 Flash overlay、测试日志 |

这些文件可随云环境快照保留。启动新任务时仍需启用环境；不需要常驻服务。
云环境设置中的安装脚本和启动说明需另行保存并发布，Git 推送不会发布环境快照。

## 构建目标

以下命令均在启用环境后，于 `/workspace/shared/zephyr-workspace` 执行。

### STM32MP157 Cortex-M4（优先）

```bash
west build -b stm32mp157c_dk2 zephyr/samples/hello_world \
  -d /workspace/shared/zephyr-builds/mp157-hello -o=-j4
```

参考板是 STM32MP157C-DK2，该目标只构建 M4 固件。
ELF 位于 `/workspace/shared/zephyr-builds/mp157-hello/zephyr/zephyr.elf`。
实际板型尚未确认，其他 STM32MP157 板需核对时钟、引脚和设备树。

### STM32F103C8T6

```bash
west build -b stm32_min_dev@blue/stm32f103xb zephyr/samples/hello_world \
  -d /workspace/shared/zephyr-builds/f103c8-hello -o=-j4 -- \
  -DDTC_OVERLAY_FILE=/workspace/shared/zephyr-onboarding/stm32f103c8.overlay
```

使用 Blue Pill 参考配置，并通过本地 overlay 将 Flash 限为 C8T6 标称的
64 KiB，RAM 为 20 KiB。不要依赖 xB 默认的 128 KiB Flash 容量。

### ESP32-S3

```bash
west build -b esp32s3_devkitc/esp32s3/procpu zephyr/samples/hello_world \
  -d /workspace/shared/zephyr-builds/esp32s3-hello -o=-j4
```

使用 DevKitC 参考配置，实际模块的 Flash、PSRAM 和引脚待确认。
当前仅验证基础固件构建，未准备或验证 Wi-Fi/Bluetooth blobs。

## 验证结果

三款目标的官方 `hello_world` 均已编译通过，SDK 下载通过官方 SHA-256 校验。
完整安装脚本已复跑成功。

脚本还构建并运行官方 `tests/kernel/threads/thread_apis`，目标为
`qemu_cortex_m3`。验证结果为 **41 项通过、0 项失败、2 项跳过**；
跳过项为 `test_thread_name_user_get_set` 和 `test_threads_cpu_mask`。
该测试验证模拟平台上的线程 API，不代表三款芯片的真机行为。

测试日志为 `/workspace/shared/zephyr-onboarding/qemu-verified.log`。
脚本检查测试汇总与 west 退出状态，在输出 `PROJECT EXECUTION SUCCESSFUL` 后
通过 QEMU monitor 正常退出，并对未完成的测试设置超时。
如需完整复验，重新运行安装脚本；它会同时刷新依赖并执行构建。

## STM32MP157 真机调试

云环境已提供 ARM GDB 和 OpenOCD。只检查调试器配置可执行：

```bash
west attach -d /workspace/shared/zephyr-builds/mp157-hello --context
```

STM32MP157 M4 固件通常由 A7/Linux 的 remoteproc 加载到 RAM 并启动，
之后再附加调试器；不应将其他 STM32 的片上 Flash 烧录流程直接套用。
上游 DK2 默认使用 RAM console，不能直接假定 UART 会输出日志。
在确认板型、Linux 配置、固件加载流程和 ST-LINK 连接后，可执行：

```bash
west attach -d /workspace/shared/zephyr-builds/mp157-hello
```

板级参考文档位于
`/workspace/shared/zephyr-workspace/zephyr/boards/st/stm32mp157c_dk2/doc/stm32mp157_dk2.rst`。
目前尚未验证真机烧录、remoteproc、串口输出或硬件调试连接。
