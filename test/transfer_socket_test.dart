import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:link_me/models/peer_device.dart';
import 'package:link_me/models/transfer_models.dart';
import 'package:link_me/services/file_service.dart';
import 'package:link_me/services/transfer_client.dart';
import 'package:link_me/services/transfer_server.dart';

void main() {
  test('sender fails when receiver closes without transfer ack', () async {
    final temp = await Directory.systemTemp.createTemp('link-me-client-test-');
    final source = File('${temp.path}${Platform.pathSeparator}hello.txt');
    await source.writeAsString('hello');

    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((socket) {
      socket.listen((_) => socket.destroy());
    });

    final updates = <TransferBatch>[];
    final batch = await TransferClient(ackTimeout: const Duration(seconds: 1))
        .sendFiles(
          peer: PeerDevice(
            deviceId: 'receiver-1',
            name: 'Receiver',
            host: InternetAddress.loopbackIPv4,
            port: server.port,
            platform: 'test',
            lastSeen: DateTime.now(),
          ),
          deviceName: 'Sender',
          deviceId: 'sender-1',
          files: [source],
          onBatchUpdated: updates.add,
        );

    expect(batch.status, TransferStatus.failed);
    expect(batch.error, TransferClient.networkUnavailableMessage);

    await server.close();
    await temp.delete(recursive: true);
  });

  test('client and server transfer duplicate file names with ack', () async {
    final temp = await Directory.systemTemp.createTemp('link-me-e2e-test-');
    final sendA = Directory('${temp.path}${Platform.pathSeparator}a')
      ..createSync();
    final sendB = Directory('${temp.path}${Platform.pathSeparator}b')
      ..createSync();
    final save = Directory('${temp.path}${Platform.pathSeparator}received')
      ..createSync();
    final first = File('${sendA.path}${Platform.pathSeparator}dup.txt');
    final second = File('${sendB.path}${Platform.pathSeparator}dup.txt');
    await first.writeAsString('first');
    await second.writeAsString('second');

    final receiverUpdates = <TransferBatch>[];
    final server = TransferServer(fileService: FileService());
    final port = await server.start(
      saveDirectoryProvider: () async => save.path,
      onBatchUpdated: receiverUpdates.add,
    );

    final senderUpdates = <TransferBatch>[];
    final batch = await TransferClient(ackTimeout: const Duration(seconds: 5))
        .sendFiles(
          peer: PeerDevice(
            deviceId: 'receiver-1',
            name: 'Receiver',
            host: InternetAddress.loopbackIPv4,
            port: port,
            platform: 'test',
            lastSeen: DateTime.now(),
          ),
          deviceName: 'Sender',
          deviceId: 'sender-1',
          files: [first, second],
          onBatchUpdated: senderUpdates.add,
        );

    expect(batch.error, isNull);
    expect(batch.status, TransferStatus.completed);
    expect(receiverUpdates.last.status, TransferStatus.completed);
    expect(
      await File(
        '${save.path}${Platform.pathSeparator}LinkMe${Platform.pathSeparator}dup.txt',
      ).readAsString(),
      'first',
    );
    expect(
      await File(
        '${save.path}${Platform.pathSeparator}LinkMe${Platform.pathSeparator}dup (1).txt',
      ).readAsString(),
      'second',
    );

    await server.stop();
    await temp.delete(recursive: true);
  });

  test('receiver can reject a transfer before any file is written', () async {
    final temp = await Directory.systemTemp.createTemp('link-me-reject-test-');
    final save = Directory('${temp.path}${Platform.pathSeparator}received')
      ..createSync();
    final source = File('${temp.path}${Platform.pathSeparator}blocked.txt');
    await source.writeAsString('blocked');

    final server = TransferServer(fileService: FileService());
    final port = await server.start(
      saveDirectoryProvider: () async => save.path,
      onBatchUpdated: (_) {},
      onIncomingRequest: (_) async => false,
    );

    final batch = await TransferClient(ackTimeout: const Duration(seconds: 3))
        .sendFiles(
          peer: PeerDevice(
            deviceId: 'receiver-1',
            name: 'Receiver',
            host: InternetAddress.loopbackIPv4,
            port: port,
            platform: 'test',
            lastSeen: DateTime.now(),
          ),
          deviceName: 'Sender',
          deviceId: 'sender-1',
          files: [source],
          onBatchUpdated: (_) {},
        );

    expect(batch.status, TransferStatus.failed);
    expect(batch.error, contains('rejected'));
    expect(await save.list().isEmpty, isTrue);

    await server.stop();
    await temp.delete(recursive: true);
  });

  test(
    'receiver uses save directory selected during incoming confirmation',
    () async {
      final temp = await Directory.systemTemp.createTemp('link-me-dir-switch-');
      final oldSave = Directory('${temp.path}${Platform.pathSeparator}old')
        ..createSync();
      final newSave = Directory('${temp.path}${Platform.pathSeparator}new')
        ..createSync();
      final source = File('${temp.path}${Platform.pathSeparator}moved.txt');
      await source.writeAsString('saved in selected directory');

      var currentSaveDirectory = oldSave.path;
      final server = TransferServer(fileService: FileService());
      final port = await server.start(
        saveDirectoryProvider: () async => currentSaveDirectory,
        onBatchUpdated: (_) {},
        onIncomingRequest: (_) async {
          currentSaveDirectory = newSave.path;
          return true;
        },
      );

      final batch = await TransferClient(ackTimeout: const Duration(seconds: 5))
          .sendFiles(
            peer: PeerDevice(
              deviceId: 'receiver-1',
              name: 'Receiver',
              host: InternetAddress.loopbackIPv4,
              port: port,
              platform: 'test',
              lastSeen: DateTime.now(),
            ),
            deviceName: 'Sender',
            deviceId: 'sender-1',
            files: [source],
            onBatchUpdated: (_) {},
          );

      expect(batch.status, TransferStatus.completed);
      expect(
        await File(
          '${newSave.path}${Platform.pathSeparator}LinkMe${Platform.pathSeparator}moved.txt',
        ).readAsString(),
        'saved in selected directory',
      );
      expect(
        File(
          '${oldSave.path}${Platform.pathSeparator}LinkMe${Platform.pathSeparator}moved.txt',
        ).existsSync(),
        isFalse,
      );

      await server.stop();
      await temp.delete(recursive: true);
    },
  );

  test('client and server push text with ack', () async {
    final receivedMessages = <IncomingTextMessage>[];
    final rememberedPeers = <PeerDevice>[];
    final server = TransferServer(fileService: FileService());
    final port = await server.start(
      saveDirectoryProvider: () async => Directory.systemTemp.path,
      onBatchUpdated: (_) {},
      onTextMessage: receivedMessages.add,
      onPeer: rememberedPeers.add,
    );

    final result = await TransferClient(ackTimeout: const Duration(seconds: 3))
        .sendText(
          peer: PeerDevice(
            deviceId: 'receiver-1',
            name: 'Receiver',
            host: InternetAddress.loopbackIPv4,
            port: port,
            platform: 'test',
            lastSeen: DateTime.now(),
          ),
          deviceName: 'Sender',
          deviceId: 'sender-1',
          senderPort: 34567,
          text: 'hello from phone',
        );

    expect(result, isTrue);
    expect(receivedMessages, hasLength(1));
    expect(receivedMessages.single.senderName, 'Sender');
    expect(receivedMessages.single.senderDeviceId, 'sender-1');
    expect(receivedMessages.single.text, 'hello from phone');
    expect(rememberedPeers.single.deviceId, 'sender-1');
    expect(rememberedPeers.single.name, 'Sender');
    expect(rememberedPeers.single.port, 34567);

    await server.stop();
  });

  test(
    'client tries fallback peer endpoints when the first endpoint is closed',
    () async {
      final closedSocket = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final closedPort = closedSocket.port;
      await closedSocket.close();

      final receivedMessages = <IncomingTextMessage>[];
      final server = TransferServer(fileService: FileService());
      final port = await server.start(
        saveDirectoryProvider: () async => Directory.systemTemp.path,
        onBatchUpdated: (_) {},
        onTextMessage: receivedMessages.add,
      );

      final result =
          await TransferClient(ackTimeout: const Duration(seconds: 3)).sendText(
            peer: PeerDevice(
              deviceId: 'receiver-1',
              name: 'Receiver',
              host: InternetAddress.loopbackIPv4,
              port: closedPort,
              platform: 'qr',
              lastSeen: DateTime.now(),
              endpoints: [
                PeerEndpoint(
                  host: InternetAddress.loopbackIPv4,
                  port: closedPort,
                ),
                PeerEndpoint(host: InternetAddress.loopbackIPv4, port: port),
              ],
            ),
            deviceName: 'Sender',
            deviceId: 'sender-1',
            senderPort: 34567,
            text: 'hello through fallback',
          );

      expect(result, isTrue);
      expect(receivedMessages.single.text, 'hello through fallback');

      await server.stop();
    },
  );

  test('server remembers sender after incoming file request', () async {
    final temp = await Directory.systemTemp.createTemp('link-me-peer-file-');
    final source = File('${temp.path}${Platform.pathSeparator}hello.txt');
    await source.writeAsString('hello');

    final rememberedPeers = <PeerDevice>[];
    final server = TransferServer(fileService: FileService());
    final port = await server.start(
      saveDirectoryProvider: () async => temp.path,
      onBatchUpdated: (_) {},
      onPeer: rememberedPeers.add,
      onIncomingRequest: (_) async => false,
    );

    await TransferClient(ackTimeout: const Duration(seconds: 3)).sendFiles(
      peer: PeerDevice(
        deviceId: 'receiver-1',
        name: 'Receiver',
        host: InternetAddress.loopbackIPv4,
        port: port,
        platform: 'test',
        lastSeen: DateTime.now(),
      ),
      deviceName: 'Sender',
      deviceId: 'sender-1',
      senderPort: 34568,
      files: [source],
      onBatchUpdated: (_) {},
    );

    expect(rememberedPeers.single.deviceId, 'sender-1');
    expect(rememberedPeers.single.name, 'Sender');
    expect(rememberedPeers.single.port, 34568);

    await server.stop();
    await temp.delete(recursive: true);
  });

  test('client and server complete peer hello handshake', () async {
    final rememberedPeers = <PeerDevice>[];
    final server = TransferServer(fileService: FileService());
    final port = await server.start(
      saveDirectoryProvider: () async => Directory.systemTemp.path,
      onBatchUpdated: (_) {},
      onPeer: rememberedPeers.add,
    );

    final ok = await TransferClient(ackTimeout: const Duration(seconds: 3))
        .sendPeerHello(
          peer: PeerDevice(
            deviceId: 'receiver-1',
            name: 'Receiver',
            host: InternetAddress.loopbackIPv4,
            port: port,
            platform: 'test',
            lastSeen: DateTime.now(),
          ),
          deviceName: 'Sender',
          deviceId: 'sender-1',
          senderPort: 34569,
        );

    expect(ok, isTrue);
    expect(rememberedPeers.single.deviceId, 'sender-1');
    expect(rememberedPeers.single.name, 'Sender');
    expect(rememberedPeers.single.port, 34569);

    await server.stop();
  });
}
