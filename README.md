# Link Me

局域网多端互传项目。

## 子应用
- `apps/desktop`：Electron 桌面端 Host
- `apps/mobile`：官方 `uni-app Vue3 + Vite` 移动端，已可输出 `h5` 和 `app-plus` 构建产物
- `packages/shared`：共享协议与工具

## 当前可用能力
- 电脑端启动局域网服务并生成二维码
- 手机端连接电脑端，电脑端人工允许连接
- 手机端推送文本、文件、多文件、文件夹到电脑端
- 电脑端为每个批次选择保存位置或直接拒绝
- 同一电脑端支持多个手机同时连接
- 单文件失败不阻断后续文件，支持仅重试失败项
- 同名文件自动重命名保存
- 桌面端支持主动断开会话
- 移动端已迁移到 `uni-app` 官方结构，可构建 `app-plus`

## 当前限制
- 目前 `app-plus` 已打通编译壳，但原生文件选择/扫码能力仍待适配
- 手机作为 Host、手机到手机直连仍属于下一阶段能力
- 桌面端到手机端的文件推送尚未完成

## 文档导航
- `docs/project-status.md`：项目状态总览（已完成 / 未完成 / 当前限制 / 下一步）
- `docs/deployment-verification.md`：部署、联调、打包、验收、排障文档
- `docs/feature-overview.md`：功能说明
- `docs/usage.md`：使用说明
- `docs/build.md`：构建与打包说明
