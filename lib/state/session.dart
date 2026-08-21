import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/http_api.dart';
import '../api/ws_client.dart';
import '../l10n/app_strings.dart';
import '../models/models.dart';
import '../voice/voice_session.dart';

enum SessionStatus { connecting, connected, disconnected, error }

/// One live connection to an Armonic instance.
///
/// The WebSocket carries auth, chat broadcasts and WebRTC signaling; every
/// read (servers, channels, history, voice presence) and invite creation
/// goes over the HTTP API with the stored JWT.
class InstanceSession extends ChangeNotifier {
  final StoredInstance instance;

  late final ArmonicHttpApi _api;
  final Future<SignalingSocket> Function(String wsUrl) _connectSocket;

  SignalingSocket? _socket;
  StreamSubscription<Map<String, dynamic>>? _sub;
  Completer<void>? _authCompleter;
  Completer<String>? _joinServerCompleter;

  SessionStatus status = SessionStatus.connecting;
  String? errorMessage;
  String? errorHint;
  String? userId;
  String? displayName;

  List<ServerInfo> servers = [];
  ServerInfo? selectedServer;
  List<ChannelInfo> channels = [];
  ChannelInfo? selectedChannel;

  final Map<String, List<ChatMessage>> _messagesByChannel = {};
  final Set<String> _historyLoaded = {};

  final _errors = StreamController<String>.broadcast();
  Stream<String> get errors => _errors.stream;

  /// Non-error feedback (e.g. "user kicked") for the UI to toast.
  final _notices = StreamController<String>.broadcast();
  Stream<String> get notices => _notices.stream;

  VoiceSession? voice;
  ChannelInfo? voiceChannel;

  /// Live voice presence per channel id, polled from GET /channel/{id}.
  final Map<String, List<VoiceMember>> _voiceMembersByChannel = {};
  Timer? _presenceTimer;

  InstanceSession(
    this.instance, {
    ArmonicHttpApi? api,
    Future<SignalingSocket> Function(String wsUrl)? connectSocket,
  }) : _connectSocket = connectSocket ?? ArmonicSocket.connect {
    _api = api ?? ArmonicHttpApi(instance.baseUrl);
  }

  /// Whether the logged-in user owns (is admin of) the selected server.
  /// False while the backend doesn't expose ownerId on GET /server.
  bool get isOwner =>
      userId != null && selectedServer?.ownerId != null &&
      selectedServer!.ownerId == userId;

  List<VoiceMember> voiceMembersFor(String channelId) =>
      _voiceMembersByChannel[channelId] ?? const [];

  /// Who is connected to the voice channel we're currently in.
  List<VoiceMember> get voiceMembers =>
      voiceChannel == null ? const [] : voiceMembersFor(voiceChannel!.id);

  String get _token => instance.token ?? '';

  List<ChatMessage> messagesFor(String channelId) =>
      _messagesByChannel[channelId] ?? const [];

  Future<void> connect() async {
    status = SessionStatus.connecting;
    errorMessage = null;
    errorHint = null;
    notifyListeners();
    try {
      final socket = await _connectSocket(wsUrlFor(instance.baseUrl));
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
    } catch (e) {
      status = SessionStatus.error;
      if (errorMessage == null) {
        debugPrint('session: connect to ${instance.baseUrl} failed: $e');
        errorMessage = e is TimeoutException
            ? strings.authTimeout
            : strings.instanceUnreachable;
        errorHint = strings.instanceUnreachableHint;
      }
      notifyListeners();
      await _socket?.close();
      return;
    }
    await _loadServers();
  }

  void _onDisconnected() {
    if (status == SessionStatus.disconnected) return;
    _presenceTimer?.cancel();
    _presenceTimer = null;
    if (voice != null) {
      voice!.dispose();
      voice = null;
      voiceChannel = null;
    }
    if (status != SessionStatus.error) {
      status = SessionStatus.disconnected;
      errorMessage ??= strings.connectionLost;
      errorHint ??= strings.connectionLostHint;
    }
    _authCompleter?.completeError(StateError(strings.connectionClosed));
    _authCompleter = null;
    notifyListeners();
  }

  void _handleMessage(Map<String, dynamic> msg) {
    switch (msg['type'] as String?) {
      case 'auth-ok':
        _onAuthOk(msg);
      case 'error':
        _onError(msg);
      case 'text-message':
        _onTextMessage(msg);
      case 'offer':
        _onOffer(msg);
      case 'candidate':
        _onCandidate(msg);
      case 'voice-state':
        _onVoiceState(msg);
      case 'voice-leave':
        _onVoiceLeave(msg);
      case 'kicked-voice':
        _notices.add(strings.youWereKickedFromVoice);
        leaveVoice();
      case 'joined-server':
        _onJoinedServer(msg);
      case 'user-kicked':
        _onUserKicked(msg);
    }
  }

  void _onAuthOk(Map<String, dynamic> msg) {
    userId = msg['userId'] as String?;
    displayName = msg['displayName'] as String?;
    _authCompleter?.complete();
    _authCompleter = null;
  }

  void _onError(Map<String, dynamic> msg) {
    final text = msg['message'] as String? ?? strings.unknownError;
    if (_authCompleter != null) {
      _authCompleter!.completeError(StateError(text));
      _authCompleter = null;
      status = SessionStatus.error;
      errorMessage = switch (text) {
        'unauthorized' || 'auth failed' => strings.sessionInvalid,
        _ => text,
      };
      notifyListeners();
    } else if (_joinServerCompleter != null) {
      _joinServerCompleter!.completeError(StateError(text));
      _joinServerCompleter = null;
    } else {
      _dropNewestPending();
      _errors.add(text);
    }
  }

  void _onTextMessage(Map<String, dynamic> msg) {
    final m = ChatMessage.fromJson(msg);
    (_messagesByChannel[m.channelId] ??= []).add(m);
    notifyListeners();
  }

  void _onOffer(Map<String, dynamic> msg) {
    final sdp = msg['sdp'];
    if (voice != null && sdp is Map) {
      voice!.handleOffer(Map<String, dynamic>.from(sdp));
      // A renegotiation means someone joined/left the room: refresh presence.
      _refreshVoicePresence();
    }
  }

  void _onCandidate(Map<String, dynamic> msg) {
    final candidate = msg['candidate'];
    if (voice != null && candidate is Map) {
      voice!.handleCandidate(Map<String, dynamic>.from(candidate));
    }
  }

  /// Another member of our voice channel changed their mute/deafen state.
  void _onVoiceState(Map<String, dynamic> msg) {
    final channelId = msg['channelId'] as String?;
    final memberId = msg['userId'] as String?;
    if (channelId == null || memberId == null) return;
    final list = _voiceMembersByChannel[channelId];
    final i = list?.indexWhere((m) => m.id == memberId) ?? -1;
    if (list == null || i == -1) {
      // Someone we haven't polled yet — refetch the whole channel.
      _refreshVoicePresence();
      return;
    }
    list[i] = list[i].copyWith(
      muted: msg['muted'] as bool? ?? false,
      deafened: msg['deafened'] as bool? ?? false,
    );
    notifyListeners();
  }

  /// A member of a voice channel hung up (or their RTC died and the server's
  /// watchdog dropped them) — remove them from the presence list right away.
  void _onVoiceLeave(Map<String, dynamic> msg) {
    final channelId = msg['channelId'] as String?;
    final memberId = msg['userId'] as String?;
    if (channelId == null || memberId == null) return;
    _voiceMembersByChannel[channelId]?.removeWhere((m) => m.id == memberId);
    notifyListeners();
  }

  /// Local-first: VoiceSession cuts the audio immediately, then the server
  /// is told so the SFU stops routing our packets / packets to us.
  void toggleMute() {
    voice?.toggleMute();
    _sendVoiceState();
  }

  void toggleDeafen() {
    voice?.toggleDeafen();
    _sendVoiceState();
  }

  void _sendVoiceState() {
    final v = voice;
    final channel = voiceChannel;
    if (v == null || channel == null) return;
    _socket?.send({
      'type': 'voice-state',
      'muted': v.muted,
      'deafened': v.deafened,
    });
    // Mirror our own entry in the presence list without waiting for a poll
    // (the server never echoes voice-state back to its author).
    final list = _voiceMembersByChannel[channel.id];
    final i = list?.indexWhere((m) => m.id == userId) ?? -1;
    if (list != null && i != -1) {
      list[i] = list[i].copyWith(muted: v.muted, deafened: v.deafened);
    }
    notifyListeners();
  }

  /// An expired/invalid JWT invalidates the whole session; anything else is
  /// a transient failure surfaced as a snackbar-style error.
  void _onHttpError(Object e, String fallback) {
    if (e is ApiException && e.statusCode == 401) {
      status = SessionStatus.error;
      errorMessage = strings.sessionInvalid;
      notifyListeners();
    } else {
      _errors.add(fallback);
    }
  }

  Future<void> _loadServers() async {
    final List<ServerInfo> loaded;
    try {
      loaded = await _api.myServers(_token);
    } catch (e) {
      _onHttpError(e, strings.couldNotLoadServers(e));
      return;
    }
    servers = loaded;
    if (selectedServer == null && servers.length == 1) {
      await selectServer(servers.first);
    } else {
      notifyListeners();
    }
  }

  Future<void> selectServer(ServerInfo server) async {
    selectedServer = server;
    channels = [];
    selectedChannel = null;
    _voiceMembersByChannel.clear();
    notifyListeners();

    final List<ChannelInfo> loaded;
    try {
      loaded = await _api.serverChannels(_token, server.id);
    } catch (e) {
      _onHttpError(e, strings.couldNotLoadChannels(e));
      return;
    }
    if (selectedServer?.id != server.id) return; // switched meanwhile

    channels = loaded;
    final firstText = channels.where((c) => c.isText).firstOrNull;
    if (selectedChannel == null && firstText != null) {
      selectChannel(firstText);
    } else {
      notifyListeners();
    }
    _startPresencePolling();
  }

  void selectChannel(ChannelInfo channel) {
    if (!channel.isText) return;
    selectedChannel = channel;
    notifyListeners();
    if (!_historyLoaded.contains(channel.id)) {
      _loadHistory(channel);
    }
  }

  Future<void> _loadHistory(ChannelInfo channel) async {
    final List<ChatMessage> history;
    try {
      history = await _api.channelMessages(_token, channel.id);
    } catch (e) {
      _onHttpError(e, strings.couldNotLoadMessages(e));
      return;
    }

    // History comes newest first; broadcasts may already be in the list.
    final existing = _messagesByChannel[channel.id] ?? [];
    final known = existing.map((m) => m.id).toSet();
    _messagesByChannel[channel.id] = [
      ...history.reversed.where((m) => !known.contains(m.id)),
      ...existing,
    ];
    _historyLoaded.add(channel.id);
    notifyListeners();
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
    // No server echo for our own messages — append optimistically. The
    // backend never acks either, so after a grace period without an "error"
    // frame (rejections arrive immediately) we consider it delivered.
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
    Timer(const Duration(seconds: 2), () => _markSent(channel.id, local.id));
  }

  void _markSent(String channelId, String localId) {
    final list = _messagesByChannel[channelId];
    if (list == null) return;
    final i = list.indexWhere((m) => m.id == localId);
    if (i == -1 || !list[i].pending) return;
    list[i] = list[i].copyWith(pending: false);
    notifyListeners();
  }

  /// The server rejected something right after we sent a message — drop the
  /// newest optimistic echo instead of leaving a ghost "sending" bubble.
  void _dropNewestPending() {
    final list = _messagesByChannel[selectedChannel?.id];
    if (list == null) return;
    final i = list.lastIndexWhere((m) => m.pending);
    if (i == -1) return;
    list.removeAt(i);
    notifyListeners();
  }

  /// Owner only — the backend answers 403 for a non-owner (ApiException).
  Future<String> createInvite() async {
    final server = selectedServer;
    if (server == null) throw StateError('sin server');
    final created = await _api.createInvite(_token, server.id);
    return created.url;
  }

  /// Redeem an invite (full link or raw token) as this already-logged-in
  /// account, via the WS join-server message. The invite becomes single-use
  /// server-side (marked used on redemption). Throws on "invalid invite".
  Future<void> joinServerWithInvite(String linkOrToken) async {
    final token = inviteTokenFromUrl(linkOrToken) ?? linkOrToken.trim();
    if (token.isEmpty) throw StateError(strings.inviteInvalid);
    final completer = Completer<String>();
    _joinServerCompleter = completer;
    _socket?.send({'type': 'join-server', 'inviteToken': token});
    final String serverId;
    try {
      serverId = await completer.future.timeout(const Duration(seconds: 10));
    } finally {
      _joinServerCompleter = null;
    }
    await _loadServers();
    final joined = servers.where((s) => s.id == serverId).firstOrNull;
    if (joined != null) await selectServer(joined);
  }

  void _onJoinedServer(Map<String, dynamic> msg) {
    final serverId = msg['serverId'] as String?;
    if (serverId != null) _joinServerCompleter?.complete(serverId);
    _joinServerCompleter = null;
  }

  /// Owner-only moderation. The server enforces authz; a non-owner attempt
  /// comes back as an "error" frame ("unauthorized") on [errors].
  void kickFromVoice(String channelId, String targetUserId) {
    final server = selectedServer;
    if (server == null) return;
    _socket?.send({
      'type': 'kick-voice',
      'serverId': server.id,
      'channelId': channelId,
      'targetUserId': targetUserId,
    });
    // Optimistic: the 10s presence poll self-heals if the kick was rejected.
    _voiceMembersByChannel[channelId]?.removeWhere((m) => m.id == targetUserId);
    notifyListeners();
  }

  void kickFromServer(String targetUserId) {
    final server = selectedServer;
    if (server == null) return;
    _socket?.send({
      'type': 'kick-server',
      'serverId': server.id,
      'targetUserId': targetUserId,
    });
  }

  /// Server confirmation of kick-server: drop the target from every presence
  /// list we hold and toast the owner.
  void _onUserKicked(Map<String, dynamic> msg) {
    final targetId = msg['targetUserId'] as String?;
    if (targetId == null) return;
    for (final list in _voiceMembersByChannel.values) {
      list.removeWhere((m) => m.id == targetId);
    }
    _notices.add(strings.userKickedFromServer);
    notifyListeners();
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
    _refreshVoicePresence();
  }

  /// Presence has no WS push for channels we're not in, so poll it while
  /// there are voice channels in view.
  void _startPresencePolling() {
    _presenceTimer?.cancel();
    if (!channels.any((c) => c.isVoice)) return;
    _presenceTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _refreshVoicePresence(),
    );
    _refreshVoicePresence();
  }

  /// GET /channel/{id} exposes who is connected right now; presence is
  /// cosmetic, so failures are ignored silently.
  Future<void> _refreshVoicePresence() async {
    final voiceChannels = channels.where((c) => c.isVoice).toList();
    if (voiceChannels.isEmpty || status != SessionStatus.connected) return;
    var changed = false;
    await Future.wait(voiceChannels.map((c) async {
      try {
        final detail = await _api.channelDetail(_token, c.id);
        _voiceMembersByChannel[c.id] = detail.connected;
        changed = true;
      } catch (_) {}
    }));
    if (changed) notifyListeners();
  }

  Future<void> leaveVoice() async {
    final session = voice;
    final channel = voiceChannel;
    voice = null;
    voiceChannel = null;
    if (session == null) return;
    // Explicit leave-voice drops our presence server-side immediately; the
    // RTC watchdog and the WS disconnect are the server's fallbacks.
    _socket?.send({'type': 'leave-voice'});
    if (channel != null) {
      _voiceMembersByChannel[channel.id]?.removeWhere((m) => m.id == userId);
    }
    await session.dispose();
    notifyListeners();
  }

  @override
  void dispose() {
    _presenceTimer?.cancel();
    voice?.dispose();
    _sub?.cancel();
    _socket?.close();
    _errors.close();
    _notices.close();
    super.dispose();
  }
}
