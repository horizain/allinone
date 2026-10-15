# allinone

A Zephyr OS-based MCU firmware framework designed to support multiple MCU platforms and enable rapid development.

当前优先支持 STM32MP157 的 Cortex-M4，兼顾 STM32F103C8T6 和 ESP32-S3。
项目尚未加入应用源码，目前使用官方示例验证开发环境。

固定版本：Zephyr **v4.4.2**、SDK **1.0.1**。
Zephyr、SDK、Python 虚拟环境和构建产物均在本地生成，不提交到 Git。

Linux x86_64（Windows 可使用 WSL2）一键初始化：

```bash
bash scripts/setup.sh
```

编译前也可自动完成首次初始化，默认编译 STM32MP157 M4：

```bash
bash scripts/build.sh
```

目录、依赖、其他芯片构建和调试方法见 [开发环境说明](docs/development.md)。
