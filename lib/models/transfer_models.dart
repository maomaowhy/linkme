import 'dart:math';

enum TransferDirection { incoming, outgoing }

enum TransferStatus { waiting, running, completed, failed, interrupted }

class TransferFileItem {
  const TransferFileItem({
    required this.name,
    required this.size,
    this.id,
    this.sha256,
    this.transferredBytes = 0,
    this.status = TransferStatus.waiting,
    this.savePath,
    this.error,
  });

  final String? id;
  final String name;
  final int size;
  final String? sha256;
  final int transferredBytes;
  final TransferStatus status;
  final String? savePath;
  final String? error;

  double get progress => size <= 0 ? 0 : min(transferredBytes / size, 1);

  TransferFileItem copyWith({
    int? transferredBytes,
    TransferStatus? status,
    String? savePath,
    String? error,
  }) {
    return TransferFileItem(
      id: id,
      name: name,
      size: size,
      sha256: sha256,
      transferredBytes: transferredBytes ?? this.transferredBytes,
      status: status ?? this.status,
      savePath: savePath ?? this.savePath,
      error: error ?? this.error,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'size': size,
    'sha256': sha256,
  };

  static TransferFileItem fromJson(Map<String, Object?> json) {
    return TransferFileItem(
      id: json['id'] as String?,
      name: json['name'] as String,
      size: json['size'] as int,
      sha256: json['sha256'] as String?,
    );
  }
}

class TransferBatch {
  const TransferBatch({
    required this.id,
    required this.peerName,
    required this.direction,
    required this.files,
    required this.createdAt,
    this.peerDeviceId,
    this.transferredBytes = 0,
    this.status = TransferStatus.waiting,
    this.error,
  });

  factory TransferBatch.create({
    required String peerName,
    String? peerDeviceId,
    required TransferDirection direction,
    required List<TransferFileItem> files,
  }) {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final random = Random().nextInt(1 << 32).toRadixString(16);
    return TransferBatch(
      id: 'transfer-$timestamp-$random',
      peerName: peerName,
      peerDeviceId: peerDeviceId,
      direction: direction,
      files: files,
      createdAt: DateTime.now(),
    );
  }

  final String id;
  final String peerName;
  final String? peerDeviceId;
  final TransferDirection direction;
  final List<TransferFileItem> files;
  final DateTime createdAt;
  final int transferredBytes;
  final TransferStatus status;
  final String? error;

  int get fileCount => files.length;
  int get totalBytes => files.fold(0, (sum, file) => sum + file.size);
  double get progress =>
      totalBytes <= 0 ? 0 : min(transferredBytes / totalBytes, 1);
  String? get firstSaveDirectory {
    for (final file in files) {
      final path = file.savePath;
      if (path == null || path.isEmpty) continue;
      final slash = path.lastIndexOf('/');
      final backslash = path.lastIndexOf('\\');
      final separator = max(slash, backslash);
      if (separator > 0) return path.substring(0, separator);
    }
    return null;
  }

  TransferBatch copyWith({
    List<TransferFileItem>? files,
    int? transferredBytes,
    TransferStatus? status,
    String? error,
  }) {
    return TransferBatch(
      id: id,
      peerName: peerName,
      peerDeviceId: peerDeviceId,
      direction: direction,
      files: files ?? this.files,
      createdAt: createdAt,
      transferredBytes: transferredBytes ?? this.transferredBytes,
      status: status ?? this.status,
      error: error ?? this.error,
    );
  }
}

class IncomingTextMessage {
  const IncomingTextMessage({
    required this.id,
    required this.senderName,
    required this.text,
    required this.createdAt,
    this.senderDeviceId,
  });

  final String id;
  final String senderName;
  final String? senderDeviceId;
  final String text;
  final DateTime createdAt;
}
