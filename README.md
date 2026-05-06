# Link Me

Link Me 现在是一个纯 Flutter 的局域网 AirDrop 风格文件互传应用，目标支持 macOS、Windows、Android、iOS。当前版本不依赖云端服务：设备在同一局域网内自动发现，点击附近设备即可多选文件并通过 TCP 直连传输。

## 当前能力

- 跨端 Flutter 单项目：`android`、`ios`、`macos`、`windows`。
- 稳定设备身份：首次启动生成并持久化 `deviceId`。
- 局域网发现：Bonjour/mDNS（NSD/DNS-SD）发现在线 Link Me 设备，兼容 iOS 本地网络权限模型。
- 局域网直传：`dart:io` TCP Socket 分片传输文件。
- 多选文件：使用 `file_picker` 选择多个文件。
- 自动接收：接收端保存到默认目录，可在首页修改并持久化。
- 接收确认：接收端会先弹窗确认，确认后才开始写入文件，拒绝则不会保存任何内容。
- 权限提示：保存目录不可写时会提示修改目录或授权，不再只让发送端看到 `receiver closed without ack`。
- 传输进度：双端展示批次进度、状态和失败信息。
- 玻璃态首页：附近设备、保存目录、传输记录集中展示。

## 运行

```bash
flutter pub get
flutter run -d macos
flutter run -d windows
flutter run -d android
flutter run -d ios
```

如果你的终端没有配置 Flutter PATH，可以使用本机当前路径：

```bash
/Users/wangzy/develop/flutter/bin/flutter --no-version-check pub get
/Users/wangzy/develop/flutter/bin/flutter --no-version-check run -d macos
```

国内网络建议：

```bash
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
```

## 打包发布

项目提供交互式打包脚本，可按平台选择构建 iOS、macOS、Android，产物统一输出到 `dist/`。首次使用前确保已安装 Flutter、Xcode；iOS 还需要 Apple Developer 账号、证书、描述文件和已登记的测试设备 UDID。

```bash
chmod +x scripts/package_release.sh
./scripts/package_release.sh
```

脚本启动后选择打包类别：

- `1) iOS IPA（Ad Hoc，Xcode archive/export）`：默认导出 Ad Hoc IPA，用于内部分发或真机安装测试。
- `2) macOS App zip`：构建 macOS Release App，并压缩成 zip。
- `3) Android APK`：构建 Android Release APK。
- `4) 全部`：按 iOS、macOS、Android 顺序依次打包。

打包产物目录：

- iOS：`dist/ios/ipa/*.ipa`，中间归档为 `dist/ios/link_me.xcarchive`，导出配置为 `dist/ios/ExportOptions.plist`。
- macOS：`dist/macos/link_me-macos.zip`。
- Android：`dist/android/link_me-android.apk`。

如果 iOS 签名失败，优先检查 Xcode 是否登录正确团队、Bundle ID 是否匹配、Ad Hoc 描述文件是否包含目标设备 UDID。也可以直接打开 `ios/Runner.xcworkspace`，选择 `Runner` scheme 后通过 Xcode 的 `Product > Archive` 手动归档和导出。

## 验证

```bash
flutter test
flutter analyze
flutter build macos --debug
```

## Web / Chrome 说明

Chrome/Web 不能使用 `dart:io` 的 TCP Socket、Bonjour/mDNS 发现和本地文件系统能力，因此浏览器版本只作为说明页，不提供文件互传。请使用 Android、iOS、macOS 或 Windows 客户端进行局域网互传。

```bash
flutter run -d chrome
flutter build web
```

以上命令应能正常打开 Web 提示页，不会再出现 `Unsupported operation: Platform._operatingSystem`。

## Android 保存目录

Android 默认保存到 App 专属外部目录，避免直接写入 `/storage/emulated/0/Download` 触发 scoped storage 的 `Permission denied`。如果用户手动选择的保存目录不可写，接收确认弹窗会提示修改目录或授权。

## 局域网使用说明

1. 两台设备连接同一个 Wi-Fi / 局域网。
2. 两端都打开 Link Me，并允许本地网络、防火墙或文件访问权限。
3. 在“附近设备”中选择目标设备。
4. 多选文件后开始发送。
5. 接收端文件默认保存到系统下载目录；可在首页修改保存目录。

## 技术说明

- 发现层：使用 `nsd` 插件发布和发现 `_linkme._tcp` Bonjour/mDNS 服务；服务 TXT 记录携带设备 ID、设备名和平台，发现到服务后继续使用现有 TCP 传输协议。
- 传输层：协议采用 4 字节大端长度前缀 JSON frame + 原始文件字节流，避免大文件一次性载入内存。
- 历史层：当前运行期保留传输批次；下一步可把批次记录落盘到 `shared_preferences` 或本地数据库。
