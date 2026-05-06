import 'dart:async';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:link_me/main.dart';
import 'package:link_me/models/peer_device.dart';
import 'package:link_me/models/transfer_models.dart';
import 'package:link_me/services/transfer_client.dart';
import 'package:link_me/state/app_state.dart';
import 'package:link_me/ui/home_page.dart';
import 'package:provider/provider.dart';

class SlowTextTransferClient extends TransferClient {
  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();
  String? sentText;

  @override
  Future<bool> sendText({
    required PeerDevice peer,
    required String deviceName,
    required String deviceId,
    required String text,
    int? senderPort,
  }) async {
    sentText = text;
    started.complete();
    await release.future;
    return true;
  }
}

void main() {
  testWidgets('renders Link Me shell', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const LinkMeApp());
    await tester.pump();

    expect(find.text('Link Me'), findsOneWidget);
    expect(find.textContaining('附近设备'), findsOneWidget);
    expect(find.byIcon(Icons.folder_rounded), findsOneWidget);
    expect(find.textContaining('正在搜索同一局域网'), findsOneWidget);
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
  });

  testWidgets('opens and closes connection qr dialog', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const LinkMeApp());
    await tester.pump();

    await tester.tap(find.byIcon(Icons.qr_code_2_rounded));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    expect(find.textContaining('暂无可展示地址'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byIcon(Icons.close_rounded), findsNothing);
  });

  testWidgets('shows one text prompt for repeated rebuilds', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final state = AppState();
    addTearDown(state.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await tester.pump();

    state.pendingTextMessage = IncomingTextMessage(
      id: 'message-1',
      senderName: 'Android Phone',
      text: 'hello from phone',
      createdAt: DateTime(2026),
    );
    state.notifyListeners();

    await tester.pump();
    await tester.pump();
    await tester.pump();

    state.notifyListeners();
    await tester.pump();
    state.notifyListeners();
    await tester.pump();

    expect(find.text('Android Phone 发来文本'), findsOneWidget);
    expect(find.text('hello from phone'), findsOneWidget);
  });

  testWidgets('sending text closes dialog without framework exception', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final transferClient = SlowTextTransferClient();
    final state = AppState(transferClient: transferClient);
    addTearDown(state.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await tester.pump();

    state.isStarting = false;
    await state.addManualPeerByAddress(
      name: 'Android Phone',
      host: '192.168.1.22',
      port: '45678',
    );
    await tester.pump();

    await tester.tap(find.text('文本').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'hello text');
    await tester.tap(find.text('发送'));
    await transferClient.started.future;
    await tester.pump();

    transferClient.release.complete();
    await tester.pumpAndSettle();

    expect(transferClient.sentText, 'hello text');
    expect(tester.takeException(), isNull);
    expect(find.text('发送文本给 Android Phone'), findsNothing);
  });

  testWidgets('nearby device card can be removed', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final state = AppState();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await tester.pump();

    state.isStarting = false;
    state.upsertPeerForTesting(
      PeerDevice(
        deviceId: 'android-1',
        name: 'Android Phone',
        host: InternetAddress('192.168.1.30'),
        port: 45678,
        platform: 'android',
        lastSeen: DateTime.now(),
      ),
    );
    await tester.pump();

    expect(find.text('Android Phone'), findsOneWidget);

    await tester.tap(find.byTooltip('移除设备'));
    await tester.pump();

    expect(find.text('Android Phone'), findsNothing);
  });
}
