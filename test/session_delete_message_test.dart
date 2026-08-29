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

  void emitMessage(String id) => socket.emit({
    'type': 'text-message',
    'id': id,
    'serverId': 's1',
    'channelId': 'c-text',
    'userId': 'u2',
    'content': 'hola',
    'createdAt': DateTime.now().toIso8601String(),
  });

  test('deleteMessage sends the frame scoped to server + channel', () async {
    session = await connectedSession(defaultBackend(), socket);
    emitMessage('m1');
    await pumpEventQueue();

    session!.deleteMessage(session!.messagesFor('c-text').single);

    expect(socket.lastOfType('delete-message'), {
      'type': 'delete-message',
      'serverId': 's1',
      'channelId': 'c-text',
      'messageId': 'm1',
    });
  });

  test('nothing is removed until the server echoes message-deleted', () async {
    session = await connectedSession(defaultBackend(), socket);
    emitMessage('m1');
    await pumpEventQueue();

    session!.deleteMessage(session!.messagesFor('c-text').single);
    await pumpEventQueue();
    expect(session!.messagesFor('c-text'), hasLength(1));

    socket.emit({
      'type': 'message-deleted',
      'id': 'm1',
      'serverId': 's1',
      'channelId': 'c-text',
      'deletedBy': 'me',
    });
    await pumpEventQueue();

    expect(session!.messagesFor('c-text'), isEmpty);
  });

  test('message-deleted for another message leaves the list alone', () async {
    session = await connectedSession(defaultBackend(), socket);
    emitMessage('m1');
    await pumpEventQueue();

    socket.emit({
      'type': 'message-deleted',
      'id': 'other',
      'serverId': 's1',
      'channelId': 'c-text',
      'deletedBy': 'me',
    });
    await pumpEventQueue();

    expect(session!.messagesFor('c-text').single.id, 'm1');
  });

  test('a pending bubble is never sent for deletion', () async {
    session = await connectedSession(defaultBackend(), socket);
    session!.sendText('todavia viajando');
    await pumpEventQueue();

    final pending = session!.messagesFor('c-text').single;
    expect(pending.pending, isTrue);
    session!.deleteMessage(pending);

    expect(socket.lastOfType('delete-message'), isNull);
  });

  test(
    'a failed delete does not drop an unrelated in-flight message',
    () async {
      session = await connectedSession(defaultBackend(), socket);
      final errors = <String>[];
      session!.errors.listen(errors.add);

      session!.sendText('mi mensaje');
      await pumpEventQueue();
      expect(session!.messagesFor('c-text'), hasLength(1));

      socket.emit({'type': 'error', 'message': 'message not found'});
      await pumpEventQueue();

      expect(session!.messagesFor('c-text'), hasLength(1));
      expect(errors, ['message not found']);
    },
  );

  test('a send rejection still drops the pending bubble', () async {
    session = await connectedSession(defaultBackend(), socket);
    session!.sendText('demasiado largo');
    await pumpEventQueue();

    socket.emit({'type': 'error', 'message': 'message content invalid'});
    await pumpEventQueue();

    expect(session!.messagesFor('c-text'), isEmpty);
  });
}
