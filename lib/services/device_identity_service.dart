import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceIdentity {
  const DeviceIdentity({required this.deviceId, required this.name});

  final String deviceId;
  final String name;
}

abstract class DeviceNameProvider {
  Future<String?> loadDeviceName();
}

class NativeDeviceNameProvider implements DeviceNameProvider {
  static const _channel = MethodChannel('link_me/device_info');

  @override
  Future<String?> loadDeviceName() async {
    try {
      final name = await _channel.invokeMethod<String>('getDeviceName');
      final cleaned = name?.trim();
      if (cleaned == null || cleaned.isEmpty) return null;
      return cleaned;
    } catch (_) {
      return null;
    }
  }
}

class DeviceIdentityService {
  DeviceIdentityService({DeviceNameProvider? deviceNameProvider})
    : _deviceNameProvider = deviceNameProvider ?? NativeDeviceNameProvider();

  static const _deviceIdKey = 'link_me.device_id';
  static const _deviceNameKey = 'link_me.device_name';

  final DeviceNameProvider _deviceNameProvider;

  Future<DeviceIdentity> load() async {
    final preferences = await SharedPreferences.getInstance();
    var deviceId = preferences.getString(_deviceIdKey);
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = _createDeviceId();
      await preferences.setString(_deviceIdKey, deviceId);
    }

    var name = preferences.getString(_deviceNameKey);
    if (name == null || name.isEmpty || _isLegacyGenericName(name)) {
      name = await _defaultDeviceName();
      await preferences.setString(_deviceNameKey, name);
    }

    return DeviceIdentity(deviceId: deviceId, name: name);
  }

  String _createDeviceId() {
    final random = Random.secure();
    final values = List<int>.generate(16, (_) => random.nextInt(256));
    final hex = values
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return 'lm-$hex';
  }

  bool _isLegacyGenericName(String name) {
    return const {
      'Android Phone',
      'iPhone',
      'Mac',
      'Windows PC',
      'Link Me Device',
    }.contains(name.trim());
  }

  Future<String> _defaultDeviceName() async {
    final nativeName = await _deviceNameProvider.loadDeviceName();
    if (nativeName != null && nativeName.isNotEmpty) return nativeName;

    final host = Platform.localHostname.trim();
    if (host.isNotEmpty && host != 'localhost') return host;
    if (Platform.isAndroid) return 'Android Phone';
    if (Platform.isIOS) return 'iPhone';
    if (Platform.isMacOS) return 'Mac';
    if (Platform.isWindows) return 'Windows PC';
    return 'Link Me Device';
  }
}
