import 'package:flutter_test/flutter_test.dart';
import 'package:link_me/services/platform_capability_service.dart';

void main() {
  test('qr scanner is only enabled on platforms supported by plugin', () {
    expect(PlatformCapabilityService.supportsQrScannerOn('android'), isTrue);
    expect(PlatformCapabilityService.supportsQrScannerOn('ios'), isTrue);
    expect(PlatformCapabilityService.supportsQrScannerOn('macos'), isTrue);
    expect(PlatformCapabilityService.supportsQrScannerOn('windows'), isFalse);
    expect(PlatformCapabilityService.supportsQrScannerOn('linux'), isFalse);
  });
}
