import 'dart:async';
import 'dart:io';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';

import '../models/peer_device.dart';
import '../models/transfer_models.dart';
import 'transfer_protocol.dart';

class TransferClient {
  TransferClient({this.ackTimeout = const Duration(seconds: 30)});

  static const networkUnavailableMessage = '网络连接异常，请检查局域网是否可用。';
  static const _flushEveryBytes = 4 * 1024 * 1024;

  final Duration ackTimeout;

  Future<TransferBatch> sendFiles({
    required PeerDevice peer,
    required String deviceName,
    required String deviceId,
    required List<File> files,
    required void Function(TransferBatch batch) onBatchUpdated,
    int? senderPort,
  }) async {
    final items = <TransferFileItem>[];
    for (var index = 0; index < files.length; index += 1) {
      items.add(await _metadataFor(files[index], index));
    }

    var batch = TransferBatch.create(
      peerName: peer.name,
      peerDeviceId: peer.deviceId,
      direction: TransferDirection.outgoing,
      files: items,
    ).copyWith(status: TransferStatus.running);
    onBatchUpdated(batch);

    StreamSubscription<List<int>>? responseSubscription;
    Socket? socket;
    var totalSent = 0;
    var waitingForAck = false;
    try {
      socket = await _connectToPeer(peer, timeout: const Duration(seconds: 8));
      final decisionCompleter = Completer<ProtocolFrame>();
      final ackCompleter = Completer<ProtocolFrame>();
      final responseDecoder = TransferStreamDecoder(
        onFrame: (frame) {
          if (frame.type == ProtocolMessageType.transferDecision) {
            if (!decisionCompleter.isCompleted) {
              decisionCompleter.complete(frame);
            }
          } else if (frame.type == ProtocolMessageType.transferAck ||
              frame.type == ProtocolMessageType.error) {
            if (!decisionCompleter.isCompleted) {
              decisionCompleter.complete(frame);
            }
            if (!ackCompleter.isCompleted) ackCompleter.complete(frame);
          }
        },
      );
      responseSubscription = socket.listen(
        responseDecoder.add,
        onError: (Object error) {
          final errorFrame = ProtocolFrame(ProtocolMessageType.error, {
            'message': 'receiver closed without ack: $error',
          });
          if (!decisionCompleter.isCompleted) {
            decisionCompleter.complete(errorFrame);
          }
          if (!ackCompleter.isCompleted) {
            ackCompleter.complete(errorFrame);
          }
        },
        onDone: () {
          const errorFrame = ProtocolFrame(ProtocolMessageType.error, {
            'message': 'receiver closed without ack',
          });
          if (!decisionCompleter.isCompleted) {
            decisionCompleter.complete(errorFrame);
          }
          if (!ackCompleter.isCompleted) {
            ackCompleter.complete(errorFrame);
          }
        },
        cancelOnError: true,
      );

      socket.add(
        TransferProtocol.encodeFrame(
          ProtocolFrame(ProtocolMessageType.transferRequest, {
            'transferId': batch.id,
            'senderName': deviceName,
            'senderDeviceId': deviceId,
            'senderPort': ?senderPort,
            'files': items.map((item) => item.toJson()).toList(growable: false),
          }),
        ),
      );

      final decision = await decisionCompleter.future.timeout(
        ackTimeout,
        onTimeout: () => throw TimeoutException('receiver decision timeout'),
      );
      if (decision.type == ProtocolMessageType.error) {
        throw StateError(
          '${decision.payload['message'] ?? 'receiver rejected transfer'}',
        );
      }
      if (decision.type != ProtocolMessageType.transferDecision ||
          decision.payload['transferId'] != batch.id ||
          decision.payload['accepted'] != true) {
        throw StateError('receiver rejected transfer');
      }

      var bytesSinceFlush = 0;
      for (var fileIndex = 0; fileIndex < files.length; fileIndex += 1) {
        final file = files[fileIndex];
        final item = items[fileIndex];
        var fileSent = 0;
        socket.add(
          TransferProtocol.encodeFrame(
            ProtocolFrame(ProtocolMessageType.fileStart, item.toJson()),
          ),
        );
        await for (final chunk in file.openRead()) {
          socket.add(chunk);
          fileSent += chunk.length;
          totalSent += chunk.length;
          bytesSinceFlush += chunk.length;
          if (bytesSinceFlush >= _flushEveryBytes) {
            await socket.flush();
            bytesSinceFlush = 0;
          }
          batch = batch.copyWith(
            transferredBytes: totalSent,
            status: TransferStatus.running,
            files: _replaceFile(
              batch.files,
              item.id,
              (entry) => entry.copyWith(
                transferredBytes: fileSent,
                status: TransferStatus.running,
              ),
            ),
          );
          onBatchUpdated(batch);
        }
        if (fileSent != item.size) {
          throw StateError('file changed while sending: ${item.name}');
        }
        socket.add(
          TransferProtocol.encodeFrame(
            ProtocolFrame(ProtocolMessageType.fileDone, {
              'id': item.id,
              'name': item.name,
              'size': item.size,
              'sha256': item.sha256,
            }),
          ),
        );
        batch = batch.copyWith(
          files: _replaceFile(
            batch.files,
            item.id,
            (entry) => entry.copyWith(
              transferredBytes: entry.size,
              status: TransferStatus.completed,
            ),
          ),
        );
        onBatchUpdated(batch);
      }

      socket.add(
        TransferProtocol.encodeFrame(
          ProtocolFrame(ProtocolMessageType.transferDone, {
            'transferId': batch.id,
          }),
        ),
      );
      await socket.flush();

      waitingForAck = true;
      final ack = await ackCompleter.future.timeout(
        ackTimeout,
        onTimeout: () => throw TimeoutException('receiver ack timeout'),
      );
      if (ack.type == ProtocolMessageType.error) {
        throw StateError('${ack.payload['message'] ?? 'receiver ack failed'}');
      }
      if (ack.type != ProtocolMessageType.transferAck ||
          ack.payload['transferId'] != batch.id) {
        throw StateError(
          'receiver did not acknowledge transfer: ${ack.payload}',
        );
      }

      waitingForAck = false;
      batch = batch.copyWith(
        transferredBytes: batch.totalBytes,
        status: TransferStatus.completed,
      );
      onBatchUpdated(batch);
      return batch;
    } catch (error) {
      final message = _userFacingError(error, waitingForAck: waitingForAck);
      batch = batch.copyWith(status: TransferStatus.failed, error: message);
      onBatchUpdated(batch);
      return batch;
    } finally {
      await responseSubscription?.cancel();
      socket?.destroy();
    }
  }

  Future<bool> sendText({
    required PeerDevice peer,
    required String deviceName,
    required String deviceId,
    required String text,
    int? senderPort,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    StreamSubscription<List<int>>? responseSubscription;
    Socket? socket;
    try {
      socket = await _connectToPeer(peer, timeout: const Duration(seconds: 8));
      final ackCompleter = Completer<ProtocolFrame>();
      final responseDecoder = TransferStreamDecoder(
        onFrame: (frame) {
          if (frame.type == ProtocolMessageType.textAck ||
              frame.type == ProtocolMessageType.error) {
            if (!ackCompleter.isCompleted) ackCompleter.complete(frame);
          }
        },
      );
      responseSubscription = socket.listen(
        responseDecoder.add,
        onError: (Object error) {
          if (!ackCompleter.isCompleted) {
            ackCompleter.complete(
              ProtocolFrame(ProtocolMessageType.error, {'message': '$error'}),
            );
          }
        },
        onDone: () {
          if (!ackCompleter.isCompleted) {
            ackCompleter.complete(
              const ProtocolFrame(ProtocolMessageType.error, {
                'message': 'receiver closed without text ack',
              }),
            );
          }
        },
        cancelOnError: true,
      );
      final messageId = 'text-${DateTime.now().microsecondsSinceEpoch}';
      socket.add(
        TransferProtocol.encodeFrame(
          ProtocolFrame(ProtocolMessageType.textPush, {
            'messageId': messageId,
            'senderName': deviceName,
            'senderDeviceId': deviceId,
            'senderPort': ?senderPort,
            'text': trimmed,
          }),
        ),
      );
      await socket.flush();
      final ack = await ackCompleter.future.timeout(
        ackTimeout,
        onTimeout: () => throw TimeoutException('receiver text ack timeout'),
      );
      if (ack.type != ProtocolMessageType.textAck ||
          ack.payload['messageId'] != messageId) {
        throw StateError('${ack.payload['message'] ?? 'receiver text failed'}');
      }
      return true;
    } catch (_) {
      return false;
    } finally {
      await responseSubscription?.cancel();
      socket?.destroy();
    }
  }

  Future<bool> sendPeerHello({
    required PeerDevice peer,
    required String deviceName,
    required String deviceId,
    required int senderPort,
  }) async {
    StreamSubscription<List<int>>? responseSubscription;
    Socket? socket;
    try {
      socket = await _connectToPeer(peer, timeout: const Duration(seconds: 5));
      final ackCompleter = Completer<ProtocolFrame>();
      final responseDecoder = TransferStreamDecoder(
        onFrame: (frame) {
          if (frame.type == ProtocolMessageType.peerAck ||
              frame.type == ProtocolMessageType.error) {
            if (!ackCompleter.isCompleted) ackCompleter.complete(frame);
          }
        },
      );
      responseSubscription = socket.listen(
        responseDecoder.add,
        onError: (Object error) {
          if (!ackCompleter.isCompleted) {
            ackCompleter.complete(
              ProtocolFrame(ProtocolMessageType.error, {'message': '$error'}),
            );
          }
        },
        onDone: () {
          if (!ackCompleter.isCompleted) {
            ackCompleter.complete(
              const ProtocolFrame(ProtocolMessageType.error, {
                'message': 'receiver closed without peer ack',
              }),
            );
          }
        },
        cancelOnError: true,
      );
      final helloId = 'hello-${DateTime.now().microsecondsSinceEpoch}';
      socket.add(
        TransferProtocol.encodeFrame(
          ProtocolFrame(ProtocolMessageType.peerHello, {
            'helloId': helloId,
            'senderName': deviceName,
            'senderDeviceId': deviceId,
            'senderPort': senderPort,
            'senderPlatform': Platform.operatingSystem,
          }),
        ),
      );
      await socket.flush();
      final ack = await ackCompleter.future.timeout(
        ackTimeout,
        onTimeout: () => throw TimeoutException('receiver peer ack timeout'),
      );
      return ack.type == ProtocolMessageType.peerAck &&
          ack.payload['helloId'] == helloId;
    } catch (_) {
      return false;
    } finally {
      await responseSubscription?.cancel();
      socket?.destroy();
    }
  }

  Future<TransferFileItem> _metadataFor(File file, int index) async {
    final output = AccumulatorSink<Digest>();
    final input = sha256.startChunkedConversion(output);
    var size = 0;
    await for (final chunk in file.openRead()) {
      size += chunk.length;
      input.add(chunk);
    }
    input.close();
    return TransferFileItem(
      id: 'file-$index',
      name: _fileName(file),
      size: size,
      sha256: output.events.single.toString(),
    );
  }

  List<TransferFileItem> _replaceFile(
    List<TransferFileItem> files,
    String? id,
    TransferFileItem Function(TransferFileItem entry) replace,
  ) {
    return files
        .map((entry) => entry.id == id ? replace(entry) : entry)
        .toList(growable: false);
  }

  Future<Socket> _connectToPeer(
    PeerDevice peer, {
    required Duration timeout,
  }) async {
    Object? lastError;
    for (final endpoint in peer.connectionEndpoints) {
      try {
        return await Socket.connect(
          endpoint.connectHost,
          endpoint.port,
          timeout: timeout,
        );
      } catch (error) {
        lastError = error;
      }
    }
    throw lastError ?? SocketException('No peer endpoint available');
  }

  String _userFacingError(Object error, {bool waitingForAck = false}) {
    final message = '$error';
    if (waitingForAck ||
        error is SocketException ||
        error is TimeoutException ||
        message.contains('receiver closed without ack') ||
        message.contains('receiver decision timeout') ||
        message.contains('receiver ack timeout')) {
      return networkUnavailableMessage;
    }
    return message;
  }

  String _fileName(File file) {
    final segments = file.path
        .split(RegExp(r'[/\\]+'))
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    if (segments.isEmpty) return 'file';
    final name = segments.last;
    if (!RegExp(r'%[0-9A-Fa-f]{2}').hasMatch(name)) return name;
    try {
      return Uri.decodeComponent(name);
    } catch (_) {
      return name;
    }
  }
}
