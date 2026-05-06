import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:link_me/models/peer_device.dart';
import 'package:link_me/models/transfer_models.dart';
import 'package:link_me/services/photo_service.dart';
import 'package:link_me/services/transfer_client.dart';
import 'package:link_me/state/app_state.dart';

class FakePhotoService extends PhotoService {
  FakePhotoService(this.file);

  final File? file;

  @override
  Future<File?> takePhoto() async => file;
}

class RecordingTransferClient extends TransferClient {
  List<File> sentFiles = const [];
  int? lastSenderPort;

  @override
  Future<TransferBatch> sendFiles({
    required PeerDevice peer,
    required String deviceName,
    required String deviceId,
    required List<File> files,
    required void Function(TransferBatch batch) onBatchUpdated,
    int? senderPort,
  }) async {
    sentFiles = files;
    lastSenderPort = senderPort;
    final batch = TransferBatch.create(
      peerName: peer.name,
      peerDeviceId: peer.deviceId,
      direction: TransferDirection.outgoing,
      files: files
          .map(
            (file) => TransferFileItem(
              name: file.uri.pathSegments.last,
              size: file.lengthSync(),
            ),
          )
          .toList(growable: false),
    ).copyWith(status: TransferStatus.completed);
    onBatchUpdated(batch);
    return batch;
  }
}

class RecordingTextTransferClient extends TransferClient {
  RecordingTextTransferClient({
    this.helloResult = true,
    this.textResult = true,
  });

  final bool helloResult;
  final bool textResult;
  String? sentText;
  int? lastSenderPort;
  PeerDevice? helloPeer;
  int? helloSenderPort;

  @override
  Future<bool> sendText({
    required PeerDevice peer,
    required String deviceName,
    required String deviceId,
    required String text,
    int? senderPort,
  }) async {
    sentText = text;
    lastSenderPort = senderPort;
    return textResult;
  }

  @override
  Future<bool> sendPeerHello({
    required PeerDevice peer,
    required String deviceName,
    required String deviceId,
    required int senderPort,
  }) async {
    helloPeer = peer;
    helloSenderPort = senderPort;
    return helloResult;
  }
}

void main() {
  test(
    'addManualPeerByAddress uses custom name with separated ip and port',
    () async {
      final state = AppState();

      final added = await state.addManualPeerByAddress(
        name: '我的手机',
        host: '192.168.162.142',
        port: '41587',
      );

      expect(added, isTrue);
      expect(state.peers.single.name, '我的手机');
      expect(state.peers.single.host.address, '192.168.162.142');
      expect(state.peers.single.port, 41587);
    },
  );

  test(
    'addManualPeerByAddress falls back to address when name is empty',
    () async {
      final state = AppState();

      final added = await state.addManualPeerByAddress(
        name: '   ',
        host: '192.168.162.142',
        port: '41587',
      );

      expect(added, isTrue);
      expect(state.peers.single.name, '手动设备 192.168.162.142');
    },
  );

  test('addPeerFromConnectionPayload adds scanned peer', () async {
    final transferClient = RecordingTextTransferClient();
    final state = AppState(transferClient: transferClient);
    state.deviceId = 'scanner-1';
    state.deviceName = 'Scanner';
    state.transferPort = 34580;

    final added = await state.addPeerFromConnectionPayload(
      '{"type":"link_me_connection","version":1,"deviceId":"device-1","name":"扫码手机","endpoints":["192.168.162.142:41587"]}',
    );

    expect(added, isTrue);
    expect(state.peers.single.deviceId, 'device-1');
    expect(state.peers.single.name, '扫码手机');
  });

  test('addPeerFromConnectionPayload reports failed hello callback', () async {
    final transferClient = RecordingTextTransferClient(helloResult: false);
    final state = AppState(transferClient: transferClient);
    state.deviceId = 'scanner-1';
    state.deviceName = 'Scanner';
    state.transferPort = 34580;

    final added = await state.addPeerFromConnectionPayload(
      '{"type":"link_me_connection","version":1,"deviceId":"device-1","name":"扫码手机","endpoints":["192.168.162.142:41587"]}',
    );

    expect(added, isFalse);
    expect(state.peers.single.deviceId, 'device-1');
    expect(transferClient.helloPeer?.deviceId, 'device-1');
    expect(state.manualConnectError, contains('无法连接'));
  });

  test('transferHistoryForPeer filters by peer device id', () {
    final state = AppState();
    final batch = TransferBatch(
      id: 'batch-1',
      peerName: 'old name',
      peerDeviceId: 'device-1',
      direction: TransferDirection.outgoing,
      files: const [TransferFileItem(name: 'hello.txt', size: 5)],
      createdAt: DateTime.now(),
    );
    state.upsertBatchForTesting(batch);

    final peer = state.peers.isEmpty ? null : state.peers.first;
    expect(peer, isNull);
    expect(
      state
          .transferHistoryForPeer(
            PeerDevice(
              deviceId: 'device-1',
              name: 'new name',
              host: InternetAddress.loopbackIPv4,
              port: 45455,
              platform: 'test',
              lastSeen: DateTime.now(),
            ),
          )
          .single
          .id,
      'batch-1',
    );
  });

  test(
    'deleteTransferBatch removes the record without deleting files by default',
    () async {
      final temp = await Directory.systemTemp.createTemp('link-me-state-');
      final received = File('${temp.path}${Platform.pathSeparator}hello.txt');
      await received.writeAsString('hello');
      final state = AppState();
      final batch = TransferBatch(
        id: 'batch-1',
        peerName: 'phone',
        direction: TransferDirection.incoming,
        files: [
          TransferFileItem(name: 'hello.txt', size: 5, savePath: received.path),
        ],
        createdAt: DateTime.now(),
        status: TransferStatus.completed,
      );
      state.upsertBatchForTesting(batch);

      final deleted = await state.deleteTransferBatch('batch-1');

      expect(deleted, isTrue);
      expect(state.batches, isEmpty);
      expect(await received.exists(), isTrue);
      await temp.delete(recursive: true);
    },
  );

  test('deleteTransferBatch can also delete received files', () async {
    final temp = await Directory.systemTemp.createTemp('link-me-state-');
    final received = File('${temp.path}${Platform.pathSeparator}hello.txt');
    await received.writeAsString('hello');
    final state = AppState();
    final batch = TransferBatch(
      id: 'batch-1',
      peerName: 'phone',
      direction: TransferDirection.incoming,
      files: [
        TransferFileItem(name: 'hello.txt', size: 5, savePath: received.path),
      ],
      createdAt: DateTime.now(),
      status: TransferStatus.completed,
    );
    state.upsertBatchForTesting(batch);

    final deleted = await state.deleteTransferBatch(
      'batch-1',
      deleteFiles: true,
    );

    expect(deleted, isTrue);
    expect(state.batches, isEmpty);
    expect(await received.exists(), isFalse);
    await temp.delete(recursive: true);
  });

  test('photo capture sends the captured file to the selected peer', () async {
    final temp = await Directory.systemTemp.createTemp('link-me-photo-state-');
    final photo = File('${temp.path}${Platform.pathSeparator}photo.jpg');
    await photo.writeAsString('image-bytes');
    final transferClient = RecordingTransferClient();
    final state = AppState(
      photoService: FakePhotoService(photo),
      transferClient: transferClient,
    );
    state.deviceId = 'sender-1';
    state.deviceName = 'Sender';
    state.transferPort = 34569;
    final peer = PeerDevice(
      deviceId: 'receiver-1',
      name: 'Receiver',
      host: InternetAddress.loopbackIPv4,
      port: 4567,
      platform: 'test',
      lastSeen: DateTime.now(),
    );

    final sent = await state.takePhotoAndSendTo(peer);

    expect(sent, isTrue);
    expect(transferClient.sentFiles.single.path, photo.path);
    expect(transferClient.lastSenderPort, 34569);
    expect(state.batches.single.status, TransferStatus.completed);
    await temp.delete(recursive: true);
  });

  test('photo capture cancellation does not send anything', () async {
    final transferClient = RecordingTransferClient();
    final state = AppState(
      photoService: FakePhotoService(null),
      transferClient: transferClient,
    );

    final sent = await state.takePhotoAndSendTo(
      PeerDevice(
        deviceId: 'receiver-1',
        name: 'Receiver',
        host: InternetAddress.loopbackIPv4,
        port: 4567,
        platform: 'test',
        lastSeen: DateTime.now(),
      ),
    );

    expect(sent, isFalse);
    expect(transferClient.sentFiles, isEmpty);
  });

  test('sendTextTo includes sender listening port for callbacks', () async {
    final transferClient = RecordingTextTransferClient();
    final state = AppState(transferClient: transferClient);
    state.deviceId = 'sender-1';
    state.deviceName = 'Sender';
    state.transferPort = 34570;

    final ok = await state.sendTextTo(
      PeerDevice(
        deviceId: 'receiver-1',
        name: 'Receiver',
        host: InternetAddress.loopbackIPv4,
        port: 4567,
        platform: 'test',
        lastSeen: DateTime.now(),
      ),
      'hello',
    );

    expect(ok, isTrue);
    expect(transferClient.sentText, 'hello');
    expect(transferClient.lastSenderPort, 34570);
  });

  test('sendTextTo reports network unavailable when sending fails', () async {
    final transferClient = RecordingTextTransferClient(textResult: false);
    final state = AppState(transferClient: transferClient);
    state.deviceId = 'sender-1';
    state.deviceName = 'Sender';
    state.transferPort = 34579;

    final ok = await state.sendTextTo(
      PeerDevice(
        deviceId: 'receiver-1',
        name: 'Receiver',
        host: InternetAddress.loopbackIPv4,
        port: 45678,
        platform: 'test',
        lastSeen: DateTime.now(),
      ),
      'hello',
    );

    expect(ok, isFalse);
    expect(state.manualConnectError, TransferClient.networkUnavailableMessage);
  });

  test(
    'direct peers remain available for callbacks while search continues',
    () {
      final state = AppState();
      state.upsertPeerForTesting(
        PeerDevice(
          deviceId: 'direct-phone',
          name: 'Sender Phone',
          host: InternetAddress.loopbackIPv4,
          port: 34571,
          platform: 'direct',
          lastSeen: DateTime.now().subtract(const Duration(minutes: 1)),
        ),
      );
      state.upsertPeerForTesting(
        PeerDevice(
          deviceId: 'stale-discovery-phone',
          name: 'Stale Phone',
          host: InternetAddress.loopbackIPv4,
          port: 34572,
          platform: 'android',
          lastSeen: DateTime.now().subtract(const Duration(minutes: 1)),
        ),
      );

      expect(state.peers.map((peer) => peer.deviceId), ['direct-phone']);
    },
  );

  test('adding scanned peer sends hello for reciprocal display', () async {
    final transferClient = RecordingTextTransferClient();
    final state = AppState(transferClient: transferClient);
    state.deviceId = 'scanner-1';
    state.deviceName = 'Scanner';
    state.transferPort = 34580;

    final added = await state.addPeerFromConnectionPayload(
      '{"type":"link_me_connection","version":1,"deviceId":"shown-1","name":"Shown Device","endpoints":["192.168.1.30:45678"]}',
    );

    expect(added, isTrue);
    expect(state.peers.single.deviceId, 'shown-1');
    expect(transferClient.helloPeer?.deviceId, 'shown-1');
    expect(transferClient.helloSenderPort, 34580);
  });

  test(
    'refreshNearbyDevices updates addresses and keeps pinned peers',
    () async {
      final state = AppState();
      state.transferPort = 34581;
      state.upsertPeerForTesting(
        PeerDevice(
          deviceId: 'manual-phone',
          name: 'Manual Phone',
          host: InternetAddress.loopbackIPv4,
          port: 4567,
          platform: 'manual',
          lastSeen: DateTime.now().subtract(const Duration(minutes: 1)),
        ),
      );

      await state.refreshNearbyDevices();

      expect(state.peers.single.deviceId, 'manual-phone');
    },
  );

  test('removePeer removes a nearby device by id', () {
    final state = AppState();
    state.upsertPeerForTesting(
      PeerDevice(
        deviceId: 'android-1',
        name: 'Android Phone',
        host: InternetAddress('192.168.1.30'),
        port: 45678,
        platform: 'android',
        lastSeen: DateTime.now(),
      ),
    );

    final removed = state.removePeer('android-1');

    expect(removed, isTrue);
    expect(state.peers, isEmpty);
  });
}
