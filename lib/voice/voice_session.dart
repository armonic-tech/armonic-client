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
      // Tracks arriving mid-deafen must start silenced too, and at whatever
      // gain the user last set rather than at full volume.
      for (final track in stream.getAudioTracks()) {
        track.enabled = !_deafened;
        _guard('setVolume', () => Helper.setVolume(_audio.volume, track));
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
