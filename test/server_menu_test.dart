import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:armonic_client/l10n/app_strings.dart';
import 'package:armonic_client/screens/server_screen.dart';
import 'package:armonic_client/state/session.dart';
import 'package:armonic_client/state/session_manager.dart';

import 'support/fakes.dart';

void main() {
  /// [connectedSession] does real I/O (fake socket frames, MockClient reads),
  /// which testWidgets' fake-async zone would never let complete.
  Future<InstanceSession> liveSession(WidgetTester tester,
      {String ownerId = 'me'}) async {
    final session = (await tester.runAsync(
        () => connectedSession(defaultBackend(ownerId: ownerId), FakeSocket())))!;
    addTearDown(session.dispose);
    return session;
  }

  Future<void> pumpScreen(WidgetTester tester, InstanceSession session) async {
    final manager = SessionManager(onSessionExpired: (_) {});
    addTearDown(manager.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<SessionManager>.value(
      value: manager,
      child: MaterialApp(home: ServerScreen(session: session)),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('the admin gets a menu on the server name, holding the invite',
      (tester) async {
    await pumpScreen(tester, await liveSession(tester));

    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pumpAndSettle();
    expect(find.text(strings.createInvite), findsOneWidget);
  });

  testWidgets('a plain member gets a plain name, no menu to open',
      (tester) async {
    await pumpScreen(
        tester, await liveSession(tester, ownerId: 'someone-else'));

    expect(find.byIcon(Icons.expand_more), findsNothing);
    // And the invite is nowhere else either — the sidebar entry is gone.
    expect(find.text(strings.createInvite), findsNothing);
  });
}
