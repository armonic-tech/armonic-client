import 'dart:convert';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../theme/armonic_colors.dart';
import '../theme/armonic_theme.dart';

/// The audio half of the settings, split out because it is the only part the
/// live [VoiceSession] cares about — it can be handed a snapshot without the
/// voice layer depending on the store.
class AudioPrefs {
  /// Empty means "whatever the platform picks", which is also what happens
  /// when a remembered device is gone (unplugged headset).
  final String inputDeviceId;
  final String outputDeviceId;

  /// Playback gain for remote voices, 0..1.
  final double volume;

  const AudioPrefs({
    this.inputDeviceId = '',
    this.outputDeviceId = '',
    this.volume = 1,
  });

  AudioPrefs copyWith({
    String? inputDeviceId,
    String? outputDeviceId,
    double? volume,
  }) => AudioPrefs(
    inputDeviceId: inputDeviceId ?? this.inputDeviceId,
    outputDeviceId: outputDeviceId ?? this.outputDeviceId,
    volume: volume ?? this.volume,
  );

  Map<String, Object?> toJson() => {
    'inputDeviceId': inputDeviceId,
    'outputDeviceId': outputDeviceId,
    'volume': volume,
  };

  factory AudioPrefs.fromJson(Map<String, Object?> json) {
    final volume = json['volume'];
    return AudioPrefs(
      inputDeviceId: json['inputDeviceId'] as String? ?? '',
      outputDeviceId: json['outputDeviceId'] as String? ?? '',
      volume: volume is num ? volume.toDouble().clamp(0.0, 1.0) : 1,
    );
  }
}

/// Everything the user can tune from Settings. Purely client-side: none of it
/// reaches the instance, so two clients on the same account can look and sound
/// completely different.
class ArmonicSettings {
  final ArmonicColors colors;

  /// Multiplies every font size in the theme.
  final double fontScale;

  /// Radius of the author avatar in the message list.
  final double chatAvatarRadius;

  final AudioPrefs audio;

  const ArmonicSettings({
    this.colors = const ArmonicColors(),
    this.fontScale = 1,
    this.chatAvatarRadius = 20,
    this.audio = const AudioPrefs(),
  });

  static const minFontScale = 0.8;
  static const maxFontScale = 1.4;
  static const minAvatarRadius = 12.0;
  static const maxAvatarRadius = 32.0;

  ArmonicSettings copyWith({
    ArmonicColors? colors,
    double? fontScale,
    double? chatAvatarRadius,
    AudioPrefs? audio,
  }) => ArmonicSettings(
    colors: colors ?? this.colors,
    fontScale: fontScale ?? this.fontScale,
    chatAvatarRadius: chatAvatarRadius ?? this.chatAvatarRadius,
    audio: audio ?? this.audio,
  );

  Map<String, Object?> toJson() => {
    'colors': colors.toJson(),
    'fontScale': fontScale,
    'chatAvatarRadius': chatAvatarRadius,
    'audio': audio.toJson(),
  };

  /// Every field falls back to its default independently, so a settings blob
  /// written by an older build (or a hand-edited one) still loads.
  factory ArmonicSettings.fromJson(
    Map<String, Object?> json, {
    ArmonicColors fallbackColors = const ArmonicColors(),
  }) {
    final colors = json['colors'];
    final audio = json['audio'];
    final fontScale = json['fontScale'];
    final avatar = json['chatAvatarRadius'];
    const d = ArmonicSettings();
    return ArmonicSettings(
      colors: colors is Map<String, Object?>
          ? ArmonicColors.fromJson(colors)
          : fallbackColors,
      fontScale: fontScale is num
          ? fontScale.toDouble().clamp(minFontScale, maxFontScale)
          : d.fontScale,
      chatAvatarRadius: avatar is num
          ? avatar.toDouble().clamp(minAvatarRadius, maxAvatarRadius)
          : d.chatAvatarRadius,
      audio: audio is Map<String, Object?>
          ? AudioPrefs.fromJson(audio)
          : d.audio,
    );
  }
}

/// Loads, holds and persists [ArmonicSettings].
///
/// Stored in the platform keystore next to the instance list rather than in a
/// file: it is the one store that works identically on web, Linux and Android,
/// and settings follow the same "belongs to this install" lifetime as the
/// saved instances. `theme.json` is still read — as the *seed* for a first
/// run, so an operator shipping a branded palette still gets it, and the user
/// can then adjust it from the UI.
class SettingsStore extends ChangeNotifier {
  static const _storageKey = 'armonic_settings';

  final FlutterSecureStorage _storage;
  ArmonicSettings _settings;
  bool loaded = false;

  SettingsStore({FlutterSecureStorage? storage, ArmonicSettings? initial})
    : _storage = storage ?? const FlutterSecureStorage(),
      _settings = initial ?? const ArmonicSettings();

  ArmonicSettings get settings => _settings;

  Future<void> load() async {
    // The file is the seed: it decides the defaults this install starts from,
    // and anything the user has since changed in the UI wins over it.
    final seeded = ArmonicSettings(colors: loadArmonicColors());
    try {
      final raw = await _storage.read(key: _storageKey);
      if (raw != null && raw.isNotEmpty) {
        final parsed = jsonDecode(raw);
        if (parsed is Map<String, Object?>) {
          _settings = ArmonicSettings.fromJson(
            parsed,
            fallbackColors: seeded.colors,
          );
        }
      } else {
        _settings = seeded;
      }
    } catch (e) {
      debugPrint('settings: error loading, using defaults: $e');
      _settings = seeded;
    }
    loaded = true;
    notifyListeners();
  }

  /// Applies [settings] immediately and persists in the background: the UI
  /// must not wait on a keystore write to repaint a color the user just
  /// dragged.
  void update(ArmonicSettings settings) {
    _settings = settings;
    notifyListeners();
    _persist();
  }

  void setColor(String token, Color value) => update(
    _settings.copyWith(colors: _settings.colors.withToken(token, value)),
  );

  void setGlow(double value) =>
      update(_settings.copyWith(colors: _settings.colors.withGlow(value)));

  void setFontScale(double value) =>
      update(_settings.copyWith(fontScale: value));

  void setChatAvatarRadius(double value) =>
      update(_settings.copyWith(chatAvatarRadius: value));

  void setAudio(AudioPrefs audio) => update(_settings.copyWith(audio: audio));

  /// Back to the built-in palette and sizes, audio devices included.
  void reset() => update(const ArmonicSettings());

  Future<void> _persist() async {
    try {
      await _storage.write(
        key: _storageKey,
        value: jsonEncode(_settings.toJson()),
      );
    } catch (e) {
      debugPrint('settings: could not persist: $e');
    }
  }
}
