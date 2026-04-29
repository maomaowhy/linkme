import 'dart:io';

class ManualEndpoint {
  const ManualEndpoint({required this.host, required this.port});

  final InternetAddress host;
  final int port;
}

class NetworkAddressService {
  const NetworkAddressService();

  static bool isUsableIpv4Address(InternetAddress address) {
    if (address.type != InternetAddressType.IPv4) return false;
    if (address.isLoopback) return false;
    final raw = address.rawAddress;
    if (raw.length != 4) return false;
    final first = raw[0];
    final second = raw[1];
    if (first == 0 || first == 127 || first >= 224) return false;
    return !(first == 169 && second == 254);
  }

  static ManualEndpoint parseEndpoint(String input) {
    final trimmed = input.trim();
    final separatorIndex = trimmed.lastIndexOf(':');
    if (separatorIndex <= 0 || separatorIndex == trimmed.length - 1) {
      throw const FormatException('请输入类似 192.168.163.142:41587 的地址。');
    }

    final hostText = trimmed.substring(0, separatorIndex).trim();
    final portText = trimmed.substring(separatorIndex + 1).trim();
    final host = InternetAddress.tryParse(hostText);
    final port = int.tryParse(portText);
    if (host == null || !isUsableIpv4Address(host)) {
      throw const FormatException(
        '请输入可连接的局域网 IPv4 地址，例如 192.168.163.142:41587。',
      );
    }
    if (port == null || port <= 0 || port > 65535) {
      throw const FormatException('端口无效，请输入 1-65535 之间的端口。');
    }
    return ManualEndpoint(host: host, port: port);
  }

  Future<List<String>> localIpv4Addresses() async {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );
    return preferredLocalIpv4Addresses(
      interfaces.expand(
        (interface) => interface.addresses.map(
          (address) => (interfaceName: interface.name, address: address),
        ),
      ),
    );
  }

  static List<String> preferredLocalIpv4Addresses(
    Iterable<({String interfaceName, InternetAddress address})> entries,
  ) {
    final unique = <String, ({String interfaceName, InternetAddress address})>{};
    for (final entry in entries) {
      if (!isUsableIpv4Address(entry.address)) continue;
      unique.putIfAbsent(entry.address.address, () => entry);
    }
    final sorted = unique.values.toList(growable: false)
      ..sort((a, b) {
        final interfaceCompare = _interfacePriority(
          a.interfaceName,
        ).compareTo(_interfacePriority(b.interfaceName));
        if (interfaceCompare != 0) return interfaceCompare;
        final addressCompare = _addressPriority(
          a.address,
        ).compareTo(_addressPriority(b.address));
        if (addressCompare != 0) return addressCompare;
        return a.address.address.compareTo(b.address.address);
      });
    return sorted.map((entry) => entry.address.address).toList(growable: false);
  }

  static int _interfacePriority(String interfaceName) {
    final normalized = interfaceName.toLowerCase();
    if (normalized == 'en0' ||
        normalized.startsWith('wlan') ||
        normalized.startsWith('wifi') ||
        normalized.contains('wi-fi')) {
      return 0;
    }
    if (normalized.startsWith('eth') || normalized.startsWith('en')) return 1;
    if (normalized.startsWith('bridge')) return 2;
    if (normalized.startsWith('pdp') ||
        normalized.startsWith('rmnet') ||
        normalized.startsWith('ccmni')) {
      return 4;
    }
    return 3;
  }

  static int _addressPriority(InternetAddress address) {
    final raw = address.rawAddress;
    if (raw[0] == 192 && raw[1] == 168) return 0;
    if (raw[0] == 10) return 1;
    if (raw[0] == 172 && raw[1] >= 16 && raw[1] <= 31) return 2;
    return 3;
  }
}
