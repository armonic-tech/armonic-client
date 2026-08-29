import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:armonic_client/l10n/app_strings.dart';
import 'package:armonic_client/screens/server_screen.dart';
import 'package:armonic_client/state/session.dart';

import 'support/fakes.dart';

void main() {
  /// [connectedSession] does real I/O, which testWidgets' fake-async zone
  /// would never let complete.
  Future<InstanceSession> liveSession(
    WidgetTester tester, [
    FakeBackend? backend,
  ]) async {
    final session = (await tester.runAsync(
      () => connectedSession(backend ?? defaultBackend(), FakeSocket()),
    ))!;
    addTearDown(session.dispose);
    return session;
  }

  Future<void> pumpChat(WidgetTester tester, InstanceSession session) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider.value(
          value: session,
          child: const Scaffold(body: ChatPane()),
        ),
      ),
    );
    await tester.pump();
  }

  Finder composer() => find.byType(TextField);

  testWidgets('typing @ lists the roster above the composer', (tester) async {
    await pumpChat(tester, await liveSession(tester));

    await tester.enterText(composer(), '@');
    await tester.pump();

    expect(find.text(strings.mentionPickerTitle), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
  });

  testWidgets('the query filters the list', (tester) async {
    await pumpChat(tester, await liveSession(tester));

    await tester.enterText(composer(), '@bo');
    await tester.pump();

    expect(find.text('Bob'), findsOneWidget);
    // "Yo" is the other roster entry and does not match "bo".
    expect(find.text('Yo'), findsNothing);
  });

  testWidgets('enter completes the highlighted name instead of sending', (
    tester,
  ) async {
    final socket = FakeSocket();
    final session = (await tester.runAsync(
      () => connectedSession(defaultBackend(), socket),
    ))!;
    addTearDown(session.dispose);
    await pumpChat(tester, session);

    await tester.enterText(composer(), 'hola @bo');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();

    expect(tester.widget<TextField>(composer()).controller!.text, 'hola @Bob ');
    // Nothing was sent: Enter belonged to the picker, not to the composer.
    expect(socket.lastOfType('text-message'), isNull);
    // And the picker closed once the mention was completed.
    expect(find.text(strings.mentionPickerTitle), findsNothing);
  });

  testWidgets('clicking a name completes it too', (tester) async {
    await pumpChat(tester, await liveSession(tester));

    await tester.enterText(composer(), '@');
    await tester.pump();
    await tester.tap(find.text('Bob'));
    await tester.pump();

    expect(tester.widget<TextField>(composer()).controller!.text, '@Bob ');
  });

  testWidgets('with the picker closed, enter still sends', (tester) async {
    final socket = FakeSocket();
    final session = (await tester.runAsync(
      () => connectedSession(defaultBackend(), socket),
    ))!;
    addTearDown(session.dispose);
    await pumpChat(tester, session);

    await tester.enterText(composer(), 'hola');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.send);
    // sendText arms a 2s "delivered" timer for the optimistic echo; let it
    // fire so no timer outlives the test.
    await tester.pump(const Duration(seconds: 3));

    expect(socket.lastOfType('text-message')!['content'], 'hola');
  });

  testWidgets('a completed mention leaves a plain-text message', (
    tester,
  ) async {
    final socket = FakeSocket();
    final session = (await tester.runAsync(
      () => connectedSession(defaultBackend(), socket),
    ))!;
    addTearDown(session.dispose);
    await pumpChat(tester, session);

    await tester.enterText(composer(), '@bo');
    await tester.pump();
    await tester.tap(find.text('Bob'));
    await tester.pump();
    await tester.enterText(
      composer(),
      '${tester.widget<TextField>(composer()).controller!.text}hola',
    );
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump(const Duration(seconds: 3));

    expect(socket.lastOfType('text-message')!['content'], '@Bob hola');
  });

  /// Emits [content] as a message from Bob and returns the session.
  Future<InstanceSession> chatWith(WidgetTester tester, String content) async {
    final socket = FakeSocket();
    final session = (await tester.runAsync(
      () => connectedSession(defaultBackend(), socket),
    ))!;
    addTearDown(session.dispose);
    await tester.runAsync(() async {
      socket.emit({
        'type': 'text-message',
        'id': 'm1',
        'serverId': 's1',
        'channelId': 'c-text',
        'userId': 'u2',
        'content': content,
        'createdAt': '2026-01-01T10:00:00Z',
      });
      await drainEvents();
    });
    return session;
  }

  /// The tile's own background, which is what carries the highlight.
  Color? tileColor(WidgetTester tester) {
    final container = tester.widget<AnimatedContainer>(
      find.byKey(MessageTile.hoverBandKey),
    );
    return (container.decoration as BoxDecoration?)?.color;
  }

  testWidgets('a message naming me is tinted and banded', (tester) async {
    // The fixture's own user is "Yo".
    await pumpChat(tester, await chatWith(tester, 'ping @Yo'));

    expect(tileColor(tester), isNot(Colors.transparent));
    expect(find.byKey(MessageTile.mentionBarKey), findsOneWidget);
  });

  testWidgets('a message naming someone else is left plain', (tester) async {
    await pumpChat(tester, await chatWith(tester, 'ping @Bob'));

    expect(tileColor(tester), Colors.transparent);
    expect(find.byKey(MessageTile.mentionBarKey), findsNothing);
  });

  testWidgets('my own name in plain text does not highlight', (tester) async {
    await pumpChat(tester, await chatWith(tester, 'Yo estuve ahí'));

    expect(tileColor(tester), Colors.transparent);
    expect(find.byKey(MessageTile.mentionBarKey), findsNothing);
  });
}
