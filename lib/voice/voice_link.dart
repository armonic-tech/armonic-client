import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../l10n/app_strings.dart';

/// Where a voice join is, from clicking the channel to audio flowing. Each
/// step waits on a different party — the mic, the server, the network — so
/// the step a join is stuck on says where to look.
enum VoiceStage {
  /// getUserMedia: waiting for the OS / browser to hand over the mic.
  microphone,

  /// `join-voice` sent, no `offer` yet: the server has not answered.
  awaitingServer,

  /// Offer received, building the answer.
  negotiating,

  /// Answer sent, ICE looking for a path between the two ends.
  connecting,

  /// ICE found a path, DTLS still handshaking on it.
  securing,

  /// Peer connection up: media can flow.
  connected,

  /// Was connected and lost the path.
  reconnecting,

  /// ICE failed, or the server refused the join.
  failed,
}

String voiceStageLabel(VoiceStage stage) => switch (stage) {
  VoiceStage.microphone => strings.voiceStageMicrophone,
  VoiceStage.awaitingServer => strings.voiceStageAwaitingServer,
  VoiceStage.negotiating => strings.voiceStageNegotiating,
  VoiceStage.connecting => strings.voiceStageConnecting,
  VoiceStage.securing => strings.voiceStageSecuring,
  VoiceStage.connected => strings.voiceStageConnected,
  VoiceStage.reconnecting => strings.voiceStageReconnecting,
  VoiceStage.failed => strings.voiceStageFailed,
};

/// Turns signaling and peer-connection events into a [VoiceStage].
///
/// Only ever moves forward through the join, except for losing a connection
/// once made: a renegotiation offer while connected (someone else started
/// talking) must not drag the banner back to "negotiating".
class VoiceLinkTracker {
  VoiceStage _stage = VoiceStage.microphone;
  final Stopwatch _clock = Stopwatch()..start();

  VoiceStage get stage => _stage;

  /// Time since the join began, for the trace in the logs.
  Duration get elapsed => _clock.elapsed;

  bool get settled =>
      _stage == VoiceStage.connected || _stage == VoiceStage.failed;

  bool joinSent() => _from({VoiceStage.microphone}, VoiceStage.awaitingServer);

  bool offerReceived() =>
      _from({VoiceStage.awaitingServer}, VoiceStage.negotiating);

  bool answerSent() => _from({VoiceStage.negotiating}, VoiceStage.connecting);

  bool fail() => _set(VoiceStage.failed);

  bool ice(RTCIceConnectionState state) => switch (state) {
    RTCIceConnectionState.RTCIceConnectionStateChecking => _from({
      VoiceStage.negotiating,
    }, VoiceStage.connecting),
    RTCIceConnectionState.RTCIceConnectionStateConnected ||
    RTCIceConnectionState.RTCIceConnectionStateCompleted => _from({
      VoiceStage.awaitingServer,
      VoiceStage.negotiating,
      VoiceStage.connecting,
    }, VoiceStage.securing),
    RTCIceConnectionState.RTCIceConnectionStateFailed => fail(),
    _ => false,
  };

  bool peer(RTCPeerConnectionState state) => switch (state) {
    RTCPeerConnectionState.RTCPeerConnectionStateConnected => _set(
      VoiceStage.connected,
    ),
    RTCPeerConnectionState.RTCPeerConnectionStateDisconnected => _from({
      VoiceStage.connected,
    }, VoiceStage.reconnecting),
    RTCPeerConnectionState.RTCPeerConnectionStateFailed => fail(),
    _ => false,
  };

  bool _from(Set<VoiceStage> allowed, VoiceStage next) =>
      allowed.contains(_stage) && _set(next);

  bool _set(VoiceStage next) {
    if (_stage == next) return false;
    _stage = next;
    return true;
  }
}
