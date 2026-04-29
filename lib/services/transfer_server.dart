import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';

import '../models/peer_device.dart';
import '../models/transfer_models.dart';
import 'file_service.dart';
import 'network_address_service.dart';
import 'transfer_protocol.dart';

class TransferServer {
  TransferServer({required this.fileService});

  final FileService fileService;
  final Set<String> _reservedPaths = <String>{};
  final Set<Socket> _activeSockets = <Socket>{};
  ServerSocket? _server;
  StreamSubscription<Socket>? _serverSubscription;
  var _generation = 0;
  int? get port => _server?.port;

  Future<int> start({
    required Future<String> Function() saveDirectoryProvider,
    required void Function(TransferBatch batch) onBatchUpdated,
    Future<bool> Function(TransferBatch batch)? onIncomingRequest,
    void Function(IncomingTextMessage message)? onTextMessage,
    void Function(PeerDevice peer)? onPeer,
  }) async {
    await stop();
    _generation += 1;
    final generation = _generation;
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, 0, shared: true);
    _serverSubscription = _server!.listen(
      (socket) => _handleSocket(
        socket,
        generation,
        saveDirectoryProvider,
        onBatchUpdated,
        onIncomingRequest ?? (_) async => true,
        onTextMessage,
        onPeer,
      ),
      onError: (_) {},
    );
    return _server!.port;
  }

  Future<void> stop() async {
    _generation += 1;
    final sockets = _activeSockets.toList(growable: false);
    _activeSockets.clear();
    for (final socket in sockets) {
      socket.destroy();
    }
    await _serverSubscription?.cancel();
    _serverSubscription = null;
    await _server?.close();
    _server = null;
    _reservedPaths.clear();
  }

  Future<void> _handleSocket(
    Socket socket,
    int generation,
    Future<String> Function() saveDirectoryProvider,
    void Function(TransferBatch batch) onBatchUpdated,
    Future<bool> Function(TransferBatch batch) onIncomingRequest,
    void Function(IncomingTextMessage message)? onTextMessage,
    void Function(PeerDevice peer)? onPeer,
  ) async {
    _activeSockets.add(socket);
    String? saveDirectory;
    TransferBatch? batch;
    var accepted = false;
    IOSink? sink;
    File? currentTarget;
    String? currentFileId;
    String? currentFileName;
    String? currentFileSha256;
    AccumulatorSink<Digest>? currentDigestOutput;
    ByteConversionSink? currentDigestInput;
    int currentFileExpectedSize = 0;
    var currentFileReceived = 0;
    var totalReceived = 0;
    Future<void> pendingFileWrite = Future.value();

    void publish(TransferBatch updated) {
      batch = updated;
      if (generation == _generation && _server != null) {
        onBatchUpdated(updated);
      }
    }

    Future<void> sendFrame(ProtocolFrame frame) async {
      socket.add(TransferProtocol.encodeFrame(frame));
      await socket.flush();
    }

    void rememberSender(ProtocolFrame frame) {
      final senderDeviceId = frame.payload['senderDeviceId'] as String?;
      final senderPort = frame.payload['senderPort'] as int?;
      if (senderDeviceId == null || senderDeviceId.isEmpty) return;
      if (senderPort == null || senderPort <= 0 || senderPort > 65535) return;
      if (!_isRememberableRemoteAddress(socket.remoteAddress)) {
        return;
      }
      onPeer?.call(
        PeerDevice(
          deviceId: senderDeviceId,
          name: frame.payload['senderName'] as String? ?? 'Nearby device',
          host: socket.remoteAddress,
          port: senderPort,
          platform: frame.payload['senderPlatform'] as String? ?? 'direct',
          lastSeen: DateTime.now(),
        ),
      );
    }

    Future<void> cleanupActiveFile({bool deletePartial = false}) async {
      final activeSink = sink;
      final activeTarget = currentTarget;
      sink = null;
      currentTarget = null;
      currentFileId = null;
      currentFileName = null;
      currentFileSha256 = null;
      currentDigestInput = null;
      currentDigestOutput = null;
      currentFileExpectedSize = 0;
      currentFileReceived = 0;
      try {
        await activeSink?.close();
      } catch (_) {
        // Best effort cleanup.
      }
      if (activeTarget != null) {
        _reservedPaths.remove(activeTarget.path);
        if (deletePartial) {
          try {
            if (await activeTarget.exists()) await activeTarget.delete();
          } catch (_) {
            // Best effort cleanup.
          }
        }
      }
    }

    void fail(Object error) {
      unawaited(cleanupActiveFile(deletePartial: true));
      final current = batch;
      if (current != null) {
        publish(
          current.copyWith(status: TransferStatus.failed, error: '$error'),
        );
      }
      unawaited(
        sendFrame(
          ProtocolFrame(ProtocolMessageType.error, {'message': '$error'}),
        ).catchError((_) {}),
      );
    }

    Future<void> handleTextPush(ProtocolFrame frame) async {
      final id = frame.payload['messageId'] as String;
      final text = frame.payload['text'] as String? ?? '';
      if (text.trim().isEmpty) {
        throw const FormatException('text message is empty');
      }
      rememberSender(frame);
      onTextMessage?.call(
        IncomingTextMessage(
          id: id,
          senderName: frame.payload['senderName'] as String? ?? 'Nearby device',
          senderDeviceId: frame.payload['senderDeviceId'] as String?,
          text: text,
          createdAt: DateTime.now(),
        ),
      );
      await sendFrame(
        ProtocolFrame(ProtocolMessageType.textAck, {
          'messageId': id,
          'status': 'ok',
        }),
      );
      await socket.close();
    }

    Future<void> handlePeerHello(ProtocolFrame frame) async {
      rememberSender(frame);
      await sendFrame(
        ProtocolFrame(ProtocolMessageType.peerAck, {
          'helloId': frame.payload['helloId'],
          'status': 'ok',
        }),
      );
      await socket.close();
    }

    Future<void> handleTransferRequest(ProtocolFrame frame) async {
      rememberSender(frame);
      final filesJson = frame.payload['files'] as List<Object?>;
      final files = filesJson
          .map(
            (item) => TransferFileItem.fromJson(
              Map<String, Object?>.from(item as Map),
            ),
          )
          .toList(growable: false);
      final incoming = TransferBatch(
        id: frame.payload['transferId'] as String,
        peerName: frame.payload['senderName'] as String? ?? 'Nearby device',
        peerDeviceId: frame.payload['senderDeviceId'] as String?,
        direction: TransferDirection.incoming,
        files: files,
        createdAt: DateTime.now(),
        status: TransferStatus.waiting,
      );
      publish(incoming);

      try {
        accepted = await onIncomingRequest(incoming);
      } catch (error) {
        accepted = false;
        fail(error);
      }

      if (accepted) {
        saveDirectory = await saveDirectoryProvider();
        publish(incoming.copyWith(status: TransferStatus.running));
      } else {
        publish(
          incoming.copyWith(
            status: TransferStatus.failed,
            error: 'receiver rejected transfer',
          ),
        );
      }
      await sendFrame(
        ProtocolFrame(ProtocolMessageType.transferDecision, {
          'transferId': incoming.id,
          'accepted': accepted,
        }),
      );
      if (!accepted) {
        await socket.close();
      }
    }

    Future<void> finalizeFile({
      required Map<String, Object?> payload,
      required IOSink? activeSink,
      required File? activeTarget,
      required String? activeFileId,
      required String? activeFileName,
      required String? activeFileSha256,
      required AccumulatorSink<Digest>? digestOutput,
      required ByteConversionSink? digestInput,
      required int expectedSize,
      required int receivedBytes,
    }) async {
      final expectedSha256 = payload['sha256'] as String? ?? activeFileSha256;
      final payloadSize = payload['size'] as int? ?? expectedSize;

      if (activeSink == null ||
          activeFileId == null ||
          activeFileName == null) {
        throw StateError('file_done received without active file');
      }
      digestInput?.close();
      await activeSink.close();
      if (activeTarget != null) {
        _reservedPaths.remove(activeTarget.path);
        await fileService.notifyFileSaved(activeTarget.path);
      }

      if (receivedBytes != payloadSize) {
        throw StateError(
          'received size mismatch for $activeFileName: $receivedBytes/$payloadSize',
        );
      }
      final actualSha256 = digestOutput?.events.single.toString();
      if (expectedSha256 != null && actualSha256 != expectedSha256) {
        throw StateError('sha256 mismatch for $activeFileName');
      }

      final current = batch;
      if (current != null) {
        publish(
          current.copyWith(
            files: _replaceFile(
              current.files,
              activeFileId,
              (file) => file.copyWith(
                transferredBytes: file.size,
                status: TransferStatus.completed,
              ),
            ),
          ),
        );
      }
    }

    Future<void> completeTransferAfterWrites(String transferId) async {
      await pendingFileWrite;
      final current = batch;
      if (current == null) return;
      final incomplete = current.files.where(
        (file) => file.status != TransferStatus.completed,
      );
      if (incomplete.isNotEmpty) {
        throw StateError('transfer has incomplete files');
      }
      publish(
        current.copyWith(
          transferredBytes: current.totalBytes,
          status: TransferStatus.completed,
        ),
      );
      await sendFrame(
        ProtocolFrame(ProtocolMessageType.transferAck, {
          'transferId': transferId,
          'status': 'ok',
        }),
      );
      await socket.close();
    }

    late final TransferStreamDecoder decoder;
    decoder = TransferStreamDecoder(
      onFrame: (frame) {
        try {
          switch (frame.type) {
            case ProtocolMessageType.transferRequest:
              unawaited(handleTransferRequest(frame).catchError(fail));
            case ProtocolMessageType.textPush:
              unawaited(handleTextPush(frame).catchError(fail));
            case ProtocolMessageType.peerHello:
              unawaited(handlePeerHello(frame).catchError(fail));
            case ProtocolMessageType.fileStart:
              if (!accepted) {
                throw StateError('transfer has not been accepted');
              }
              final file = TransferFileItem.fromJson(frame.payload);
              final directory = saveDirectory;
              if (directory == null || directory.isEmpty) {
                throw StateError('save directory is not ready');
              }
              final target = _reserveWritableFileSync(directory, file.name);
              currentTarget = target;
              currentFileId = file.id;
              currentFileName = file.name;
              currentFileSha256 = file.sha256;
              currentFileExpectedSize = file.size;
              currentFileReceived = 0;
              currentDigestOutput = AccumulatorSink<Digest>();
              currentDigestInput = sha256.startChunkedConversion(
                currentDigestOutput!,
              );
              sink = target.openWrite();
              final current = batch;
              if (current != null) {
                publish(
                  current.copyWith(
                    files: _replaceFile(
                      current.files,
                      file.id,
                      (entry) => entry.copyWith(
                        status: TransferStatus.running,
                        savePath: target.path,
                      ),
                    ),
                  ),
                );
              }
              decoder.expectFileBytes(
                file.size,
                onBytes: (chunk) {
                  sink?.add(chunk);
                  currentDigestInput?.add(chunk);
                  currentFileReceived += chunk.length;
                  totalReceived += chunk.length;
                  final current = batch;
                  final activeId = currentFileId;
                  if (current != null && activeId != null) {
                    publish(
                      current.copyWith(
                        transferredBytes: totalReceived,
                        status: TransferStatus.running,
                        files: _replaceFile(
                          current.files,
                          activeId,
                          (entry) => entry.copyWith(
                            transferredBytes: currentFileReceived,
                            status: TransferStatus.running,
                          ),
                        ),
                      ),
                    );
                  }
                },
                onDone: () {},
              );
            case ProtocolMessageType.fileDone:
              final activeSink = sink;
              final activeTarget = currentTarget;
              final activeFileId = currentFileId;
              final activeFileName = currentFileName;
              final activeFileSha256 = currentFileSha256;
              final activeDigestInput = currentDigestInput;
              final activeDigestOutput = currentDigestOutput;
              final expectedSize = currentFileExpectedSize;
              final receivedBytes = currentFileReceived;
              sink = null;
              currentTarget = null;
              currentFileId = null;
              currentFileName = null;
              currentFileSha256 = null;
              currentDigestInput = null;
              currentDigestOutput = null;
              currentFileExpectedSize = 0;
              currentFileReceived = 0;
              pendingFileWrite = pendingFileWrite.then(
                (_) => finalizeFile(
                  payload: frame.payload,
                  activeSink: activeSink,
                  activeTarget: activeTarget,
                  activeFileId: activeFileId,
                  activeFileName: activeFileName,
                  activeFileSha256: activeFileSha256,
                  digestOutput: activeDigestOutput,
                  digestInput: activeDigestInput,
                  expectedSize: expectedSize,
                  receivedBytes: receivedBytes,
                ),
              );
              unawaited(pendingFileWrite.catchError(fail));
            case ProtocolMessageType.transferDone:
              final transferId = frame.payload['transferId'] as String;
              unawaited(
                completeTransferAfterWrites(transferId).catchError(fail),
              );
            case ProtocolMessageType.error:
              fail(frame.payload['message'] ?? 'Unknown transfer error');
          }
        } catch (error) {
          fail(error);
        }
      },
    );

    socket.listen(
      decoder.add,
      onError: fail,
      onDone: () {
        _activeSockets.remove(socket);
        unawaited(cleanupActiveFile());
        final current = batch;
        if (current != null && current.status == TransferStatus.running) {
          publish(current.copyWith(status: TransferStatus.interrupted));
        }
      },
      cancelOnError: true,
    );
  }

  File _reserveWritableFileSync(String directoryPath, String fileName) {
    final normalizedDirectoryPath = fileService.normalizeSaveDirectory(
      directoryPath,
    );
    final directory = Directory(normalizedDirectoryPath)
      ..createSync(recursive: true);
    final safeName = fileService.sanitizeFileName(fileName);
    var candidate = File('${directory.path}${Platform.pathSeparator}$safeName');
    if (!candidate.existsSync() && !_reservedPaths.contains(candidate.path)) {
      _reservedPaths.add(candidate.path);
      return candidate;
    }

    final dot = safeName.lastIndexOf('.');
    final base = dot > 0 ? safeName.substring(0, dot) : safeName;
    final extension = dot > 0 ? safeName.substring(dot) : '';
    var index = 1;
    while (candidate.existsSync() || _reservedPaths.contains(candidate.path)) {
      candidate = File(
        '${directory.path}${Platform.pathSeparator}$base ($index)$extension',
      );
      index += 1;
    }
    _reservedPaths.add(candidate.path);
    return candidate;
  }

  bool _isRememberableRemoteAddress(InternetAddress address) {
    if (NetworkAddressService.isUsableIpv4Address(address)) return true;
    return address.type == InternetAddressType.IPv4 && address.isLoopback;
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
}
