import 'package:flutter/material.dart';

import '../../models/peer_device.dart';
import 'glass_card.dart';

class DeviceCard extends StatelessWidget {
  const DeviceCard({
    super.key,
    required this.peer,
    required this.onSend,
    required this.onSendText,
    required this.onOpen,
    required this.onRemove,
  });

  final PeerDevice peer;
  final VoidCallback onSend;
  final VoidCallback onSendText;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onOpen,
      child: GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF9BE7FF), Color(0xFFB388FF)],
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Icon(
                    _iconFor(peer.platform),
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        peer.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${peer.platform} · ${peer.displayEndpoint}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.72),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '移除设备',
                  onPressed: onRemove,
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onSend,
                    icon: const Icon(Icons.near_me_rounded),
                    label: const Text('文件'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onSendText,
                    icon: const Icon(Icons.notes_rounded),
                    label: const Text('文本'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(String platform) {
    if (platform.contains('android') || platform.contains('ios')) {
      return Icons.phone_iphone_rounded;
    }
    if (platform.contains('macos')) return Icons.laptop_mac_rounded;
    if (platform.contains('windows')) return Icons.desktop_windows_rounded;
    return Icons.devices_rounded;
  }
}
