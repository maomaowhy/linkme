import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:link_me/models/transfer_models.dart';
import 'package:link_me/services/transfer_protocol.dart';

void main() {
  test('encodes and decodes a length-prefixed json frame', () {
    final frame = ProtocolFrame('hello', {
      'deviceId': 'phone-1',
      'name': 'Wang iPhone',
      'port': 45881,
    });

    final bytes = TransferProtocol.encodeFrame(frame);
    expect(bytes.length, greaterThan(4));
    expect(TransferProtocol.decodeFrame(bytes), frame);
  });

  test('decoder emits frames and exact file bytes across chunk boundaries', () {
    final emittedFrames = <ProtocolFrame>[];
    final fileChunks = <List<int>>[];
    var fileDone = false;

    late TransferStreamDecoder decoder;
    decoder = TransferStreamDecoder(
      onFrame: (frame) {
        emittedFrames.add(frame);
        if (frame.type == ProtocolMessageType.fileStart) {
          decoder.expectFileBytes(
            frame.payload['size'] as int,
            onBytes: (chunk) => fileChunks.add(chunk),
            onDone: () => fileDone = true,
          );
        }
      },
    );

    final fileBytes = utf8.encode('hello-link-me');
    final streamBytes = <int>[
      ...TransferProtocol.encodeFrame(
        ProtocolFrame(ProtocolMessageType.transferRequest, {
          'transferId': 'batch-1',
          'files': [
            {'name': 'a.txt', 'size': fileBytes.length},
          ],
        }),
      ),
      ...TransferProtocol.encodeFrame(
        ProtocolFrame(ProtocolMessageType.fileStart, {
          'name': 'a.txt',
          'size': fileBytes.length,
        }),
      ),
      ...fileBytes,
      ...TransferProtocol.encodeFrame(
        ProtocolFrame(ProtocolMessageType.transferDone, {
          'transferId': 'batch-1',
        }),
      ),
    ];

    for (var index = 0; index < streamBytes.length; index += 3) {
      final end = index + 3 > streamBytes.length
          ? streamBytes.length
          : index + 3;
      decoder.add(streamBytes.sublist(index, end));
    }

    expect(emittedFrames.map((frame) => frame.type), [
      ProtocolMessageType.transferRequest,
      ProtocolMessageType.fileStart,
      ProtocolMessageType.transferDone,
    ]);
    expect(fileChunks.expand((chunk) => chunk).toList(), fileBytes);
    expect(fileDone, isTrue);
  });

  test('transfer batch aggregates file counts and total bytes', () {
    final batch = TransferBatch.create(
      peerName: 'MacBook',
      direction: TransferDirection.outgoing,
      files: const [
        TransferFileItem(name: 'one.mov', size: 10),
        TransferFileItem(name: 'two.zip', size: 30),
      ],
    );

    expect(batch.fileCount, 2);
    expect(batch.totalBytes, 40);
    expect(batch.progress, 0);

    final updated = batch.copyWith(transferredBytes: 20);
    expect(updated.progress, 0.5);
  });

  test('transfer batch exposes first received directory', () {
    final batch = TransferBatch.create(
      peerName: 'sender',
      direction: TransferDirection.incoming,
      files: const [
        TransferFileItem(
          name: 'hello.txt',
          size: 5,
          savePath: '/Users/wangzy/Downloads/LinkMe/hello.txt',
        ),
      ],
    );

    expect(batch.firstSaveDirectory, '/Users/wangzy/Downloads/LinkMe');
  });

  test('transfer batch preserves peer device id when copied', () {
    final batch = TransferBatch(
      id: 'batch-1',
      peerName: 'phone',
      peerDeviceId: 'device-1',
      direction: TransferDirection.outgoing,
      files: const [TransferFileItem(name: 'a.txt', size: 1)],
      createdAt: DateTime.now(),
    );

    expect(
      batch.copyWith(status: TransferStatus.completed).peerDeviceId,
      'device-1',
    );
  });
}
