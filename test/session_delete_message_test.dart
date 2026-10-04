import 'package:flutter_test/flutter_test.dart';

import 'package:armonic_client/l10n/app_strings.dart';
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

  test('the deleting admin gets a notice, other members do not', () async {
    session = await connectedSession(defaultBackend(), socket);
    final notices = <String>[];
    session!.notices.listen(notices.add);

    emitMessage('m1');
    emitMessage('m2');
    await pumpEventQueue();

    socket.emit({
      'type': 'message-deleted',
      'id': 'm1',
      'serverId': 's1',
      'channelId': 'c-text',
      'deletedBy': 'someone-else',
    });
    await pumpEventQueue();
    expect(notices, isEmpty);

    socket.emit({
      'type': 'message-deleted',
      'id': 'm2',
      'serverId': 's1',
      'channelId': 'c-text',
      'deletedBy': session!.userId,
    });
    await pumpEventQueue();
    expect(notices, [strings.messageDeleted]);
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

  test('message-ack swaps the local id so the delete matches a row', () async {
    session = await connectedSession(defaultBackend(), socket);
    session!.sendText('mi mensaje');
    await pumpEventQueue();

    final localId = socket.lastOfType('text-message')!['clientMsgId'] as String;
    expect(session!.messagesFor('c-text').single.id, localId);

    socket.emit({
      'type': 'message-ack',
      'clientMsgId': localId,
      'id': 'm-real',
      'serverId': 's1',
      'channelId': 'c-text',
      'createdAt': DateTime.now().toIso8601String(),
    });
    await pumpEventQueue();

    final sent = session!.messagesFor('c-text').single;
    expect(sent.id, 'm-real');
    expect(sent.pending, isFalse);

    session!.deleteMessage(sent);
    expect(socket.lastOfType('delete-message')!['messageId'], 'm-real');
  });

  test(
    'a message that never got its ack cannot be sent for deletion',
    () async {
      session = await connectedSession(defaultBackend(), socket);
      session!.sendText('sin ack');
      await pumpEventQueue();

      // An older backend that never acks: the fallback clears pending, but the
      // id is still the local one no row has.
      final local = session!
          .messagesFor('c-text')
          .single
          .copyWith(pending: false);
      expect(local.deletable, isFalse);
      session!.deleteMessage(local);

      expect(socket.lastOfType('delete-message'), isNull);
    },
  );

  test('"message not found" drops the bubble it names', () async {
    session = await connectedSession(defaultBackend(), socket);
    final errors = <String>[];
    session!.errors.listen(errors.add);
    emitMessage('m1');
    emitMessage('m2');
    await pumpEventQueue();

    session!.deleteMessage(session!.messagesFor('c-text').first);
    socket.emit({
      'type': 'error',
      'message': 'message not found',
      'messageId': 'm1',
      'channelId': 'c-text',
    });
    await pumpEventQueue();

    expect(session!.messagesFor('c-text').map((m) => m.id), ['m2']);
    expect(errors, ['message not found']);
  });

  test('a send rejection still drops the pending bubble', () async {
    session = await connectedSession(defaultBackend(), socket);
    session!.sendText('demasiado largo');
    await pumpEventQueue();

    socket.emit({'type': 'error', 'message': 'message content invalid'});
    await pumpEventQueue();

    expect(session!.messagesFor('c-text'), isEmpty);
  });
}
