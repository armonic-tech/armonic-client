import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:armonic_client/l10n/app_strings.dart';
import 'package:armonic_client/widgets/voice_status_panel.dart';

void main() {
  Future<void> pumpBar(
    WidgetTester tester, {
    String instanceLabel = 'Casa',
    String serverName = 'Armonic',
    List<String> members = const ['Leo', 'Bob'],
    bool muted = false,
    bool deafened = false,
    VoidCallback? onOpen,
    VoidCallback? onToggleMute,
    VoidCallback? onLeave,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: VoiceStatusPanel(
          channelName: 'General',
          instanceLabel: instanceLabel,
          serverName: serverName,
          memberLabels: members,
          muted: muted,
          deafened: deafened,
          onToggleMute: onToggleMute ?? () {},
          onToggleDeafen: () {},
          onLeave: onLeave ?? () {},
          onOpen: onOpen,
        ),
      ),
    ));
  }

  testWidgets('names the channel, the instance and the server it belongs to',
      (tester) async {
    await pumpBar(tester);

    expect(find.text(strings.voiceLabel('General')), findsOneWidget);
    expect(find.text(strings.voiceLocation('Casa', 'Armonic')), findsOneWidget);
    expect(find.text('Leo, Bob'), findsOneWidget);
  });

  testWidgets('a one-server instance is named once, not twice',
      (tester) async {
    await pumpBar(tester, instanceLabel: 'Armonic', serverName: 'Armonic');

    expect(find.text('Armonic'), findsOneWidget);
  });

  testWidgets('the controls stay reachable while reading elsewhere',
      (tester) async {
    var mutes = 0;
    var leaves = 0;
    await pumpBar(tester,
        onToggleMute: () => mutes++, onLeave: () => leaves++);

    await tester.tap(find.byIcon(Icons.mic));
    await tester.tap(find.byIcon(Icons.call_end));

    expect(mutes, 1);
    expect(leaves, 1);
  });

  testWidgets('muted and deafened swap to the struck-through icons',
      (tester) async {
    await pumpBar(tester, muted: true, deafened: true);

    expect(find.byIcon(Icons.mic_off), findsOneWidget);
    expect(find.byIcon(Icons.headset_off), findsOneWidget);
  });

  testWidgets('tapping the call takes you back to the instance hosting it',
      (tester) async {
    var opened = 0;
    await pumpBar(tester, onOpen: () => opened++);

    await tester.tap(find.text(strings.voiceLabel('General')));

    expect(opened, 1);
  });

  testWidgets('no jump offered when that instance is already on screen',
      (tester) async {
    await pumpBar(tester);

    expect(
      find.byWidgetPredicate(
          (w) => w is Tooltip && w.message == strings.goToVoiceServer),
      findsNothing,
    );
  });
}
