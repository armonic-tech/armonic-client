import 'dart:typed_data';

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

  test('a server with no logo reports none', () async {
    session = await connectedSession(defaultBackend(), socket);
    expect(session!.serverLogoId, isNull);
  });

  test('the logoId of GET /server is kept', () async {
    final backend = defaultBackend();
    backend.servers.first['logoId'] = 'att-logo';
    session = await connectedSession(backend, socket);
    expect(session!.serverLogoId, 'att-logo');
  });

  // What makes the rail repaint for a member who did not upload anything:
  // the owner's POST is broadcast, nobody refetches.
  test('server-updated carries a new logo into the live state', () async {
    session = await connectedSession(defaultBackend(), socket);

    socket.emit({
      'type': 'server-updated',
      'serverId': 's1',
      'logoId': 'att-new',
      'logoUrl': '/server/s1/logo?v=att-new',
      'logoThumbUrl': '/server/s1/logo/thumb?v=att-new',
    });
    await drainEvents();

    expect(session!.serverLogoId, 'att-new');
    expect(session!.serverLogoThumbPath, '/server/s1/logo/thumb?v=att-new');
    expect(session!.servers.first.logoId, 'att-new');
  });

  test('the owner uploading a logo updates the live state', () async {
    final backend = defaultBackend(ownerId: 'me');
    session = await connectedSession(backend, socket);

    await session!.setServerLogo(Uint8List.fromList([1, 2, 3]), 'logo.png');

    expect(backend.uploadedPaths, contains('/server/s1/logo'));
    expect(session!.serverLogoId, 'att-logo-new');
    // The path the rail paints comes from the server, never composed here.
    expect(
      session!.serverLogoThumbPath,
      '/server/s1/logo/thumb?v=att-logo-new',
    );
  });

  test('the owner can leave the server with no logo', () async {
    final backend = defaultBackend(ownerId: 'me');
    backend.servers.first['logoId'] = 'att-logo';
    session = await connectedSession(backend, socket);

    await session!.removeServerLogo();

    expect(backend.deletedPaths, contains('/server/s1/logo'));
    expect(session!.serverLogoId, isNull);
  });

  // The removal push carries no logoId at all; a client already painting a
  // logo has to drop it on that alone.
  test('server-updated without a logoId clears the one we had', () async {
    final backend = defaultBackend();
    backend.servers.first['logoId'] = 'att-logo';
    session = await connectedSession(backend, socket);

    socket.emit({'type': 'server-updated', 'serverId': 's1'});
    await drainEvents();

    expect(session!.serverLogoId, isNull);
    expect(session!.serverLogoThumbPath, isNull);
    expect(session!.servers.first.logoId, isNull);
  });

  // What a client talking to an instance whose backend predates the logo
  // routes gets: the route 404s, which is not a problem with the image.
  test('an instance without the logo route says so instead of blaming the '
      'image', () async {
    final backend = defaultBackend(ownerId: 'me');
    backend.uploadStatus = 404;
    session = await connectedSession(backend, socket);

    await expectLater(
      session!.setServerLogo(Uint8List.fromList([1, 2, 3]), 'logo.png'),
      throwsA(
        isA<UploadFailure>().having(
          (e) => e.message,
          'message',
          strings.instanceTooOldForFeature,
        ),
      ),
    );
  });

  test('a frame for another server leaves ours alone', () async {
    final backend = defaultBackend();
    backend.servers.first['logoId'] = 'att-logo';
    session = await connectedSession(backend, socket);

    socket.emit({
      'type': 'server-updated',
      'serverId': 'other',
      'logoId': 'att-new',
    });
    await drainEvents();

    expect(session!.serverLogoId, 'att-logo');
  });
}
