import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:armonic_client/l10n/app_strings.dart';
import 'package:armonic_client/models/models.dart';
import 'package:armonic_client/screens/server_screen.dart';

ChannelInfo _channel(String name, String type) =>
    ChannelInfo(id: '$type-$name', serverId: 's1', name: name, type: type);

void main() {
  group('channelNameError', () {
    final channels = [
      _channel('general', 'text'),
      _channel('General', 'voice'),
    ];

    test('rejects a name already used by a channel of the same type', () {
      expect(channelNameError(channels, 'general', 'text'),
          strings.channelNameTaken);
    });

    test('is case-insensitive, like the backend', () {
      expect(channelNameError(channels, 'GeNeRaL', 'text'),
          strings.channelNameTaken);
    });

    test('ignores surrounding whitespace, like the backend trim', () {
      expect(channelNameError(channels, '  general  ', 'text'),
          strings.channelNameTaken);
    });

    test('allows the same name for the other type', () {
      // The bootstrap server itself ships general/text next to General/voice,
      // so scoping by type is required, not a nicety.
      final onlyText = [_channel('general', 'text')];
      expect(channelNameError(onlyText, 'General', 'voice'), isNull);
      expect(channelNameError(onlyText, 'General', 'text'),
          strings.channelNameTaken);
    });

    test('the seeded general/General pair blocks both of its own types', () {
      expect(channelNameError(channels, 'general', 'text'),
          strings.channelNameTaken);
      expect(channelNameError(channels, 'general', 'voice'),
          strings.channelNameTaken);
    });

    test('accepts a free name', () {
      expect(channelNameError(channels, 'random', 'text'), isNull);
    });

    test('rejects empty and whitespace-only names', () {
      expect(channelNameError(channels, '', 'text'), strings.channelNameEmpty);
      expect(
          channelNameError(channels, '   ', 'text'), strings.channelNameEmpty);
    });

    test('rejects names over the 64-char cap', () {
      expect(channelNameError(channels, 'a' * 65, 'text'),
          strings.channelNameTooLong);
      expect(channelNameError(channels, 'a' * 64, 'text'), isNull);
    });
  });

  group('the prompt enforces the validator', () {
    Future<String?> open(WidgetTester tester) async {
      String? result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async => result = await promptForText(
                context,
                title: 'Nuevo canal',
                label: 'Nombre',
                confirmLabel: 'Crear',
                maxLength: 64,
                validator: (v) => channelNameError(
                    [_channel('general', 'text')], v, 'text'),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('a duplicate name shows the error and blocks confirming',
        (tester) async {
      await open(tester);

      await tester.enterText(find.byType(TextField), 'General');
      await tester.pump();

      expect(find.text(strings.channelNameTaken), findsOneWidget);
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull, reason: 'Crear must be disabled');

      // The dialog must still be open — nothing was submitted.
      await tester.tap(find.text('Crear'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('Enter on a duplicate does not submit either', (tester) async {
      await open(tester);

      await tester.enterText(find.byType(TextField), 'general');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text(strings.channelNameTaken), findsOneWidget);
    });

    testWidgets('Enter on an untouched empty field does not submit',
        (tester) async {
      await open(tester);

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text(strings.channelNameEmpty), findsOneWidget);
    });

    testWidgets('the error clears once the name is free again',
        (tester) async {
      await open(tester);

      await tester.enterText(find.byType(TextField), 'general');
      await tester.pump();
      expect(find.text(strings.channelNameTaken), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'random');
      await tester.pump();
      expect(find.text(strings.channelNameTaken), findsNothing);

      await tester.tap(find.text('Crear'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
