# Link Me Flutter Rewrite Progress

## 已完成

### Flutter 单项目替换

- 已清理旧 uni-app / Electron / shared workspace，改为 Flutter 单项目结构。
- 已生成 Android、iOS、macOS、Windows、Web 平台工程。
- Web 入口已拆为提示页，避免浏览器加载 `dart:io` 触发 `Unsupported operation: Platform._operatingSystem`。

### 设备与连接

- 已实现稳定持久化设备身份，优先显示真实设备名称。
- 已实现 UDP 局域网设备发现；跨网段场景可通过手动地址或二维码交换地址建立连接。
- 已支持手动添加连接，名称、IP 地址、端口号分开填写。
- 已支持顶部展示本机地址，并通过小二维码入口出示连接二维码。
- 已支持扫码连接：扫描 Link Me 二维码后添加对方设备。

### 文件传输

- 已实现 TCP 文件发送与接收，支持 Android、macOS 之间主动连接互传。
- 接收端新增确认弹窗，确认后发送端才开始传输；拒绝时发送端显示 rejected，接收端不写文件。
- 发送端等待接收端 `transfer_ack`，无 ACK 会标记失败。
- 接收端在文件写入完成、大小校验和 SHA-256 校验通过后才标记批次完成。
- 同名文件接收使用路径保留机制，避免并发或重复传输覆盖。
- 协议使用 `fileId` 更新进度，避免同批次同名文件状态混淆。

### 保存目录

- 默认保存目录统一为系统 Downloads 下的 `LinkMe`，例如 macOS：`/Users/用户名/Downloads/LinkMe`。
- 用户选择目录后会自动归一到其下的 `LinkMe` 子目录并持久化。
- 选择不可写目录时会提示不可写，配置不会静默失败。
- 接收完成后，接收方会弹窗提示保存路径，并可直接打开保存目录。

### UI 与记录

- 首页改为玻璃态风格顶部信息卡 + 主体 Tab。
- 主体 Tab 已拆为 `附近设备` 与 `传输记录`。
- 浮动加号按钮打开连接方式：出示二维码、扫一扫、手动添加。
- 附近设备卡片支持点击查看设备详情和该设备的传输历史。
- 传输记录支持删除，并可选择是否同时删除已接收文件。
- 传输记录按方向区分：接收为蓝色色调，发送为绿色色调，并展示明显标签。

### 平台权限

- Android 已声明网络、组播、相机、媒体/存储相关权限。
- Android 已将相机硬件标记为非必需，避免无摄像头设备无法安装。
- iOS/macOS 已声明本地网络、相册、相机 说明文案。


### 本轮补充

- macOS/桌面端接收文件提示改为页面内持久提示卡，不再只依赖弹窗路由；收到手机端文件请求时可直接接收、拒绝或修改目录。
- 新增文本直推协议：设备卡片和设备详情支持发送文本。
- 接收文本会直接弹窗展示，并支持一键复制。
- 新增文本推送 socket 回归测试，覆盖发送、接收和 ACK。


### 拍照发送

- 新增拍照发送入口：浮动加号中选择「拍照发送」。
- 拍照完成后弹出设备列表，选择设备后复用现有文件传输协议直接推送照片。
- Android/macOS 摄像头权限配置已补齐；macOS sandbox 增加 camera entitlement。
- 新增状态层测试覆盖拍照发送和取消拍照不发送。

## 当前验证

- `PUB_HOSTED_URL=https://mirrors.tuna.tsinghua.edu.cn/dart-pub/ flutter --no-version-check test`：通过，34/34 tests passed。
- `PUB_HOSTED_URL=https://mirrors.tuna.tsinghua.edu.cn/dart-pub/ flutter --no-version-check analyze`：通过，No issues found。
- `PUB_HOSTED_URL=https://mirrors.tuna.tsinghua.edu.cn/dart-pub/ flutter --no-version-check build apk --debug`：通过，产物为 `build/app/outputs/flutter-apk/app-debug.apk`。
- `PUB_HOSTED_URL=https://mirrors.tuna.tsinghua.edu.cn/dart-pub/ flutter --no-version-check build macos --debug`：通过，产物为 `build/macos/Build/Products/Debug/link_me.app`。

## 待你验收

- Android ↔ Android：同网段自动发现、确认接收、保存到 `Download/LinkMe`、接收完成后打开目录。
- macOS ↔ Android：跨网段用手动地址或二维码交换地址后互传。
- macOS ↔ macOS：同网段发现和互传；首次运行需允许本地网络/防火墙访问。
- 保存目录：默认是否为 `Downloads/LinkMe`，选择不可写目录时是否有明确提示。
- UI：顶部本机地址、小二维码、Tab、浮动加号、设备详情、收发记录颜色是否符合预期。

## 已知边界

- UDP 自动发现通常不能跨不同网段或不同网关广播域；跨网段需使用手动地址、二维码 或网络层打通路由/广播转发。
