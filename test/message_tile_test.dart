import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:armonic_client/l10n/app_strings.dart';
import 'package:armonic_client/models/models.dart';
import 'package:armonic_client/screens/server_screen.dart';

void main() {
  final message = ChatMessage(
    id: 'm1',
    channelId: 'c-text',
    serverId: 's1',
    userId: 'u2',
    content: 'hola',
    createdAt: DateTime(2026, 1, 1, 10, 30),
  );

  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(width: 400, height: 80, child: child),
          ),
        ),
      );

  Future<void> rightClick(WidgetTester tester, Finder finder) async {
    final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
    await gesture.down(tester.getCenter(finder));
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('right-click as admin opens the menu and fires the delete',
      (tester) async {
    var deleted = false;
    await tester.pumpWidget(wrap(MessageTile(
      message: message,
      isOwn: false,
      author: 'Bob',
      onDelete: () => deleted = true,
    )));

    await rightClick(tester, find.byType(MessageTile));
    expect(find.text(strings.deleteMessage), findsOneWidget);

    await tester.tap(find.text(strings.deleteMessage));
    await tester.pumpAndSettle();
    expect(deleted, isTrue);
  });

  testWidgets('long-press also opens the menu (mobile)', (tester) async {
    await tester.pumpWidget(wrap(MessageTile(
      message: message,
      isOwn: false,
      author: 'Bob',
      onDelete: () {},
    )));

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

  testWidgets('hovering an admin-actionable message tints its background',
      (tester) async {
    await tester.pumpWidget(wrap(MessageTile(
      message: message,
      isOwn: false,
      author: 'Bob',
      onDelete: () {},
    )));

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
    await tester.pumpWidget(wrap(MessageTile(
      message: message,
      isOwn: false,
      author: 'Bob',
    )));

    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await pointer.addPointer(location: Offset.zero);
    addTearDown(pointer.removePointer);
    await pointer.moveTo(tester.getCenter(find.byType(MessageTile)));
    await tester.pumpAndSettle();

    expect(bandColor(tester), isNull);
  });

  testWidgets('no menu for a non-admin (callback null)', (tester) async {
    await tester.pumpWidget(wrap(MessageTile(
      message: message,
      isOwn: false,
      author: 'Bob',
    )));

    await rightClick(tester, find.byType(MessageTile));
    expect(find.text(strings.deleteMessage), findsNothing);
  });
}