# Link Me Mobile Uni-App Migration Design

## Goal
将 `apps/mobile` 从普通 `Vue 3 + Vite` 页面应用迁移为官方 `uni-app Vue 3 + Vite` CLI 结构，为后续 `app-plus` Android APK 打包提供正确入口与配置，同时尽量保留现有局域网传输协议、服务层和测试资产。

## Chosen Approach
采用官方 `dcloudio/uni-preset-vue#vite-ts` 的最小结构：
- `@dcloudio/vite-plugin-uni`
- `createSSRApp` 入口
- `pages.json` + `manifest.json`
- 页面放到 `src/pages/**`

现有的 LAN 传输逻辑保留在 `src/services/**`，页面层改为 `uni-app` 页面组件调用；Web 形态仍可通过 `uni build`/`uni dev` 的 H5 目标做功能验证。

## Scope
### In scope
- 迁移 `apps/mobile/package.json` 到 `uni-app` CLI 脚本
- 补 `manifest.json`
- 将当前 `App.vue` 的能力拆入 `pages/index/index.vue`
- 保留现有测试，补针对迁移配置的测试
- 更新文档中的真实状态与打包说明

### Out of scope
- Android 真机文件系统原生适配
- 原生扫码 API 接入
- 手机作为 Host
- 手机到手机直连
- 桌面向手机推送

## Compatibility Strategy
- `services/http-transfer.ts`、`services/lan-client.ts` 继续复用
- 仍保留浏览器 `WebSocket` / `fetch` 路径，确保 H5 可用
- 文件选择在 `app-plus` 下先提供占位提示，H5 下继续使用 `<input type=file>`

## Validation
- `pnpm --filter @link-me/mobile test`
- `pnpm --filter @link-me/mobile build:h5`
- 如 CLI 支持，再补 `pnpm --filter @link-me/mobile build:app-plus`
