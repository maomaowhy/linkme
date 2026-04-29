import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/peer_device.dart';
import '../models/transfer_models.dart';
import '../services/connection_payload_service.dart';
import '../services/device_identity_service.dart';
import '../services/discovery_service.dart';
import '../services/file_service.dart';
import '../services/network_address_service.dart';
import '../services/permission_service.dart';
import '../services/photo_service.dart';
import '../services/transfer_client.dart';
import '../services/transfer_server.dart';

class IncomingTransferPrompt {
  IncomingTransferPrompt({required this.batch});

  final TransferBatch batch;
  final Completer<bool> _decision = Completer<bool>();

  Future<bool> get decision => _decision.future;

  void complete(bool accepted) {
    if (!_decision.isCompleted) _decision.complete(accepted);
  }
}

class AppState extends ChangeNotifier {
  AppState({
    DeviceIdentityService? identityService,
    FileService? fileService,
    PermissionService? permissionService,
    DiscoveryService? discoveryService,
    NetworkAddressService? networkAddressService,
    ConnectionPayloadService? connectionPayloadService,
    PhotoService? photoService,
    TransferServer? transferServer,
    TransferClient? transferClient,
  }) : _identityService = identityService ?? DeviceIdentityService(),
       _fileService = fileService ?? FileService(),
       _permissionService = permissionService ?? PermissionService(),
       _discoveryService = discoveryService ?? DiscoveryService(),
       _networkAddressService =
           networkAddressService ?? const NetworkAddressService(),
       _connectionPayloadService =
           connectionPayloadService ?? ConnectionPayloadService(),
       _photoService = photoService ?? PhotoService(),
       _transferServer =
           transferServer ??
           TransferServer(fileService: fileService ?? FileService()),
       _transferClient = transferClient ?? TransferClient();

  final DeviceIdentityService _identityService;
  final FileService _fileService;
  final PermissionService _permissionService;
  final DiscoveryService _discoveryService;
  final NetworkAddressService _networkAddressService;
  final ConnectionPayloadService _connectionPayloadService;
  final PhotoService _photoService;
  final TransferServer _transferServer;
  final TransferClient _transferClient;

  String deviceId = '';
  String deviceName = 'Link Me';
  String saveDirectory = '';
  String? errorMessage;
  String? saveDirectoryError;
  String? manualConnectError;
  bool isStarting = true;
  int? transferPort;
  List<String> localIpv4Addresses = const [];
  IncomingTransferPrompt? pendingIncomingPrompt;
  IncomingTextMessage? pendingTextMessage;
  bool _disposed = false;

  final Map<String, PeerDevice> _peers = {};
  final List<TransferBatch> _batches = [];

  List<PeerDevice> get peers =>
      _peers.values.toList(growable: false)
        ..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
  List<TransferBatch> get batches => List.unmodifiable(_batches);
  TransferBatch? get currentBatch => _batches.isEmpty ? null : _batches.first;
  List<String> get localEndpoints {
    final port = transferPort;
    if (port == null) return const [];
    return localIpv4Addresses
        .map((address) => '$address:$port')
        .toList(growable: false);
  }

  String get connectionPayload => _connectionPayloadService.encode(
    deviceId: deviceId,
    deviceName: deviceName,
    endpoints: localEndpoints,
  );

  List<TransferBatch> transferHistoryForPeer(PeerDevice peer) {
    return _batches
        .where((batch) {
          return batch.peerDeviceId == peer.deviceId ||
              batch.peerName == peer.name;
        })
        .toList(growable: false);
  }

  Future<void> initialize() async {
    try {
      isStarting = true;
      notifyListeners();
      await _permissionService.requestStartupPermissions();
      final identity = await _identityService.load();
      deviceId = identity.deviceId;
      deviceName = identity.name;
      saveDirectory = await _fileService.loadSaveDirectory();
      final port = await _transferServer.start(
        saveDirectoryProvider: () async => saveDirectory,
        onBatchUpdated: _upsertBatch,
        onIncomingRequest: _confirmIncomingTransfer,
        onTextMessage: _receiveTextMessage,
        onPeer: _upsertPeer,
      );
      transferPort = port;
      localIpv4Addresses = await _networkAddressService.localIpv4Addresses();
      await _discoveryService.start(
        deviceId: deviceId,
        deviceName: deviceName,
        transferPort: port,
        onPeer: _upsertPeer,
      );
    } catch (error) {
      errorMessage = '$error';
    } finally {
      isStarting = false;
      notifyListeners();
    }
  }

  Future<File?> takePhoto() {
    return _photoService.takePhoto();
  }

  Future<bool> sendCapturedPhotoTo(PeerDevice peer, File photo) async {
    final batch = await _transferClient.sendFiles(
      peer: peer,
      deviceName: deviceName,
      deviceId: deviceId,
      senderPort: transferPort,
      files: [photo],
      onBatchUpdated: _upsertBatch,
    );
    return batch.status == TransferStatus.completed;
  }

  Future<bool> takePhotoAndSendTo(PeerDevice peer) async {
    final photo = await takePhoto();
    if (photo == null) return false;
    return sendCapturedPhotoTo(peer, photo);
  }

  Future<void> sendFilesTo(PeerDevice peer) async {
    final files = await _fileService.pickFiles();
    if (files.isEmpty) return;
    unawaited(
      _transferClient.sendFiles(
        peer: peer,
        deviceName: deviceName,
        deviceId: deviceId,
        senderPort: transferPort,
        files: files,
        onBatchUpdated: _upsertBatch,
      ),
    );
  }

  Future<bool> sendTextTo(PeerDevice peer, String text) async {
    final ok = await _transferClient.sendText(
      peer: peer,
      deviceName: deviceName,
      deviceId: deviceId,
      senderPort: transferPort,
      text: text,
    );
    if (!ok) {
      manualConnectError = '文本发送失败，请确认对方在线并可访问。';
    } else {
      manualConnectError = null;
    }
    notifyListeners();
    return ok;
  }

  Future<bool> chooseSaveDirectory() async {
    final directory = await _fileService.chooseSaveDirectory();
    if (directory == null || directory.isEmpty) return false;
    try {
      final resolved = await _fileService.requireWritableSaveDirectory(
        directory,
      );
      saveDirectory = resolved;
      saveDirectoryError = null;
      await _fileService.persistSaveDirectory(saveDirectory);
      notifyListeners();
      return true;
    } catch (error) {
      saveDirectoryError = '$error';
    }
    notifyListeners();
    return false;
  }

  Future<bool> addManualPeer(String endpointText) async {
    try {
      final endpoint = NetworkAddressService.parseEndpoint(endpointText);
      return _addManualEndpoint(
        name: '',
        hostAddress: endpoint.host.address,
        port: endpoint.port,
      );
    } catch (error) {
      manualConnectError = '$error';
      notifyListeners();
      return false;
    }
  }

  Future<bool> addManualPeerByAddress({
    required String name,
    required String host,
    required String port,
  }) async {
    try {
      final endpoint = NetworkAddressService.parseEndpoint(
        '${host.trim()}:${port.trim()}',
      );
      return _addManualEndpoint(
        name: name,
        hostAddress: endpoint.host.address,
        port: endpoint.port,
      );
    } catch (error) {
      manualConnectError = '$error';
      notifyListeners();
      return false;
    }
  }

  Future<bool> addPeerFromConnectionPayload(String payload) async {
    try {
      final peer = _connectionPayloadService.decode(payload);
      _peers[peer.deviceId] = peer;
      manualConnectError = null;
      notifyListeners();
      final connected = await _sendPeerHello(peer);
      if (!connected) {
        manualConnectError = '已添加设备，但无法连接对方。请确认两台设备在同一 Wi‑Fi，并允许本地网络访问。';
      }
      notifyListeners();
      return connected;
    } catch (error) {
      manualConnectError = '$error';
      notifyListeners();
      return false;
    }
  }

  Future<void> refreshNearbyDevices() async {
    try {
      localIpv4Addresses = await _networkAddressService.localIpv4Addresses();
      _dropExpiredPeers();
      final port = transferPort;
      if (deviceId.isNotEmpty && port != null) {
        await _discoveryService.start(
          deviceId: deviceId,
          deviceName: deviceName,
          transferPort: port,
          onPeer: _upsertPeer,
        );
      }
      errorMessage = null;
    } catch (error) {
      errorMessage = '$error';
    }
    notifyListeners();
  }

  Future<bool> _sendPeerHello(PeerDevice peer) async {
    final port = transferPort;
    if (deviceId.isEmpty || port == null) return false;
    return _transferClient.sendPeerHello(
      peer: peer,
      deviceName: deviceName,
      deviceId: deviceId,
      senderPort: port,
    );
  }

  bool _addManualEndpoint({
    required String name,
    required String hostAddress,
    required int port,
  }) {
    final trimmedName = name.trim();
    final peer = PeerDevice(
      deviceId: 'manual-$hostAddress:$port',
      name: trimmedName.isEmpty ? '手动设备 $hostAddress' : trimmedName,
      host: NetworkAddressService.parseEndpoint('$hostAddress:$port').host,
      port: port,
      platform: 'manual',
      lastSeen: DateTime.now(),
    );
    _peers[peer.deviceId] = peer;
    manualConnectError = null;
    notifyListeners();
    return true;
  }

  Future<bool> openDirectory(String directoryPath) {
    return _fileService.openDirectory(directoryPath);
  }

  Future<bool> deleteTransferBatch(
    String batchId, {
    bool deleteFiles = false,
  }) async {
    final index = _batches.indexWhere((entry) => entry.id == batchId);
    if (index < 0) return false;
    final batch = _batches.removeAt(index);
    if (deleteFiles) {
      await _fileService.deleteSavedFiles(batch.files);
    }
    notifyListeners();
    return true;
  }

  void dismissTextMessage() {
    pendingTextMessage = null;
    notifyListeners();
  }

  void _receiveTextMessage(IncomingTextMessage message) {
    pendingTextMessage = message;
    notifyListeners();
  }

  Future<bool> acceptIncomingTransfer() async {
    final prompt = pendingIncomingPrompt;
    if (prompt == null) return false;
    try {
      saveDirectory = await _fileService.requireWritableSaveDirectory(
        saveDirectory,
      );
      pendingIncomingPrompt = null;
      saveDirectoryError = null;
      prompt.complete(true);
      notifyListeners();
      return true;
    } catch (error) {
      saveDirectoryError = '$error';
      notifyListeners();
      return false;
    }
  }

  void rejectIncomingTransfer() {
    final prompt = pendingIncomingPrompt;
    pendingIncomingPrompt = null;
    prompt?.complete(false);
    notifyListeners();
  }

  Future<bool> _confirmIncomingTransfer(TransferBatch batch) {
    if (pendingIncomingPrompt != null) return Future.value(false);
    final prompt = IncomingTransferPrompt(batch: batch);
    pendingIncomingPrompt = prompt;
    notifyListeners();
    return prompt.decision;
  }

  void _upsertPeer(PeerDevice peer) {
    _peers[peer.deviceId] = peer;
    _dropExpiredPeers();
    notifyListeners();
  }

  @visibleForTesting
  void upsertPeerForTesting(PeerDevice peer) {
    _upsertPeer(peer);
  }

  void _dropExpiredPeers() {
    final cutoff = DateTime.now().subtract(const Duration(seconds: 8));
    _peers.removeWhere(
      (_, peer) =>
          !_isPinnedPeer(peer) && peer.lastSeen.isBefore(cutoff),
    );
  }

  bool _isPinnedPeer(PeerDevice peer) {
    return peer.platform == 'manual' ||
        peer.platform == 'qr' ||
        peer.platform == 'direct';
  }

  void _upsertBatch(TransferBatch batch) {
    final index = _batches.indexWhere((entry) => entry.id == batch.id);
    if (index >= 0) {
      _batches[index] = batch;
    } else {
      _batches.insert(0, batch);
    }
    notifyListeners();
  }

  @visibleForTesting
  void upsertBatchForTesting(TransferBatch batch) {
    _upsertBatch(batch);
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _discoveryService.stop();
    _transferServer.stop();
    super.dispose();
  }
}
