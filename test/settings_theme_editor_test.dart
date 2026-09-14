import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:armonic_client/l10n/app_strings.dart';
import 'package:armonic_client/screens/settings_screen.dart';
import 'package:armonic_client/state/settings_store.dart';
import 'package:armonic_client/theme/armonic_colors.dart';
import 'package:armonic_client/theme/armonic_theme.dart';
import 'package:armonic_client/theme/theme_presets.dart';

import 'support/fakes.dart';

void main() {
  setUp(fakeSecureStorage);

  final forest = themePresets.singleWhere((p) => p.id == 'forest').colors;

  Future<SettingsStore> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final store = SettingsStore();
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsStore>.value(
        value: store,
        child: MaterialApp(
          theme: buildArmonicTheme(const ArmonicColors()),
          home: const SettingsDialog(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return store;
  }

  Finder apply() => find.widgetWithText(FilledButton, strings.apply);

  /// The preset row sits below the dialog's fold; scroll the pane to it.
  Future<void> pick(WidgetTester tester, String id) async {
    final card = find.text(strings.themePresetName(id));
    await tester.scrollUntilVisible(
      card,
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(card);
    await tester.pumpAndSettle();
  }

  testWidgets('picking a preset only previews it until applied', (
    tester,
  ) async {
    final store = await pump(tester);

    expect(tester.widget<FilledButton>(apply()).enabled, isFalse);

    await pick(tester, 'forest');

    expect(store.settings.colors, const ArmonicColors());
    expect(find.text(strings.unappliedChanges), findsOneWidget);

    await tester.tap(apply());
    await tester.pumpAndSettle();

    expect(store.settings.colors, forest);
    expect(find.text(strings.unappliedChanges), findsNothing);
  });

  testWidgets('discard drops the draft back to what is applied', (
    tester,
  ) async {
    final store = await pump(tester);

    await pick(tester, 'forest');
    await tester.tap(find.widgetWithText(TextButton, strings.discard));
    await tester.pumpAndSettle();

    expect(store.settings.colors, const ArmonicColors());
    expect(tester.widget<FilledButton>(apply()).enabled, isFalse);
  });

  testWidgets('the footer reset also resets a pending draft', (tester) async {
    final store = await pump(tester);
    store.setColors(forest);
    await tester.pumpAndSettle();

    await pick(tester, 'grape');
    await tester.tap(find.text(strings.resetSettings));
    await tester.pumpAndSettle();

    expect(store.settings.colors, const ArmonicColors());
    expect(find.text(strings.unappliedChanges), findsNothing);
  });
}
