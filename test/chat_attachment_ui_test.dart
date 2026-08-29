import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:armonic_client/l10n/app_strings.dart';
import 'package:armonic_client/screens/server_screen.dart';
import 'package:armonic_client/state/session.dart';
import 'package:armonic_client/util/pick_image.dart';

import 'support/fakes.dart';

/// The smallest valid PNG, so Image.memory has something real to decode.
final _pngBytes = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

const _attachmentJson = {
  'id': 'att-1',
  'serverId': 's1',
  'userId': 'me',
  'mime': 'image/png',
  'size': 70,
  'width': 640,
  'height': 480,
  'url': '/attachment/att-1',
  'thumbUrl': '/attachment/att-1/thumb',
  'createdAt': '2026-01-01T10:00:00Z',
};

void main() {
  Future<InstanceSession> liveSession(
    WidgetTester tester,
    FakeBackend backend,
    FakeSocket socket,
  ) async {
    final session = (await tester.runAsync(
      () => connectedSession(backend, socket),
    ))!;
    addTearDown(session.dispose);
    return session;
  }

  Future<void> pumpChat(
    WidgetTester tester,
    InstanceSession session, {
    PickedImage? picked,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider.value(
          value: session,
          child: Scaffold(
            body: SizedBox(
              width: 500,
              height: 600,
              child: ChatPane(pickImage: () async => picked),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('attaching uploads at once and shows a preview', (tester) async {
    final backend = defaultBackend()..uploadResponse = _attachmentJson;
    backend.blobs['/attachment/att-1/thumb'] = _pngBytes;
    final socket = FakeSocket();
    final session = await liveSession(tester, backend, socket);
    await pumpChat(
      tester,
      session,
      picked: PickedImage(_pngBytes, 'photo.png'),
    );

    expect(find.byTooltip(strings.removeAttachment), findsNothing);

    await tester.tap(find.byIcon(Icons.image_outlined));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();

    // Uploading on pick, not on send, means it is already validated by the
    // time the user commits to sending.
    expect(backend.uploadedPaths, ['/server/s1/upload']);
    expect(find.byTooltip(strings.removeAttachment), findsOneWidget);
    expect(find.text('640x480'), findsOneWidget);
  });

  testWidgets('sending with an attachment clears the preview', (tester) async {
    final backend = defaultBackend()..uploadResponse = _attachmentJson;
    backend.blobs['/attachment/att-1/thumb'] = _pngBytes;
    final socket = FakeSocket();
    final session = await liveSession(tester, backend, socket);
    await pumpChat(
      tester,
      session,
      picked: PickedImage(_pngBytes, 'photo.png'),
    );

    await tester.tap(find.byIcon(Icons.image_outlined));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.send));
    // sendText arms a 2s "delivered" timer for the optimistic echo; let it
    // fire so no timer outlives the test.
    await tester.pump(const Duration(seconds: 3));

    final sent = socket.lastOfType('text-message')!;
    expect(sent['attachmentId'], 'att-1');
    expect(sent['content'], '');
    expect(find.byTooltip(strings.removeAttachment), findsNothing);
  });

  testWidgets('removing the preview drops the attachment from the next send', (
    tester,
  ) async {
    final backend = defaultBackend()..uploadResponse = _attachmentJson;
    backend.blobs['/attachment/att-1/thumb'] = _pngBytes;
    final socket = FakeSocket();
    final session = await liveSession(tester, backend, socket);
    await pumpChat(
      tester,
      session,
      picked: PickedImage(_pngBytes, 'photo.png'),
    );

    await tester.tap(find.byIcon(Icons.image_outlined));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();

    await tester.tap(find.byTooltip(strings.removeAttachment));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'solo texto');
    await tester.tap(find.byIcon(Icons.send));
    // sendText arms a 2s "delivered" timer for the optimistic echo; let it
    // fire so no timer outlives the test.
    await tester.pump(const Duration(seconds: 3));

    final sent = socket.lastOfType('text-message')!;
    expect(sent['content'], 'solo texto');
    expect(sent.containsKey('attachmentId'), isFalse);
  });

  testWidgets('a rejected upload tells the user why and stages nothing', (
    tester,
  ) async {
    final backend = defaultBackend()..uploadStatus = 413;
    final session = await liveSession(tester, backend, FakeSocket());
    await pumpChat(tester, session, picked: PickedImage(_pngBytes, 'huge.png'));

    await tester.tap(find.byIcon(Icons.image_outlined));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();

    expect(find.text(strings.imageTooLarge), findsOneWidget);
    expect(find.byTooltip(strings.removeAttachment), findsNothing);
  });

  testWidgets('cancelling the picker changes nothing', (tester) async {
    final backend = defaultBackend()..uploadResponse = _attachmentJson;
    final session = await liveSession(tester, backend, FakeSocket());
    await pumpChat(tester, session, picked: null);

    await tester.tap(find.byIcon(Icons.image_outlined));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();

    expect(backend.uploadedPaths, isEmpty);
    expect(find.byTooltip(strings.removeAttachment), findsNothing);
  });

  testWidgets('a message with an image renders its thumbnail', (tester) async {
    final backend = defaultBackend();
    backend.blobs['/attachment/att-9/thumb'] = _pngBytes;
    final socket = FakeSocket();
    final session = await liveSession(tester, backend, socket);

    await tester.runAsync(() async {
      socket.emit({
        'type': 'text-message',
        'id': 'm1',
        'serverId': 's1',
        'channelId': 'c-text',
        'userId': 'u2',
        'content': '',
        'attachmentId': 'att-9',
        'createdAt': '2026-01-01T10:00:00Z',
      });
      await drainEvents();
    });
    await pumpChat(tester, session);
    await tester.pump();

    expect(find.byKey(MessageTile.imageKey), findsOneWidget);
    // The author comes from the roster, not from a raw id.
    expect(find.text('Bob'), findsOneWidget);
  });

  testWidgets('a text-only message renders no image', (tester) async {
    final backend = defaultBackend();
    final socket = FakeSocket();
    final session = await liveSession(tester, backend, socket);

    await tester.runAsync(() async {
      socket.emit({
        'type': 'text-message',
        'id': 'm1',
        'serverId': 's1',
        'channelId': 'c-text',
        'userId': 'u2',
        'content': 'hola',
        'createdAt': '2026-01-01T10:00:00Z',
      });
      await drainEvents();
    });
    await pumpChat(tester, session);

    expect(find.byKey(MessageTile.imageKey), findsNothing);
    expect(find.text('hola'), findsOneWidget);
  });
}
