import 'package:flutter/material.dart';

import '../../models/transfer_models.dart';
import 'glass_card.dart';

class TransferCard extends StatelessWidget {
  const TransferCard({super.key, required this.batch, required this.onDelete});

  final TransferBatch batch;
  final Future<void> Function(TransferBatch batch) onDelete;

  @override
  Widget build(BuildContext context) {
    final isIncoming = batch.direction == TransferDirection.incoming;
    final accent = isIncoming
        ? const Color(0xFF60A5FA)
        : const Color(0xFF4ADE80);
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 14),
      tintColor: accent.withValues(alpha: 0.18),
      borderColor: accent.withValues(alpha: 0.44),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isIncoming
                    ? Icons.call_received_rounded
                    : Icons.call_made_rounded,
                color: Colors.white,
              ),
              const SizedBox(width: 10),
              _DirectionBadge(isIncoming: isIncoming),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${isIncoming ? '接收自' : '发送到'} ${batch.peerName}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: '删除记录',
                onPressed: () => onDelete(batch),
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                _statusText(batch.status),
                style: TextStyle(color: _statusColor(batch.status)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: batch.progress,
              minHeight: 9,
              backgroundColor: Colors.white.withValues(alpha: 0.18),
              valueColor: AlwaysStoppedAnimation(_statusColor(batch.status)),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '${batch.fileCount} 个文件 · ${_formatBytes(batch.transferredBytes)} / ${_formatBytes(batch.totalBytes)}',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.78)),
          ),
          if (batch.error != null) ...[
            const SizedBox(height: 8),
            Text(
              batch.error!,
              style: const TextStyle(color: Color(0xFFFFB4AB)),
            ),
          ],
          if (isIncoming && batch.files.any((file) => file.savePath != null))
            ..._savedFilePathRows(batch),
        ],
      ),
    );
  }

  List<Widget> _savedFilePathRows(TransferBatch batch) {
    return [
      const SizedBox(height: 10),
      Text(
        '已保存到',
        style: TextStyle(color: Colors.white.withValues(alpha: 0.72)),
      ),
      const SizedBox(height: 6),
      ...batch.files
          .where((file) => file.savePath != null)
          .map(
            (file) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: SelectableText(
                file.savePath!,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.68),
                  fontSize: 12,
                ),
              ),
            ),
          ),
    ];
  }

  String _statusText(TransferStatus status) {
    return switch (status) {
      TransferStatus.waiting => '等待中',
      TransferStatus.running => '传输中',
      TransferStatus.completed => '已完成',
      TransferStatus.failed => '失败',
      TransferStatus.interrupted => '已中断',
    };
  }

  Color _statusColor(TransferStatus status) {
    return switch (status) {
      TransferStatus.completed => const Color(0xFF85F7B8),
      TransferStatus.failed ||
      TransferStatus.interrupted => const Color(0xFFFFB4AB),
      _ => const Color(0xFF9BE7FF),
    };
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(1)} GB';
  }
}

class _DirectionBadge extends StatelessWidget {
  const _DirectionBadge({required this.isIncoming});

  final bool isIncoming;

  @override
  Widget build(BuildContext context) {
    final color = isIncoming
        ? const Color(0xFF60A5FA)
        : const Color(0xFF4ADE80);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.7)),
      ),
      child: Text(
        isIncoming ? '接收' : '发送',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
