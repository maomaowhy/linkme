# Unified Mobile Scan Experience Design

## Goal
为 `apps/mobile` 提供统一的“扫码”入口：点击单个按钮后弹出“扫一扫 / 从相册选图”，并同时覆盖 `H5` 与 `app-plus` 运行形态。

## Scope
- 将现有按钮统一改造成动作面板入口
- `app-plus` 接入官方 `uni.scanCode` 与 `uni.chooseImage`
- `H5` 接入动作面板、全屏扫码层、扫码框与解析中状态
- 为相册图片识别补充加载态与更明确的错误提示
- 更新测试与文档，反映真实平台能力与运行通路

## Chosen Approach
1. 入口统一：页面只保留一个“扫码”按钮，点击后使用 `uni.showActionSheet` 展示“扫一扫 / 从相册选图”。
2. `app-plus` 扫一扫：直接调用 `uni.scanCode`；从相册选图：调用 `uni.chooseImage` 后使用 `plus.barcode.scan` 识别本地图片。
3. `H5` 扫一扫：打开一个页面内全屏扫码层，使用浏览器摄像头预览，并在扫描框内持续解析二维码；从相册选图：优先 `uni.chooseImage`，失败时回退到 DOM file input。
4. 解码统一：保留现有图片解码服务，继续优先浏览器原生能力，降级到 `jsqr`；对 `app-plus` 新增本地路径二维码解析入口。

## UI / UX
- 单个主按钮：`扫码`
- 动作面板：`扫一扫` / `从相册选图`
- `H5` 扫一扫：全屏遮罩、扫描框、关闭按钮、`识别中...` 提示、打开摄像头加载态
- 图片识别：显示 `图片解析中...` loading，解析成功后自动写入二维码内容
- 失败提示：明确区分“未识别到二维码”“未授予相机权限”“当前环境不支持扫码”

## Components
- `apps/mobile/src/pages/index/index.vue`
  - 统一扫码入口
  - 托管动作面板、loading、扫码结果写入
- `apps/mobile/src/components/H5ScannerOverlay.vue`
  - H5 全屏扫码层与扫码框 UI
  - 摄像头启动、停止、结果回传
- `apps/mobile/src/services/scan.ts`
  - 新增 `app-plus` 本地图片路径解码入口
  - 复用现有图片文件解码逻辑
- `apps/mobile/src/services/dom-file-picker.ts`
  - 保留 H5 兜底文件输入能力
- `apps/mobile/src/services/scan*.test.ts`
  - 补充 `app-plus` 图片路径解码测试
  - 保持 H5 选图与图片解码测试覆盖

## Platform Notes
- `uni.scanCode` 在当前 `uni-h5` 运行时不支持，因此 H5 的“扫一扫”必须走浏览器摄像头实现
- `uni.chooseImage` 可作为两端统一的“相册选图”入口
- `app-plus` 原生文件/文件夹选择暂不在本次范围内；本次仅完成扫码入口

## Error Handling
- 用户取消动作面板：静默返回
- 用户取消扫码 / 选图：静默返回
- 摄像头权限失败：展示权限错误
- 图片中未找到二维码：展示明确错误文案
- H5 不支持摄像头 API：提示切换浏览器或使用相册选图

## Testing
- 为 `scan.ts` 新增 `app-plus` 路径解码测试
- 保留 `scan-picker.ts` 与 `dom-file-picker.ts` 的既有测试
- 最终执行：
  - `pnpm --filter @link-me/mobile test ...`
  - `pnpm --filter @link-me/mobile build:h5`

## Notes
- 本次实现以“先功能闭环，再逐步增强手电筒/摄像头切换”等高级能力为原则
- H5 扫一扫先实现后置摄像头优先、关闭按钮、识别中提示；手电筒和摄像头切换不在本次范围
