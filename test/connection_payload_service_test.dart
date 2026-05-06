import 'package:flutter_test/flutter_test.dart';
import 'package:link_me/services/connection_payload_service.dart';

void main() {
  test('encodes and decodes a Link Me connection payload', () {
    final service = ConnectionPayloadService();

    final payload = service.encode(
      deviceId: 'device-1',
      deviceName: '我的手机',
      endpoints: ['192.168.162.142:41587'],
    );
    final peer = service.decode(payload);

    expect(peer.deviceId, 'device-1');
    expect(peer.name, '我的手机');
    expect(peer.host.address, '192.168.162.142');
    expect(peer.port, 41587);
  });

  test('skips unusable QR endpoints and uses the first routable endpoint', () {
    final peer = ConnectionPayloadService().decode(
      '{"type":"link_me_connection","version":1,"deviceId":"device-1","name":"电脑","endpoints":["0.0.1.1:53138","169.254.10.20:53138","192.168.1.20:53138"]}',
    );

    expect(peer.host.address, '192.168.1.20');
    expect(peer.port, 53138);
    expect(peer.endpoints.map((endpoint) => endpoint.displayHost), [
      '192.168.1.20',
    ]);
  });

  test('keeps every usable QR endpoint for connection fallback', () {
    final peer = ConnectionPayloadService().decode(
      '{"type":"link_me_connection","version":1,"deviceId":"device-1","name":"手机","endpoints":["10.0.0.5:53138","192.168.1.20:53138"]}',
    );

    expect(peer.host.address, '10.0.0.5');
    expect(peer.endpoints.map((endpoint) => endpoint.displayHost), [
      '10.0.0.5',
      '192.168.1.20',
    ]);
  });

  test('rejects QR payloads without routable endpoints', () {
    expect(
      () => ConnectionPayloadService().decode(
        '{"type":"link_me_connection","version":1,"deviceId":"device-1","name":"电脑","endpoints":["0.0.1.1:53138"]}',
      ),
      throwsFormatException,
    );
  });

  test('rejects non Link Me QR payloads', () {
    expect(
      () => ConnectionPayloadService().decode('{"type":"other"}'),
      throwsFormatException,
    );
  });
}
