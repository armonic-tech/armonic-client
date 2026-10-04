import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:armonic_client/api/http_api.dart';
import 'package:armonic_client/l10n/app_strings.dart';
import 'package:armonic_client/models/models.dart';
import 'package:armonic_client/screens/server_screen.dart';
import 'package:armonic_client/state/attachment_cache.dart';
import 'package:armonic_client/widgets/attachment_image.dart';

void main() {
  final message = ChatMessage(
    id: 'm1',
    channelId: 'c-text',
    serverId: 's1',
    userId: 'u2',
    content: 'hola',
    createdAt: DateTime(2026, 1, 1, 10, 30),
  );

  final locked = ChatMessage(
    id: 'm2',
    channelId: 'c-text',
    serverId: 's1',
    userId: 'u2',
    content: '{"v":1}',
    encrypted: true,
    locked: true,
    createdAt: DateTime(2026, 1, 1, 10, 31),
  );

  final withImage = ChatMessage(
    id: 'm3',
    channelId: 'c-text',
    serverId: 's1',
    userId: 'u2',
    content: '',
    attachmentId: 'att-1',
    createdAt: DateTime(2026, 1, 1, 10, 32),
  );

  Widget wrap(Widget child, {double height = 80}) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(width: 400, height: height, child: child),
      ),
    ),
  );

  Future<void> rightClick(WidgetTester tester, Finder finder) async {
    final gesture = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.down(tester.getCenter(finder));
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('a locked message shows the padlock line, not the envelope', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        MessageTile(message: locked, isOwn: false, author: 'Bob'),
        height: 160,
      ),
    );
    expect(find.byKey(MessageTile.lockedKey), findsOneWidget);
    expect(find.text(strings.lockedMessage), findsOneWidget);
    expect(find.textContaining('"v":1'), findsNothing);
  });

  testWidgets('a clear-text message in an encrypted server is marked', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        MessageTile(
          message: message,
          isOwn: false,
          author: 'Bob',
          e2eeActive: true,
        ),
      ),
    );
    expect(find.byTooltip(strings.unencryptedMessage), findsOneWidget);
  });

  testWidgets('with auto-download off the image is a button until tapped', (
    tester,
  ) async {
    final cache = AttachmentCache(
      ArmonicHttpApi(
        'http://test',
        client: MockClient((_) async => http.Response('nope', 404)),
      ),
      () => 'jwt',
    );
    await tester.pumpWidget(
      wrap(
        MessageTile(
          message: withImage,
          isOwn: false,
          author: 'Bob',
          attachments: cache,
          autoDownloadImages: false,
        ),
        height: 400,
      ),
    );
    expect(find.byKey(MessageTile.downloadKey), findsOneWidget);
    expect(find.byType(AttachmentImage), findsNothing);

    await tester.tap(find.byKey(MessageTile.downloadKey));
    await tester.pump();
    expect(find.byKey(MessageTile.downloadKey), findsNothing);
    expect(find.byType(AttachmentImage), findsOneWidget);
  });

  testWidgets('right-click as admin opens the menu and fires the delete', (
    tester,
  ) async {
    var deleted = false;
    await tester.pumpWidget(
      wrap(
        MessageTile(
          message: message,
          isOwn: false,
          author: 'Bob',
          onDelete: () => deleted = true,
        ),
      ),
    );

    await rightClick(tester, find.byType(MessageTile));
    expect(find.text(strings.deleteMessage), findsOneWidget);

    await tester.tap(find.text(strings.deleteMessage));
    await tester.pumpAndSettle();
    expect(deleted, isTrue);
  });

  testWidgets('long-press also opens the menu (mobile)', (tester) async {
    await tester.pumpWidget(
      wrap(
        MessageTile(
          message: message,
          isOwn: false,
          author: 'Bob',
          onDelete: () {},
        ),
      ),
    );

    await tester.longPress(find.byType(MessageTile));
    await tester.pumpAndSettle();
    expect(find.text(strings.deleteMessage), findsOneWidget);
  });

  /// Colour of the tile's own background band, or null when the tile does not
  /// draw one (non-admin).
  Color? bandColor(WidgetTester tester) {
    final band = find.byKey(MessageTile.hoverBandKey);
    if (band.evaluate().isEmpty) return null;
    final decoration =
        tester.widget<AnimatedContainer>(band).decoration as BoxDecoration;
    return decoration.color;
  }

  testWidgets('hovering an admin-actionable message tints its background', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        MessageTile(
          message: message,
          isOwn: false,
          author: 'Bob',
          onDelete: () {},
        ),
      ),
    );

    expect(bandColor(tester), Colors.transparent);

    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: Offset.zero);
    addTearDown(pointer.removePointer);
    await pointer.moveTo(tester.getCenter(find.byType(MessageTile)));
    await tester.pumpAndSettle();

    expect(bandColor(tester), isNot(Colors.transparent));

    await pointer.moveTo(Offset.zero);
    await tester.pumpAndSettle();
    expect(bandColor(tester), Colors.transparent);
  });

  testWidgets('a non-admin tile never highlights', (tester) async {
    await tester.pumpWidget(
      wrap(MessageTile(message: message, isOwn: false, author: 'Bob')),
    );

    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: Offset.zero);
    addTearDown(pointer.removePointer);
    await pointer.moveTo(tester.getCenter(find.byType(MessageTile)));
    await tester.pumpAndSettle();

    expect(bandColor(tester), isNull);
  });

  testWidgets('no menu for a non-admin (callback null)', (tester) async {
    await tester.pumpWidget(
      wrap(MessageTile(message: message, isOwn: false, author: 'Bob')),
    );

    await rightClick(tester, find.byType(MessageTile));
    expect(find.text(strings.deleteMessage), findsNothing);
  });
}
