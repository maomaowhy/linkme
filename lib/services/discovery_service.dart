import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/peer_device.dart';
import 'network_address_service.dart';

class DiscoveryService {
  DiscoveryService({this.discoveryPort = 45454});

  final int discoveryPort;
  RawDatagramSocket? _socket;
  Timer? _announceTimer;
  String? _deviceId;
  String? _deviceName;
  int? _transferPort;
  void Function(PeerDevice peer)? _onPeer;

  static bool usablePeerAddress(InternetAddress address) {
    return NetworkAddressService.isUsableIpv4Address(address);
  }

  static Set<String> broadcastTargetsFor(Iterable<String> localIpv4Addresses) {
    final targets = <String>{'255.255.255.255'};
    for (final address in localIpv4Addresses) {
      final parts = address
          .split('.')
          .map(int.tryParse)
          .toList(growable: false);
      if (parts.length != 4 || parts.any((part) => part == null)) continue;
      final first = parts[0]!;
      if (first == 0 || first == 127 || first >= 224) continue;
      targets.add('${parts[0]}.${parts[1]}.${parts[2]}.255');
    }
    return targets;
  }

  Future<void> start({
    required String deviceId,
    required String deviceName,
    required int transferPort,
    required void Function(PeerDevice peer) onPeer,
  }) async {
    await stop();
    _deviceId = deviceId;
    _deviceName = deviceName;
    _transferPort = transferPort;
    _onPeer = onPeer;
    _socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      discoveryPort,
      reuseAddress: true,
    );
    _socket!.broadcastEnabled = true;
    _socket!.listen(_handleSocketEvent, onError: (_) {});
    _safeAnnounce();
    _announceTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _safeAnnounce(),
    );
  }

  Future<void> stop() async {
    _announceTimer?.cancel();
    _announceTimer = null;
    _socket?.close();
    _socket = null;
  }

  void _safeAnnounce() {
    unawaited(_announce().catchError((_) {}));
  }

  Future<void> _announce() async {
    final socket = _socket;
    final deviceId = _deviceId;
    final deviceName = _deviceName;
    final transferPort = _transferPort;
    if (socket == null ||
        deviceId == null ||
        deviceName == null ||
        transferPort == null) {
      return;
    }

    final payload = utf8.encode(
      jsonEncode({
        'type': 'link_me_presence',
        'version': 1,
        'deviceId': deviceId,
        'name': deviceName,
        'platform': Platform.operatingSystem,
        'port': transferPort,
      }),
    );
    Set<String> targets;
    try {
      targets = await _broadcastTargets();
    } catch (_) {
      targets = const {'255.255.255.255'};
    }
    for (final target in targets) {
      try {
        final address = InternetAddress.tryParse(target);
        if (address == null) continue;
        socket.send(payload, address, discoveryPort);
      } catch (_) {
        // Ignore per-interface broadcast failures and keep trying others.
      }
    }
  }

  Future<Set<String>> _broadcastTargets() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      return broadcastTargetsFor(
        interfaces
            .expand((interface) => interface.addresses)
            .map((address) => address.address),
      );
    } catch (_) {
      return {'255.255.255.255'};
    }
  }

  void _handleSocketEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final datagram = _socket?.receive();
    if (datagram == null) return;
    try {
      final json =
          jsonDecode(utf8.decode(datagram.data)) as Map<String, Object?>;
      if (json['type'] != 'link_me_presence') return;
      if (json['deviceId'] == _deviceId) return;
      if (!usablePeerAddress(datagram.address)) return;
      final peer = PeerDevice(
        deviceId: json['deviceId'] as String,
        name: json['name'] as String,
        host: datagram.address,
        port: json['port'] as int,
        platform: json['platform'] as String? ?? 'unknown',
        lastSeen: DateTime.now(),
      );
      _onPeer?.call(peer);
      unawaited(_announceTo(datagram.address).catchError((_) {}));
    } catch (_) {
      return;
    }
  }

  Future<void> _announceTo(InternetAddress address) async {
    if (!usablePeerAddress(address)) return;
    final socket = _socket;
    final deviceId = _deviceId;
    final deviceName = _deviceName;
    final transferPort = _transferPort;
    if (socket == null ||
        deviceId == null ||
        deviceName == null ||
        transferPort == null) {
      return;
    }

    final payload = utf8.encode(
      jsonEncode({
        'type': 'link_me_presence',
        'version': 1,
        'deviceId': deviceId,
        'name': deviceName,
        'platform': Platform.operatingSystem,
        'port': transferPort,
      }),
    );
    try {
      socket.send(payload, address, discoveryPort);
    } catch (_) {
      // Best effort reply; periodic broadcasts still continue.
    }
  }
}
