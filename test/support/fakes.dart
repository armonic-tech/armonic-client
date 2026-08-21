import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:armonic_client/api/http_api.dart';
import 'package:armonic_client/api/ws_client.dart';
import 'package:armonic_client/models/models.dart';
import 'package:armonic_client/state/session.dart';

/// In-memory [SignalingSocket]: records every frame the session sends and
/// lets the test emit server frames. Replies auth-ok to the auth frame.
class FakeSocket implements SignalingSocket {
  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  final sent = <Map<String, dynamic>>[];
  bool _closed = false;
  final String userId;

  final String? authError;

  FakeSocket({this.userId = 'me', this.authError});

  @override
  Stream<Map<String, dynamic>> get messages => _controller.stream;

  @override
  bool get isClosed => _closed;

  @override
  void send(Map<String, dynamic> message) {
    sent.add(message);
    if (message['type'] == 'auth') {
      emit(authError != null
          ? {'type': 'error', 'message': authError}
          : {'type': 'auth-ok', 'userId': userId, 'displayName': 'Yo'});
    }
  }

  void emit(Map<String, dynamic> frame) => _controller.add(frame);

  Map<String, dynamic>? lastOfType(String type) =>
      sent.where((m) => m['type'] == type).lastOrNull;

  @override
  Future<void> close() async {
    _closed = true;
    await _controller.close();
  }
}

/// Mutable backend state served over a MockClient: one instance whose
/// servers/channels/presence the test can rewrite mid-flight.
class FakeBackend {
  final List<Map<String, dynamic>> servers;
  final Map<String, List<Map<String, dynamic>>> channelsByServer;
  final Map<String, List<Map<String, dynamic>>> connectedByChannel;

  FakeBackend({
    required this.servers,
    required this.channelsByServer,
    Map<String, List<Map<String, dynamic>>>? connectedByChannel,
  }) : connectedByChannel = connectedByChannel ?? {};

  http.Client client() => MockClient((request) async {
        final path = request.url.path;
        if (path == '/server') {
          return http.Response(jsonEncode(servers), 200);
        }
        final serverMatch = RegExp(r'^/server/([^/]+)$').firstMatch(path);
        if (serverMatch != null) {
          final channels = channelsByServer[serverMatch.group(1)] ?? [];
          if (channels.isEmpty) return http.Response('not found', 404);
          return http.Response(jsonEncode(channels), 200);
        }
        if (path.endsWith('/messages')) {
          return http.Response(jsonEncode([]), 200);
        }
        final channelMatch = RegExp(r'^/channel/([^/]+)$').firstMatch(path);
        if (channelMatch != null) {
          final id = channelMatch.group(1)!;
          final channel = channelsByServer.values
              .expand((list) => list)
              .where((c) => c['id'] == id)
              .firstOrNull;
          if (channel == null) return http.Response('not found', 404);
          final connected = connectedByChannel[id] ?? [];
          return http.Response(
              jsonEncode({
                ...channel,
                'connected': connected,
                'connectedCount': connected.length,
              }),
              200);
        }
        return http.Response('unexpected: $path', 500);
      });
}

/// One server ("s1") with a text and a voice channel; "u2" (Bob) is sitting
/// in the voice channel.
FakeBackend defaultBackend({String ownerId = 'me'}) => FakeBackend(
      servers: [
        {'id': 's1', 'name': 'Test', 'ownerId': ownerId},
      ],
      channelsByServer: {
        's1': [
          {'id': 'c-text', 'serverId': 's1', 'name': 'general', 'type': 'text'},
          {'id': 'c-voice', 'serverId': 's1', 'name': 'General', 'type': 'voice'},
        ],
      },
      connectedByChannel: {
        'c-voice': [
          {'id': 'u2', 'displayName': 'Bob'},
        ],
      },
    );

/// Fully connected session against [backend] and [socket] (auth handshake
/// done, servers/channels loaded).
Future<InstanceSession> connectedSession(
    FakeBackend backend, FakeSocket socket) async {
  final session = InstanceSession(
    StoredInstance(baseUrl: 'http://test', token: 'jwt'),
    api: ArmonicHttpApi('http://test', client: backend.client()),
    connectSocket: (_) async => socket,
  );
  await session.connect();
  // Drain the fire-and-forget loads (history, presence poll) so nothing
  // notifies after the test disposes the session.
  await drainEvents();
  return session;
}

/// Let queued async work (unawaited futures, stream deliveries) settle.
Future<void> drainEvents([int rounds = 20]) async {
  for (var i = 0; i < rounds; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
