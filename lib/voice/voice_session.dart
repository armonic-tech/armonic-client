import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../state/settings_store.dart';

class VoiceSession {
  final void Function(Map<String, dynamic> sdp) sendAnswer;
  final void Function(Map<String, dynamic> candidate) sendCandidate;
  final void Function() onChanged;

  /// Device choice and playback gain from Settings. Mutable: changing either
  /// mid-call has to reach the live tracks, not only the next call.
  AudioPrefs _audio;

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  final List<RTCIceCandidate> _pendingCandidates = [];
  final Map<String, RTCVideoRenderer> _remoteRenderers = {};
  bool _remoteDescSet = false;
  bool _muted = false;
  bool _deafened = false;
  bool _disposed = false;

  Timer? _statsTimer;
  int _lastBytesReceived = 0;
  int _lastBytesSent = 0;
  String? _lastPair;

  Future<void> _offerChain = Future.value();

  VoiceSession({
    required this.sendAnswer,
    required this.sendCandidate,
    required this.onChanged,
    AudioPrefs initialAudio = const AudioPrefs(),
  }) : _audio = initialAudio;

  AudioPrefs get audio => _audio;

  /// Effective mic state: deafen implies mute (same invariant as the server).
  bool get muted => _muted || _deafened;
  bool get deafened => _deafened;
  List<RTCVideoRenderer> get remoteRenderers =>
      List.unmodifiable(_remoteRenderers.values);

  Future<void> start() async {
    // The device is requested in the constraints rather than switched after
    // the fact: getUserMedia is the only point where the choice is guaranteed
    // to apply, and a stale id must not stop the mic from opening at all.
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': _audio.inputDeviceId.isEmpty
          ? true
          : {
              'deviceId': {'ideal': _audio.inputDeviceId},
            },
      'video': false,
    });
    await _applyOutputDevice();
  }

  /// Settings changed while this call is up.
  Future<void> applyAudio(AudioPrefs audio) async {
    final outputChanged = audio.outputDeviceId != _audio.outputDeviceId;
    final inputChanged = audio.inputDeviceId != _audio.inputDeviceId;
    _audio = audio;
    if (outputChanged) await _applyOutputDevice();
    if (inputChanged && _localStream != null) {
      // Only the capture device can be re-pointed live; the peer connection
      // keeps the same track, so no renegotiation is needed.
      await _guard('selectAudioInput', () async {
        if (audio.inputDeviceId.isNotEmpty) {
          await Helper.selectAudioInput(audio.inputDeviceId);
        }
      });
    }
    _applyVolume();
  }

  Future<void> _applyOutputDevice() async {
    if (_audio.outputDeviceId.isEmpty) return;
    await _guard(
      'selectAudioOutput',
      () => Helper.selectAudioOutput(_audio.outputDeviceId),
    );
  }

  void _applyVolume() {
    for (final renderer in _remoteRenderers.values) {
      for (final track in renderer.srcObject?.getAudioTracks() ?? const []) {
        _guard('setVolume', () => Helper.setVolume(_audio.volume, track));
      }
    }
  }

  /// Device routing is best-effort: several of these throw
  /// `UnimplementedError` on desktop/web, and a call must never die because
  /// the platform cannot honor a preference.
  Future<void> _guard(String what, Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      debugPrint('voice: $what unsupported here ($e)');
    }
  }

  /// The peer connection can die without a word on the socket, and the
  /// server's RTC watchdog drops voice presence on `disconnected` too — which
  /// is recoverable ICE churn, not a hangup. Every transition is logged so
  /// that "the user vanished from the channel" is diagnosable from stdout.
  void _log(String what) =>
      debugPrint('[voice ${DateTime.now().toIso8601String()}] $what');

  /// ICE reaching `connected` only proves a path was found, not that media is
  /// travelling it. These counters are what separate "RTP never arrives" (a
  /// network problem: wrong pair, MTU, firewall) from "RTP arrives but nobody
  /// hears it" (a playback problem: output device, gain, muted track) — the
  /// two need opposite fixes and look identical from the UI.
  Future<void> _logStats() async {
    final pc = _pc;
    if (pc == null || _disposed) return;
    try {
      final reports = await pc.getStats();

      var received = 0, sent = 0, lost = 0;
      final candidates = <String, Map<dynamic, dynamic>>{};
      final pairs = <String, Map<dynamic, dynamic>>{};
      String? selectedPairId;
      Map<dynamic, dynamic>? nominated;

      for (final r in reports) {
        final v = r.values;
        if (r.type == 'inbound-rtp') {
          received += _int(v['bytesReceived']);
          lost += _int(v['packetsLost']);
        } else if (r.type == 'outbound-rtp') {
          sent += _int(v['bytesSent']);
        } else if (r.type == 'candidate-pair') {
          pairs[r.id] = v;
          if (v['nominated'] == true) nominated = v;
        } else if (r.type == 'transport') {
          selectedPairId = v['selectedCandidatePairId'] as String?;
        } else if (r.type == 'local-candidate' ||
            r.type == 'remote-candidate') {
          candidates[r.id] = v;
        }
      }

      // Several pairs can sit in `succeeded`; only the one the transport points
      // at carries media, and reading any other reports zero traffic on a call
      // that is working.
      final pair = pairs[selectedPairId] ?? nominated;

      final rxDelta = received - _lastBytesReceived;
      final txDelta = sent - _lastBytesSent;
      _lastBytesReceived = received;
      _lastBytesSent = sent;

      final flow = rxDelta > 0
          ? 'audio in'
          : (_remoteRenderers.isEmpty ? 'no remote track yet' : 'NO RTP IN');
      _log(
        'stats: rx ${_kb(received)} (+${_kb(rxDelta)}/5s, $lost lost) '
        'tx ${_kb(sent)} (+${_kb(txDelta)}/5s) — $flow',
      );

      if (pair != null) {
        final desc =
            '${_endpoint(candidates[pair['localCandidateId']])} -> '
            '${_endpoint(candidates[pair['remoteCandidateId']])}';
        if (desc != _lastPair) {
          _lastPair = desc;
          _log('selected candidate pair: $desc');
        }
        // Transport-level bytes, which include STUN. Growing here while
        // inbound-rtp stays at zero means packets do arrive and something
        // above the transport drops them; flat here means nothing arrives.
        _log(
          'transport: rx ${_kb(_int(pair['bytesReceived']))} '
          'tx ${_kb(_int(pair['bytesSent']))}',
        );
      }
    } catch (e) {
      _log('getStats failed: $e');
    }
  }

  int _int(Object? v) => (v is num) ? v.toInt() : 0;

  String _kb(int bytes) => '${(bytes / 1024).toStringAsFixed(1)}KB';

  /// Which address actually carries the media — a pair over 10.8.0.x means it
  /// goes through the VPN, anything else means it does not.
  String _endpoint(Map<dynamic, dynamic>? c) {
    if (c == null) return '?';
    final addr = c['address'] ?? c['ip'] ?? '?';
    return '$addr:${c['port'] ?? '?'} (${c['candidateType'] ?? '?'})';
  }

  /// `typ <x>` is the 8th token of an ICE candidate line; a call with only
  /// `host` candidates dies the moment the two peers are not on one LAN.
  String _candidateType(String? candidate) {
    final parts = candidate?.split(' ') ?? const [];
    final i = parts.indexOf('typ');
    return (i != -1 && i + 1 < parts.length) ? parts[i + 1] : 'unknown';
  }

  Future<RTCPeerConnection> _ensurePeerConnection() async {
    if (_pc != null) return _pc!;
    final pc = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
    });
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _logStats(),
    );
    pc.onConnectionState = (state) => _log('peer-connection $state');
    pc.onIceConnectionState = (state) => _log('ice-connection $state');
    pc.onIceGatheringState = (state) => _log('ice-gathering $state');
    pc.onSignalingState = (state) => _log('signaling $state');
    pc.onIceCandidate = (candidate) {
      final map = candidate.toMap() as Map;
      _log('local candidate typ ${_candidateType(candidate.candidate)}');
      sendCandidate(Map<String, dynamic>.from(map));
    };
    pc.onTrack = (event) async {
      if (event.streams.isEmpty) return;
      final stream = event.streams.first;
      if (_remoteRenderers.containsKey(stream.id)) return;
      final renderer = RTCVideoRenderer();
      await renderer.initialize();
      renderer.srcObject = stream;
      if (_disposed) {
        renderer.dispose();
        return;
      }
      // Tracks arriving mid-deafen must start silenced too, and at whatever
      // gain the user last set rather than at full volume.
      for (final track in stream.getAudioTracks()) {
        track.enabled = !_deafened;
        _guard('setVolume', () => Helper.setVolume(_audio.volume, track));
      }
      _remoteRenderers[stream.id] = renderer;
      _log('remote track added, streams now ${_remoteRenderers.length}');
      onChanged();
    };
    _pc = pc;
    return pc;
  }

  Future<void> handleOffer(Map<String, dynamic> sdp) {
    _offerChain = _offerChain.then((_) => _answerOffer(sdp));
    return _offerChain;
  }

  Future<void> _answerOffer(Map<String, dynamic> sdp) async {
    if (_disposed) return;
    _log('offer received (renegotiation: $_remoteDescSet)');
    final pc = await _ensurePeerConnection();
    await pc.setRemoteDescription(
      RTCSessionDescription(sdp['sdp'] as String?, sdp['type'] as String?),
    );
    _remoteDescSet = true;
    for (final c in _pendingCandidates) {
      await pc.addCandidate(c);
    }
    _pendingCandidates.clear();

    if (_localStream != null &&
        (await pc.getSenders()).where((s) => s.track != null).isEmpty) {
      for (final track in _localStream!.getAudioTracks()) {
        track.enabled = !muted;
        await pc.addTrack(track, _localStream!);
      }
    }

    final answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    _log('answer sent');
    sendAnswer({'type': answer.type, 'sdp': answer.sdp});
  }

  Future<void> handleCandidate(Map<String, dynamic> candidate) async {
    final c = RTCIceCandidate(
      candidate['candidate'] as String?,
      candidate['sdpMid'] as String?,
      (candidate['sdpMLineIndex'] as num?)?.toInt(),
    );
    if (_pc == null || !_remoteDescSet) {
      _pendingCandidates.add(c);
      _log('remote candidate queued (${_pendingCandidates.length} pending)');
    } else {
      _log('remote candidate typ ${_candidateType(c.candidate)}');
      await _pc!.addCandidate(c);
    }
  }

  void toggleMute() {
    _muted = !_muted;
    _applyLocalAudio();
  }

  void toggleDeafen() {
    _deafened = !_deafened;
    _applyLocalAudio();
  }

  /// Local-first enforcement: zero the mic capture and the remote playback
  /// immediately, without waiting for the server to process voice-state.
  void _applyLocalAudio() {
    for (final track in _localStream?.getAudioTracks() ?? const []) {
      track.enabled = !muted;
    }
    for (final renderer in _remoteRenderers.values) {
      for (final track in renderer.srcObject?.getAudioTracks() ?? const []) {
        track.enabled = !_deafened;
      }
    }
    onChanged();
  }

  Future<void> dispose() async {
    _log('session disposed');
    _disposed = true;
    _statsTimer?.cancel();
    _statsTimer = null;
    for (final renderer in _remoteRenderers.values) {
      renderer.srcObject = null;
      await renderer.dispose();
    }
    _remoteRenderers.clear();
    for (final track in _localStream?.getTracks() ?? const []) {
      await track.stop();
    }
    await _localStream?.dispose();
    _localStream = null;
    await _pc?.close();
    _pc = null;
  }
}
