import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/peer_device.dart';
import '../models/transfer_models.dart';
import '../services/file_service.dart';
import '../services/platform_capability_service.dart';
import '../services/transfer_client.dart';
import '../state/app_state.dart';
import 'widgets/device_card.dart';
import 'widgets/glass_card.dart';
import 'widgets/transfer_card.dart';

String? _saveDirectoryLabel(String path) {
  if (path.isEmpty) return null;
  final parts = path
      .split(RegExp(r'[/\\]+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return null;
  if (parts.length == 1) return parts.last;
  return '${parts[parts.length - 2]} / ${parts.last}';
}

String _directoryAccessHint(String path) {
  if (!Platform.isIOS) return path;
  return '$path\n\n可在 iPhone「文件」App 中访问：我的 iPhone > Link Me > LinkMe。iOS 不允许 App 静默写入全局 iCloud Drive/Downloads。';
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
  return '${(mb / 1024).toStringAsFixed(1)} GB';
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final Set<String> _shownCompletedBatchIds = <String>{};
  String? _presentingTextMessageId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    _scheduleTextPrompt(state);
    _scheduleCompletedReceivePrompt(state);
    return Scaffold(
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 30, right: 4),
        child: FloatingActionButton(
          onPressed: _showConnectionActions,
          backgroundColor: const Color(0xFF9BE7FF),
          foregroundColor: const Color(0xFF111827),
          elevation: 10,
          child: const Icon(Icons.add_rounded),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF111827), Color(0xFF263B80), Color(0xFF7C3AED)],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1040),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                    child: Column(
                      children: [
                        _Header(
                          state: state,
                          onConfigureSaveDirectory: _showSaveDirectoryDialog,
                          onShowQr: _showQrDialog,
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: _HomeTabs(
                            state: state,
                            onSend: state.sendFilesTo,
                            onSendText: _showSendTextDialog,
                            onOpenPeer: _showPeerDetails,
                            onRemovePeer: state.removePeer,
                            onDeleteTransfer: _confirmDeleteTransfer,
                            onRefreshPeers: state.refreshNearbyDevices,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (state.pendingIncomingPrompt != null)
                _IncomingTransferBanner(
                  prompt: state.pendingIncomingPrompt!,
                  saveDirectory: state.saveDirectory,
                  saveDirectoryError: state.saveDirectoryError,
                  onReject: state.rejectIncomingTransfer,
                  onAccept: state.acceptIncomingTransfer,
                  onChangeDirectory: state.chooseSaveDirectory,
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _scheduleTextPrompt(AppState state) {
    final message = state.pendingTextMessage;
    if (message == null) return;
    if (_presentingTextMessageId != null) return;
    _presentingTextMessageId = message.id;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _presentingTextMessageId = null;
        return;
      }
      await _showTextMessagePrompt(message.id);
      if (mounted) {
        _presentingTextMessageId = null;
        final latestMessage = context.read<AppState>().pendingTextMessage;
        if (latestMessage != null && latestMessage.id != message.id) {
          _scheduleTextPrompt(context.read<AppState>());
        }
      } else {
        _presentingTextMessageId = null;
      }
    });
  }

  Future<void> _showTextMessagePrompt(String messageId) async {
    final state = context.read<AppState>();
    final message = state.pendingTextMessage;
    if (message == null || message.id != messageId || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF172554),
          title: Text('${message.senderName} 发来文本'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SelectableText(
              message.text,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.86)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text('关闭'),
            ),
            FilledButton.icon(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                await Clipboard.setData(ClipboardData(text: message.text));
                if (!dialogContext.mounted) return;
                messenger.showSnackBar(const SnackBar(content: Text('文本已复制')));
              },
              icon: const Icon(Icons.copy_rounded),
              label: const Text('复制'),
            ),
          ],
        );
      },
    );
    if (state.pendingTextMessage?.id == messageId) {
      state.dismissTextMessage();
    }
  }

  void _scheduleCompletedReceivePrompt(AppState state) {
    final batch = state.batches.where((entry) {
      return entry.direction == TransferDirection.incoming &&
          entry.status == TransferStatus.completed &&
          entry.firstSaveDirectory != null &&
          !_shownCompletedBatchIds.contains(entry.id);
    }).firstOrNull;
    if (batch == null) return;
    _shownCompletedBatchIds.add(batch.id);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _showCompletedReceivePrompt(batch.id);
    });
  }

  Future<void> _showCompletedReceivePrompt(String batchId) async {
    final state = context.read<AppState>();
    final batch = state.batches
        .where((entry) => entry.id == batchId)
        .firstOrNull;
    final directory = batch?.firstSaveDirectory;
    if (batch == null || directory == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF172554),
          title: const Text('文件接收完成'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${batch.fileCount} 个文件已保存到：',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.82)),
                ),
                const SizedBox(height: 8),
                SelectableText(
                  _directoryAccessHint(directory),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.68),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('稍后'),
            ),
            FilledButton(
              onPressed: () async {
                final action = FileService.saveLocationOpenActionFor(
                  Platform.operatingSystem,
                );
                final messenger = ScaffoldMessenger.of(context);
                final navigator = Navigator.of(dialogContext);
                final opened = action.canAttemptOpen
                    ? await state.openDirectory(directory)
                    : false;
                if (!dialogContext.mounted) return;
                navigator.pop();
                if (!opened) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(action.failureMessage),
                      duration: const Duration(seconds: 5),
                    ),
                  );
                }
              },
              child: Text(
                FileService.saveLocationOpenActionFor(
                  Platform.operatingSystem,
                ).buttonLabel,
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmDeleteTransfer(TransferBatch batch) async {
    var deleteFiles = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF172554),
              title: const Text('删除传输记录？'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '将从传输记录中移除「${batch.peerName}」这个批次。',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.82),
                      ),
                    ),
                    if (batch.files.any((file) => file.savePath != null)) ...[
                      const SizedBox(height: 12),
                      CheckboxListTile(
                        value: deleteFiles,
                        onChanged: (value) {
                          setDialogState(() {
                            deleteFiles = value ?? false;
                          });
                        },
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text('同时删除已接收的文件'),
                        subtitle: const Text('默认不勾选，只删除记录。'),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('删除记录'),
                ),
              ],
            );
          },
        );
      },
    );
    if (confirmed != true || !mounted) return;
    await context.read<AppState>().deleteTransferBatch(
      batch.id,
      deleteFiles: deleteFiles,
    );
  }

  Future<void> _showSaveDirectoryDialog() async {
    final state = context.read<AppState>();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF172554),
          title: const Text('保存位置'),
          content: Consumer<AppState>(
            builder: (context, dialogState, _) {
              return ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '当前保存到',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.72),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      dialogState.saveDirectory.isEmpty
                          ? '正在加载保存目录'
                          : _directoryAccessHint(dialogState.saveDirectory),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.82),
                        fontSize: 13,
                      ),
                    ),
                    if (dialogState.saveDirectoryError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        dialogState.saveDirectoryError!,
                        style: const TextStyle(color: Color(0xFFFFB4AB)),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('关闭'),
            ),
            FilledButton(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final ok = await state.chooseSaveDirectory();
                if (!dialogContext.mounted) return;
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      ok
                          ? '保存目录已设置为：${state.saveDirectory}'
                          : state.saveDirectoryError ?? '保存目录不可写，请选择其他目录',
                    ),
                  ),
                );
              },
              child: const Text('修改目录'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showAddConnectionDialog() async {
    final nameController = TextEditingController();
    final hostController = TextEditingController();
    final portController = TextEditingController();
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            backgroundColor: const Color(0xFF172554),
            title: const Text('主动连接'),
            content: Consumer<AppState>(
              builder: (context, dialogState, _) {
                return ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          dialogState.localEndpoints.isEmpty
                              ? '本机地址获取中，自动搜索不可用时可让对方填写你的地址。'
                              : '我的地址：${dialogState.localEndpoints.join(' / ')}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.68),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 14),
                        _DialogTextField(
                          controller: nameController,
                          label: '连接名称（可选）',
                          hintText: '例如 我的安卓手机',
                        ),
                        const SizedBox(height: 12),
                        _DialogTextField(
                          controller: hostController,
                          label: 'IP 地址',
                          hintText: '例如 192.168.162.142',
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _DialogTextField(
                          controller: portController,
                          label: '端口号',
                          hintText: '例如 41587',
                          keyboardType: TextInputType.number,
                        ),
                        if (dialogState.manualConnectError != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            dialogState.manualConnectError!,
                            style: const TextStyle(color: Color(0xFFFFB4AB)),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () async {
                  final appState = context.read<AppState>();
                  final messenger = ScaffoldMessenger.of(context);
                  final ok = await appState.addManualPeerByAddress(
                    name: nameController.text,
                    host: hostController.text,
                    port: portController.text,
                  );
                  if (!dialogContext.mounted) return;
                  if (ok) {
                    Navigator.of(dialogContext).pop();
                    messenger.showSnackBar(
                      const SnackBar(content: Text('已添加主动连接设备')),
                    );
                  }
                },
                child: const Text('添加'),
              ),
            ],
          );
        },
      );
    } finally {
      nameController.dispose();
      hostController.dispose();
      portController.dispose();
    }
  }

  Future<void> _showConnectionActions() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF172554),
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ActionTile(
                  icon: Icons.qr_code_rounded,
                  title: '出示二维码',
                  subtitle: '让对方扫码快速连接这台设备',
                  value: 'show_qr',
                ),
                _ActionTile(
                  icon: Icons.qr_code_scanner_rounded,
                  title: '扫一扫',
                  subtitle: '扫描对方的 Link Me 二维码',
                  value: 'scan_qr',
                ),
                _ActionTile(
                  icon: Icons.photo_camera_rounded,
                  title: '拍照发送',
                  subtitle: '拍照后选择设备直接推送',
                  value: 'photo',
                ),
                _ActionTile(
                  icon: Icons.edit_location_alt_rounded,
                  title: '手动添加',
                  subtitle: '输入名称、IP 地址和端口号',
                  value: 'manual',
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'show_qr':
        await _showQrDialog();
      case 'scan_qr':
        await _showQrScanner();
      case 'photo':
        await _showTakePhotoFlow();
      case 'manual':
        await _showAddConnectionDialog();
    }
  }

  Future<void> _showQrDialog() async {
    final state = context.read<AppState>();
    final endpoints = state.localEndpoints;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        final hasAddress = endpoints.isNotEmpty;
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 26,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
              decoration: BoxDecoration(
                color: const Color(0xFF172554),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.32),
                    blurRadius: 36,
                    offset: const Offset(0, 18),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  if (hasAddress)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: QrImageView(
                        data: state.connectionPayload,
                        size: 240,
                        backgroundColor: Colors.white,
                      ),
                    )
                  else
                    Icon(
                      Icons.wifi_find_rounded,
                      color: Colors.white.withValues(alpha: 0.74),
                      size: 58,
                    ),
                  const SizedBox(height: 14),
                  SelectableText(
                    hasAddress
                        ? endpoints.join('\n')
                        : '暂无可展示地址，请确认已连接 Wi‑Fi 或稍后重试。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.72),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showQrScanner() async {
    if (!PlatformCapabilityService.supportsQrScanner) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前平台暂不支持摄像头扫码，请使用手动添加或二维码出示。')),
      );
      return;
    }
    var handled = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF172554),
          title: const Text('扫一扫连接'),
          content: SizedBox(
            width: 360,
            height: 360,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: MobileScanner(
                onDetect: (capture) async {
                  if (handled) return;
                  final code = capture.barcodes
                      .map((barcode) => barcode.rawValue)
                      .whereType<String>()
                      .firstOrNull;
                  if (code == null) return;
                  handled = true;
                  final appState = context.read<AppState>();
                  final messenger = ScaffoldMessenger.of(context);
                  final ok = await appState.addPeerFromConnectionPayload(code);
                  if (!dialogContext.mounted) return;
                  Navigator.of(dialogContext).pop();
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        ok
                            ? '已通过二维码添加设备'
                            : appState.manualConnectError ?? '二维码无效',
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showTakePhotoFlow() async {
    final state = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final photo = await state.takePhoto();
    if (!mounted) return;
    if (photo == null) {
      messenger.showSnackBar(const SnackBar(content: Text('已取消拍照')));
      return;
    }
    final peer = await _choosePeerForPhoto();
    if (!mounted || peer == null) return;
    final sent = await state.sendCapturedPhotoTo(peer, photo);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text(sent ? '照片已发送给 ${peer.name}' : '照片发送失败')),
    );
  }

  Future<PeerDevice?> _choosePeerForPhoto() async {
    final peers = context.read<AppState>().peers;
    if (peers.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('暂无可发送设备，请先发现或手动添加设备')));
      return null;
    }
    return showModalBottomSheet<PeerDevice>(
      context: context,
      backgroundColor: const Color(0xFF172554),
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '选择照片接收设备',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 420),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: peers.length,
                    itemBuilder: (context, index) {
                      final peer = peers[index];
                      return ListTile(
                        leading: const Icon(
                          Icons.devices_rounded,
                          color: Colors.white,
                        ),
                        title: Text(
                          peer.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        subtitle: Text(
                          peer.displayEndpoint,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.66),
                          ),
                        ),
                        onTap: () => Navigator.of(context).pop(peer),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showSendTextDialog(PeerDevice peer) async {
    final appState = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return _SendTextDialog(
          peer: peer,
          appState: appState,
          messenger: messenger,
        );
      },
    );
  }

  Future<void> _showPeerDetails(PeerDevice peer) async {
    final state = context.read<AppState>();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF172554),
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 22),
            child: Consumer<AppState>(
              builder: (context, dialogState, _) {
                final history = dialogState.transferHistoryForPeer(peer);
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      peer.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    SelectableText(
                      '${peer.displayEndpoint} · ${peer.platform}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () {
                              Navigator.of(context).pop();
                              state.sendFilesTo(peer);
                            },
                            icon: const Icon(Icons.near_me_rounded),
                            label: const Text('发送文件'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.of(context).pop();
                              _showSendTextDialog(peer);
                            },
                            icon: const Icon(Icons.notes_rounded),
                            label: const Text('发送文本'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      '历史传输',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.86),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 420),
                      child: history.isEmpty
                          ? Text(
                              '暂无与该设备的传输记录。',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.68),
                              ),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: history.length,
                              itemBuilder: (context, index) {
                                return TransferCard(
                                  batch: history[index],
                                  onDelete: _confirmDeleteTransfer,
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _SendTextDialog extends StatefulWidget {
  const _SendTextDialog({
    required this.peer,
    required this.appState,
    required this.messenger,
  });

  final PeerDevice peer;
  final AppState appState;
  final ScaffoldMessengerState messenger;

  @override
  State<_SendTextDialog> createState() => _SendTextDialogState();
}

class _SendTextDialogState extends State<_SendTextDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _isSending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF172554),
      title: Text('发送文本给 ${widget.peer.name}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: TextField(
          controller: _controller,
          enabled: !_isSending,
          minLines: 4,
          maxLines: 8,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: '输入要推送的文本',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.42)),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.1),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSending ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _isSending ? null : _send,
          child: _isSending
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('发送'),
        ),
      ],
    );
  }

  Future<void> _send() async {
    setState(() => _isSending = true);
    final ok = await widget.appState.sendTextTo(widget.peer, _controller.text);
    if (!mounted) return;
    if (ok) Navigator.of(context).pop();
    final message = ok
        ? '文本已发送'
        : widget.appState.manualConnectError ??
              TransferClient.networkUnavailableMessage;
    widget.messenger.showSnackBar(SnackBar(content: Text(message)));
    if (!ok && mounted) setState(() => _isSending = false);
  }
}

class _IncomingTransferBanner extends StatelessWidget {
  const _IncomingTransferBanner({
    required this.prompt,
    required this.saveDirectory,
    required this.saveDirectoryError,
    required this.onReject,
    required this.onAccept,
    required this.onChangeDirectory,
  });

  final IncomingTransferPrompt prompt;
  final String saveDirectory;
  final String? saveDirectoryError;
  final VoidCallback onReject;
  final Future<bool> Function() onAccept;
  final Future<bool> Function() onChangeDirectory;

  @override
  Widget build(BuildContext context) {
    final batch = prompt.batch;
    return Positioned(
      left: 18,
      right: 18,
      top: 14,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: GlassCard(
            tintColor: const Color(0xFF1D4ED8).withValues(alpha: 0.24),
            borderColor: const Color(0xFF93C5FD).withValues(alpha: 0.48),
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.download_rounded, color: Colors.white),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${batch.peerName} 请求发送 ${batch.fileCount} 个文件',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '合计 ${_formatBytes(batch.totalBytes)} · 保存到 ${saveDirectory.isEmpty ? '正在加载保存目录' : saveDirectory}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.78)),
                ),
                if (saveDirectoryError != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    saveDirectoryError!,
                    style: const TextStyle(color: Color(0xFFFFB4AB)),
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    TextButton(onPressed: onReject, child: const Text('拒绝')),
                    OutlinedButton(
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final ok = await onChangeDirectory();
                        messenger.showSnackBar(
                          SnackBar(content: Text(ok ? '保存目录已更新' : '保存目录不可写')),
                        );
                      },
                      child: const Text('修改目录'),
                    ),
                    FilledButton(
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final ok = await onAccept();
                        if (!ok) {
                          messenger.showSnackBar(
                            const SnackBar(content: Text('保存目录不可写，请先修改目录')),
                          );
                        }
                      },
                      child: const Text('接收'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.state,
    required this.onConfigureSaveDirectory,
    required this.onShowQr,
  });

  final AppState state;
  final VoidCallback onConfigureSaveDirectory;
  final VoidCallback onShowQr;

  @override
  Widget build(BuildContext context) {
    final address = state.localEndpoints.isEmpty
        ? '等待本机地址'
        : state.localEndpoints.first;
    final label = _saveDirectoryLabel(state.saveDirectory) ?? '正在加载';
    final title = Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [Color(0xFF9BE7FF), Color(0xFFFFC2E2)],
            ),
          ),
          child: const Icon(Icons.air_rounded, color: Colors.white, size: 28),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Link Me',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                state.deviceName == 'Link Me' ? '当前设备' : state.deviceName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.72)),
              ),
            ],
          ),
        ),
      ],
    );
    final saveButton = _SaveDirectoryButton(
      label: label,
      onPressed: onConfigureSaveDirectory,
    );

    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 640) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                title,
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _AddressPill(address: address, onTap: onShowQr),
                    ),
                    const SizedBox(width: 10),
                    saveButton,
                  ],
                ),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: title),
                  const SizedBox(width: 14),
                  saveButton,
                ],
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: _AddressPill(address: address, onTap: onShowQr),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SaveDirectoryButton extends StatelessWidget {
  const _SaveDirectoryButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 240),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.folder_rounded, color: Colors.white, size: 17),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.84),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: Colors.white.withValues(alpha: 0.72),
                  size: 17,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AddressPill extends StatelessWidget {
  const _AddressPill({required this.address, required this.onTap});

  final String address;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.qr_code_2_rounded, color: Colors.white, size: 16),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                address,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.78),
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeTabs extends StatelessWidget {
  const _HomeTabs({
    required this.state,
    required this.onSend,
    required this.onSendText,
    required this.onOpenPeer,
    required this.onRemovePeer,
    required this.onDeleteTransfer,
    required this.onRefreshPeers,
  });

  final AppState state;
  final void Function(PeerDevice peer) onSend;
  final void Function(PeerDevice peer) onSendText;
  final void Function(PeerDevice peer) onOpenPeer;
  final bool Function(String deviceId) onRemovePeer;
  final Future<void> Function(TransferBatch batch) onDeleteTransfer;
  final Future<void> Function() onRefreshPeers;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          GlassCard(
            padding: const EdgeInsets.all(6),
            child: Row(
              children: [
                Expanded(
                  child: TabBar(
                    indicatorSize: TabBarIndicatorSize.tab,
                    indicator: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    dividerColor: Colors.transparent,
                    tabs: [
                      Tab(text: '附近设备 (${state.peers.length})'),
                      Tab(text: '传输记录 (${state.batches.length})'),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Tooltip(
                  message: '刷新附近设备',
                  child: IconButton(
                    onPressed: onRefreshPeers,
                    icon: const Icon(Icons.refresh_rounded),
                    color: Colors.white,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(2, 2, 2, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: TabBarView(
                  physics: const BouncingScrollPhysics(),
                  children: [
                    _PeersTab(
                      state: state,
                      onSend: onSend,
                      onSendText: onSendText,
                      onOpenPeer: onOpenPeer,
                      onRemovePeer: onRemovePeer,
                    ),
                    _TransfersTab(
                      batches: state.batches,
                      onDeleteTransfer: onDeleteTransfer,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PeersTab extends StatelessWidget {
  const _PeersTab({
    required this.state,
    required this.onSend,
    required this.onSendText,
    required this.onOpenPeer,
    required this.onRemovePeer,
  });

  final AppState state;
  final void Function(PeerDevice peer) onSend;
  final void Function(PeerDevice peer) onSendText;
  final void Function(PeerDevice peer) onOpenPeer;
  final bool Function(String deviceId) onRemovePeer;

  @override
  Widget build(BuildContext context) {
    if (state.isStarting) return _EmptyPeers(error: state.errorMessage);
    if (state.peers.isEmpty) return _EmptyPeers(error: state.errorMessage);
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(2, 2, 2, 110),
      itemCount: state.peers.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 360,
        mainAxisExtent: 176,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
      ),
      itemBuilder: (context, index) {
        final peer = state.peers[index];
        return DeviceCard(
          peer: peer,
          onSend: () => onSend(peer),
          onSendText: () => onSendText(peer),
          onOpen: () => onOpenPeer(peer),
          onRemove: () => onRemovePeer(peer.deviceId),
        );
      },
    );
  }
}

class _TransfersTab extends StatelessWidget {
  const _TransfersTab({required this.batches, required this.onDeleteTransfer});

  final List<TransferBatch> batches;
  final Future<void> Function(TransferBatch batch) onDeleteTransfer;

  @override
  Widget build(BuildContext context) {
    if (batches.isEmpty) return const _EmptyTransfers();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(2, 2, 2, 110),
      itemCount: batches.length,
      itemBuilder: (context, index) {
        return TransferCard(batch: batches[index], onDelete: onDeleteTransfer);
      },
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Colors.white),
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: Colors.white.withValues(alpha: 0.66)),
      ),
      onTap: () => Navigator.of(context).pop(value),
    );
  }
}

class _DialogTextField extends StatelessWidget {
  const _DialogTextField({
    required this.controller,
    required this.label,
    required this.hintText,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String label;
  final String hintText;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.72)),
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.42)),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.1),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

class _EmptyPeers extends StatefulWidget {
  const _EmptyPeers({this.error});

  final String? error;

  @override
  State<_EmptyPeers> createState() => _EmptyPeersState();
}

class _EmptyPeersState extends State<_EmptyPeers>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: GlassCard(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SearchPulse(controller: _controller),
              const SizedBox(height: 18),
              const Text(
                '正在搜索同一局域网内的 Link Me 设备',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.error ?? '请确保两端已打开 App，并允许本地网络/防火墙访问。',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.72)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchPulse extends StatelessWidget {
  const _SearchPulse({required this.controller});

  final Animation<double> controller;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 112,
      height: 112,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          return Stack(
            alignment: Alignment.center,
            children: [
              for (var index = 0; index < 3; index += 1)
                _PulseRing(progress: (controller.value + index / 3) % 1),
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF9BE7FF), Color(0xFFB388FF)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF9BE7FF).withValues(alpha: 0.34),
                      blurRadius: 24,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.radar_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PulseRing extends StatelessWidget {
  const _PulseRing({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final size = 54 + progress * 58;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: const Color(
            0xFF9BE7FF,
          ).withValues(alpha: (1 - progress) * 0.45),
          width: 1.4,
        ),
      ),
    );
  }
}

class _EmptyTransfers extends StatelessWidget {
  const _EmptyTransfers();

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Text(
        '暂无传输记录。选择附近设备后即可多选文件发送。',
        style: TextStyle(color: Colors.white.withValues(alpha: 0.78)),
      ),
    );
  }
}
