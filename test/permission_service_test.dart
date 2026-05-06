import 'package:flutter_test/flutter_test.dart';
import 'package:link_me/services/permission_service.dart';
import 'package:permission_handler/permission_handler.dart';

import 'dart:io';

void main() {
  test(
    'Android startup permissions include nearby Wi-Fi for LAN discovery',
    () {
      expect(
        PermissionService.startupPermissionsFor('android'),
        contains(Permission.nearbyWifiDevices),
      );
    },
  );

  test('iOS startup permissions do not request Android-only nearby Wi-Fi', () {
    expect(
      PermissionService.startupPermissionsFor('ios'),
      isNot(contains(Permission.nearbyWifiDevices)),
    );
  });

  test('Android manifest declares nearby Wi-Fi permission', () async {
    final manifest = await File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsString();

    expect(manifest, contains('android.permission.NEARBY_WIFI_DEVICES'));
    expect(
      manifest,
      contains('android:usesPermissionFlags="neverForLocation"'),
    );
  });

  test('macOS plist declares Link Me Bonjour service variants', () async {
    final plist = await File('macos/Runner/Info.plist').readAsString();

    expect(plist, contains('<key>NSLocalNetworkUsageDescription</key>'));
    expect(plist, contains('<string>_linkme._tcp</string>'));
    expect(plist, contains('<string>_linkme._tcp.</string>'));
  });
}
