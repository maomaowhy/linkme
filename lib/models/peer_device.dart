import 'dart:io';

class PeerEndpoint {
  const PeerEndpoint({this.host, this.hostName, required this.port})
    : assert(host != null || hostName != null);

  final InternetAddress? host;
  final String? hostName;
  final int port;

  Object get connectHost => host ?? hostName!;
  String get displayHost => host?.address ?? hostName!;
}

class PeerDevice {
  const PeerDevice({
    required this.deviceId,
    required this.name,
    required this.host,
    required this.port,
    required this.platform,
    required this.lastSeen,
    this.endpoints = const [],
  });

  final String deviceId;
  final String name;
  final InternetAddress host;
  final int port;
  final String platform;
  final DateTime lastSeen;
  final List<PeerEndpoint> endpoints;

  List<PeerEndpoint> get connectionEndpoints {
    if (endpoints.isNotEmpty) return endpoints;
    return [PeerEndpoint(host: host, port: port)];
  }

  String get displayHost => connectionEndpoints.first.displayHost;
  String get displayEndpoint => '$displayHost:$port';

  PeerDevice copyWith({
    String? name,
    InternetAddress? host,
    int? port,
    String? platform,
    DateTime? lastSeen,
    List<PeerEndpoint>? endpoints,
  }) {
    return PeerDevice(
      deviceId: deviceId,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      platform: platform ?? this.platform,
      lastSeen: lastSeen ?? this.lastSeen,
      endpoints: endpoints ?? this.endpoints,
    );
  }
}
