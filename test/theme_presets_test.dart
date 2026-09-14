import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:armonic_client/theme/armonic_colors.dart';
import 'package:armonic_client/theme/armonic_theme.dart';
import 'package:armonic_client/theme/theme_presets.dart';

void main() {
  test('the first preset is the built-in palette', () {
    expect(themePresets.first.colors, const ArmonicColors());
  });

  test('presets are distinct, uniquely keyed, and found by equality', () {
    final ids = themePresets.map((p) => p.id).toSet();
    expect(ids.length, themePresets.length);
    final palettes = themePresets.map((p) => p.colors).toSet();
    expect(palettes.length, themePresets.length);
    for (final preset in themePresets) {
      expect(presetMatching(preset.colors)?.id, preset.id);
    }
  });

  test('a preset survives storage and still matches itself', () {
    for (final preset in themePresets) {
      final restored = ArmonicColors.fromJson(preset.colors.toJson());
      expect(restored, preset.colors, reason: preset.id);
    }
  });

  test('one tweaked token makes a preset custom', () {
    final tweaked = themePresets[1].colors.withToken(
      'accent',
      const Color(0xFF123456),
    );
    expect(presetMatching(tweaked), isNull);
  });

  test('the theme brightness follows the background', () {
    final light = themePresets.singleWhere((p) => p.id == 'daylight');
    expect(buildArmonicTheme(light.colors).brightness, Brightness.light);
    expect(
      buildArmonicTheme(const ArmonicColors()).brightness,
      Brightness.dark,
    );
  });
}
