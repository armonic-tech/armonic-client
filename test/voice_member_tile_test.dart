import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:armonic_client/l10n/app_strings.dart';
import 'package:armonic_client/models/models.dart';
import 'package:armonic_client/screens/server_screen.dart';

void main() {
  final bob = VoiceMember(id: 'u2', displayName: 'Bob');

  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: Center(child: child)),
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

  testWidgets('right-click as admin opens the kick menu and fires the action', (
    tester,
  ) async {
    var kickedVoice = false;
    var kickedServer = false;
    await tester.pumpWidget(
      wrap(
        VoiceMemberTile(
          member: bob,
          isSelf: false,
          muted: false,
          deafened: false,
          onKickVoice: () => kickedVoice = true,
          onKickServer: () => kickedServer = true,
        ),
      ),
    );

    await rightClick(tester, find.byType(VoiceMemberTile));
    expect(find.text(strings.kickFromVoice), findsOneWidget);
    expect(find.text(strings.kickFromServer), findsOneWidget);

    await tester.tap(find.text(strings.kickFromVoice));
    await tester.pumpAndSettle();
    expect(kickedVoice, isTrue);
    expect(kickedServer, isFalse);
  });

  testWidgets('long-press also opens the menu (mobile)', (tester) async {
    await tester.pumpWidget(
      wrap(
        VoiceMemberTile(
          member: bob,
          isSelf: false,
          muted: false,
          deafened: false,
          onKickVoice: () {},
          onKickServer: () {},
        ),
      ),
    );

    await tester.longPress(find.byType(VoiceMemberTile));
    await tester.pumpAndSettle();
    expect(find.text(strings.kickFromServer), findsOneWidget);
  });

  testWidgets('no menu for a non-admin (callbacks null)', (tester) async {
    await tester.pumpWidget(
      wrap(
        VoiceMemberTile(
          member: bob,
          isSelf: false,
          muted: false,
          deafened: false,
        ),
      ),
    );

    await rightClick(tester, find.byType(VoiceMemberTile));
    expect(find.text(strings.kickFromVoice), findsNothing);
    expect(find.text(strings.kickFromServer), findsNothing);
  });
}
