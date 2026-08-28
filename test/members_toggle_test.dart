import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:armonic_client/l10n/app_strings.dart';
import 'package:armonic_client/screens/server_screen.dart';
import 'package:armonic_client/state/session_manager.dart';
import 'package:armonic_client/widgets/members_panel.dart';

import 'support/fakes.dart';

void main() {
  Future<void> pumpScreen(WidgetTester tester) async {
    // Wide enough that the roster column is allowed to show at all.
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final session = (await tester
        .runAsync(() => connectedSession(defaultBackend(), FakeSocket())))!;
    addTearDown(session.dispose);

    final manager = SessionManager(onSessionExpired: (_) {});
    addTearDown(manager.dispose);

    await tester.pumpWidget(ChangeNotifierProvider<SessionManager>.value(
      value: manager,
      child: MaterialApp(home: ServerScreen(session: session)),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('the roster shows by default and the app bar button hides it',
      (tester) async {
    await pumpScreen(tester);

    expect(find.byType(MembersPanel), findsOneWidget);

    // Both the app bar and the panel's own X carry this tooltip; this is the
    // app bar one.
    await tester.tap(find.descendant(
      of: find.byType(AppBar),
      matching: find.byTooltip(strings.hideMembers),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(MembersPanel), findsNothing);

    await tester.tap(find.byTooltip(strings.showMembers));
    await tester.pumpAndSettle();
    expect(find.byType(MembersPanel), findsOneWidget);
  });

  testWidgets('the panel can also close itself', (tester) async {
    await pumpScreen(tester);

    // Two ways in reach: the app bar toggle and the panel's own X. The X is
    // the one that sits next to the thing being closed.
    await tester.tap(find.descendant(
      of: find.byType(MembersPanel),
      matching: find.byIcon(Icons.close),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(MembersPanel), findsNothing);
    expect(find.byTooltip(strings.showMembers), findsOneWidget);
  });

  testWidgets('the roster has no manual refresh to press', (tester) async {
    await pumpScreen(tester);

    expect(
      find.descendant(
        of: find.byType(MembersPanel),
        matching: find.byIcon(Icons.refresh),
      ),
      findsNothing,
      reason: 'the roster polls itself; a button would only be a chore',
    );
  });
}
