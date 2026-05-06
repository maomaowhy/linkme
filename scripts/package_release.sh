#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FLUTTER_BIN="${FLUTTER_BIN:-}"
if [[ -z "$FLUTTER_BIN" ]]; then
  if command -v flutter >/dev/null 2>&1; then
    FLUTTER_BIN="flutter"
  elif [[ -x "/Users/wangzy/develop/flutter/bin/flutter" ]]; then
    FLUTTER_BIN="/Users/wangzy/develop/flutter/bin/flutter"
  else
    echo "未找到 flutter。请设置 FLUTTER_BIN=/path/to/flutter 后重试。" >&2
    exit 1
  fi
fi

DIST_DIR="$ROOT_DIR/dist"
APP_NAME="link_me"
IOS_SCHEME="Runner"
IOS_WORKSPACE="$ROOT_DIR/ios/Runner.xcworkspace"
MACOS_APP_PATH="$ROOT_DIR/build/macos/Build/Products/Release/link_me.app"

say() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
fail() { echo "错误：$*" >&2; exit 1; }

prompt_default() {
  local label="$1"
  local default_value="$2"
  local value
  read -r -p "$label [$default_value]: " value
  echo "${value:-$default_value}"
}

ensure_pub_get() {
  say "安装 Flutter 依赖"
  "$FLUTTER_BIN" --no-version-check pub get
}

write_export_options() {
  local path="$1"
  local method="$2"
  local team_id="$3"
  cat > "$path" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>$method</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>destination</key>
  <string>export</string>
  <key>stripSwiftSymbols</key>
  <true/>
  <key>compileBitcode</key>
  <false/>
PLIST
  if [[ -n "$team_id" ]]; then
    cat >> "$path" <<PLIST
  <key>teamID</key>
  <string>$team_id</string>
PLIST
  fi
  cat >> "$path" <<PLIST
</dict>
</plist>
PLIST
}

build_ios_ipa() {
  local out_dir="$DIST_DIR/ios"
  mkdir -p "$out_dir"

  [[ -d "$IOS_WORKSPACE" ]] || fail "找不到 $IOS_WORKSPACE"

  echo "请选择 iOS 导出方式："
  echo "  1) ad-hoc（内部分发，需要设备 UDID）"
  echo "  2) development（真机调试/开发包）"
  echo "  3) app-store（提交 App Store/TestFlight）"
  echo "  4) enterprise（企业签名）"
  local method_choice
  read -r -p "导出方式 [1]: " method_choice
  method_choice="${method_choice:-1}"

  local export_method="ad-hoc"
  case "$method_choice" in
    1) export_method="ad-hoc" ;;
    2) export_method="development" ;;
    3) export_method="app-store" ;;
    4) export_method="enterprise" ;;
    *) fail "未知 iOS 导出方式：$method_choice" ;;
  esac

  local team_id
  team_id="$(prompt_default "Apple Team ID（自动签名可留空）" "")"
  local allow_updates
  allow_updates="$(prompt_default "是否允许 Xcode 自动更新签名配置？yes/no" "yes")"

  local archive_path="$out_dir/${APP_NAME}.xcarchive"
  local export_path="$out_dir/ipa"
  local export_options="$out_dir/ExportOptions.plist"
  rm -rf "$archive_path" "$export_path"
  mkdir -p "$export_path"

  say "生成 iOS Flutter Release 配置"
  "$FLUTTER_BIN" --no-version-check build ios \
    --release \
    --config-only

  if command -v pod >/dev/null 2>&1; then
    say "安装 iOS Pods"
    (cd ios && pod install)
  else
    echo "未找到 pod，跳过 pod install；如 Xcode 构建失败请先安装 CocoaPods。"
  fi

  write_export_options "$export_options" "$export_method" "$team_id"

  say "通过 Xcode archive 生成 iOS 归档"
  local archive_cmd=(
    xcodebuild archive
    -workspace "$IOS_WORKSPACE"
    -scheme "$IOS_SCHEME"
    -configuration Release
    -archivePath "$archive_path"
    -destination "generic/platform=iOS"
  )
  if [[ -n "$team_id" ]]; then
    archive_cmd+=(DEVELOPMENT_TEAM="$team_id")
  fi
  if [[ "$allow_updates" == "yes" || "$allow_updates" == "y" ]]; then
    archive_cmd+=(-allowProvisioningUpdates)
  fi
  "${archive_cmd[@]}"

  say "导出 IPA"
  local export_cmd=(
    xcodebuild -exportArchive
    -archivePath "$archive_path"
    -exportPath "$export_path"
    -exportOptionsPlist "$export_options"
  )
  if [[ "$allow_updates" == "yes" || "$allow_updates" == "y" ]]; then
    export_cmd+=(-allowProvisioningUpdates)
  fi
  "${export_cmd[@]}"

  local ipa
  ipa="$(find "$export_path" -maxdepth 1 -name '*.ipa' -print -quit)"
  [[ -n "$ipa" ]] || fail "未找到导出的 IPA，请检查 Xcode 签名配置。"
  say "iOS IPA 已生成：$ipa"
}

build_macos_app() {
  local out_dir="$DIST_DIR/macos"
  mkdir -p "$out_dir"

  say "构建 macOS Release App"
  "$FLUTTER_BIN" --no-version-check build macos --release

  [[ -d "$MACOS_APP_PATH" ]] || fail "找不到 macOS app：$MACOS_APP_PATH"
  local zip_path="$out_dir/${APP_NAME}-macos.zip"
  rm -f "$zip_path"
  ditto -c -k --keepParent "$MACOS_APP_PATH" "$zip_path"
  say "macOS App 压缩包已生成：$zip_path"
}

build_android_apk() {
  local out_dir="$DIST_DIR/android"
  mkdir -p "$out_dir"

  say "构建 Android Release APK"
  "$FLUTTER_BIN" --no-version-check build apk --release

  local source_apk="$ROOT_DIR/build/app/outputs/flutter-apk/app-release.apk"
  [[ -f "$source_apk" ]] || fail "找不到 APK：$source_apk"
  local target_apk="$out_dir/${APP_NAME}-android.apk"
  cp "$source_apk" "$target_apk"
  say "Android APK 已生成：$target_apk"
}

main() {
  echo "Link Me 打包脚本"
  echo "请选择需要打包的平台："
  echo "  1) iOS IPA（Ad Hoc，Xcode archive/export）"
  echo "  2) macOS App zip"
  echo "  3) Android APK"
  echo "  4) 全部"
  local choice
  read -r -p "选择 [1]: " choice
  choice="${choice:-1}"

  mkdir -p "$DIST_DIR"
  ensure_pub_get

  case "$choice" in
    1) build_ios_ipa ;;
    2) build_macos_app ;;
    3) build_android_apk ;;
    4)
      build_ios_ipa
      build_macos_app
      build_android_apk
      ;;
    *) fail "未知平台选择：$choice" ;;
  esac

  say "打包完成。输出目录：$DIST_DIR"
}

main "$@"
