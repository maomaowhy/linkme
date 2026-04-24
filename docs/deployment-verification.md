# 部署与验证文档

## 1. 文档目标
本文档用于指导以下工作：
- 在本地准备项目运行环境
- 启动桌面端与移动端进行局域网联调
- 构建桌面端与移动端产物
- 通过 HBuilderX 将 `app-plus` 产物继续打包为 Android APK
- 依据验收清单验证项目当前已完成能力
- 在常见问题发生时快速排查

## 2. 环境要求

### 2.1 基础环境
- Node.js `20.x`
- pnpm `10.x`
- 局域网 Wi-Fi 环境
- 一台电脑
- 一台或多台手机

### 2.2 平台工具
- 桌面端开发：当前仓库环境即可
- Android APK 继续打包：需要 `HBuilderX`
- Windows / macOS 安装包生成：需要在对应目标平台执行更稳妥

## 3. 获取项目与安装依赖
在项目根目录执行：

```bash
pnpm install
```

如果使用 `nvm`，建议先切换到 Node 20：

```bash
export NVM_DIR="$HOME/.nvm"
. "/opt/homebrew/opt/nvm/nvm.sh"
nvm use 20
```

## 4. 开发部署

### 4.1 启动桌面端
```bash
pnpm dev:desktop
```

预期结果：
- Electron 窗口启动
- 页面显示桌面 Host 信息
- 页面显示二维码
- 页面显示待审批设备列表与会话列表区域

### 4.2 启动移动端 H5
```bash
pnpm dev:mobile
```

预期结果：
- `uni-app h5` 开发服务启动
- 可在浏览器中打开移动端页面
- 页面可见二维码文本输入框、连接按钮、文件选择区、批次结果区

## 5. 构建部署

### 5.1 共享包构建
```bash
pnpm build:shared
```

### 5.2 桌面端构建
```bash
pnpm build:desktop
```

预期结果：
- `apps/desktop/dist`
- `apps/desktop/dist-electron`

### 5.3 移动端 H5 构建
```bash
pnpm build:mobile
```

预期结果：
- `apps/mobile/dist/build/h5`

### 5.4 移动端 app-plus 构建
```bash
pnpm build:mobile:app
```

预期结果：
- `apps/mobile/dist/build/app`
- CLI 输出提示：用 HBuilderX 打开该目录继续运行或打包

## 6. Android APK 打包路径
当前仓库内并不是“一条命令直接产出 APK”，而是先得到 `app-plus` 工程，再通过 HBuilderX 继续操作。

### 6.1 生成 app-plus 工程
```bash
pnpm build:mobile:app
```

### 6.2 用 HBuilderX 打开工程目录
打开：
- `apps/mobile/dist/build/app`

### 6.3 在 HBuilderX 中继续操作
- 导入该目录为项目
- 根据 HBuilderX 的 Android 打包流程执行云打包或本地打包
- 输出正式 `.apk`

### 6.4 当前状态说明
- `app-plus` 构建链已打通
- APK 最终产物仍依赖 HBuilderX 后续流程
- 原生文件选择 / 扫码能力尚未完成，因此 APK 当前更适合做“壳与页面结构验证”

## 7. 桌面安装包打包路径

### 7.1 目录包验证
```bash
pnpm pack:desktop:dir
```

说明：
- 当前代码配置已完成
- 若 `electron-builder` 下载 Electron 发行包时网络中断，可能出现外部下载失败

### 7.2 Windows 安装包
```bash
pnpm pack:desktop
```
建议在 Windows 上执行，以生成 `.exe` / `nsis`

### 7.3 macOS 安装包
```bash
pnpm pack:desktop
```
建议在 macOS 上执行，以生成 `.dmg`

## 8. 联调验证文档

### 8.1 基础连接验证
验证目标：手机能够连接桌面 Host

步骤：
1. 启动桌面端
2. 启动移动端 H5
3. 将桌面端二维码内容粘贴到移动端输入框
4. 点击“连接桌面端”
5. 在桌面端允许连接

预期结果：
- 移动端状态从 `idle/pending` 进入 `connected`
- 桌面端会话列表出现新设备
- 桌面端待审批列表减少

### 8.2 多设备连接验证
验证目标：桌面端支持多个手机同时连接

步骤：
1. 让手机 A 连接桌面 Host
2. 让手机 B 使用同样方式连接桌面 Host
3. 在桌面端分别审批

预期结果：
- 桌面端会话列表中同时存在多个设备
- 任一设备断开，不影响其他设备状态

### 8.3 手机推送文件到电脑验证
验证目标：验证当前最核心、最完整的主链路

步骤：
1. 手机端连接并处于 `connected`
2. 手机端选择多个文件或整个文件夹
3. 点击“开始推送”
4. 桌面端在对应会话中点击“选择位置并接收”
5. 选择保存目录

预期结果：
- 桌面端出现该批次任务
- 文件逐个写入目标目录
- 批次中某个文件失败时，后续文件继续推送
- 批次结束后能看到成功数 / 失败数 / 总数

### 8.4 拒绝接收验证
步骤：
1. 手机端发起推送
2. 桌面端点击“拒绝”

预期结果：
- 桌面端批次状态变为 `rejected`
- 移动端退出等待状态，并显示拒绝提示

### 8.5 自动重命名验证
步骤：
1. 向同一保存目录连续推送两个同名文件
2. 观察目标目录结果

预期结果：
- 原文件保留
- 新文件自动使用 `name (1).ext`、`name (2).ext` 等命名方式保存

### 8.6 失败项重试验证
步骤：
1. 制造其中一个文件失败
2. 任务结束后点击“重试失败项”

预期结果：
- 成功项不重复传输
- 仅失败项进入重试
- 重试次数在结果中可见

### 8.7 主动断开验证
步骤：
1. 桌面端选择某个已连接会话
2. 点击“断开连接”

预期结果：
- 该会话状态变为断开
- 该设备连接关闭
- 其他会话不受影响

## 9. 当前不能作为验收项的内容
以下内容当前不能作为“必须通过”的验收项：
- 手机作为 Host
- 手机到手机直连
- 桌面端向手机端推送文件
- `app-plus` 原生文件/文件夹选择
- `app-plus` 原生扫码识别
- 本仓库内一键输出正式 Android APK

## 10. 已验证命令清单
本项目当前已完成并验证通过的关键命令包括：

```bash
pnpm test
pnpm build:shared
pnpm build:desktop
pnpm build:mobile
pnpm build:mobile:app
```

说明：
- `pnpm build:mobile` 对应移动端 `h5` 构建
- `pnpm build:mobile:app` 对应移动端 `app-plus` 构建
- `pnpm pack:desktop:dir` 受 Electron 发行包下载稳定性影响，可能出现外部网络导致的失败

## 11. 常见问题排查

### 11.1 桌面端能启动，但手机连不上
排查：
- 电脑与手机是否在同一局域网
- 桌面端显示的 IP 是否是可访问的局域网地址
- 防火墙是否拦截端口
- 二维码内容是否过期

### 11.2 手机连接后长期停留在等待中
排查：
- 桌面端是否已经点击允许连接
- 当前会话是否被主动断开
- 桌面端日志中是否存在连接异常

### 11.3 手机发起推送后没有开始上传
排查：
- 桌面端是否点击“选择位置并接收”
- 桌面端是否误点击“拒绝”
- 移动端是否仍处于 `connected`

### 11.4 Electron 打包失败
排查：
- 是否为 `electron-builder` 下载 Electron 包时网络中断
- 是否在目标平台上执行目标安装包打包
- 是否可先执行 `pnpm build:desktop` 验证代码构建正常

### 11.5 app-plus 有构建产物，但没有 APK
说明：
- 这是当前设计内的正常现象
- `uni-app` CLI 当前输出的是 `app-plus` 工程
- 仍需用 HBuilderX 继续打包成正式 APK

## 12. 验收结论模板
可在每次联调后按下面格式记录：

```markdown
# 验收记录

- 验证日期：YYYY-MM-DD
- 验证环境：macOS / Windows / Android / H5
- 桌面端版本：本地源码构建
- 移动端形态：H5 / app-plus

## 通过项
- [ ] 桌面 Host 启动
- [ ] 手机连接审批
- [ ] 多设备连接
- [ ] 手机推送文件到电脑
- [ ] 文件夹推送
- [ ] 拒绝接收
- [ ] 自动重命名
- [ ] 失败项重试
- [ ] 主动断开连接

## 未通过项
- [ ] 填写具体现象

## 备注
- 填写补充信息
```
