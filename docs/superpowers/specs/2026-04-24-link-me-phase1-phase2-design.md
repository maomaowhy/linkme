# Link Me Phase 1 / Phase 2 Unified Product Design

## Goal
将 `Link Me` 从当前偏工程化的“会话/批次管理工具”重构为更接近 AirDrop 心智的系统级传输工具：先完成 `app-plus Android` 与 `H5` 的统一发送闭环，再统一桌面端和移动端的玻璃态视觉与交互语言。

## Product Scope

### Phase 1 — 功能闭环
1. 完成 `app-plus Android` 的发送能力闭环
2. `H5` 与 `app-plus` 统一为“多选文件发送”，移除文件夹入口
3. 移动端同一 `deviceId` 重连时复用原会话，不新建会话
4. 桌面端首次接收时选择保存位置，可勾选设为默认位置
5. 默认保存位置持久化到本地，默认值为桌面目录
6. 双端显示传输进度与最终结果
7. 未完成批次在断连重连后标记为中断，允许后续手动重试失败项
8. 修复 H5 上传与桌面端的 CORS / 接收链路问题

### Phase 2 — 视觉重构
1. 桌面端改为“发送面板优先”结构，弱化后台管理感
2. 移动端改为“连接状态 + 主操作 + 当前进度”的轻量结构
3. 双端统一玻璃态（Glassmorphism + Apple HIG）风格
4. 默认隐藏工程化技术信息：二维码原始 JSON、会话 ID、大段状态字段
5. 强化动效、空间感、卡片层级与状态反馈

## Out of Scope
1. `app-plus` 文件夹选择
2. iOS 原生文件选择能力
3. 断点续传
4. 桌面端向手机端反向推送
5. 手机作为 Host
6. 公网或跨 NAT 连接
7. 手电筒、摄像头切换等扫码高级能力

## Confirmed Product Decisions

### 1. 设备身份
- 设备身份使用稳定的本地持久化 `deviceId`
- 不使用 IP 地址或 MAC 地址作为设备主标识
- `deviceId` 在移动端首次运行时生成，并持久化到本地存储
- 后续连接时始终复用该 `deviceId`

### 2. 会话复用
- 桌面端以 `deviceId` 作为会话复用键
- 同一 `deviceId` 再次连接时：
  - 不创建新会话
  - 复用旧会话
  - 保留历史消息、历史批次与最近状态
- 若存在未完成批次：
  - 标记为“中断”
  - 不自动续传
  - 用户可后续手动重试失败项

### 3. 保存位置策略
- 桌面端默认保存位置初始值为桌面目录
- 首次接收且用户未确认默认路径时：
  - 弹窗要求用户选择保存目录
  - 弹窗内支持“设为默认位置”勾选项
- 若已存在默认保存路径：
  - 后续接收默认自动保存
  - 不再每次弹窗
- 用户可在桌面端设置页修改默认保存位置
- 默认保存路径本地持久化

### 4. 文件选择策略
- `H5` 与 `app-plus Android` 都统一为多选文件
- 当前版本移除文件夹选择入口
- 当前版本不再承诺文件夹推送

### 5. 扫码入口策略
- 移动端仅保留一个“扫码”按钮
- 点击后弹出：
  - `扫一扫`
  - `从相册选图`
- `H5`：
  - `扫一扫` 走自定义全屏扫码层
  - `从相册选图` 走 `uni.chooseImage` + 浏览器兜底
- `app-plus`：
  - `扫一扫` 走 `uni.scanCode`
  - `从相册选图` 走 `uni.chooseImage` + `plus.barcode.scan`

## User Experience Model

### Core Mental Model
用户不再面对“会话管理系统”，而是面对一个系统级传输工具：
1. 建立连接
2. 选择文件
3. 发送并查看进度

### User-Facing Principles
- 技术信息默认隐藏
- 页面永远存在一个主操作焦点
- 连接状态明确、进度反馈明确、结果反馈明确
- 首次配置可见，后续操作尽可能自动化

## Information Architecture

### Desktop — Phase 2 Structure
桌面端改为“发送面板优先”，结构如下：
1. 左侧轻导航
   - 会话 / 设备 / 设置（保留但弱化）
   - 默认保存位置入口
2. 中间主区域（核心）
   - 当前连接设备
   - 默认保存位置状态
   - 当前进行中的批次进度
   - 最近历史记录
3. 会话/设备管理概念保留在数据层，不再作为首页主视觉

### Mobile — Phase 2 Structure
移动端首页改为：
1. 顶部状态卡
   - 设备名
   - 连接状态
2. 主操作区
   - 扫码
   - 选择文件
3. 底部主按钮
   - 开始发送
4. 当前批次进度区
5. 最近一次结果区
6. 技术信息收纳到“详情 / 调试信息”中，默认隐藏

## Visual Direction

### Style Goal
从“工具后台 UI”升级为“系统级工具 UI（接近 AirDrop）”。

### Visual Principles
1. 强层级，弱边框
2. 大留白，低噪声
3. 单页只保留一个主要操作焦点
4. 玻璃卡片用于承载状态与操作
5. 通过颜色与动效表达状态，而不是堆砌文字

### Glassmorphism Rules
- 背景：浅蓝白渐变 + 柔光斑
- 卡片：半透明 + blur + 内高光 + 柔和投影
- 主操作按钮：系统蓝渐变
- 成功状态：绿色轻标签
- 危险状态：红色强调按钮
- 模糊分级：大卡片 blur 高于小卡片

### Information Reduction Rules
默认隐藏以下信息：
- 二维码原始 JSON
- 会话 ID
- 冗余的成功 / 失败 / 总计技术统计
- 与用户操作无关的工程字段

## Technical Architecture

### Mobile Runtime Split
#### H5
- 扫码：自定义浏览器摄像头扫码层
- 相册识别：`uni.chooseImage`，失败时回退 DOM file input
- 多选文件：浏览器 file input
- 上传：基于现有 HTTP 传输接口

#### app-plus Android
- 扫码：`uni.scanCode`
- 相册识别：`uni.chooseImage` + `plus.barcode.scan`
- 多选文件：Android `Native.js` 文件选择能力
- 上传：复用现有 HTTP 传输接口

### Session Model Changes
- 当前连接逻辑从“每次 connect 创建一条新 session”改为“按 deviceId 查找或创建 session”
- 连接层仅替换 socket 绑定
- 传输记录和消息记录继续挂在原 session 上

### Transfer Model Changes
- 批次状态新增：`interrupted`
- 断连时若批次未完成，更新为 `interrupted`
- 保留失败项明细，供手动重试
- 当前进行中批次需暴露进度给桌面端与移动端 UI

### Desktop Persistence
本地持久化以下设置：
- 默认保存目录
- 是否已确认使用默认保存目录
- 可选：最近一次成功保存目录（用于设置页回显）

## Detailed Flow Design

### Flow A — 首次发送（无默认目录）
1. 移动端已连接桌面端
2. 用户多选文件并点击“开始发送”
3. 桌面端收到传输请求
4. 桌面端弹窗：选择保存位置
5. 弹窗中可勾选“设为默认位置”
6. 用户确认后，桌面端发送接受信号
7. 移动端开始上传
8. 双端展示进度
9. 完成后写入历史记录

### Flow B — 后续发送（已配置默认目录）
1. 用户点击开始发送
2. 桌面端自动接受并写入默认目录
3. 双端展示进度
4. 完成后写入历史记录

### Flow C — 同设备重连
1. 移动端以持久化的 `deviceId` 再次连接
2. 桌面端查找已存在的 session
3. 若存在：复用原会话并替换 socket
4. 历史记录继续显示在同一个设备面板中
5. 未完成批次标记为中断

## Error Handling

### Scan Errors
- 用户取消扫码：静默返回
- 用户取消选图：静默返回
- 图片中未识别到二维码：明确错误文案
- 相机权限失败：明确提示权限问题
- 当前浏览器不支持摄像头：提示改用相册选图

### Upload Errors
- H5 预检失败：明确作为桌面端服务配置错误处理
- 保存目录无权限：桌面端提示并标记批次失败
- 网络断开：批次标记中断
- 单文件失败：不阻断后续文件，写入失败项

### Reconnect Errors
- 同设备重连过程中旧 socket 失效：允许直接替换
- 批次恢复不自动续传：由用户手动重试失败项

## Testing Strategy

### Mobile
- 稳定 `deviceId` 生成与持久化测试
- 扫码入口分流测试（camera / album）
- H5 与 app-plus 文件选择入口测试
- 图片二维码解码测试
- HTTP 上传请求构造测试

### Desktop
- `deviceId` 会话复用测试
- 默认保存目录持久化测试
- 首次接收弹窗 / 默认目录自动接收分支测试
- 断连时批次中断状态测试
- CORS 预检测试

### Integration
- H5 → 桌面端 多文件发送闭环
- app-plus Android → 桌面端 多文件发送闭环
- 同 deviceId 重连复用原会话闭环

## File / Module Impact

### Mobile
- `apps/mobile/src/pages/index/index.vue`
- `apps/mobile/src/components/H5ScannerOverlay.vue`
- 新增移动端首页拆分组件（Phase 2）
- `apps/mobile/src/services/scan.ts`
- `apps/mobile/src/services/scan-picker.ts`
- `apps/mobile/src/services/dom-file-picker.ts`
- 新增 Android Native.js 文件选择 service
- 新增移动端本地 deviceId storage service

### Desktop
- `apps/desktop/electron/server/app.ts`
- `apps/desktop/electron/server/host-service.ts`
- `apps/desktop/electron/server/transfer-manager.ts`
- 新增默认保存目录 store / config service
- `apps/desktop/src/components/SessionView.vue`
- `apps/desktop/src/components/HostDashboard.vue`
- 新增 Phase 2 视觉重构组件

## Risks
1. `app-plus Android` Native.js 文件选择与 URI 转文件数据链路需要小心适配
2. 会话复用会影响现有依赖 session 生命周期的逻辑
3. 双端进度展示依赖传输状态上报，需要数据层同步补强
4. 视觉重构涉及信息架构变化，必须避免“好看但难用”

## Delivery Plan
- 先完成 Phase 1 功能闭环
- Phase 1 验证通过后，再推进 Phase 2 视觉重构
- Phase 2 在不破坏 Phase 1 行为的前提下替换界面结构与样式
