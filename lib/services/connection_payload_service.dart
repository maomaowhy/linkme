import 'dart:convert';
import 'dart:io';

import '../models/peer_device.dart';
import 'network_address_service.dart';

class ConnectionPayloadService {
  static const payloadType = 'link_me_connection';
  static const payloadVersion = 1;

  String encode({
    required String deviceId,
    required String deviceName,
    required List<String> endpoints,
  }) {
    return jsonEncode({
      'type': payloadType,
      'version': payloadVersion,
      'deviceId': deviceId,
      'name': deviceName,
      'endpoints': endpoints,
    });
  }

  PeerDevice decode(String payload, {String fallbackPlatform = 'qr'}) {
    final json = jsonDecode(payload) as Map<String, Object?>;
    if (json['type'] != payloadType) {
      throw const FormatException('不是 Link Me 连接二维码。');
    }
    final endpoints = (json['endpoints'] as List<Object?>?)
        ?.whereType<String>()
        .toList(growable: false);
    if (endpoints == null || endpoints.isEmpty) {
      throw const FormatException('二维码中没有可连接地址。');
    }
    final parsedEndpoints = <PeerEndpoint>[];
    for (final candidate in endpoints) {
      try {
        final endpoint = _parseEndpoint(candidate);
        if (parsedEndpoints.any(
          (entry) =>
              entry.host.address == endpoint.host.address &&
              entry.port == endpoint.port,
        )) {
          continue;
        }
        parsedEndpoints.add(
          PeerEndpoint(host: endpoint.host, port: endpoint.port),
        );
      } catch (_) {
        // Try the next advertised address; multi-network devices may include unusable interfaces.
      }
    }
    if (parsedEndpoints.isEmpty) {
      throw const FormatException('二维码中没有可连接地址。');
    }
    final endpoint = parsedEndpoints.first;
    return PeerDevice(
      deviceId:
          json['deviceId'] as String? ??
          'qr-${endpoint.host.address}:${endpoint.port}',
      name: json['name'] as String? ?? '扫码设备 ${endpoint.host.address}',
      host: endpoint.host,
      port: endpoint.port,
      platform: fallbackPlatform,
      lastSeen: DateTime.now(),
      endpoints: parsedEndpoints,
    );
  }

  ({InternetAddress host, int port}) _parseEndpoint(String endpoint) {
    final separatorIndex = endpoint.lastIndexOf(':');
    if (separatorIndex <= 0 || separatorIndex == endpoint.length - 1) {
      throw const FormatException('连接地址格式无效。');
    }
    final host = InternetAddress.tryParse(
      endpoint.substring(0, separatorIndex),
    );
    final port = int.tryParse(endpoint.substring(separatorIndex + 1));
    if (host == null ||
        !NetworkAddressService.isUsableIpv4Address(host) ||
        port == null ||
        port <= 0 ||
        port > 65535) {
      throw const FormatException('连接地址格式无效。');
    }
    return (host: host, port: port);
  }
}
