import 'package:flutter_test/flutter_test.dart';
import 'package:link_me/services/device_identity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeDeviceNameProvider implements DeviceNameProvider {
  const FakeDeviceNameProvider(this.name);

  final String? name;

  @override
  Future<String?> loadDeviceName() async => name;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'uses platform device name when no custom name has been saved',
    () async {
      SharedPreferences.setMockInitialValues({});

      final identity = await DeviceIdentityService(
        deviceNameProvider: const FakeDeviceNameProvider('王的 ZTE A2021'),
      ).load();

      expect(identity.name, '王的 ZTE A2021');

      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('link_me.device_name'), '王的 ZTE A2021');
    },
  );

  test('keeps saved custom name even if platform name changes', () async {
    SharedPreferences.setMockInitialValues({'link_me.device_name': '我的手机'});

    final identity = await DeviceIdentityService(
      deviceNameProvider: const FakeDeviceNameProvider('ZTE A2021'),
    ).load();

    expect(identity.name, '我的手机');
  });

  test('refreshes old generic Android Phone name with platform name', () async {
    SharedPreferences.setMockInitialValues({
      'link_me.device_name': 'Android Phone',
    });

    final identity = await DeviceIdentityService(
      deviceNameProvider: const FakeDeviceNameProvider('ZTE A2021'),
    ).load();

    expect(identity.name, 'ZTE A2021');

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('link_me.device_name'), 'ZTE A2021');
  });
}
