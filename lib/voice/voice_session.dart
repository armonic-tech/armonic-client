import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

class VoiceSession {
  final void Function(Map<String, dynamic> sdp) sendAnswer;
  final void Function(Map<String, dynamic> candidate) sendCandidate;
  final void Function() onChanged;

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  final List<RTCIceCandidate> _pendingCandidates = [];
  final Map<String, RTCVideoRenderer> _remoteRenderers = {};
  bool _remoteDescSet = false;
  bool _muted = false;
  bool _deafened = false;
  bool _disposed = false;

  Future<void> _offerChain = Future.value();

  VoiceSession({
    required this.sendAnswer,
    required this.sendCandidate,
    required this.onChanged,
  });

  /// Effective mic state: deafen implies mute (same invariant as the server).
  bool get muted => _muted || _deafened;
  bool get deafened => _deafened;
  List<RTCVideoRenderer> get remoteRenderers =>
      List.unmodifiable(_remoteRenderers.values);

  Future<void> start() async {
    _localStream = await navigator.mediaDevices
        .getUserMedia({'audio': true, 'video': false});
  }

  Future<RTCPeerConnection> _ensurePeerConnection() async {
    if (_pc != null) return _pc!;
    final pc = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
    });
    pc.onIceCandidate = (candidate) {
      final map = candidate.toMap() as Map;
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
      // Tracks arriving mid-deafen must start silenced too.
      for (final track in stream.getAudioTracks()) {
        track.enabled = !_deafened;
      }
      _remoteRenderers[stream.id] = renderer;
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
    } else {
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
    _disposed = true;
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
