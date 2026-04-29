import 'dart:io';

class PlatformCapabilityService {
  const PlatformCapabilityService._();

  static bool get supportsQrScanner =>
      supportsQrScannerOn(Platform.operatingSystem);

  static bool supportsQrScannerOn(String operatingSystem) {
    return switch (operatingSystem) {
      'android' || 'ios' || 'macos' => true,
      _ => false,
    };
  }
}
