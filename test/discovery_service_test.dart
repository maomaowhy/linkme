import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:link_me/models/peer_device.dart';
import 'package:link_me/services/discovery_service.dart';

class FakeBonjourRegistration implements BonjourRegistrationHandle {}

class FakeBonjourDiscovery implements BonjourDiscoveryHandle {}

class FakeBonjourBackend implements BonjourBackend {
  BonjourServiceRecord? registeredService;
  String? discoveryType;
  void Function(BonjourServiceRecord service, BonjourServiceStatus status)?
  listener;
  var unregisterCalled = false;
  var stopDiscoveryCalled = false;

  @override
  Future<BonjourRegistrationHandle> register(
    BonjourServiceRecord service,
  ) async {
    registeredService = service;
    return FakeBonjourRegistration();
  }

  @override
  Future<BonjourDiscoveryHandle> startDiscovery(
    String serviceType,
    void Function(BonjourServiceRecord service, BonjourServiceStatus status)
    onService,
  ) async {
    discoveryType = serviceType;
    listener = onService;
    return FakeBonjourDiscovery();
  }

  @override
  Future<void> unregister(BonjourRegistrationHandle registration) async {
    unregisterCalled = true;
  }

  @override
  Future<void> stopDiscovery(BonjourDiscoveryHandle discovery) async {
    stopDiscoveryCalled = true;
  }

  void emitFound(BonjourServiceRecord service) {
    listener?.call(service, BonjourServiceStatus.found);
  }
}

Uint8List text(String value) => Uint8List.fromList(utf8.encode(value));

void main() {
  test('start registers and discovers the Link Me Bonjour service', () async {
    final backend = FakeBonjourBackend();
    final service = DiscoveryService(backend: backend, platformName: 'ios');

    await service.start(
      deviceId: 'device-1',
      deviceName: 'iPhone',
      transferPort: 45678,
      advertisedEndpoints: const ['192.168.1.8:45678'],
      onPeer: (_) {},
    );

    expect(backend.registeredService?.type, DiscoveryService.serviceType);
    expect(backend.registeredService?.txt?['eps'], text('192.168.1.8:45678'));
    expect(backend.registeredService?.port, 45678);
    expect(backend.registeredService?.txt?['did'], text('device-1'));
    expect(backend.registeredService?.txt?['dn'], text('iPhone'));
    expect(backend.registeredService?.txt?['plat'], text('ios'));
    expect(backend.discoveryType, DiscoveryService.serviceType);
  });

  test('discovered Bonjour services are converted to peer devices', () async {
    final backend = FakeBonjourBackend();
    final peers = <PeerDevice>[];
    final service = DiscoveryService(backend: backend, platformName: 'android');

    await service.start(
      deviceId: 'android-1',
      deviceName: 'Android',
      transferPort: 45678,
      onPeer: peers.add,
    );

    backend.emitFound(
      BonjourServiceRecord(
        name: 'iPhone',
        type: DiscoveryService.serviceType,
        host: 'iphone.local',
        port: 56789,
        addresses: [InternetAddress('192.168.1.30')],
        txt: {
          'did': text('ios-1'),
          'dn': text('Wang iPhone'),
          'plat': text('ios'),
        },
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(peers, hasLength(1));
    expect(peers.single.deviceId, 'ios-1');
    expect(peers.single.name, 'Wang iPhone');
    expect(peers.single.host.address, '192.168.1.30');
    expect(peers.single.port, 56789);
    expect(peers.single.platform, 'ios');
    expect(
      peers.single.endpoints.map((endpoint) => endpoint.displayHost),
      contains('192.168.1.30'),
    );
  });

  test(
    'discovered Android Bonjour services can use advertised endpoints',
    () async {
      final backend = FakeBonjourBackend();
      final peers = <PeerDevice>[];
      final service = DiscoveryService(backend: backend, platformName: 'macos');

      await service.start(
        deviceId: 'mac-1',
        deviceName: 'Mac',
        transferPort: 45678,
        onPeer: peers.add,
      );

      backend.emitFound(
        BonjourServiceRecord(
          name: 'Android',
          type: DiscoveryService.serviceType,
          host: 'localhost',
          port: 56789,
          txt: {
            'did': text('android-1'),
            'dn': text('Android Phone'),
            'plat': text('android'),
            'eps': text('192.168.1.40:56789'),
          },
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(peers, hasLength(1));
      expect(peers.single.endpoints.single.displayHost, '192.168.1.40');
      expect(peers.single.port, 56789);
    },
  );

  test('discovered Apple Bonjour services can use local hostnames', () async {
    final backend = FakeBonjourBackend();
    final peers = <PeerDevice>[];
    final service = DiscoveryService(backend: backend, platformName: 'macos');

    await service.start(
      deviceId: 'mac-1',
      deviceName: 'Mac',
      transferPort: 45678,
      onPeer: peers.add,
    );

    backend.emitFound(
      BonjourServiceRecord(
        name: 'iPhone',
        type: DiscoveryService.serviceType,
        host: 'iphone.local.',
        port: 56789,
        txt: {
          'did': text('ios-1'),
          'dn': text('Wang iPhone'),
          'plat': text('ios'),
        },
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(peers, hasLength(1));
    expect(peers.single.endpoints.single.hostName, 'iphone.local');
    expect(peers.single.endpoints.single.displayHost, 'iphone.local');
  });

  test('discovery ignores self and lost Bonjour events', () async {
    final backend = FakeBonjourBackend();
    final peers = <PeerDevice>[];
    final service = DiscoveryService(backend: backend);

    await service.start(
      deviceId: 'self-1',
      deviceName: 'Self',
      transferPort: 45678,
      onPeer: peers.add,
    );

    final self = BonjourServiceRecord(
      name: 'Self',
      type: DiscoveryService.serviceType,
      port: 45678,
      addresses: [InternetAddress('192.168.1.20')],
      txt: {'did': text('self-1')},
    );
    backend.listener?.call(self, BonjourServiceStatus.found);
    backend.listener?.call(self, BonjourServiceStatus.lost);
    await Future<void>.delayed(Duration.zero);

    expect(peers, isEmpty);
  });

  test('stop unregisters Bonjour service and stops discovery', () async {
    final backend = FakeBonjourBackend();
    final service = DiscoveryService(backend: backend);

    await service.start(
      deviceId: 'device-1',
      deviceName: 'Device',
      transferPort: 45678,
      onPeer: (_) {},
    );
    await service.stop();

    expect(backend.unregisterCalled, isTrue);
    expect(backend.stopDiscoveryCalled, isTrue);
  });
}
