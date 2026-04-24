# Link Me Subproject A Design

## Goal
完成 `Link Me` 当前版本的核心发送闭环：让 `H5` 与 `app-plus Android` 都能稳定完成多选文件发送，桌面端支持默认保存位置与自动接收，同一移动设备重连时复用原会话并保留历史，同时在功能闭环完成后再进行第一版玻璃态视觉重构。

## Scope

### In Scope
1. `H5` 与 `app-plus Android` 统一为多选文件发送
2. 移除当前文件夹选择入口
3. `app-plus Android` 接入原生多选文件能力
4. 移动端使用稳定持久化 `deviceId`
5. 桌面端按 `deviceId` 复用会话，不重复创建新会话
6. 重连时保留历史记录，未完成批次标记为中断
7. 桌面端首次接收时弹窗选择保存目录，并支持设为默认位置
8. 默认保存目录持久化到本地，默认值为桌面目录
9. 双端展示当前批次进度和最终结果
10. 修复并验证 H5 上传到桌面端的接收链路与 CORS
11. 在功能闭环完成后，重构双端 UI 结构并加入第一版玻璃态视觉

### Out of Scope
1. 桌面端向移动端推送
2. 移动端之间互传
3. 移动端接收推送提醒与点击接收
4. `app-plus` 文件夹选择
5. iOS 原生文件选择能力
6. 断点续传
7. 反向传输能力

## Product Rules

### Device Identity
- 移动端首次运行时生成稳定 `deviceId`
- `deviceId` 持久化到本地存储
- 后续连接始终复用该 `deviceId`
- 不使用 IP 地址或 MAC 地址作为身份标识

### Session Reuse
- 桌面端按 `deviceId` 查找已有会话
- 若找到已有会话：
  - 复用原会话
  - 仅替换当前连接绑定
  - 历史消息与历史批次继续保留
- 若旧会话存在未完成批次：
  - 将批次标记为 `interrupted`
  - 不自动续传
  - 保留失败项，允许后续手动重试

### Save Directory
- 默认保存目录初始值为桌面目录
- 首次接收时若用户尚未确认默认目录：
  - 桌面端弹窗选择目录
  - 弹窗支持“设为默认位置”
- 若已存在默认目录：
  - 后续接收直接自动保存
  - 不重复弹窗
- 用户可在桌面端设置页修改默认保存目录

### File Selection
- `H5`：使用浏览器多选文件
- `app-plus Android`：使用原生多选文件
- 当前版本移除文件夹选择入口
- 当前版本不承诺文件夹推送能力

## User Flow

### Flow 1: Connect
1. 用户在移动端打开首页
2. 页面显示连接状态卡与扫码入口
3. 用户扫码连接桌面端
4. 桌面端按 `deviceId` 复用或创建会话
5. 首页只展示用户相关状态，不默认展示 JSON 与 session id

### Flow 2: First Transfer Without Confirmed Default Directory
1. 用户在移动端点击“选择文件”并多选文件
2. 用户点击“开始发送”
3. 桌面端收到推送请求
4. 桌面端弹出目录选择对话框
5. 对话框中可勾选“设为默认位置”
6. 用户确认后，桌面端接受本次推送
7. 移动端开始上传
8. 双端展示当前批次进度
9. 完成后双端记录结果

### Flow 3: Transfer With Default Directory
1. 用户再次选择文件并开始发送
2. 桌面端自动使用默认目录接收
3. 不再弹窗
4. 双端继续显示当前批次进度与结果

### Flow 4: Same Device Reconnect
1. 移动端再次连接桌面端
2. 桌面端识别相同 `deviceId`
3. 复用原会话并保留历史记录
4. 若存在未完成批次，则标记为 `interrupted`
5. 用户可在历史记录中查看并手动重试失败项

## Information Architecture

### Desktop
功能闭环完成前，先最小修改结构以支持默认保存目录与更清晰的当前批次展示；功能稳定后再做 Phase 2 UI。

最终首页结构：
1. 左侧轻导航
   - 会话
   - 设备
   - 设置
2. 中间主面板（发送面板优先）
   - 当前连接设备
   - 默认保存目录状态
   - 当前批次进度
   - 最近传输记录
3. 会话概念仍存在，但 UI 不再强调“后台管理”

### Mobile
最终首页结构：
1. 顶部连接状态卡
2. 主操作区
   - 扫码
   - 选择文件
3. 底部主按钮
   - 开始发送
4. 当前批次进度区
5. 最近结果区
6. JSON 原始内容、session id 等技术信息默认隐藏到详情区域

## Visual Direction

### Phase Order
- 先完成功能闭环
- 再做结构优化
- 最后套玻璃态视觉样式

### Style Rules
- 背景使用浅蓝白渐变
- 卡片使用半透明、模糊、内高光与柔和阴影
- 主按钮使用系统蓝渐变
- 成功使用绿色轻标签
- 危险操作使用红色强调
- 控制信息密度，减少技术字段暴露

## Technical Architecture

### Mobile
#### Shared
- 新增 `deviceId` 存储服务
- 首页逻辑拆分成更清晰的状态、选择、发送三部分
- 统一传输状态模型，支持显示当前进度

#### H5
- 多选文件继续走浏览器文件输入
- 扫码保持当前 `扫一扫 / 从相册选图` 入口
- 上传继续走 HTTP 传输接口

#### app-plus Android
- 扫码继续使用 `uni.scanCode`
- 相册识别继续使用 `uni.chooseImage + plus.barcode.scan`
- 多选文件新增 Android `Native.js` 文件选择 service
- 将原生返回的文件 URI / 路径转成可上传的文件体

### Desktop
- `host-service` 增加默认保存目录配置读写
- 接收流程新增“默认目录是否已确认”的判断
- 连接管理新增按 `deviceId` 查找或复用会话能力
- 传输状态增加 `interrupted`
- 桌面端 HTTP 服务继续保留并验证 CORS

## Error Handling

### Mobile
- 用户取消选文件：静默返回
- 原生文件选择失败：展示明确错误
- 上传失败：记录失败项并展示错误信息
- 扫码失败：保持当前明确错误文案

### Desktop
- 默认目录不可写：拒绝本次接收并提示错误
- 目录选择取消：保持本次传输待处理或拒绝
- 会话重连：不丢历史，旧连接安全替换
- 批次中断：明确标记 `interrupted`

## Testing Strategy

### Mobile Tests
- `deviceId` 生成与持久化
- 多选文件入口能力
- 上传请求构造与批次状态
- `app-plus` 文件路径 / 文件体处理

### Desktop Tests
- 默认保存目录持久化
- 首次接收弹窗分支
- 已设默认目录自动接收分支
- `deviceId` 会话复用
- 批次中断状态
- CORS 预检

### Build Verification
- `apps/mobile`：`build:h5`
- `apps/mobile`：`build:app-plus`
- `apps/desktop`：`build:main`

### Manual Verification Checklist
1. H5 多选文件发送到桌面端
2. app-plus Android 多选文件发送到桌面端
3. 首次发送时桌面端弹目录选择
4. 勾选默认目录后，后续自动保存
5. 同一设备重连复用原会话
6. 历史记录保留
7. 断连后未完成批次显示中断

## Files Expected To Change

### Mobile
- `apps/mobile/src/pages/index/index.vue`
- 新增 / 修改移动端首页拆分组件
- `apps/mobile/src/services/scan.ts`
- `apps/mobile/src/services/http-transfer.ts`
- 新增 `device-id` service
- 新增 Android Native.js file picker service
- 相关测试文件

### Desktop
- `apps/desktop/electron/server/app.ts`
- `apps/desktop/electron/server/host-service.ts`
- `apps/desktop/electron/server/transfer-manager.ts`
- `apps/desktop/src/components/HostDashboard.vue`
- `apps/desktop/src/components/SessionView.vue`
- 新增默认目录配置存储模块
- 相关测试文件

## Risks
1. Android `Native.js` 多选文件 URI 到文件体读取链路复杂度较高
2. 会话复用会影响现有连接与传输状态管理
3. 默认保存目录流程会改变桌面端接受时机
4. 玻璃态视觉重构不能影响 Phase 1 功能闭环

## Delivery Order
1. 修正并验证桌面端接收链路
2. 引入稳定 `deviceId` 与会话复用
3. 完成默认保存目录逻辑
4. 完成 Android 多选文件能力
5. 完成双端进度展示补强
6. 完成首页结构优化
7. 最后应用第一版玻璃态视觉
