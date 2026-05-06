# Repository Guidelines

## Project Structure & Module Organization

This is a Flutter app for local-network, AirDrop-style file transfer across Android, iOS, macOS, and Windows. Main Dart code lives in `lib/`: app entry points are under `lib/app/`, UI screens and widgets under `lib/ui/`, state management in `lib/state/`, models in `lib/models/`, and platform/network/file-transfer logic in `lib/services/`. Tests live in `test/` and generally mirror service or state responsibilities. Platform projects are in `android/`, `ios/`, `macos/`, `windows/`, and `web/`. Generated output such as `build/`, `.dart_tool/`, and platform ephemeral files should not be edited manually.

## Build, Test, and Development Commands

- `flutter pub get` installs Dart and Flutter dependencies.
- `flutter run -d macos` runs the desktop app locally.
- `flutter run -d android` or `flutter run -d ios` runs on a connected device or simulator.
- `flutter test` runs the full Flutter test suite.
- `flutter analyze` runs static analysis using `analysis_options.yaml` and `flutter_lints`.
- `flutter build macos --debug` and `flutter build apk --debug` validate platform builds.

If Flutter is not on `PATH`, use `/Users/wangzy/develop/flutter/bin/flutter --no-version-check ...`.

## Coding Style & Naming Conventions

Use Dart defaults and run `dart format` before finalizing changes. Prefer clear, descriptive names over abbreviations. Keep service classes focused, e.g. `TransferClient`, `DiscoveryService`, and `FileService`. Use `snake_case.dart` filenames, `PascalCase` classes, and `camelCase` members. Keep platform-specific behavior isolated in services or native platform folders rather than UI code.

## Testing Guidelines

Use `flutter_test`. Add focused tests for new behavior, especially transfer protocol, discovery, permissions, and file handling edge cases. Name tests by behavior, for example `sendTextTo reports network unavailable when sending fails`. Run targeted tests first, then `flutter test` before handoff.

## Commit & Pull Request Guidelines

Existing history uses short feature-style messages such as `[feature]flutter的tcp实现`. Keep commits concise and scoped. PRs should include a summary, affected platforms, verification commands, and screenshots or screen recordings for UI changes. Call out permission, entitlement, or networking changes explicitly.

## Security & Configuration Tips

Local-network behavior depends on platform permissions: iOS/macOS `NSLocalNetworkUsageDescription` and `NSBonjourServices`, Android nearby Wi-Fi/multicast permissions, and firewall access on desktop. Do not commit certificates, provisioning profiles, signing secrets, or local machine paths unless they are documented examples.

## 必做
如果遇到了额度不足和中断，继续请求，直到重复请求10次，依然没有结果，则终止
