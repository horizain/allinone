# 云开发环境

本地与云环境统一使用 [开发环境说明](development.md) 中的脚本和固定版本。

```bash
bash scripts/setup.sh
bash scripts/build.sh stm32mp157
bash scripts/test.sh
```

默认环境目录为仓库内被 Git 忽略的 `.dev/`。如需复用此前云环境的依赖：

```bash
export ALLINONE_ENV_DIR=/workspace/shared
bash scripts/setup.sh
bash scripts/build.sh stm32mp157
```

旧入口 `scripts/cloud/setup-zephyr.sh` 保留兼容，只执行初始化，不再自动构建或测试。
每个新 shell 需要重新启用激活脚本；无需常驻服务。
Git 提交与推送不发布云环境快照；云环境配置仍需在环境设置中保存并发布。
