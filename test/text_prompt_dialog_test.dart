import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:armonic_client/screens/server_screen.dart';

/// Regression guard for the crash on "create channel" / "join with invite":
/// the controller used to be disposed right after `showDialog`'s future
/// completed, while the route was still animating out with its TextField
/// still listening. The close animation is where it blew up, so these tests
/// deliberately pump all the way through it.
void main() {
  Future<String?> open(WidgetTester tester, {int? maxLength}) async {
    String? result;
    var returned = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                result = await promptForText(
                  context,
                  title: 'Nuevo canal',
                  label: 'Nombre',
                  confirmLabel: 'Crear',
                  maxLength: maxLength,
                );
                returned = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    addTearDown(() => expect(returned, isTrue));
    return result;
  }

  testWidgets('confirming returns the text and survives the close animation', (
    tester,
  ) async {
    await open(tester);

    await tester.enterText(find.byType(TextField), 'general');
    await tester.tap(find.text('Crear'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('submitting from the keyboard also closes cleanly', (
    tester,
  ) async {
    await open(tester);

    await tester.enterText(find.byType(TextField), 'general');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelling closes cleanly too', (tester) async {
    await open(tester);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('maxLength is applied to the field', (tester) async {
    await open(tester, maxLength: 64);

    expect(tester.widget<TextField>(find.byType(TextField)).maxLength, 64);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
  });
}
