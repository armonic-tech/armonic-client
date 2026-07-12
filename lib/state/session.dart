import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../api/http_api.dart';
import '../api/ws_client.dart';
import '../models/models.dart';
import '../voice/voice_session.dart';

enum SessionStatus { connecting, connected, disconnected, error }

class InstanceSession extends ChangeNotifier {
  final StoredInstance instance;

  ArmonicSocket? _socket;
  StreamSubscription<Map<String, dynamic>>? _sub;
  Completer<void>? _authCompleter;

  SessionStatus status = SessionStatus.connecting;
  String? errorMessage;
  String? userId;
  String? displayName;

  List<ServerInfo> servers = [];
  ServerInfo? selectedServer;
  List<ChannelInfo> channels = [];
  ChannelInfo? selectedChannel;

  final Map<String, List<ChatMessage>> _messagesByChannel = {};

  final Queue<String> _pendingHistoryRequests = Queue();
  final Set<String> _historyLoaded = {};

  final _errors = StreamController<String>.broadcast();
  Stream<String> get errors => _errors.stream;

  Completer<String>? _invitePending;

  VoiceSession? voice;
  ChannelInfo? voiceChannel;

  InstanceSession(this.instance);

  List<ChatMessage> messagesFor(String channelId) =>
      _messagesByChannel[channelId] ?? const [];

  Future<void> connect() async {
    status = SessionStatus.connecting;
    errorMessage = null;
    notifyListeners();
    try {
      final socket = await ArmonicSocket.connect(wsUrlFor(instance.baseUrl));
      _socket = socket;
      _sub = socket.messages.listen(
        _handleMessage,
        onError: (_) => _onDisconnected(),
        onDone: _onDisconnected,
      );

      _authCompleter = Completer<void>();
      socket.send({
        'type': 'auth',
        'token': instance.token,
        if (instance.displayName != null && instance.displayName!.isNotEmpty)
          'name': instance.displayName,
      });
      await _authCompleter!.future.timeout(const Duration(seconds: 10));

      status = SessionStatus.connected;
      notifyListeners();
      socket.send({'type': 'get-servers'});
    } catch (e) {
      status = SessionStatus.error;
      errorMessage = e is TimeoutException
          ? 'El servidor no respondió al auth'
          : e.toString();
      notifyListeners();
      await _socket?.close();
    }
  }

  void _onDisconnected() {
    if (status == SessionStatus.disconnected) return;
    if (voice != null) {
      voice!.dispose();
      voice = null;
      voiceChannel = null;
    }
    if (status != SessionStatus.error) {
      status = SessionStatus.disconnected;
    }
    _authCompleter?.completeError(StateError('conexión cerrada'));
    _authCompleter = null;
    notifyListeners();
  }

  void _handleMessage(Map<String, dynamic> msg) {
    switch (msg['type'] as String?) {
      case 'auth-ok':
        userId = msg['userId'] as String?;
        displayName = msg['displayName'] as String?;
        _authCompleter?.complete();
        _authCompleter = null;
        break;

      case 'error':
        final text = msg['message'] as String? ?? 'error desconocido';
        if (_authCompleter != null) {
          _authCompleter!.completeError(StateError(text));
          _authCompleter = null;
          status = SessionStatus.error;
          errorMessage = text == 'unauthorized'
              ? 'Sesión inválida o vencida — volvé a iniciar sesión'
              : text;
          notifyListeners();
        } else if (_invitePending != null) {
          _invitePending!.completeError(StateError(text));
          _invitePending = null;
        } else {
          _errors.add(text);
        }
        break;

      case 'servers':
        servers = [
          for (final s in msg['servers'] as List? ?? const [])
            ServerInfo.fromJson(s as Map<String, dynamic>)
        ];

        if (selectedServer == null && servers.length == 1) {
          selectServer(servers.first);
        } else {
          notifyListeners();
        }
        break;

      case 'channels':
        if (msg['serverId'] != selectedServer?.id) break;
        channels = [
          for (final c in msg['channels'] as List? ?? const [])
            ChannelInfo.fromJson(c as Map<String, dynamic>)
        ];
        final firstText = channels.where((c) => c.isText).firstOrNull;
        if (selectedChannel == null && firstText != null) {
          selectChannel(firstText);
        } else {
          notifyListeners();
        }
        break;

      case 'messages':
        if (_pendingHistoryRequests.isEmpty) break;
        final channelId = _pendingHistoryRequests.removeFirst();
        final history = [
          for (final m in msg['messages'] as List? ?? const [])
            ChatMessage.fromJson(m as Map<String, dynamic>)
        ];

        final existing = _messagesByChannel[channelId] ?? [];
        final known = existing.map((m) => m.id).toSet();
        _messagesByChannel[channelId] = [
          ...history.reversed.where((m) => !known.contains(m.id)),
          ...existing,
        ];
        _historyLoaded.add(channelId);
        notifyListeners();
        break;

      case 'text-message':
        final m = ChatMessage.fromJson(msg);
        (_messagesByChannel[m.channelId] ??= []).add(m);
        notifyListeners();
        break;

      case 'invite-created':
        _invitePending?.complete(msg['url'] as String? ?? '');
        _invitePending = null;
        break;

      case 'offer':
        final sdp = msg['sdp'];
        if (voice != null && sdp is Map) {
          voice!.handleOffer(Map<String, dynamic>.from(sdp));
        }
        break;

      case 'candidate':
        final candidate = msg['candidate'];
        if (voice != null && candidate is Map) {
          voice!.handleCandidate(Map<String, dynamic>.from(candidate));
        }
        break;
    }
  }

  void selectServer(ServerInfo server) {
    selectedServer = server;
    channels = [];
    selectedChannel = null;
    notifyListeners();
    _socket?.send({'type': 'get-channels', 'serverId': server.id});
  }

  void selectChannel(ChannelInfo channel) {
    if (!channel.isText) return;
    selectedChannel = channel;
    notifyListeners();
    if (!_historyLoaded.contains(channel.id)) {
      _pendingHistoryRequests.add(channel.id);
      _socket?.send({
        'type': 'get-messages',
        'serverId': channel.serverId,
        'channelId': channel.id,
      });
    }
  }

  void sendText(String content) {
    final server = selectedServer;
    final channel = selectedChannel;
    if (server == null || channel == null || content.isEmpty) return;
    _socket?.send({
      'type': 'text-message',
      'serverId': server.id,
      'channelId': channel.id,
      'content': content,
    });
    // No server echo for our own messages — append optimistically.
    final local = ChatMessage(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      channelId: channel.id,
      serverId: server.id,
      userId: userId ?? '',
      content: content,
      createdAt: DateTime.now(),
      pending: true,
    );
    (_messagesByChannel[channel.id] ??= []).add(local);
    notifyListeners();
  }

  Future<String> createInvite() {
    final server = selectedServer;
    if (server == null) return Future.error(StateError('sin server'));
    _invitePending = Completer<String>();
    _socket?.send({'type': 'create-invite', 'serverId': server.id});
    return _invitePending!.future.timeout(const Duration(seconds: 10));
  }

  Future<void> joinVoice(ChannelInfo channel) async {
    if (voiceChannel?.id == channel.id) return;
    await leaveVoice();
    final session = VoiceSession(
      sendAnswer: (sdp) => _socket?.send({'type': 'answer', 'sdp': sdp}),
      sendCandidate: (c) => _socket?.send({'type': 'candidate', 'candidate': c}),
      onChanged: notifyListeners,
    );
    // Mic must be live before the first answer so its SDP carries our track.
    await session.start();
    voice = session;
    voiceChannel = channel;
    notifyListeners();
    _socket?.send({
      'type': 'join-voice',
      'serverId': channel.serverId,
      'channelId': channel.id,
    });
  }

  Future<void> leaveVoice() async {
    final session = voice;
    voice = null;
    voiceChannel = null;
    if (session != null) {
      await session.dispose();
      notifyListeners();
    }
  }

  @override
  void dispose() {
    voice?.dispose();
    _sub?.cancel();
    _socket?.close();
    _errors.close();
    super.dispose();
  }
}
