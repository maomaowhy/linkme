import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:link_me/services/file_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TestFileService extends FileService {
  TestFileService(this.fallbackPath);

  final String fallbackPath;

  @override
  Future<String> defaultSaveDirectory() async => fallbackPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'desktopDownloadsPathFromEnvironment uses the user Downloads folder',
    () {
      expect(
        FileService.desktopDownloadsPathFromEnvironment({
          'HOME': '/Users/wangzy',
        }, 'macos'),
        '/Users/wangzy${Platform.pathSeparator}Downloads',
      );
    },
  );

  test('downloads directory API is not used on iOS', () {
    expect(FileService.supportsDownloadsDirectoryApi('ios'), isFalse);
    expect(FileService.supportsDownloadsDirectoryApi('android'), isFalse);
    expect(FileService.supportsDownloadsDirectoryApi('macos'), isTrue);
  });

  test('iosDefaultSaveRoot uses the app Documents folder directly', () {
    final documents =
        '${Directory.systemTemp.path}${Platform.pathSeparator}Documents';

    expect(FileService.iosDefaultSaveRoot(documents), documents);
  });

  test('saveLocationOpenActionFor describes per-platform behavior', () {
    final ios = FileService.saveLocationOpenActionFor('ios');
    expect(ios.buttonLabel, '查看文件位置');
    expect(ios.canAttemptOpen, isFalse);
    expect(ios.failureMessage, contains('文件 App'));

    final android = FileService.saveLocationOpenActionFor('android');
    expect(android.buttonLabel, '查看保存位置');
    expect(android.canAttemptOpen, isTrue);
    expect(android.failureMessage, contains('下载'));

    final macos = FileService.saveLocationOpenActionFor('macos');
    expect(macos.buttonLabel, '打开文件夹');
    expect(macos.canAttemptOpen, isTrue);
    expect(macos.failureMessage, contains('Finder'));
  });

  test('migrateIosDownloadsSaveDirectory removes the extra Downloads segment', () {
    final documents =
        '${Directory.systemTemp.path}${Platform.pathSeparator}Documents';
    final oldPath =
        '$documents${Platform.pathSeparator}Downloads${Platform.pathSeparator}LinkMe';

    expect(
      FileService.migrateIosDownloadsSaveDirectory(oldPath, documents),
      '$documents${Platform.pathSeparator}LinkMe',
    );
    expect(
      FileService.migrateIosDownloadsSaveDirectory(
        '$documents${Platform.pathSeparator}Custom${Platform.pathSeparator}LinkMe',
        documents,
      ),
      isNull,
    );
  });

  test('normalizeSaveDirectory stores files under a LinkMe child folder', () {
    final service = FileService();
    final base =
        '${Directory.systemTemp.path}${Platform.pathSeparator}Downloads';

    expect(
      service.normalizeSaveDirectory(base),
      '$base${Platform.pathSeparator}LinkMe',
    );
    expect(
      service.normalizeSaveDirectory('$base${Platform.pathSeparator}LinkMe'),
      '$base${Platform.pathSeparator}LinkMe',
    );
    expect(
      service.normalizeSaveDirectory('$base${Platform.pathSeparator}linkme'),
      '$base${Platform.pathSeparator}linkme',
    );
  });

  test(
    'resolveWritableSaveDirectory falls back when current path is not writable',
    () async {
      SharedPreferences.setMockInitialValues({});
      final temp = await Directory.systemTemp.createTemp(
        'link-me-file-service-',
      );
      final notDirectory = File(
        '${temp.path}${Platform.pathSeparator}not-a-dir',
      );
      final fallback = Directory(
        '${temp.path}${Platform.pathSeparator}fallback',
      );
      await notDirectory.writeAsString('blocks directory creation');

      final service = TestFileService(fallback.path);
      final resolved = await service.resolveWritableSaveDirectory(
        notDirectory.path,
      );

      expect(resolved, '${fallback.path}${Platform.pathSeparator}LinkMe');
      await service.ensureWritableDirectory(resolved);

      await temp.delete(recursive: true);
    },
  );

  test(
    'requireWritableSaveDirectory reports an unwritable selected path',
    () async {
      SharedPreferences.setMockInitialValues({});
      final temp = await Directory.systemTemp.createTemp(
        'link-me-file-service-explicit-',
      );
      final notDirectory = File(
        '${temp.path}${Platform.pathSeparator}not-a-dir',
      );
      await notDirectory.writeAsString('blocks directory creation');

      final service = TestFileService(temp.path);

      expect(
        () => service.requireWritableSaveDirectory(notDirectory.path),
        throwsA(isA<SaveDirectoryException>()),
      );

      await temp.delete(recursive: true);
    },
  );

  test(
    'loadSaveDirectory migrates old Android private app directory',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'link-me-file-service-private-',
      );
      final fallback = Directory(
        '${temp.path}${Platform.pathSeparator}Download',
      );
      final oldPrivate =
          '/storage/emulated/0/Android/data/com.linkme.app/files/LinkMe';
      SharedPreferences.setMockInitialValues({
        'link_me.save_directory': oldPrivate,
      });

      final service = TestFileService(fallback.path);
      final resolved = await service.loadSaveDirectory();

      expect(resolved, '${fallback.path}${Platform.pathSeparator}LinkMe');
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('link_me.save_directory'), resolved);

      await temp.delete(recursive: true);
    },
  );
}
