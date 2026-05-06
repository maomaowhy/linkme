import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  static List<Permission> startupPermissionsFor(String operatingSystem) {
    if (operatingSystem == 'android') {
      return const [
        Permission.nearbyWifiDevices,
        Permission.storage,
        Permission.photos,
        Permission.videos,
        Permission.audio,
      ];
    }
    if (operatingSystem == 'ios') {
      return const [Permission.photos];
    }
    return const [];
  }

  Future<void> requestStartupPermissions() async {
    for (final permission in startupPermissionsFor(Platform.operatingSystem)) {
      await permission.request();
    }
  }
}
