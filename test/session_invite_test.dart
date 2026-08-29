import 'package:flutter_test/flutter_test.dart';

import 'package:armonic_client/api/http_api.dart';
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

  test(
    'inviteTokenFromUrl extracts the token; raw tokens pass through null',
    () {
      expect(inviteTokenFromUrl('http://host:4000?invite=abc123'), 'abc123');
      expect(inviteTokenFromUrl('host:4000/?invite=abc123'), 'abc123');
      expect(inviteTokenFromUrl('just-a-token'), isNull);
    },
  );

  test(
    'joinServerWithInvite redeems a link and selects the new server',
    () async {
      final backend = defaultBackend();
      session = await connectedSession(backend, socket);

      final future = session!.joinServerWithInvite(
        'http://host:4000?invite=tok-1',
      );
      await pumpEventQueue();

      expect(socket.lastOfType('join-server'), {
        'type': 'join-server',
        'inviteToken': 'tok-1',
      });

      // The backend adds the membership, marks the invite used (single-use)
      // and replies joined-server; the reloaded GET /server now includes s2.
      backend.servers.add({'id': 's2', 'name': 'Otro', 'ownerId': 'admin'});
      backend.channelsByServer['s2'] = [
        {'id': 'c2', 'serverId': 's2', 'name': 'general', 'type': 'text'},
      ];
      socket.emit({'type': 'joined-server', 'serverId': 's2', 'channels': []});
      await future;

      expect(session!.servers.map((s) => s.id), contains('s2'));
      expect(session!.selectedServer?.id, 's2');
    },
  );

  test('a raw token (no URL) is sent as-is', () async {
    session = await connectedSession(defaultBackend(), socket);
    final future = session!.joinServerWithInvite('tok-raw');
    await pumpEventQueue();
    expect(socket.lastOfType('join-server')?['inviteToken'], 'tok-raw');
    socket.emit({'type': 'joined-server', 'serverId': 's1', 'channels': []});
    await future;
  });

  test('an invalid/used invite rejects with the server message', () async {
    session = await connectedSession(defaultBackend(), socket);
    final future = session!.joinServerWithInvite('tok-used');
    await pumpEventQueue();

    socket.emit({'type': 'error', 'message': 'invalid invite'});

    await expectLater(
      future,
      throwsA(
        isA<StateError>().having((e) => e.message, 'message', 'invalid invite'),
      ),
    );
  });
}
