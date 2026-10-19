import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:armonic_client/l10n/app_strings.dart';
import 'package:armonic_client/screens/mobile_shell.dart';
import 'package:armonic_client/screens/server_screen.dart';
import 'package:armonic_client/state/instance_store.dart';
import 'package:armonic_client/state/session.dart';
import 'package:armonic_client/state/session_manager.dart';
import 'package:armonic_client/widgets/call_bar.dart';
import 'package:armonic_client/widgets/members_sheet.dart';
import 'package:armonic_client/widgets/members_panel.dart';

import 'support/fakes.dart';

void main() {
  Future<InstanceSession> liveSession(
    WidgetTester tester, {
    String ownerId = 'me',
    Size size = const Size(400, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // Not torn down here: the shell hands it to a SessionManager, which
    // disposes it with itself.
    return (await tester.runAsync(
      () => connectedSession(defaultBackend(ownerId: ownerId), FakeSocket()),
    ))!;
  }

  Future<void> pumpShell(WidgetTester tester, InstanceSession session) async {
    final manager = SessionManager(
      onSessionExpired: (_) {},
      createSession: (_) => session,
    );
    addTearDown(manager.dispose);
    final store = InstanceStore();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SessionManager>.value(value: manager),
          ChangeNotifierProvider<InstanceStore>.value(value: store),
        ],
        child: MaterialApp(
          home: MobileShell(
            instances: [session.instance],
            selected: session.instance,
            onSelect: (_) {},
            onRemove: (_) {},
            onAdd: () {},
            membershipOf: (_) => Membership.member,
            canInvite: (_) => false,
            onCreateInvite: (_) {},
            onSignIn: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the phone layout shows the chat alone, channels in a drawer', (
    tester,
  ) async {
    final session = await liveSession(tester);
    await pumpShell(tester, session);

    // No columns: the roster panel is gone and the channel list is hidden.
    expect(find.byType(ChatPane), findsOneWidget);
    expect(find.byType(MembersPanel), findsNothing);
    expect(find.byType(MobileDrawer), findsNothing);
    // The app bar names the channel the chat is showing.
    expect(find.text('general'), findsOneWidget);

    await tester.tap(find.byTooltip(strings.openMenu));
    await tester.pumpAndSettle();

    expect(find.byType(MobileDrawer), findsOneWidget);
    expect(find.text(strings.textHeader), findsOneWidget);
    expect(find.text(strings.voiceHeader), findsOneWidget);
    // The voice channel lists who is in it.
    expect(find.text('Bob'), findsOneWidget);
  });

  testWidgets('the online counter opens the roster sheet', (tester) async {
    final session = await liveSession(tester);
    await pumpShell(tester, session);

    await tester.tap(find.byTooltip(strings.showMembers));
    await tester.pumpAndSettle();

    expect(find.byType(MembersSheet), findsOneWidget);
    expect(find.text(strings.membersTotal(2)), findsOneWidget);
    expect(find.text('Yo'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    // The admin gets the invite button, and nobody is in a call.
    expect(find.text(strings.inviteToInstance), findsOneWidget);
    expect(find.byType(CallBar), findsOneWidget);
    expect(find.byIcon(Icons.call_end), findsNothing);
  });

  // The smallest phone a guest at a demo might bring (iPhone SE, 1st gen):
  // any overflow below fails the test through FlutterError.
  testWidgets('a 320px phone fits the drawer, roster and invite QR', (
    tester,
  ) async {
    final backend = defaultBackend();
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final session = (await tester.runAsync(
      () => connectedSession(backend, FakeSocket()),
    ))!;
    await pumpShell(tester, session);

    await tester.tap(find.byTooltip(strings.openMenu));
    await tester.pumpAndSettle();
    expect(find.byType(MobileDrawer), findsOneWidget);
    await tester.tapAt(const Offset(315, 300));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip(strings.showMembers));
    await tester.pumpAndSettle();
    await tester.tap(find.text(strings.inviteToInstance));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.textContaining('invite=tok-qr-1'), findsOneWidget);

    expect(backend.lastInviteBody, isEmpty);
    await tester.tap(find.text(strings.copyAndClose));
    await tester.pumpAndSettle();

    // The presentation QR is one multi-use invite for the whole room.
    showPresentationQr(tester.element(find.byType(ChatPane)), session);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(backend.lastInviteBody, '{"multiUse":true}');
    expect(find.text(strings.inviteQrCaption), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);

    // Someone redeemed it: the roster poll counts them, the code stays.
    backend.membersByServer['s1']!.add({
      'id': 'guest',
      'displayName': 'Ana',
      'isOwner': false,
      'online': true,
    });
    await tester.pump(const Duration(seconds: 3));
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(find.text(strings.joinedViaQr(1)), findsOneWidget);
    expect(backend.invitesCreated, 2);
  });

  testWidgets('a plain member gets no invite button in the sheet', (
    tester,
  ) async {
    final session = await liveSession(tester, ownerId: 'u2');
    await pumpShell(tester, session);

    await tester.tap(find.byTooltip(strings.showMembers));
    await tester.pumpAndSettle();

    expect(find.byType(MembersSheet), findsOneWidget);
    expect(find.text(strings.inviteToInstance), findsNothing);
  });

  testWidgets('a wide window keeps the column layout', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final session = (await tester.runAsync(
      () => connectedSession(defaultBackend(), FakeSocket()),
    ))!;
    addTearDown(session.dispose);
    final manager = SessionManager(onSessionExpired: (_) {});
    addTearDown(manager.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<SessionManager>.value(
        value: manager,
        child: MaterialApp(home: ServerScreen(session: session)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MembersPanel), findsOneWidget);
    expect(find.byTooltip(strings.openMenu), findsNothing);
  });
}
