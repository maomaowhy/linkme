import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  Future<void> requestStartupPermissions() async {
    if (Platform.isAndroid) {
      await Permission.storage.request();
      await Permission.photos.request();
      await Permission.videos.request();
      await Permission.audio.request();
    } else if (Platform.isIOS) {
      await Permission.photos.request();
    }
  }
}
