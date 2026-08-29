import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:armonic_client/l10n/app_strings.dart';
import 'package:armonic_client/screens/server_screen.dart';
import 'package:armonic_client/state/session.dart';
import 'package:armonic_client/widgets/attachment_image.dart';
import 'package:armonic_client/widgets/members_panel.dart';

import 'support/fakes.dart';

/// The smallest valid PNG, so Image.memory has something real to decode.
final pngBytes = Uint8List.fromList([
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
            body: SizedBox(width: 200, height: 600, child: MembersPanel()),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  test('selecting a server loads the roster and indexes it by id', () async {
    final session = await connectedSession(defaultBackend(), FakeSocket());
    addTearDown(session.dispose);

    expect(session.members, hasLength(2));
    expect(session.authorLabel('u2'), 'Bob');
    expect(session.memberFor('me')!.isOwner, isTrue);
    expect(session.memberFor('u2')!.online, isFalse);
  });

  test('an unknown author falls back to an id prefix', () async {
    final session = await connectedSession(defaultBackend(), FakeSocket());
    addTearDown(session.dispose);

    expect(session.authorLabel('0123456789abcdef'), '01234567');
  });

  test('a message from someone not in the roster triggers a refetch', () async {
    final backend = defaultBackend();
    final socket = FakeSocket();
    final session = await connectedSession(backend, socket);
    addTearDown(session.dispose);

    // Someone joined after our last fetch.
    backend.membersByServer['s1'] = [
      ...backend.membersByServer['s1']!,
      {'id': 'u3', 'displayName': 'Carla', 'online': true},
    ];
    socket.emit({
      'type': 'text-message',
      'id': 'm1',
      'serverId': 's1',
      'channelId': 'c-text',
      'userId': 'u3',
      'content': 'hola',
      'createdAt': '2026-01-01T10:00:00Z',
    });
    await drainEvents();

    expect(session.authorLabel('u3'), 'Carla');
  });

  test('roster avatars become attachment paths', () async {
    final backend = defaultBackend();
    backend.membersByServer['s1'] = [
      {'id': 'u2', 'displayName': 'Bob', 'avatarId': 'att-b'},
      {'id': 'u4', 'displayName': 'Dana'},
    ];
    final session = await connectedSession(backend, FakeSocket());
    addTearDown(session.dispose);

    expect(session.avatarPathFor('u2'), '/attachment/att-b');
    // No avatar set means no URL is invented for it.
    expect(session.avatarPathFor('u4'), isNull);
  });

  testWidgets('the panel groups members by presence and badges the owner', (
    tester,
  ) async {
    await pumpPanel(tester, await liveSession(tester));

    expect(
      find.text('${strings.onlineLabel} — 1'.toUpperCase()),
      findsOneWidget,
    );
    expect(
      find.text('${strings.offlineLabel} — 1'.toUpperCase()),
      findsOneWidget,
    );
    expect(find.text('Yo'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text(strings.ownerBadge), findsOneWidget);
  });

  testWidgets('a voice member shows their avatar, resolved via the roster', (
    tester,
  ) async {
    // The socket's copy of an avatar is read once at auth and never updated,
    // so the tile must read the roster instead or it shows initials forever
    // after someone changes their picture.
    final backend = defaultBackend();
    backend.membersByServer['s1'] = [
      {'id': 'u2', 'displayName': 'Bob', 'avatarId': 'att-bob'},
    ];
    backend.connectedByChannel['c-voice'] = [
      {'id': 'u2', 'displayName': 'Bob'}, // no avatarId on the wire: stale
    ];
    backend.blobs['/attachment/att-bob'] = pngBytes;

    final session = await liveSession(tester, backend);
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider.value(
          value: session,
          child: Scaffold(
            body: VoiceMemberTile(
              member: session.voiceMembersFor('c-voice').single,
              isSelf: false,
              muted: false,
              deafened: false,
              avatarPath: session.avatarPathFor('u2'),
              attachments: session.attachments,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(session.avatarPathFor('u2'), '/attachment/att-bob');
    expect(find.byType(AttachmentImage), findsOneWidget);
  });

  testWidgets('a voice member with no avatar falls back to initials', (
    tester,
  ) async {
    final session = await liveSession(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider.value(
          value: session,
          child: Scaffold(
            body: VoiceMemberTile(
              member: session.voiceMembersFor('c-voice').single,
              isSelf: false,
              muted: false,
              deafened: false,
              avatarPath: session.avatarPathFor('u2'),
              attachments: session.attachments,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(AttachmentImage), findsNothing);
    expect(find.text('BO'), findsOneWidget);
  });

  testWidgets('an empty roster says so instead of showing nothing', (
    tester,
  ) async {
    final backend = defaultBackend();
    backend.membersByServer['s1'] = [];
    await pumpPanel(tester, await liveSession(tester, backend));

    expect(find.text(strings.noMembers), findsOneWidget);
  });
}
