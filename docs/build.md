# 构建与打包说明

> 关联文档：`docs/project-status.md`、`docs/deployment-verification.md`

## 开发环境
- Node.js 20+
- pnpm 10+
- macOS / Windows（桌面端打包）
- HBuilderX / uni-app Android 构建链路（用于 APK）

## 安装依赖
```bash
pnpm install
```

## 桌面端开发
```bash
pnpm dev:desktop
```

## 移动端 H5 开发
```bash
pnpm dev:mobile
```

## 共享包构建
```bash
pnpm build:shared
```

## 桌面端构建
```bash
pnpm build:desktop
```

## 移动端 H5 构建
```bash
pnpm build:mobile
```
说明：输出 `uni-app` 的 H5 产物，用于当前最完整的移动端功能验证。

## 移动端 app-plus 构建
```bash
pnpm build:mobile:app
```
说明：当前会输出 `dist/build/app`，这是 `uni-app app-plus` 工程产物，不是最终 `.apk` 文件。

## 从 app-plus 到 Android APK
1. 运行 `pnpm build:mobile:app`
2. 用 HBuilderX 打开 `apps/mobile/dist/build/app`
3. 在 HBuilderX 中执行云打包或本地打包
4. 输出正式 Android `.apk`

## 桌面端目录打包验证
```bash
pnpm pack:desktop:dir
```
说明：当前代码配置已通过构建校验；若 `electron-builder` 拉取 Electron 发行包时网络异常，目录包可能因外部下载 EOF 失败。

## Windows 安装包
```bash
pnpm pack:desktop
```
说明：在 Windows 上生成 `.exe` / `nsis` 更稳妥。

## macOS 安装包
```bash
pnpm pack:desktop
```
说明：在 macOS 上可输出 `.dmg`。
