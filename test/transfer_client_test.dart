import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:link_me/models/peer_device.dart';
import 'package:link_me/models/transfer_models.dart';
import 'package:link_me/services/transfer_client.dart';

void main() {
  test('sendFiles accepts non-ascii file names from picked iOS files', () async {
    final temp = await Directory.systemTemp.createTemp('link-me-client-');
    final file = File('${temp.path}${Platform.pathSeparator}EXT_2.0动作链.md');
    await file.writeAsString('hello');
    final updates = <TransferBatch>[];

    final batch = await TransferClient().sendFiles(
      peer: PeerDevice(
        deviceId: 'receiver-1',
        name: 'Receiver',
        host: InternetAddress.loopbackIPv4,
        port: 1,
        platform: 'test',
        lastSeen: DateTime.now(),
      ),
      deviceName: 'Sender',
      deviceId: 'sender-1',
      files: [file],
      onBatchUpdated: updates.add,
    );

    expect(batch.status, TransferStatus.failed);
    expect(updates.first.files.single.name, 'EXT_2.0动作链.md');
    await temp.delete(recursive: true);
  });
}
