import 'package:flutter_test/flutter_test.dart';

import 'package:armonic_client/state/session.dart';

import 'support/fakes.dart';

/// The roster is polled rather than pushed, so it must keep itself current
/// without a refresh button for the user to remember to press.
void main() {
  test('the roster refreshes on its own while a server is on screen',
      () async {
    final backend = defaultBackend();
    final session = await connectedSession(backend, FakeSocket(),
        pollInterval: const Duration(milliseconds: 20));
    addTearDown(session.dispose);

    expect(session.members, hasLength(2));
    expect(session.avatarPathFor('u2'), isNull);

    // Someone joined and someone changed their picture, neither of which the
    // socket tells us about.
    backend.membersByServer['s1'] = [
      ...backend.membersByServer['s1']!,
      {'id': 'u3', 'displayName': 'Carla', 'online': true},
    ];
    backend.membersByServer['s1']![1] = {
      'id': 'u2',
      'displayName': 'Bob',
      'avatarId': 'att-new',
      'online': true,
    };

    await pumpPolling(session);

    expect(session.members, hasLength(3));
    expect(session.authorLabel('u3'), 'Carla');
    expect(session.avatarPathFor('u2'), '/attachment/att-new');
    expect(session.memberFor('u2')!.online, isTrue);
  });

  test('a server with no voice channels still polls its roster', () async {
    // Polling used to start only for voice presence; the roster needs it too.
    final backend = FakeBackend(
      servers: [
        {'id': 's1', 'name': 'Test', 'ownerId': 'me'},
      ],
      channelsByServer: {
        's1': [
          {'id': 'c-text', 'serverId': 's1', 'name': 'general', 'type': 'text'},
        ],
      },
      membersByServer: {
        's1': [
          {'id': 'me', 'displayName': 'Yo', 'online': true},
        ],
      },
    );
    final session = await connectedSession(backend, FakeSocket(),
        pollInterval: const Duration(milliseconds: 20));
    addTearDown(session.dispose);

    expect(session.members, hasLength(1));

    backend.membersByServer['s1'] = [
      ...backend.membersByServer['s1']!,
      {'id': 'u9', 'displayName': 'Nueva', 'online': true},
    ];
    await pumpPolling(session);

    expect(session.members, hasLength(2));
  });

  test('a failing poll leaves the last roster in place and stays quiet',
      () async {
    final backend = defaultBackend();
    final session = await connectedSession(backend, FakeSocket(),
        pollInterval: const Duration(milliseconds: 20));
    addTearDown(session.dispose);

    final errors = <String>[];
    session.errors.listen(errors.add);

    backend.membersFail = true;
    await pumpPolling(session);

    // Toasting on every flaky tick would be worse than showing slightly old
    // names, so the polled refresh fails silently.
    expect(session.members, hasLength(2));
    expect(errors, isEmpty);
  });
}

/// Waits out a poll tick of the shortened interval these tests inject.
Future<void> pumpPolling(InstanceSession session) async {
  await Future<void>.delayed(const Duration(milliseconds: 60));
  await drainEvents();
}
