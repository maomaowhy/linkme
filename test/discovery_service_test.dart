import 'package:flutter_test/flutter_test.dart';
import 'package:link_me/services/discovery_service.dart';

import 'dart:io';

void main() {
  test('usablePeerAddress rejects unspecified and multicast addresses', () {
    expect(
      DiscoveryService.usablePeerAddress(InternetAddress.anyIPv4),
      isFalse,
    );
    expect(
      DiscoveryService.usablePeerAddress(InternetAddress.loopbackIPv4),
      isFalse,
    );
    expect(
      DiscoveryService.usablePeerAddress(InternetAddress('224.0.0.1')),
      isFalse,
    );
    expect(
      DiscoveryService.usablePeerAddress(InternetAddress('192.168.1.2')),
      isTrue,
    );
  });

  test('broadcastTargets excludes unspecified and loopback addresses', () {
    final targets = DiscoveryService.broadcastTargetsFor([
      '0.0.0.0',
      '127.0.0.1',
      '224.0.0.1',
    ]);

    expect(targets, contains('255.255.255.255'));
    expect(targets, isNot(contains('0.0.0.255')));
    expect(targets, isNot(contains('127.0.0.255')));
    expect(targets, isNot(contains('224.0.0.255')));
  });

  test('broadcastTargets includes limited and subnet broadcasts', () {
    final targets = DiscoveryService.broadcastTargetsFor([
      '192.168.31.42',
      '10.0.0.8',
    ]);

    expect(targets, contains('255.255.255.255'));
    expect(targets, contains('192.168.31.255'));
    expect(targets, contains('10.0.0.255'));
  });
}
