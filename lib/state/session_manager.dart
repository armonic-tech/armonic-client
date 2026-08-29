import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'session.dart';
import 'settings_store.dart';

/// Owns one live [InstanceSession] per instance the user has opened.
///
/// Sessions outlive the screen that shows them: picking another instance in
/// the rail only changes which one is on screen, so an open call (and the
/// socket carrying it) survives while you read another instance's channels.
/// Releasing one is explicit — [release] on removal, or a new token for the
/// same URL.
class SessionManager extends ChangeNotifier {
  /// Called when a session reports its stored JWT was rejected; the owner of
  /// the credential (the instance store) drops it.
  final void Function(String baseUrl) onSessionExpired;

  /// Injectable for tests, which can't open real sockets.
  final InstanceSession Function(StoredInstance instance)? createSession;

  final Map<String, InstanceSession> _sessions = {};
  InstanceSession? _voiceSession;
  String? _selectedUrl;
  bool _disposed = false;
  bool _notifyQueued = false;

  SessionManager({required this.onSessionExpired, this.createSession});

  /// The session currently in a voice channel, if any. At most one across all
  /// instances — [joinVoice] hangs up whatever call was already running.
  InstanceSession? get voiceSession => _voiceSession;

  /// Which instance the shell is showing. It lives here, not in the shell's
  /// State, so anything deep in the tree can move it — the call panel's "take
  /// me back to the call" being the reason it had to.
  String? get selectedUrl => _selectedUrl;

  void select(String baseUrl) {
    if (_selectedUrl == baseUrl) return;
    _selectedUrl = baseUrl;
    _notifySoon();
  }

  /// The live session for [baseUrl], or null if it was never opened. Unlike
  /// [sessionFor] this never creates one — it answers questions *about* an
  /// instance (does this user administer it?) without connecting to it.
  InstanceSession? peek(String baseUrl) => _sessions[baseUrl];

  /// The live session for [instance], created and connected on first ask.
  ///
  /// A different token for the same URL (a re-login after the JWT died) can
  /// never work on the cached session, so that one is dropped and replaced.
  InstanceSession sessionFor(StoredInstance instance) {
    final cached = _sessions[instance.baseUrl];
    if (cached != null && cached.instance.token == instance.token) {
      return cached;
    }
    if (cached != null) release(instance.baseUrl);

    final session =
        createSession?.call(instance) ??
        InstanceSession(
          instance,
          onSessionExpired: () => onSessionExpired(instance.baseUrl),
        );
    _sessions[instance.baseUrl] = session;
    session.addListener(_onSessionChanged);
    // connect() notifies synchronously and this is called from build(): the
    // microtask keeps that out of the frame that asked for the session. By
    // then the session may already be gone (released in the same frame), and
    // connecting a disposed one throws.
    scheduleMicrotask(() {
      if (identical(_sessions[instance.baseUrl], session)) session.connect();
    });
    return session;
  }

  /// Join [channel] on [session], ending any call on another instance first —
  /// two live calls would mean two open mics and one shared pair of ears.
  Future<void> joinVoice(
    InstanceSession session,
    ChannelInfo channel, {
    AudioPrefs audio = const AudioPrefs(),
  }) async {
    for (final other in _sessions.values) {
      if (!identical(other, session) && other.voiceChannel != null) {
        await other.leaveVoice();
      }
    }
    await session.joinVoice(channel, audio: audio);
  }

  /// Push changed audio settings into the call in progress, if any.
  Future<void> applyAudio(AudioPrefs audio) async =>
      _voiceSession?.voice?.applyAudio(audio);

  void release(String baseUrl) {
    final session = _sessions.remove(baseUrl);
    if (session == null) return;
    session.removeListener(_onSessionChanged);
    session.dispose();
    if (identical(session, _voiceSession)) {
      _voiceSession = null;
      _notifySoon();
    }
  }

  /// Sessions notify on every frame they receive; only a change of *which*
  /// one holds the call concerns the shell, the bar itself listens to the
  /// session for mute/member updates.
  void _onSessionChanged() {
    final current = _sessions.values
        .where((s) => s.voiceChannel != null)
        .firstOrNull;
    if (identical(current, _voiceSession)) return;
    _voiceSession = current;
    _notifySoon();
  }

  /// Every notification is deferred: [sessionFor] runs inside `build`, and
  /// marking listeners dirty mid-build is an error.
  void _notifySoon() {
    if (_notifyQueued || _disposed) return;
    _notifyQueued = true;
    scheduleMicrotask(() {
      _notifyQueued = false;
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    for (final session in _sessions.values) {
      session.removeListener(_onSessionChanged);
      session.dispose();
    }
    _sessions.clear();
    super.dispose();
  }
}
