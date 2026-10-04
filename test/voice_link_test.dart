import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'package:armonic_client/l10n/app_strings.dart';
import 'package:armonic_client/models/models.dart';
import 'package:armonic_client/screens/server_screen.dart';
import 'package:armonic_client/state/session.dart';
import 'package:armonic_client/voice/voice_link.dart';
import 'package:armonic_client/widgets/voice_status_panel.dart';

import 'support/fakes.dart';

void main() {
  group('VoiceLinkTracker', () {
    test('walks the join step by step', () {
      final link = VoiceLinkTracker();
      final seen = <VoiceStage>[link.stage];
      void step(bool changed) {
        if (changed) seen.add(link.stage);
      }

      step(link.joinSent());
      step(link.offerReceived());
      step(link.answerSent());
      step(link.ice(RTCIceConnectionState.RTCIceConnectionStateChecking));
      step(link.ice(RTCIceConnectionState.RTCIceConnectionStateConnected));
      step(link.peer(RTCPeerConnectionState.RTCPeerConnectionStateConnected));

      expect(seen, [
        VoiceStage.microphone,
        VoiceStage.awaitingServer,
        VoiceStage.negotiating,
        VoiceStage.connecting,
        VoiceStage.securing,
        VoiceStage.connected,
      ]);
      expect(link.settled, isTrue);
    });

    test('a renegotiation offer once connected does not go backwards', () {
      final link = VoiceLinkTracker()
        ..joinSent()
        ..offerReceived()
        ..answerSent()
        ..peer(RTCPeerConnectionState.RTCPeerConnectionStateConnected);

      // Someone else started talking: a new offer and answer round trip.
      expect(link.offerReceived(), isFalse);
      expect(link.answerSent(), isFalse);
      expect(
        link.ice(RTCIceConnectionState.RTCIceConnectionStateChecking),
        isFalse,
      );
      expect(link.stage, VoiceStage.connected);
    });

    test('losing the path reconnects, and a dead path fails', () {
      final link = VoiceLinkTracker()
        ..joinSent()
        ..offerReceived()
        ..answerSent()
        ..peer(RTCPeerConnectionState.RTCPeerConnectionStateConnected);

      link.peer(RTCPeerConnectionState.RTCPeerConnectionStateDisconnected);
      expect(link.stage, VoiceStage.reconnecting);
      link.peer(RTCPeerConnectionState.RTCPeerConnectionStateConnected);
      expect(link.stage, VoiceStage.connected);

      link.ice(RTCIceConnectionState.RTCIceConnectionStateFailed);
      expect(link.stage, VoiceStage.failed);
    });

    test('a disconnect before ever connecting is not "reconnecting"', () {
      final link = VoiceLinkTracker()
        ..joinSent()
        ..offerReceived()
        ..answerSent();
      expect(
        link.peer(RTCPeerConnectionState.RTCPeerConnectionStateDisconnected),
        isFalse,
      );
      expect(link.stage, VoiceStage.connecting);
    });

    test('a refused join fails straight from waiting on the server', () {
      final link = VoiceLinkTracker()..joinSent();
      expect(link.fail(), isTrue);
      expect(link.stage, VoiceStage.failed);
    });
  });

  group('voice-link', () {
    late FakeSocket socket;
    InstanceSession? session;

    setUp(() => socket = FakeSocket());
    tearDown(() async {
      await drainEvents();
      session?.dispose();
    });

    test('greys a member until the server says their link is up', () async {
      session = await connectedSession(defaultBackend(), socket);
      await pumpEventQueue();

      socket.emit({
        'type': 'voice-link',
        'userId': 'u2',
        'channelId': 'c-voice',
        'linked': false,
      });
      await pumpEventQueue();
      final bob = session!.voiceMembersFor('c-voice').single;
      expect(bob.linked, isFalse);
      expect(
        session!.voiceLinkIssue('c-voice', bob),
        strings.voiceMemberConnecting,
      );

      socket.emit({
        'type': 'voice-link',
        'userId': 'u2',
        'channelId': 'c-voice',
        'linked': true,
      });
      await pumpEventQueue();
      expect(
        session!.voiceLinkIssue(
          'c-voice',
          session!.voiceMembersFor('c-voice').single,
        ),
        isNull,
      );
    });

    test('a server that does not report links greys nobody', () async {
      session = await connectedSession(defaultBackend(), socket);
      await pumpEventQueue();
      final bob = session!.voiceMembersFor('c-voice').single;
      expect(bob.linked, isNull);
      expect(session!.voiceLinkIssue('c-voice', bob), isNull);
    });
  });

  testWidgets('the stage line names the step and warns when it drags', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: VoiceStageLine(stage: VoiceStage.connecting, stalled: true),
        ),
      ),
    );
    expect(find.text(strings.voiceStageConnecting), findsOneWidget);
    expect(find.text(strings.voiceStageSlow), findsOneWidget);
  });

  testWidgets('a member that cannot be heard yet is greyed with a reason', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VoiceMemberTile(
            member: VoiceMember(id: 'u2', displayName: 'Bob', linked: false),
            isSelf: false,
            muted: false,
            deafened: false,
            linkIssue: strings.voiceMemberConnecting,
          ),
        ),
      ),
    );
    expect(
      find.byWidgetPredicate(
        (w) => w is Tooltip && w.message == strings.voiceMemberConnecting,
      ),
      findsOneWidget,
    );
    final opacity = tester.widget<Opacity>(find.byType(Opacity).first);
    expect(opacity.opacity, lessThan(1));
  });
}
