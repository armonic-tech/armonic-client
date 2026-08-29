import 'package:flutter_test/flutter_test.dart';

import 'package:armonic_client/state/session.dart';

import 'support/fakes.dart';

void main() {
  late FakeSocket socket;
  InstanceSession? session;

  setUp(() => socket = FakeSocket());
  tearDown(() async {
    await drainEvents();
    session?.dispose();
  });

  group('isOwner', () {
    test('true when the logged-in user is the server owner', () async {
      session = await connectedSession(defaultBackend(ownerId: 'me'), socket);
      expect(session!.isOwner, isTrue);
    });

    test('false for a regular member', () async {
      session = await connectedSession(
        defaultBackend(ownerId: 'admin'),
        socket,
      );
      expect(session!.isOwner, isFalse);
    });

    test('false while the backend does not expose ownerId', () async {
      final backend = defaultBackend();
      backend.servers.first.remove('ownerId');
      session = await connectedSession(backend, socket);
      expect(session!.isOwner, isFalse);
    });
  });

  group('kick-voice', () {
    test('sends the frame and drops the member optimistically', () async {
      session = await connectedSession(defaultBackend(), socket);
      await pumpEventQueue(); // presence poll fills c-voice with u2
      expect(session!.voiceMembersFor('c-voice').map((m) => m.id), ['u2']);

      session!.kickFromVoice('c-voice', 'u2');

      expect(socket.lastOfType('kick-voice'), {
        'type': 'kick-voice',
        'serverId': 's1',
        'channelId': 'c-voice',
        'targetUserId': 'u2',
      });
      expect(session!.voiceMembersFor('c-voice'), isEmpty);
    });

    test(
      'a non-admin attempt rejected by the server surfaces the error',
      () async {
        session = await connectedSession(
          defaultBackend(ownerId: 'admin'),
          socket,
        );
        final errors = <String>[];
        session!.errors.listen(errors.add);

        // The UI hides the menu for non-owners, but the server is the actual
        // enforcement: a forged kick-voice comes back as an error frame.
        session!.kickFromVoice('c-voice', 'u2');
        socket.emit({'type': 'error', 'message': 'unauthorized'});
        await pumpEventQueue();

        expect(errors, ['unauthorized']);
      },
    );
  });

  group('kick-server', () {
    test(
      'sends the frame and user-kicked cleans presence + notifies',
      () async {
        session = await connectedSession(defaultBackend(), socket);
        await pumpEventQueue();
        final notices = <String>[];
        session!.notices.listen(notices.add);

        session!.kickFromServer('u2');
        expect(socket.lastOfType('kick-server'), {
          'type': 'kick-server',
          'serverId': 's1',
          'targetUserId': 'u2',
        });

        socket.emit({'type': 'user-kicked', 'targetUserId': 'u2'});
        await pumpEventQueue();

        expect(session!.voiceMembersFor('c-voice'), isEmpty);
        expect(notices, hasLength(1));
      },
    );
  });
}
