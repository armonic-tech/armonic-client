import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:armonic_client/state/settings_store.dart';
import 'package:armonic_client/theme/armonic_colors.dart';
import 'package:armonic_client/theme/armonic_theme.dart';

import 'support/fakes.dart';

void main() {
  setUp(fakeSecureStorage);

  const storage = FlutterSecureStorage();

  Future<void> seed(Map<String, Object?> blob) =>
      storage.write(key: 'armonic_settings', value: jsonEncode(blob));

  test('a palette survives a round trip through JSON', () {
    const original = ArmonicColors();
    final restored = ArmonicColors.fromJson(original.toJson());

    expect(restored.accent, original.accent);
    expect(restored.background, original.background);
    expect(restored.border, original.border);
    expect(restored.glowOpacity, original.glowOpacity);
  });

  test('withToken changes one color and leaves the rest alone', () {
    const before = ArmonicColors();
    final after = before.withToken('accent', const Color(0xFF10B981));

    expect(after.accent, const Color(0xFF10B981));
    expect(after.background, before.background);
    expect(after.mention, before.mention);
  });

  test('settings persist and reload', () async {
    final store = SettingsStore(storage: storage);

    store.setFontScale(1.25);
    store.setChatAvatarRadius(28);
    store.setColor('accent', const Color(0xFF10B981));
    store.setAudio(const AudioPrefs(outputDeviceId: 'spk-1', volume: 0.5));
    // The write is fire-and-forget so the UI never waits on the keystore.
    await Future<void>.delayed(Duration.zero);

    final reloaded = SettingsStore(storage: storage);
    await reloaded.load();

    expect(reloaded.settings.fontScale, 1.25);
    expect(reloaded.settings.chatAvatarRadius, 28);
    expect(reloaded.settings.colors.accent, const Color(0xFF10B981));
    expect(reloaded.settings.audio.outputDeviceId, 'spk-1');
    expect(reloaded.settings.audio.volume, 0.5);
  });

  test('a stored blob missing fields keeps the defaults for them', () async {
    await seed({'fontScale': 1.1});
    final store = SettingsStore(storage: storage);
    await store.load();

    expect(store.settings.fontScale, 1.1);
    expect(
      store.settings.chatAvatarRadius,
      const ArmonicSettings().chatAvatarRadius,
    );
    expect(store.settings.colors.accent, const ArmonicColors().accent);
  });

  test('a corrupt blob falls back to defaults instead of throwing', () async {
    await storage.write(key: 'armonic_settings', value: 'not json at all');
    final store = SettingsStore(storage: storage);
    await store.load();

    expect(store.loaded, isTrue);
    expect(store.settings.fontScale, const ArmonicSettings().fontScale);
  });

  test('out-of-range values are clamped rather than honored', () async {
    await seed({
      'fontScale': 99.0,
      'chatAvatarRadius': 0.0,
      'audio': {'volume': 5.0},
    });
    final store = SettingsStore(storage: storage);
    await store.load();

    expect(store.settings.fontScale, ArmonicSettings.maxFontScale);
    expect(store.settings.chatAvatarRadius, ArmonicSettings.minAvatarRadius);
    expect(store.settings.audio.volume, 1.0);
  });

  test('reset returns every axis to its default', () {
    final store = SettingsStore(storage: storage);
    store.setFontScale(1.4);
    store.setColor('accent', const Color(0xFFFF0000));

    store.reset();

    expect(store.settings.fontScale, const ArmonicSettings().fontScale);
    expect(store.settings.colors.accent, const ArmonicColors().accent);
  });

  test('the theme carries the configured sizes and colors', () {
    final theme = buildArmonicTheme(
      const ArmonicColors().withToken('accent', const Color(0xFF10B981)),
      fontScale: 2,
      chatAvatarRadius: 30,
    );

    expect(theme.colorScheme.primary, const Color(0xFF10B981));
    expect(theme.extension<ArmonicTokens>()!.chatAvatarRadius, 30);
    // bodySmall is 12 at scale 1.
    expect(theme.textTheme.bodySmall!.fontSize, 24);
  });
}
