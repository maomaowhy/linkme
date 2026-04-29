import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:link_me/services/network_address_service.dart';

void main() {
  test('parseEndpoint accepts an IPv4 address with port', () {
    final endpoint = NetworkAddressService.parseEndpoint(
      '192.168.163.142:41587',
    );

    expect(endpoint.host.address, '192.168.163.142');
    expect(endpoint.port, 41587);
  });

  test('parseEndpoint rejects endpoints without a usable port', () {
    expect(
      () => NetworkAddressService.parseEndpoint('192.168.163.142'),
      throwsFormatException,
    );
    expect(
      () => NetworkAddressService.parseEndpoint('192.168.163.142:99999'),
      throwsFormatException,
    );
  });

  test('parseEndpoint rejects unroutable IPv4 addresses', () {
    expect(
      () => NetworkAddressService.parseEndpoint('0.0.1.1:53138'),
      throwsFormatException,
    );
    expect(
      () => NetworkAddressService.parseEndpoint('127.0.0.1:53138'),
      throwsFormatException,
    );
    expect(
      () => NetworkAddressService.parseEndpoint('224.0.0.1:53138'),
      throwsFormatException,
    );
    expect(
      () => NetworkAddressService.parseEndpoint('169.254.10.20:53138'),
      throwsFormatException,
    );
  });

  test('preferredLocalIpv4Addresses puts iOS Wi-Fi before other interfaces', () {
    final addresses = NetworkAddressService.preferredLocalIpv4Addresses([
      (interfaceName: 'awdl0', address: InternetAddress('169.254.10.20')),
      (interfaceName: 'bridge100', address: InternetAddress('172.20.10.1')),
      (interfaceName: 'en0', address: InternetAddress('192.168.1.20')),
      (interfaceName: 'pdp_ip0', address: InternetAddress('10.10.10.10')),
    ]);

    expect(addresses, ['192.168.1.20', '172.20.10.1', '10.10.10.10']);
  });
}
