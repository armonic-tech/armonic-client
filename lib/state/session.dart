import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/http_api.dart';
import '../api/ws_client.dart';
import '../l10n/app_strings.dart';
import '../media/attachment_crypto.dart';
import '../media/image_pipeline.dart';
import '../mls/client.dart';
import '../models/models.dart';
import '../util/errors.dart';
import '../voice/voice_session.dart';
import 'settings_store.dart';
import 'attachment_cache.dart';
import '../util/log.dart';

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

  /// End-to-end encryption for this instance: the device's keys and one
  /// MLS group per server. Null disables it (tests that only care about
  /// the clear-text protocol).
  late final MlsClient? mls;

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
    MlsClient? Function(ArmonicHttpApi api, String Function() token)? mlsFor,
    this.onSessionExpired,
    this.pollInterval = const Duration(seconds: 10),
  }) : _connectSocket = connectSocket ?? ArmonicSocket.connect {
    _api = api ?? ArmonicHttpApi(instance.baseUrl);
    attachments = AttachmentCache(_api, () => _token);
    mls = mlsFor != null
        ? mlsFor(_api, () => _token)
        : MlsClient(_api, () => _token, baseUrl: instance.baseUrl);
    mls?.onChanged = _onMlsChanged;
  }

  /// Whether messages to the selected server can be encrypted right now.
  E2eeStatus get e2eeStatus {
    final server = selectedServer;
    if (mls == null || server == null) return E2eeStatus.starting;
    return mls!.statusFor(server.id);
  }

  bool get canSendEncrypted => e2eeStatus == E2eeStatus.ready;

  /// A new epoch may have unlocked messages that arrived before we had its
  /// key (or before the group existed on this device): retry them.
  void _onMlsChanged() {
    if (_disposed) return;
    _retryLocked();
    _notify();
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

  /// Logo of the server on screen, if its owner set one.
  String? get serverLogoId => selectedServer?.logoId;

  /// Where the rail reads that logo from, as the backend spelled it. Null
  /// means this server has no logo — a fact, not "unknown": the rail paints
  /// initials on it, which is what makes a removal visible at once.
  String? get serverLogoThumbPath => selectedServer?.logoThumbPath;

  /// Whether the logged-in user owns (is admin of) the selected server.
  /// An unclaimed server sends no ownerId at all, so it stays false rather
  /// than matching two empty strings.
  bool get isOwner =>
      userId != null &&
      selectedServer?.ownerId != null &&
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
    Log.i('session', 'connecting to ${instance.baseUrl}');
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
      Log.i('session', 'connected to ${instance.baseUrl} as $userId');
      _notify();
    } catch (e) {
      status = SessionStatus.error;
      Log.w('session', 'connect to ${instance.baseUrl} failed', e);
      if (errorMessage == null) {
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
    Log.w(
      'session',
      'socket to ${instance.baseUrl} closed '
          '(status ${status.name}, close ${_socket?.closeReason ?? 'unknown'}'
          '${voice != null ? ', was in voice' : ''})',
    );
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
      case 'message-ack':
        _onMessageAck(msg);
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
      case 'voice-link':
        _onVoiceLink(msg);
      case 'kicked-voice':
        final elsewhere = msg['reason'] == 'joined-elsewhere';
        Log.i('voice', 'call ended by server (${msg['reason'] ?? 'kicked'})');
        _reportNotice(
          elsewhere
              ? strings.voiceMovedToOtherDevice
              : strings.youWereKickedFromVoice,
        );
        leaveVoice();
      case 'joined-server':
        _onJoinedServer(msg);
      case 'user-kicked':
        _onUserKicked(msg);
      case 'server-updated':
        _applyServerLogo(
          msg['serverId'] as String?,
          msg['logoId'] as String?,
          msg['logoThumbUrl'] as String?,
        );
      case 'mls-commit':
        _onMlsCommit(msg);
      case 'mls-sync':
        final serverId = msg['serverId'] as String?;
        if (serverId != null) mls?.sync(serverId);
      default:
        Log.d('session', 'unhandled frame ${msg['type']}');
    }
  }

  void _onMlsCommit(Map<String, dynamic> msg) {
    final serverId = msg['serverId'] as String?;
    final epoch = (msg['epoch'] as num?)?.toInt();
    final payload = msg['payload'] as String?;
    if (serverId == null || epoch == null || payload == null) return;
    mls?.onCommitFrame(
      serverId,
      epoch,
      msg['senderDeviceId'] as String? ?? '',
      payload,
    );
  }

  Future<void> _startE2ee() async {
    final m = mls;
    final id = userId;
    if (m == null || id == null) return;
    await m.ensureDevice(id);
    for (final server in servers) {
      await m.sync(server.id);
    }
    _notify();
  }

  /// Decrypts an incoming or fetched message in place. Messages this
  /// device has no key for stay [ChatMessage.locked].
  Future<void> _decryptInto(String channelId, ChatMessage m) async {
    final client = mls;
    if (client == null || !m.encrypted || !m.locked) return;
    final body = await client.decryptBody(m.serverId, channelId, m.content);
    if (body == null || _disposed) return;
    final list = _messagesByChannel[channelId];
    final i = list?.indexWhere((x) => x.id == m.id) ?? -1;
    if (list == null || i == -1) return;
    list[i] = list[i].copyWith(
      content: body.text,
      locked: false,
      attachmentRef: body.attachment,
    );
    _notify();
  }

  void _retryLocked() {
    for (final entry in _messagesByChannel.entries) {
      for (final m in entry.value.where((m) => m.locked)) {
        _decryptInto(entry.key, m);
      }
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
    Log.w('session', 'server error frame: $text');
    if (text == 'could not join voice') voice?.markFailed();
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
      final botError = switch (text) {
        'bot offline' => strings.botOffline,
        'not a bot' => strings.notABot,
        'invalid channel' => strings.botInvalidChannel,
        _ => null,
      };
      if (botError != null) {
        _reportError(botError);
        return;
      }
      if (text == 'message not found') {
        _dropMissingMessage(msg);
      } else if (text != 'could not delete message' &&
          text != 'could not join voice') {
        _dropNewestPending();
      }
      _reportError(text);
    }
  }

  void _onTextMessage(Map<String, dynamic> msg) {
    final m = ChatMessage.fromJson(msg);
    (_messagesByChannel[m.channelId] ??= []).add(m);
    if (m.encrypted) _decryptInto(m.channelId, m);
    // Someone we have no roster entry for just spoke — they joined after our
    // last fetch, so pull the roster again rather than showing a raw id.
    if (m.userId.isNotEmpty && !_membersById.containsKey(m.userId)) {
      _loadMembers();
    }
    _notify();
  }

  /// The backend never echoes our own messages back, so an optimistic bubble
  /// carries a local id until this arrives with the persisted one. Without the
  /// swap, deleting a message sent in this session targets an id no row has.
  void _onMessageAck(Map<String, dynamic> msg) {
    final channelId = msg['channelId'] as String?;
    final localId = msg['clientMsgId'] as String?;
    final id = msg['id'] as String?;
    if (channelId == null || localId == null || id == null) return;
    final list = _messagesByChannel[channelId];
    if (list == null) return;
    final i = list.indexWhere((m) => m.id == localId);
    if (i == -1) return;
    list[i] = list[i].copyWith(id: id, pending: false);
    _notify();
  }

  void _onMessageDeleted(Map<String, dynamic> msg) {
    final channelId = msg['channelId'] as String?;
    final messageId = msg['id'] as String?;
    if (channelId == null || messageId == null) return;
    _messagesByChannel[channelId]?.removeWhere((m) => m.id == messageId);
    // The broadcast reaches every member, but only the admin who asked for the
    // deletion is waiting for an answer — for everyone else the message just
    // disappearing is the whole story.
    if (msg['deletedBy'] == userId) _reportNotice(strings.messageDeleted);
    _notify();
  }

  /// The server has no live row for a message we asked to delete: someone
  /// deleted it already and the `message-deleted` frame never reached us.
  /// Keeping the bubble would only invite another failed delete.
  void _dropMissingMessage(Map<String, dynamic> msg) {
    final channelId = msg['channelId'] as String?;
    final messageId = msg['messageId'] as String?;
    if (channelId == null || messageId == null) return;
    Log.w('session', 'message $messageId already gone server-side, dropping');
    _messagesByChannel[channelId]?.removeWhere((m) => m.id == messageId);
    _notify();
  }

  void deleteMessage(ChatMessage message) {
    if (!message.deletable) {
      Log.w('session', 'delete of ${message.id} skipped: no persisted id yet');
      return;
    }
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
    if (memberId == userId && voiceChannel?.id == channelId) {
      // The server dropped *our* presence while we still believe we are in
      // the call — its RTC watchdog firing, not a leave we asked for.
      Log.w('voice', 'server dropped our presence in $channelId');
      voice?.markFailed();
    }
    _voiceMembersByChannel[channelId]?.removeWhere((m) => m.id == memberId);
    if (voiceChannel?.id == channelId && memberId != userId) {
      voice?.dropRemoteFrom(memberId);
    }
    _notify();
  }

  /// A member's peer connection came up (or is still coming up, for someone
  /// who just joined) — the push that greys and un-greys names without
  /// waiting for the presence poll.
  void _onVoiceLink(Map<String, dynamic> msg) {
    final channelId = msg['channelId'] as String?;
    final memberId = msg['userId'] as String?;
    if (channelId == null || memberId == null) return;
    final list = _voiceMembersByChannel[channelId];
    final i = list?.indexWhere((m) => m.id == memberId) ?? -1;
    if (list == null || i == -1) {
      _refreshVoicePresence();
      return;
    }
    list[i] = list[i].copyWith(linked: msg['linked'] as bool? ?? false);
    _notify();
  }

  /// Why [member] of [channelId] cannot be heard yet, or null when nothing
  /// stands in the way — what greys a name in the voice lists.
  ///
  /// Ourselves: our own peer connection's stage. Someone else, seen from
  /// inside the call: their link must be up *and* their audio must have been
  /// relayed to us; either alone still means silence. Seen from outside the
  /// call: only their link. A server that predates link reporting sends no
  /// `linked`, and then nobody is greyed.
  String? voiceLinkIssue(String channelId, VoiceMember member) {
    final v = voice;
    final inThisCall = v != null && voiceChannel?.id == channelId;
    if (member.id == userId && inThisCall) {
      return v.stage == VoiceStage.connected ? null : voiceStageLabel(v.stage);
    }
    final linked = member.linked;
    if (linked == null) return null;
    if (!linked) return strings.voiceMemberConnecting;
    if (!inThisCall) return null;
    if (v.stage != VoiceStage.connected) return voiceStageLabel(v.stage);
    return v.audibleFrom.contains(member.id)
        ? null
        : strings.voiceMemberNotHeard;
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
    // An ApiException was already logged with its status by the HTTP layer;
    // anything else (a parse error on a 200, a TypeError) was not.
    if (e is! ApiException) Log.e('session', 'request handling failed', e);
    if (e is ApiException && e.statusCode == 401) {
      Log.w('session', 'token rejected by ${instance.baseUrl}, expiring');
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
    _startE2ee();
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

  /// An extra roster refresh on top of the regular poll, for a screen that
  /// needs to notice a new member sooner (the rotating invite QR).
  Future<void> refreshMembers() => _loadMembers(silent: true);

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
    for (final m in history.where((m) => m.encrypted)) {
      _decryptInto(channel.id, m);
    }
  }

  /// [content] may be empty when [attachmentId] is set — an image-only
  /// message is a normal thing to send, and the backend accepts it.
  ///
  /// When the group is ready the body goes out MLS-encrypted, with the
  /// attachment's keys ([attachmentRef]) inside it. When it is not, the
  /// message is refused rather than sent in the clear: a server that has
  /// an encrypted group must never see plaintext from a member that is
  /// merely still waiting for its keys.
  void sendText(
    String content, {
    String? attachmentId,
    EncryptedAttachmentRef? attachmentRef,
  }) {
    final server = selectedServer;
    final channel = selectedChannel;
    final hasAttachment = attachmentId != null && attachmentId.isNotEmpty;
    if (server == null || channel == null) return;
    if (content.isEmpty && !hasAttachment) return;
    final client = mls;
    switch (client?.statusFor(server.id)) {
      case E2eeStatus.ready:
        _sendEncrypted(server, channel, content, attachmentId, attachmentRef);
        return;
      case E2eeStatus.waitingForKeys:
        // The group exists but this device has no key for it. Refusing is
        // the point: falling back to plaintext would hand the server the
        // message the rest of the members are encrypting.
        _reportError(strings.e2eeNotReady);
        return;
      case E2eeStatus.starting:
      case null:
        break;
    }
    final clientMsgId =
        '${ChatMessage.localIdPrefix}${DateTime.now().microsecondsSinceEpoch}';
    _socket?.send({
      'type': 'text-message',
      'serverId': server.id,
      'channelId': channel.id,
      'content': content,
      if (hasAttachment) 'attachmentId': attachmentId,
      'clientMsgId': clientMsgId,
    });
    _appendOptimistic(clientMsgId, channel, server, content, attachmentId);
  }

  Future<void> _sendEncrypted(
    ServerInfo server,
    ChannelInfo channel,
    String content,
    String? attachmentId,
    EncryptedAttachmentRef? attachmentRef,
  ) async {
    final hasAttachment = attachmentId != null && attachmentId.isNotEmpty;
    final envelope = await mls!.encryptBody(
      server.id,
      channel.id,
      content,
      attachment: attachmentRef,
    );
    if (_disposed) return;
    if (envelope == null) {
      _reportError(strings.e2eeNotReady);
      return;
    }
    final clientMsgId =
        '${ChatMessage.localIdPrefix}${DateTime.now().microsecondsSinceEpoch}';
    _socket?.send({
      'type': 'text-message',
      'serverId': server.id,
      'channelId': channel.id,
      'content': envelope,
      'encrypted': true,
      if (hasAttachment) 'attachmentId': attachmentId,
      'clientMsgId': clientMsgId,
    });
    _appendOptimistic(
      clientMsgId,
      channel,
      server,
      content,
      attachmentId,
      encrypted: true,
      attachmentRef: attachmentRef,
    );
  }

  void _appendOptimistic(
    String clientMsgId,
    ChannelInfo channel,
    ServerInfo server,
    String content,
    String? attachmentId, {
    bool encrypted = false,
    EncryptedAttachmentRef? attachmentRef,
  }) {
    final hasAttachment = attachmentId != null && attachmentId.isNotEmpty;
    // No server echo for our own messages — append optimistically under the
    // local id, which `message-ack` swaps for the persisted one. The timer is
    // the fallback for an older backend that doesn't ack: after a grace period
    // without an "error" frame (rejections arrive immediately) we consider it
    // delivered; the id stays local, so it is not offered for deletion
    // ([ChatMessage.deletable]) until the channel is re-fetched.
    final local = ChatMessage(
      id: clientMsgId,
      channelId: channel.id,
      serverId: server.id,
      userId: userId ?? '',
      content: content,
      attachmentId: hasAttachment ? attachmentId : null,
      createdAt: DateTime.now(),
      pending: true,
      encrypted: encrypted,
      attachmentRef: attachmentRef,
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
  ///
  /// With encryption on, the image is sanitized and thumbnailed *here*
  /// (the server cannot see it), encrypted under a fresh key, and the two
  /// ciphertexts are uploaded; the key rides in [StagedAttachment.ref].
  Future<StagedAttachment> uploadImage(Uint8List bytes, String filename) async {
    final server = selectedServer;
    if (server == null) throw StateError(strings.pickTextChannel);
    if (mls != null && mls!.statusFor(server.id) != E2eeStatus.starting) {
      if (!canSendEncrypted) throw UploadFailure(strings.e2eeNotReady);
      final PreparedImage prepared;
      try {
        prepared = await prepareImage(bytes);
      } on ImageRejected catch (e) {
        Log.w('upload', 'image rejected locally: ${e.reason.name}');
        throw UploadFailure(imageRejectionMessage(e.reason));
      }
      final encrypted = await encryptAttachment(prepared);
      try {
        final att = await _api.uploadEncrypted(
          _token,
          server.id,
          encrypted.blob,
          encrypted.thumb,
        );
        // The preview needs the plaintext; seed the cache so no tile has to
        // download and decrypt what was just produced locally.
        attachments.seed(att.thumbUrl, prepared.thumb);
        attachments.seed(att.url, prepared.bytes);
        return StagedAttachment(att, ref: encrypted.ref);
      } catch (e) {
        if (e is ApiException && e.statusCode == 401) _onHttpError(e, '');
        throw UploadFailure(uploadErrorMessage(e));
      }
    }
    try {
      return StagedAttachment(
        await _api.uploadImage(_token, server.id, bytes, filename),
      );
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

  /// Uploads an image and points the server's logo at it. Owner only — the
  /// backend answers 403 for anyone else. Every connected member gets the
  /// `server-updated` push, so nobody has to refetch to see it.
  Future<void> setServerLogo(Uint8List bytes, String filename) async {
    final server = selectedServer;
    if (server == null) throw StateError('sin server');
    final ServerLogo uploaded;
    try {
      uploaded = await _api.uploadServerLogo(
        _token,
        server.id,
        bytes,
        filename,
      );
    } catch (e) {
      if (e is ApiException && e.statusCode == 401) {
        _onHttpError(e, '');
      }
      throw UploadFailure(uploadErrorMessage(e, featureMissingOn404: true));
    }
    // Applied locally as well as pushed: the `server-updated` broadcast
    // reaches us too, but a socket that happens to be down must not leave
    // the uploader looking at the old logo.
    _applyServerLogo(server.id, uploaded.logoId, uploaded.logoThumbPath);
  }

  /// Owner only: leaves the server with no logo, so every client falls back
  /// to its initials. The `server-updated` push carries no logoId, which is
  /// what makes the other members drop theirs too.
  Future<void> removeServerLogo() async {
    final server = selectedServer;
    if (server == null) throw StateError('sin server');
    try {
      await _api.deleteServerLogo(_token, server.id);
    } catch (e) {
      if (e is ApiException && e.statusCode == 401) {
        _onHttpError(e, '');
      }
      throw UploadFailure(uploadErrorMessage(e, featureMissingOn404: true));
    }
    _applyServerLogo(server.id, null, null);
  }

  void _applyServerLogo(String? serverId, String? logoId, String? thumbPath) {
    if (serverId == null) return;
    servers = [
      for (final s in servers)
        s.id == serverId ? s.withLogo(logoId, thumbPath) : s,
    ];
    if (selectedServer?.id == serverId) {
      selectedServer = selectedServer!.withLogo(logoId, thumbPath);
    }
    _notify();
  }

  /// Owner only — the backend answers 403 for a non-owner (ApiException).
  Future<String> createInvite({bool bot = false, bool multiUse = false}) async {
    final server = selectedServer;
    if (server == null) throw StateError('sin server');
    final created = await _api.createInvite(
      _token,
      server.id,
      bot: bot,
      multiUse: multiUse,
    );
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

  /// Owner-only: ask a bot member to join [channelId]. It is the only call
  /// that bot may join until dismissed or kicked; the bot shows up through
  /// the usual voice presence once it has joined.
  void summonBot(String channelId, String botUserId) {
    final server = selectedServer;
    if (server == null) return;
    _socket?.send({
      'type': 'summon-bot',
      'serverId': server.id,
      'channelId': channelId,
      'targetUserId': botUserId,
    });
  }

  /// The voice channel [userId] is in, from the presence this session polls.
  ChannelInfo? voiceChannelOf(String userId) {
    for (final channel in channels.where((c) => c.isVoice)) {
      if (voiceMembersFor(channel.id).any((m) => m.id == userId)) {
        return channel;
      }
    }
    return null;
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

  Future<void> joinVoice(
    ChannelInfo channel, {
    AudioPrefs audio = const AudioPrefs(),
  }) async {
    if (voiceChannel?.id == channel.id) return;
    await leaveVoice();
    final session = VoiceSession(
      sendAnswer: (sdp) => _socket?.send({'type': 'answer', 'sdp': sdp}),
      sendCandidate: (c) =>
          _socket?.send({'type': 'candidate', 'candidate': c}),
      onChanged: _notify,
      initialAudio: audio,
    );
    // On screen before the mic opens: a permission prompt can hold the join
    // here for as long as the user takes, and the banner should say so.
    voice = session;
    voiceChannel = channel;
    _notify();
    // Mic must be live before the first answer so its SDP carries our track.
    try {
      await session.start();
    } catch (e, st) {
      Log.w('voice', 'could not open the microphone', e, st);
      if (identical(voice, session)) {
        voice = null;
        voiceChannel = null;
        _notify();
      }
      await session.dispose();
      rethrow;
    }
    if (!identical(voice, session)) return; // left while the mic was opening
    Log.i('voice', 'join-voice ${channel.id}');
    _socket?.send({
      'type': 'join-voice',
      'serverId': channel.serverId,
      'channelId': channel.id,
    });
    session.joinSent();
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
    await Future.wait(
      voiceChannels.map((c) async {
        try {
          final detail = await _api.channelDetail(_token, c.id);
          _voiceMembersByChannel[c.id] = detail.connected;
          changed = true;
        } catch (_) {}
      }),
    );
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

/// An uploaded image waiting to be sent: the server's attachment row plus,
/// when it was encrypted, the reference the message body must carry.
class StagedAttachment {
  final Attachment attachment;
  final EncryptedAttachmentRef? ref;
  const StagedAttachment(this.attachment, {this.ref});

  String get id => attachment.id;
  int get width => ref?.width ?? attachment.width;
  int get height => ref?.height ?? attachment.height;
  String get thumbUrl => attachment.thumbUrl;
}

/// An upload the user should be told about, carrying a message already
/// translated by [uploadErrorMessage].
class UploadFailure implements Exception {
  final String message;
  const UploadFailure(this.message);

  @override
  String toString() => message;
}
