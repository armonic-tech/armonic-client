import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/http_api.dart';
import '../api/ws_client.dart';
import '../l10n/app_strings.dart';
import '../models/models.dart';
import '../util/errors.dart';
import '../voice/voice_session.dart';
import 'attachment_cache.dart';

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

  /// The caller's own avatar, from auth-ok and refreshed after an upload.
  String? avatarId;

  /// Bytes for every attachment this instance serves, behind its JWT.
  late final AttachmentCache attachments;

  /// The server roster, and the index the chat uses to turn a message's
  /// userId into a name and a picture.
  List<Member> members = [];
  Map<String, Member> _membersById = const {};

  /// The stored JWT was rejected, so reconnecting with it is pointless.
  /// Distinct from [status] == error, which covers transient failures too.
  bool sessionExpired = false;

  /// Fired once when [sessionExpired] flips, so the owner of the stored
  /// credential can drop it. The session itself never touches storage.
  final VoidCallback? onSessionExpired;

  List<ServerInfo> servers = [];

  bool serversLoaded = false;
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

  bool _disposed = false;

  /// How often voice presence and the roster are re-read. Injectable so tests
  /// do not have to wait out the real interval.
  final Duration pollInterval;

  InstanceSession(
    this.instance, {
    ArmonicHttpApi? api,
    Future<SignalingSocket> Function(String wsUrl)? connectSocket,
    this.onSessionExpired,
    this.pollInterval = const Duration(seconds: 10),
  }) : _connectSocket = connectSocket ?? ArmonicSocket.connect {
    _api = api ?? ArmonicHttpApi(instance.baseUrl);
    attachments = AttachmentCache(_api, () => _token);
  }

  /// The roster entry for a message author, or null while the roster is still
  /// loading or for someone who has since been removed.
  Member? memberFor(String userId) => _membersById[userId];

  /// What to show as a message's author: their display name when the roster
  /// knows them, an id prefix otherwise.
  String authorLabel(String userId) =>
      _membersById[userId]?.label ?? shortId(userId);

  String? avatarPathFor(String userId) => _membersById[userId]?.avatarPath;

  String? get myAvatarPath =>
      avatarId == null || avatarId!.isEmpty ? null : attachmentPath(avatarId!);

  /// Whether the logged-in user owns (is admin of) the selected server.
  /// An unclaimed server sends no ownerId at all, so it stays false rather
  /// than matching two empty strings.
  bool get isOwner =>
      userId != null && selectedServer?.ownerId != null &&
      selectedServer!.ownerId == userId;

  List<VoiceMember> voiceMembersFor(String channelId) =>
      _voiceMembersByChannel[channelId] ?? const [];

  /// Who is connected to the voice channel we're currently in.
  List<VoiceMember> get voiceMembers =>
      voiceChannel == null ? const [] : voiceMembersFor(voiceChannel!.id);

  String get _token => instance.token ?? '';

  /// Fire-and-forget work (a connect in flight, a history load, a presence
  /// poll, the send-ack timer) can land after the session was disposed — its
  /// lifetime belongs to SessionManager, not to the screen that started that
  /// work. Notifying a disposed ChangeNotifier throws, so every notification
  /// goes through here.
  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  /// Same reason as [_notify]: an HTTP read or a socket frame can land after
  /// dispose, and adding to a closed StreamController throws.
  void _reportError(String message) {
    if (_disposed) return;
    _errors.add(message);
  }

  void _reportNotice(String message) {
    if (_disposed) return;
    _notices.add(message);
  }

  List<ChatMessage> messagesFor(String channelId) =>
      _messagesByChannel[channelId] ?? const [];

  Future<void> connect() async {
    status = SessionStatus.connecting;
    errorMessage = null;
    errorHint = null;
    _notify();
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
      _notify();
    } catch (e) {
      status = SessionStatus.error;
      if (errorMessage == null) {
        debugPrint('session: connect to ${instance.baseUrl} failed: $e');
        errorMessage = e is TimeoutException
            ? strings.authTimeout
            : strings.instanceUnreachable;
        errorHint = strings.instanceUnreachableHint;
      }
      _notify();
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
    _notify();
  }

  void _handleMessage(Map<String, dynamic> msg) {
    switch (msg['type'] as String?) {
      case 'auth-ok':
        _onAuthOk(msg);
      case 'error':
        _onError(msg);
      case 'text-message':
        _onTextMessage(msg);
      case 'message-deleted':
        _onMessageDeleted(msg);
      case 'channel-created':
        _onChannelCreated(msg);
      case 'channel-deleted':
        _onChannelDeleted(msg);
      case 'offer':
        _onOffer(msg);
      case 'candidate':
        _onCandidate(msg);
      case 'voice-state':
        _onVoiceState(msg);
      case 'voice-leave':
        _onVoiceLeave(msg);
      case 'kicked-voice':
        _reportNotice(strings.youWereKickedFromVoice);
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
    final avatar = msg['avatarId'] as String?;
    avatarId = (avatar == null || avatar.isEmpty) ? null : avatar;
    _authCompleter?.complete();
    _authCompleter = null;
  }

  void _onError(Map<String, dynamic> msg) {
    final text = msg['message'] as String? ?? strings.unknownError;
    if (_authCompleter != null) {
      _authCompleter!.completeError(StateError(text));
      _authCompleter = null;
      final rejected = text == 'unauthorized' || text == 'auth failed';
      status = SessionStatus.error;
      errorMessage = rejected ? strings.sessionInvalid : text;
      if (rejected) _expireSession();
      _notify();
    } else if (_joinServerCompleter != null) {
      _joinServerCompleter!.completeError(StateError(text));
      _joinServerCompleter = null;
    } else {
      if (text != 'message not found' && text != 'could not delete message') {
        _dropNewestPending();
      }
      _reportError(text);
    }
  }

  void _onTextMessage(Map<String, dynamic> msg) {
    final m = ChatMessage.fromJson(msg);
    (_messagesByChannel[m.channelId] ??= []).add(m);
    // Someone we have no roster entry for just spoke — they joined after our
    // last fetch, so pull the roster again rather than showing a raw id.
    if (m.userId.isNotEmpty && !_membersById.containsKey(m.userId)) {
      _loadMembers();
    }
    _notify();
  }

  void _onMessageDeleted(Map<String, dynamic> msg) {
    final channelId = msg['channelId'] as String?;
    final messageId = msg['id'] as String?;
    if (channelId == null || messageId == null) return;
    _messagesByChannel[channelId]?.removeWhere((m) => m.id == messageId);
    _notify();
  }

  void deleteMessage(ChatMessage message) {
    if (message.pending) return;
    _socket?.send({
      'type': 'delete-message',
      'serverId': message.serverId,
      'channelId': message.channelId,
      'messageId': message.id,
    });
  }

  void createChannel(String name, String type) {
    final server = selectedServer;
    if (server == null) return;
    _socket?.send({
      'type': 'create-channel',
      'serverId': server.id,
      'name': name,
      'channelType': type,
    });
  }

  void deleteChannel(ChannelInfo channel) {
    _socket?.send({
      'type': 'delete-channel',
      'serverId': channel.serverId,
      'channelId': channel.id,
    });
  }

  void _onChannelCreated(Map<String, dynamic> msg) {
    final raw = msg['channel'];
    if (raw is! Map) return;
    final channel = ChannelInfo.fromJson(Map<String, dynamic>.from(raw));
    if (channel.serverId != selectedServer?.id) return;
    if (channels.any((c) => c.id == channel.id)) return;
    channels = [...channels, channel];
    if (channel.isVoice) _startPresencePolling();
    _notify();
  }


  void _onChannelDeleted(Map<String, dynamic> msg) {
    final channelId = msg['channelId'] as String?;
    if (channelId == null || msg['serverId'] != selectedServer?.id) return;

    if (voiceChannel?.id == channelId) {
      voice?.dispose();
      voice = null;
      voiceChannel = null;
    }
    channels = channels.where((c) => c.id != channelId).toList();
    _messagesByChannel.remove(channelId);
    _historyLoaded.remove(channelId);
    _voiceMembersByChannel.remove(channelId);
    if (selectedChannel?.id == channelId) {
      selectedChannel = null;
      final firstText = channels.where((c) => c.isText).firstOrNull;
      if (firstText != null) {
        selectChannel(firstText);
        return; // selectChannel notifies
      }
    }
    _notify();
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
    _notify();
  }

  /// A member of a voice channel hung up (or their RTC died and the server's
  /// watchdog dropped them) — remove them from the presence list right away.
  void _onVoiceLeave(Map<String, dynamic> msg) {
    final channelId = msg['channelId'] as String?;
    final memberId = msg['userId'] as String?;
    if (channelId == null || memberId == null) return;
    _voiceMembersByChannel[channelId]?.removeWhere((m) => m.id == memberId);
    _notify();
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
    _notify();
  }

  void _expireSession() {
    if (sessionExpired) return;
    sessionExpired = true;
    onSessionExpired?.call();
  }

  /// An expired/invalid JWT invalidates the whole session; anything else is
  /// a transient failure surfaced as a snackbar-style error.
  void _onHttpError(Object e, String fallback) {
    if (e is ApiException && e.statusCode == 401) {
      status = SessionStatus.error;
      errorMessage = strings.sessionInvalid;
      _expireSession();
      _notify();
    } else {
      _reportError(fallback);
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
    serversLoaded = true;
    if (selectedServer == null && servers.length == 1) {
      await selectServer(servers.first);
    } else {
      _notify();
    }
  }

  Future<void> selectServer(ServerInfo server) async {
    selectedServer = server;
    channels = [];
    selectedChannel = null;
    members = [];
    _membersById = const {};
    _voiceMembersByChannel.clear();
    _notify();

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
      _notify();
    }
    _startPresencePolling();
    _loadMembers();
  }

  /// The roster is what turns a message's userId into a name and an avatar,
  /// so a failure degrades the chat rather than breaking it: ids stay visible
  /// and the error is surfaced without tearing the session down.
  Future<void> _loadMembers({bool silent = false}) async {
    final server = selectedServer;
    if (server == null) return;
    final List<Member> loaded;
    try {
      loaded = await _api.serverMembers(_token, server.id);
    } catch (e) {
      // The polled refresh must not toast on every flaky tick; only the load
      // the user is actually waiting for reports failure.
      if (!silent) _onHttpError(e, strings.couldNotLoadMembers(e));
      return;
    }
    if (selectedServer?.id != server.id) return; // switched meanwhile
    members = loaded;
    _membersById = {for (final m in loaded) m.id: m};
    _notify();
  }



  void selectChannel(ChannelInfo channel) {
    if (!channel.isText) return;
    selectedChannel = channel;
    _notify();
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
    _notify();
  }

  /// [content] may be empty when [attachmentId] is set — an image-only
  /// message is a normal thing to send, and the backend accepts it.
  void sendText(String content, {String? attachmentId}) {
    final server = selectedServer;
    final channel = selectedChannel;
    final hasAttachment = attachmentId != null && attachmentId.isNotEmpty;
    if (server == null || channel == null) return;
    if (content.isEmpty && !hasAttachment) return;
    _socket?.send({
      'type': 'text-message',
      'serverId': server.id,
      'channelId': channel.id,
      'content': content,
      if (hasAttachment) 'attachmentId': attachmentId,
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
      attachmentId: hasAttachment ? attachmentId : null,
      createdAt: DateTime.now(),
      pending: true,
    );
    (_messagesByChannel[channel.id] ??= []).add(local);
    _notify();
    Timer(const Duration(seconds: 2), () => _markSent(channel.id, local.id));
  }

  void _markSent(String channelId, String localId) {
    final list = _messagesByChannel[channelId];
    if (list == null) return;
    final i = list.indexWhere((m) => m.id == localId);
    if (i == -1 || !list[i].pending) return;
    list[i] = list[i].copyWith(pending: false);
    _notify();
  }

  /// The server rejected something right after we sent a message — drop the
  /// newest optimistic echo instead of leaving a ghost "sending" bubble.
  void _dropNewestPending() {
    final list = _messagesByChannel[selectedChannel?.id];
    if (list == null) return;
    final i = list.lastIndexWhere((m) => m.pending);
    if (i == -1) return;
    list.removeAt(i);
    _notify();
  }

  /// Uploads an image to the selected server and returns the attachment to
  /// hand to [sendText]. Throws a message already fit to show the user.
  Future<Attachment> uploadImage(Uint8List bytes, String filename) async {
    final server = selectedServer;
    if (server == null) throw StateError(strings.pickTextChannel);
    try {
      return await _api.uploadImage(_token, server.id, bytes, filename);
    } catch (e) {
      if (e is ApiException && e.statusCode == 401) {
        _onHttpError(e, '');
      }
      throw UploadFailure(uploadErrorMessage(e));
    }
  }

  /// Uploads an image and points the caller's avatar at it. The change is
  /// visible to sessions that connect afterwards; ours updates locally.
  Future<void> setAvatar(Uint8List bytes, String filename) async {
    final Attachment uploaded;
    try {
      uploaded = await _api.uploadAvatar(_token, bytes, filename);
    } catch (e) {
      if (e is ApiException && e.statusCode == 401) {
        _onHttpError(e, '');
      }
      throw UploadFailure(uploadErrorMessage(e));
    }
    avatarId = uploaded.id;
    // Our own roster entry still carries the old avatar until it is refetched.
    await _loadMembers();
    _notify();
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
    await _loadMembers();
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
    _notify();
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
    _reportNotice(strings.userKickedFromServer);
    _loadMembers();
    _notify();
  }

  Future<void> joinVoice(ChannelInfo channel) async {
    if (voiceChannel?.id == channel.id) return;
    await leaveVoice();
    final session = VoiceSession(
      sendAnswer: (sdp) => _socket?.send({'type': 'answer', 'sdp': sdp}),
      sendCandidate: (c) => _socket?.send({'type': 'candidate', 'candidate': c}),
      onChanged: _notify,
    );
    // Mic must be live before the first answer so its SDP carries our track.
    await session.start();
    voice = session;
    voiceChannel = channel;
    _notify();
    _socket?.send({
      'type': 'join-voice',
      'serverId': channel.serverId,
      'channelId': channel.id,
    });
    _refreshVoicePresence();
  }

  /// Neither voice presence nor the roster has a WS push covering every
  /// change (who is in a channel we're not in, who came online, who changed
  /// their picture), so both are polled while a server is on screen. This is
  /// what keeps the roster current without a refresh button for the user to
  /// remember to press.
  void _startPresencePolling() {
    _presenceTimer?.cancel();
    if (selectedServer == null) return;
    _presenceTimer = Timer.periodic(pollInterval, (_) {
      _refreshVoicePresence();
      _loadMembers(silent: true);
    });
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
    if (changed) _notify();
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
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _presenceTimer?.cancel();
    voice?.dispose();
    _sub?.cancel();
    _socket?.close();
    _errors.close();
    _notices.close();
    super.dispose();
  }
}

/// An upload the user should be told about, carrying a message already
/// translated by [uploadErrorMessage].
class UploadFailure implements Exception {
  final String message;
  const UploadFailure(this.message);

  @override
  String toString() => message;
}
