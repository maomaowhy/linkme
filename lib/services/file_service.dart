import 'dart:io';

import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/transfer_models.dart';

class SaveDirectoryException implements Exception {
  const SaveDirectoryException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => cause == null ? message : '$message: $cause';
}

class FileService {
  static const _saveDirectoryKey = 'link_me.save_directory';
  static const appFolderName = 'LinkMe';
  static const _channel = MethodChannel('link_me/file_system');

  Future<List<File>> pickFiles() async {
    final result = await FilePicker.pickFiles(
      allowMultiple: true,
      withData: false,
      lockParentWindow: true,
    );
    if (result == null) return const [];
    return result.files
        .where((file) => file.path != null)
        .map((file) => File(file.path!))
        .toList(growable: false);
  }

  Future<String> loadSaveDirectory() async {
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getString(_saveDirectoryKey);
    if (saved != null && saved.isNotEmpty) {
      final normalized = normalizeSaveDirectory(saved);
      if (_isAndroidAppPrivateDirectory(normalized)) {
        await preferences.remove(_saveDirectoryKey);
      } else {
        try {
          await ensureWritableDirectory(normalized);
          if (normalized != saved) await persistSaveDirectory(normalized);
          return normalized;
        } catch (_) {
          await preferences.remove(_saveDirectoryKey);
        }
      }
    }
    final fallback = await resolveWritableSaveDirectory(
      await defaultSaveDirectory(),
    );
    await persistSaveDirectory(fallback);
    return fallback;
  }

  Future<void> persistSaveDirectory(String path) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _saveDirectoryKey,
      normalizeSaveDirectory(path),
    );
  }

  Future<String> requireWritableSaveDirectory(String currentPath) async {
    await _ensureValidRootDirectory(currentPath);
    final normalized = normalizeSaveDirectory(currentPath);
    await ensureWritableDirectory(normalized);
    await persistSaveDirectory(normalized);
    return normalized;
  }

  Future<String> resolveWritableSaveDirectory(String currentPath) async {
    if (currentPath.isNotEmpty) {
      final normalized = normalizeSaveDirectory(currentPath);
      try {
        await ensureWritableDirectory(normalized);
        await persistSaveDirectory(normalized);
        return normalized;
      } catch (_) {
        // Fall back below.
      }
    }
    final fallback = normalizeSaveDirectory(await defaultSaveDirectory());
    await ensureWritableDirectory(fallback);
    await persistSaveDirectory(fallback);
    return fallback;
  }

  String normalizeSaveDirectory(String directoryPath) {
    final trimmed = directoryPath.trim();
    if (trimmed.isEmpty) return trimmed;
    final withoutTrailingSeparators = trimmed.replaceFirst(
      RegExp(r'[/\\]+$'),
      '',
    );
    final segments = withoutTrailingSeparators.split(RegExp(r'[/\\]+'));
    if (segments.isNotEmpty &&
        segments.last.toLowerCase() == appFolderName.toLowerCase()) {
      return withoutTrailingSeparators;
    }
    return '$withoutTrailingSeparators${Platform.pathSeparator}$appFolderName';
  }

  bool _isAndroidAppPrivateDirectory(String directoryPath) {
    final normalized = directoryPath.replaceAll('\\', '/').toLowerCase();
    return normalized.contains('/android/data/') &&
        normalized.contains('/files');
  }

  Future<String?> chooseSaveDirectory() async {
    final selected = await FilePicker.getDirectoryPath(lockParentWindow: true);
    if (selected == null || selected.isEmpty) return null;
    return normalizeSaveDirectory(selected);
  }

  Future<String> defaultSaveDirectory() async {
    if (Platform.isAndroid) {
      final publicDownload = Directory('/storage/emulated/0/Download');
      if (await publicDownload.exists()) return publicDownload.path;
      final external = await getExternalStorageDirectory();
      if (external != null) return external.path;
    }
    final desktopDownloads = desktopDownloadsPathFromEnvironment(
      Platform.environment,
      Platform.operatingSystem,
    );
    if (desktopDownloads != null) return desktopDownloads;
    if (supportsDownloadsDirectoryApi(Platform.operatingSystem)) {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) return downloads.path;
    }
    final documents = await getApplicationDocumentsDirectory();
    return documents.path;
  }

  static bool supportsDownloadsDirectoryApi(String operatingSystem) {
    return operatingSystem == 'macos' ||
        operatingSystem == 'linux' ||
        operatingSystem == 'windows';
  }

  static String? desktopDownloadsPathFromEnvironment(
    Map<String, String> environment,
    String operatingSystem,
  ) {
    if (operatingSystem == 'macos' || operatingSystem == 'linux') {
      final home = environment['HOME'];
      if (home == null || home.isEmpty) return null;
      return '$home${Platform.pathSeparator}Downloads';
    }
    if (operatingSystem == 'windows') {
      final profile = environment['USERPROFILE'];
      if (profile == null || profile.isEmpty) return null;
      return '$profile${Platform.pathSeparator}Downloads';
    }
    return null;
  }

  Future<void> deleteSavedFiles(List<TransferFileItem> files) async {
    for (final item in files) {
      final path = item.savePath;
      if (path == null || path.isEmpty) continue;
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Keep deleting the rest; missing or protected files should not block record removal.
      }
    }
  }

  Future<void> ensureWritableDirectory(String directoryPath) async {
    try {
      final directory = Directory(directoryPath);
      await directory.create(recursive: true);
      final probe = File(
        '${directory.path}${Platform.pathSeparator}.link_me_write_probe',
      );
      await probe.writeAsString('ok', flush: true);
      if (await probe.exists()) await probe.delete();
    } catch (error) {
      throw SaveDirectoryException(
        '当前保存目录不可写：$directoryPath。请允许存储权限，或选择一个可写目录。',
        error,
      );
    }
  }

  Future<void> _ensureValidRootDirectory(String directoryPath) async {
    final trimmed = directoryPath.trim();
    if (trimmed.isEmpty) {
      throw const SaveDirectoryException('请选择一个保存目录。');
    }
    final root = Directory(trimmed);
    if (await FileSystemEntity.type(root.path) == FileSystemEntityType.file) {
      throw SaveDirectoryException('当前保存目录不是文件夹：$trimmed。');
    }
  }

  Future<void> notifyFileSaved(String path) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('scanFile', {'path': path});
    } catch (_) {
      // Best effort only; the file has already been written.
    }
  }

  Future<bool> openDirectory(String directoryPath) async {
    if (directoryPath.trim().isEmpty) return false;
    if (Platform.isAndroid) {
      try {
        return await _channel.invokeMethod<bool>('openDirectory', {
              'path': directoryPath,
            }) ??
            false;
      } catch (_) {
        return false;
      }
    }

    final command = switch (Platform.operatingSystem) {
      'macos' => 'open',
      'windows' => 'explorer',
      'linux' => 'xdg-open',
      _ => null,
    };
    if (command == null) return false;
    try {
      final result = await Process.run(command, [directoryPath]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<File> createWritableFile(String directoryPath, String fileName) async {
    final normalizedDirectory = normalizeSaveDirectory(directoryPath);
    await ensureWritableDirectory(normalizedDirectory);
    final directory = Directory(normalizedDirectory);
    final safeName = sanitizeFileName(fileName);
    var candidate = File('${directory.path}${Platform.pathSeparator}$safeName');
    if (!await candidate.exists()) return candidate;

    final dot = safeName.lastIndexOf('.');
    final base = dot > 0 ? safeName.substring(0, dot) : safeName;
    final extension = dot > 0 ? safeName.substring(dot) : '';
    var index = 1;
    while (await candidate.exists()) {
      candidate = File(
        '${directory.path}${Platform.pathSeparator}$base ($index)$extension',
      );
      index += 1;
    }
    return candidate;
  }

  String sanitizeFileName(String input) {
    final cleaned = input.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return cleaned.isEmpty ? 'received-file' : cleaned;
  }
}
