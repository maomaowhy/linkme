import 'dart:convert';
import 'dart:typed_data';

class ProtocolMessageType {
  static const hello = 'hello';
  static const peerHello = 'peer_hello';
  static const peerAck = 'peer_ack';
  static const transferRequest = 'transfer_request';
  static const fileStart = 'file_start';
  static const fileDone = 'file_done';
  static const transferDone = 'transfer_done';
  static const transferDecision = 'transfer_decision';
  static const transferAck = 'transfer_ack';
  static const textPush = 'text_push';
  static const textAck = 'text_ack';
  static const error = 'error';
}

class ProtocolFrame {
  const ProtocolFrame(this.type, this.payload);

  final String type;
  final Map<String, Object?> payload;

  Map<String, Object?> toJson() => {'type': type, 'payload': payload};

  static ProtocolFrame fromJson(Map<String, Object?> json) {
    return ProtocolFrame(
      json['type'] as String,
      Map<String, Object?>.from(json['payload'] as Map),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ProtocolFrame &&
        other.type == type &&
        jsonEncode(other.payload) == jsonEncode(payload);
  }

  @override
  int get hashCode => Object.hash(type, jsonEncode(payload));

  @override
  String toString() => 'ProtocolFrame($type, $payload)';
}

class TransferProtocol {
  static const maxFrameBytes = 1024 * 1024;

  static Uint8List encodeFrame(ProtocolFrame frame) {
    final jsonBytes = utf8.encode(jsonEncode(frame.toJson()));
    if (jsonBytes.length > maxFrameBytes) {
      throw ArgumentError('Protocol frame is too large: ${jsonBytes.length}');
    }
    final bytes = Uint8List(4 + jsonBytes.length);
    final data = ByteData.view(bytes.buffer);
    data.setUint32(0, jsonBytes.length, Endian.big);
    bytes.setRange(4, bytes.length, jsonBytes);
    return bytes;
  }

  static ProtocolFrame decodeFrame(List<int> bytes) {
    if (bytes.length < 4) {
      throw const FormatException('Frame is missing length prefix');
    }
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    final length = data.getUint32(0, Endian.big);
    if (length > maxFrameBytes) {
      throw FormatException('Frame length exceeds limit: $length');
    }
    if (bytes.length != 4 + length) {
      throw FormatException(
        'Frame length mismatch: expected ${4 + length}, got ${bytes.length}',
      );
    }
    final decoded =
        jsonDecode(utf8.decode(bytes.sublist(4))) as Map<String, Object?>;
    return ProtocolFrame.fromJson(decoded);
  }
}

typedef FrameCallback = void Function(ProtocolFrame frame);
typedef BytesCallback = void Function(List<int> bytes);
typedef DoneCallback = void Function();

class TransferStreamDecoder {
  TransferStreamDecoder({required this.onFrame});

  final FrameCallback onFrame;
  final List<int> _buffer = [];
  int? _activeFileBytesRemaining;
  BytesCallback? _onFileBytes;
  DoneCallback? _onFileDone;

  void expectFileBytes(
    int bytes, {
    required BytesCallback onBytes,
    required DoneCallback onDone,
  }) {
    _activeFileBytesRemaining = bytes;
    _onFileBytes = onBytes;
    _onFileDone = onDone;
  }

  void add(List<int> bytes) {
    _buffer.addAll(bytes);
    _drain();
  }

  void _drain() {
    while (_buffer.isNotEmpty) {
      final remaining = _activeFileBytesRemaining;
      if (remaining != null) {
        if (remaining == 0) {
          _finishFileBytes();
          continue;
        }
        final take = remaining < _buffer.length ? remaining : _buffer.length;
        final chunk = List<int>.from(_buffer.take(take));
        _buffer.removeRange(0, take);
        _activeFileBytesRemaining = remaining - take;
        _onFileBytes?.call(chunk);
        if (_activeFileBytesRemaining == 0) {
          _finishFileBytes();
        }
        continue;
      }

      if (_buffer.length < 4) return;
      final header = Uint8List.fromList(_buffer.take(4).toList());
      final length = ByteData.sublistView(header).getUint32(0, Endian.big);
      if (length > TransferProtocol.maxFrameBytes) {
        throw FormatException('Frame length exceeds limit: $length');
      }
      if (_buffer.length < 4 + length) return;
      final frameBytes = List<int>.from(_buffer.take(4 + length));
      _buffer.removeRange(0, 4 + length);
      onFrame(TransferProtocol.decodeFrame(frameBytes));
    }
  }

  void _finishFileBytes() {
    _activeFileBytesRemaining = null;
    final onDone = _onFileDone;
    _onFileBytes = null;
    _onFileDone = null;
    onDone?.call();
  }
}
