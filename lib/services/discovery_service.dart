import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:nsd/nsd.dart' as nsd;

import '../models/peer_device.dart';
import 'network_address_service.dart';

class BonjourServiceRecord {
  const BonjourServiceRecord({
    required this.name,
    required this.type,
    this.host,
    required this.port,
    this.addresses = const [],
    this.txt,
  });

  final String name;
  final String type;
  final String? host;
  final int port;
  final List<InternetAddress> addresses;
  final Map<String, Uint8List?>? txt;
}

enum BonjourServiceStatus { found, lost }

abstract class BonjourRegistrationHandle {}

abstract class BonjourDiscoveryHandle {}

abstract class BonjourBackend {
  Future<BonjourRegistrationHandle> register(BonjourServiceRecord service);

  Future<BonjourDiscoveryHandle> startDiscovery(
    String serviceType,
    void Function(BonjourServiceRecord service, BonjourServiceStatus status)
    onService,
  );

  Future<void> unregister(BonjourRegistrationHandle registration);

  Future<void> stopDiscovery(BonjourDiscoveryHandle discovery);
}

class NsdBonjourRegistrationHandle implements BonjourRegistrationHandle {
  NsdBonjourRegistrationHandle(this.registration);

  final nsd.Registration registration;
}

class NsdBonjourDiscoveryHandle implements BonjourDiscoveryHandle {
  NsdBonjourDiscoveryHandle(this.discovery);

  final nsd.Discovery discovery;
}

class NsdBonjourBackend implements BonjourBackend {
  @override
  Future<BonjourRegistrationHandle> register(
    BonjourServiceRecord service,
  ) async {
    final registration = await nsd.register(
      nsd.Service(
        name: service.name,
        type: service.type,
        port: service.port,
        txt: service.txt,
      ),
    );
    return NsdBonjourRegistrationHandle(registration);
  }

  @override
  Future<BonjourDiscoveryHandle> startDiscovery(
    String serviceType,
    void Function(BonjourServiceRecord service, BonjourServiceStatus status)
    onService,
  ) async {
    final discovery = await nsd.startDiscovery(
      serviceType,
      ipLookupType: nsd.IpLookupType.v4,
    );
    discovery.addServiceListener((service, status) {
      final port = service.port;
      final name = service.name;
      final type = service.type;
      if (port == null || name == null || type == null) return;
      onService(
        BonjourServiceRecord(
          name: name,
          type: type,
          host: service.host,
          port: port,
          addresses: service.addresses ?? const [],
          txt: service.txt,
        ),
        status == nsd.ServiceStatus.found
            ? BonjourServiceStatus.found
            : BonjourServiceStatus.lost,
      );
    });
    return NsdBonjourDiscoveryHandle(discovery);
  }

  @override
  Future<void> unregister(BonjourRegistrationHandle registration) async {
    if (registration is NsdBonjourRegistrationHandle) {
      await nsd.unregister(registration.registration);
    }
  }

  @override
  Future<void> stopDiscovery(BonjourDiscoveryHandle discovery) async {
    if (discovery is NsdBonjourDiscoveryHandle) {
      await nsd.stopDiscovery(discovery.discovery);
    }
  }
}

class DiscoveryService {
  DiscoveryService({
    BonjourBackend? backend,
    String? platformName,
    this.discoveryPort = 45454,
  }) : _backend = backend ?? NsdBonjourBackend(),
       _platformName = platformName ?? Platform.operatingSystem;

  static const serviceType = '_linkme._tcp';

  final int discoveryPort;
  final BonjourBackend _backend;
  final String _platformName;

  BonjourRegistrationHandle? _registration;
  BonjourDiscoveryHandle? _discovery;
  String? _deviceId;
  void Function(PeerDevice peer)? _onPeer;

  static bool usablePeerAddress(InternetAddress address) {
    return NetworkAddressService.isUsableIpv4Address(address);
  }

  Future<void> start({
    required String deviceId,
    required String deviceName,
    required int transferPort,
    List<String> advertisedEndpoints = const [],
    required void Function(PeerDevice peer) onPeer,
  }) async {
    await stop();
    _deviceId = deviceId;
    _onPeer = onPeer;
    _registration = await _backend.register(
      BonjourServiceRecord(
        name: _serviceName(deviceName, deviceId),
        type: serviceType,
        port: transferPort,
        txt: {
          'did': _txt(deviceId),
          'dn': _txt(deviceName),
          'plat': _txt(_platformName),
          if (advertisedEndpoints.isNotEmpty)
            'eps': _txt(advertisedEndpoints.join(',')),
        },
      ),
    );
    _discovery = await _backend.startDiscovery(
      serviceType,
      _handleBonjourEvent,
    );
  }

  Future<void> stop() async {
    final discovery = _discovery;
    _discovery = null;
    if (discovery != null) {
      try {
        await _backend.stopDiscovery(discovery);
      } catch (_) {}
    }

    final registration = _registration;
    _registration = null;
    if (registration != null) {
      try {
        await _backend.unregister(registration);
      } catch (_) {}
    }
  }

  void _handleBonjourEvent(
    BonjourServiceRecord service,
    BonjourServiceStatus status,
  ) {
    if (status != BonjourServiceStatus.found) return;
    unawaited(
      _peerFromService(service)
          .then((peer) {
            if (peer == null) return;
            _onPeer?.call(peer);
          })
          .catchError((_) {}),
    );
  }

  Future<PeerDevice?> _peerFromService(BonjourServiceRecord service) async {
    final port = service.port;
    if (port <= 0 || port > 65535) return null;
    final deviceId = _txtString(service.txt, 'did') ?? service.name;
    if (deviceId.isEmpty || deviceId == _deviceId) return null;
    final endpoints = await _endpointsFor(service, port);
    if (endpoints.isEmpty) return null;
    return PeerDevice(
      deviceId: deviceId,
      name: _txtString(service.txt, 'dn') ?? service.name,
      host: endpoints.first.host ?? InternetAddress.anyIPv4,
      port: endpoints.first.port,
      platform: _txtString(service.txt, 'plat') ?? 'bonjour',
      lastSeen: DateTime.now(),
      endpoints: endpoints,
    );
  }

  Future<List<PeerEndpoint>> _endpointsFor(
    BonjourServiceRecord service,
    int port,
  ) async {
    final addresses = <InternetAddress>[];
    final hostNames = <String>[];
    final advertised = _txtString(service.txt, 'eps');
    if (advertised != null) {
      for (final endpointText in advertised.split(',')) {
        try {
          final endpoint = NetworkAddressService.parseEndpoint(endpointText);
          addresses.add(endpoint.host);
        } catch (_) {}
      }
    }
    for (final address in service.addresses) {
      if (usablePeerAddress(address)) addresses.add(address);
    }
    final host = service.host;
    final parsedHost = host == null ? null : InternetAddress.tryParse(host);
    if (parsedHost != null && usablePeerAddress(parsedHost)) {
      addresses.add(parsedHost);
    } else if (host != null && _usableLocalHostName(host)) {
      hostNames.add(_normalizeLocalHostName(host));
    } else if (host != null && addresses.isEmpty) {
      try {
        final resolved = await InternetAddress.lookup(
          host,
          type: InternetAddressType.IPv4,
        );
        addresses.addAll(resolved.where(usablePeerAddress));
      } catch (_) {}
    }
    final unique = <String, PeerEndpoint>{};
    for (final address in addresses) {
      unique.putIfAbsent(
        '${address.address}:$port',
        () => PeerEndpoint(host: address, port: port),
      );
    }
    for (final hostName in hostNames) {
      unique.putIfAbsent(
        '$hostName:$port',
        () => PeerEndpoint(hostName: hostName, port: port),
      );
    }
    return unique.values.toList(growable: false);
  }

  static bool _usableLocalHostName(String host) {
    final normalized = _normalizeLocalHostName(host);
    return normalized.isNotEmpty && normalized.toLowerCase().endsWith('.local');
  }

  static String _normalizeLocalHostName(String host) {
    return host.trim().replaceFirst(RegExp(r'\.+$'), '');
  }

  static Uint8List _txt(String value) => Uint8List.fromList(utf8.encode(value));

  static String? _txtString(Map<String, Uint8List?>? txt, String key) {
    final value = txt?[key];
    if (value == null) return null;
    try {
      return utf8.decode(value);
    } catch (_) {
      return null;
    }
  }

  static String _serviceName(String deviceName, String deviceId) {
    final name = deviceName.trim().isEmpty ? 'Link Me' : deviceName.trim();
    final suffix = deviceId.length <= 6
        ? deviceId
        : deviceId.substring(deviceId.length - 6);
    return '$name-$suffix';
  }
}
