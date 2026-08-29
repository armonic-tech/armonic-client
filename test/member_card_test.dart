import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:armonic_client/l10n/app_strings.dart';
import 'package:armonic_client/screens/server_screen.dart';
import 'package:armonic_client/state/session.dart';
import 'package:armonic_client/widgets/members_panel.dart';

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

  Future<void> pumpPanel(WidgetTester tester, InstanceSession session) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider.value(
          value: session,
          child: const Scaffold(
            body: SizedBox(width: 260, height: 600, child: MembersPanel()),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('clicking a member opens their card', (tester) async {
    final session = await liveSession(tester);
    await pumpPanel(tester, session);

    await tester.tap(find.text('Bob'));
    await tester.pumpAndSettle();

    // The card is up: the status block only exists there, and the name is now
    // on screen twice (roster row + card).
    expect(find.text(strings.memberStatusLabel), findsOneWidget);
    expect(find.text('Bob'), findsNWidgets(2));
  });

  // Being in a call is the more specific fact, so it wins over plain presence
  // — the fixture has Bob connected to the "General" voice channel.
  testWidgets('the card names the voice channel when they are in one', (
    tester,
  ) async {
    final session = await liveSession(tester);
    await pumpPanel(tester, session);

    await tester.tap(find.text('Bob'));
    await tester.pumpAndSettle();

    expect(find.text(strings.inVoiceStatus('General')), findsOneWidget);
  });

  testWidgets('otherwise it falls back to online/offline', (tester) async {
    final backend = defaultBackend();
    backend.connectedByChannel['c-voice'] = [];
    backend.membersByServer['s1'] = [
      {'id': 'u2', 'displayName': 'Bob', 'online': true},
    ];
    final session = await liveSession(tester, backend);
    await pumpPanel(tester, session);

    await tester.tap(find.text('Bob'));
    await tester.pumpAndSettle();

    expect(find.text(strings.onlineLabel), findsOneWidget);
  });

  testWidgets('a plain member sees no kick action on the card', (tester) async {
    final session = await liveSession(tester, defaultBackend(ownerId: 'other'));
    await pumpPanel(tester, session);

    await tester.tap(find.text('Bob'));
    await tester.pumpAndSettle();

    expect(find.text(strings.memberStatusLabel), findsOneWidget);
    expect(find.text(strings.kickFromServer), findsNothing);
  });

  testWidgets('the owner gets the kick action, but never on themselves', (
    tester,
  ) async {
    final session = await liveSession(tester);
    await pumpPanel(tester, session);

    await tester.tap(find.text('Bob'));
    await tester.pumpAndSettle();
    expect(find.text(strings.kickFromServer), findsOneWidget);

    // Dismiss, then open our own card: kicking yourself is not offered.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yo'));
    await tester.pumpAndSettle();

    expect(find.text(strings.kickFromServer), findsNothing);
  });

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

  /// A message from Bob, so the chat has an author row to click.
  Future<InstanceSession> chatWithMessage(WidgetTester tester) async {
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
        'content': 'hola',
        'createdAt': '2026-01-01T10:00:00Z',
      });
      await drainEvents();
    });
    return session;
  }

  testWidgets("clicking a message author's name opens their card", (
    tester,
  ) async {
    await pumpChat(tester, await chatWithMessage(tester));

    // The author row is the only "Bob" on screen before the card opens.
    await tester.tap(find.text('Bob'));
    await tester.pumpAndSettle();

    expect(find.text(strings.memberStatusLabel), findsOneWidget);
    expect(find.text('Bob'), findsNWidgets(2));
  });

  testWidgets("clicking a message author's avatar opens it too", (
    tester,
  ) async {
    await pumpChat(tester, await chatWithMessage(tester));

    // Bob has no avatar set, so the tile falls back to his initials.
    await tester.tap(find.text('BO').first);
    await tester.pumpAndSettle();

    expect(find.text(strings.memberStatusLabel), findsOneWidget);
  });
}
