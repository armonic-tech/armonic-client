import 'dart:ui';

/// The color palette of the app, one field per role the UI paints with.
///
/// Defaults are the "Armonic Redesign" canvas (dark navy + electric blue,
/// pink for mentions/danger). Every field can be overridden by the user's
/// `theme.json` — see [ArmonicColors.fromJson] and `theme.example.json` at
/// the repo root for the file format and where it is looked up.
class ArmonicColors {
  /// Chat area / base window background.
  final Color background;

  /// The instance rail — the darkest column on the far left.
  final Color backgroundRail;

  /// Channel sidebar and members panel.
  final Color backgroundSidebar;

  /// Raised panels: voice card, call panel, dialogs.
  final Color panel;

  /// Highest panels: rail squares, image placeholders.
  final Color panelHigh;

  /// Hover band behind a message under the pointer.
  final Color surfaceHover;

  /// Background of the selected channel row.
  final Color selection;

  /// Small chips: reaction pills, file cards.
  final Color chip;

  /// The electric blue — buttons, selected indicators, links.
  final Color accent;

  /// Text/icons painted on top of [accent].
  final Color onAccent;

  /// Lighter accent for secondary highlights ('#' of the active channel,
  /// live voice info).
  final Color accentSoft;

  /// Palest accent — initials on navy avatars, owner badge text.
  final Color accentPale;

  /// Avatar circles / selected rail tile / owner badge background.
  final Color accentDeep;

  /// Headline text: usernames, channel names, titles.
  final Color textPrimary;

  /// Message bodies and most reading text.
  final Color textBody;

  /// Secondary text: descriptions, inactive channel names.
  final Color textSecondary;

  /// Muted text: hints, date separators.
  final Color textMuted;

  /// Faintest text: section headers, timestamps' neighbors, idle icons.
  final Color textFaint;

  /// Mentions, destructive actions, unreachable instances.
  final Color mention;

  /// Text painted on top of [mention].
  final Color onMention;

  /// "Attention but not danger" — the needs-login dot on the rail.
  final Color warning;

  /// Hairline borders between panels (usually translucent white).
  final Color border;

  /// Strength of the ambient corner-to-corner glow painted over the whole
  /// window (design option 2a). 0 disables it entirely.
  final double glowOpacity;

  const ArmonicColors({
    this.background = const Color(0xFF0B0D1A),
    this.backgroundRail = const Color(0xFF080A14),
    this.backgroundSidebar = const Color(0xFF0E1123),
    this.panel = const Color(0xFF141830),
    this.panelHigh = const Color(0xFF161A30),
    this.surfaceHover = const Color(0xFF11142A),
    this.selection = const Color(0xFF152246),
    this.chip = const Color(0xFF182347),
    this.accent = const Color(0xFF4C86F6),
    this.onAccent = const Color(0xFF07142E),
    this.accentSoft = const Color(0xFF8AB4FF),
    this.accentPale = const Color(0xFFBCD4FF),
    this.accentDeep = const Color(0xFF24406F),
    this.textPrimary = const Color(0xFFEEF2FF),
    this.textBody = const Color(0xFFCCD3E8),
    this.textSecondary = const Color(0xFFA2AAC6),
    this.textMuted = const Color(0xFF8D96B4),
    this.textFaint = const Color(0xFF6C7596),
    this.mention = const Color(0xFFFF5A8A),
    this.onMention = const Color(0xFF2A0812),
    this.warning = const Color(0xFFF2B04A),
    this.border = const Color(0x14FFFFFF),
    this.glowOpacity = 0.22,
  });

  /// Overlays [json] (a flat `{"token": "#RRGGBB"}` map) on the defaults.
  ///
  /// Unknown keys and unparseable values are ignored one by one rather than
  /// failing the whole file, so a typo costs that one color, not the theme.
  factory ArmonicColors.fromJson(Map<String, Object?> json) {
    Color pick(String key, Color fallback) => parseHex(json[key]) ?? fallback;
    const d = ArmonicColors();
    final glow = json['glowOpacity'];
    return ArmonicColors(
      background: pick('background', d.background),
      backgroundRail: pick('backgroundRail', d.backgroundRail),
      backgroundSidebar: pick('backgroundSidebar', d.backgroundSidebar),
      panel: pick('panel', d.panel),
      panelHigh: pick('panelHigh', d.panelHigh),
      surfaceHover: pick('surfaceHover', d.surfaceHover),
      selection: pick('selection', d.selection),
      chip: pick('chip', d.chip),
      accent: pick('accent', d.accent),
      onAccent: pick('onAccent', d.onAccent),
      accentSoft: pick('accentSoft', d.accentSoft),
      accentPale: pick('accentPale', d.accentPale),
      accentDeep: pick('accentDeep', d.accentDeep),
      textPrimary: pick('textPrimary', d.textPrimary),
      textBody: pick('textBody', d.textBody),
      textSecondary: pick('textSecondary', d.textSecondary),
      textMuted: pick('textMuted', d.textMuted),
      textFaint: pick('textFaint', d.textFaint),
      mention: pick('mention', d.mention),
      onMention: pick('onMention', d.onMention),
      warning: pick('warning', d.warning),
      border: pick('border', d.border),
      glowOpacity: glow is num
          ? glow.toDouble().clamp(0.0, 1.0)
          : d.glowOpacity,
    );
  }

  /// The inverse of [fromJson], so a palette survives a round trip through
  /// storage. Keys match [fromJson]'s exactly — that pairing is what lets
  /// [withToken] edit one color without a 22-argument `copyWith`.
  Map<String, Object?> toJson() => {
    for (final entry in tokens.entries) entry.key: _toHex(entry.value),
    'glowOpacity': glowOpacity,
  };

  /// Every color by its JSON key. Also what drives the settings UI's list of
  /// editable swatches, so a new token shows up there for free.
  Map<String, Color> get tokens => {
    'background': background,
    'backgroundRail': backgroundRail,
    'backgroundSidebar': backgroundSidebar,
    'panel': panel,
    'panelHigh': panelHigh,
    'surfaceHover': surfaceHover,
    'selection': selection,
    'chip': chip,
    'accent': accent,
    'onAccent': onAccent,
    'accentSoft': accentSoft,
    'accentPale': accentPale,
    'accentDeep': accentDeep,
    'textPrimary': textPrimary,
    'textBody': textBody,
    'textSecondary': textSecondary,
    'textMuted': textMuted,
    'textFaint': textFaint,
    'mention': mention,
    'onMention': onMention,
    'warning': warning,
    'border': border,
  };

  /// This palette with one token replaced.
  ArmonicColors withToken(String key, Color value) =>
      ArmonicColors.fromJson({...toJson(), key: _toHex(value)});

  ArmonicColors withGlow(double value) =>
      ArmonicColors.fromJson({...toJson(), 'glowOpacity': value});

  static String _toHex(Color c) {
    int channel(double v) => (v * 255).round().clamp(0, 255);
    return '#'
        '${channel(c.a).toRadixString(16).padLeft(2, '0')}'
        '${channel(c.r).toRadixString(16).padLeft(2, '0')}'
        '${channel(c.g).toRadixString(16).padLeft(2, '0')}'
        '${channel(c.b).toRadixString(16).padLeft(2, '0')}';
  }

  /// "#RRGGBB", "RRGGBB" or "#AARRGGBB" → [Color]; null when it is neither.
  /// Public because the settings UI validates what the user types with the
  /// same parser the file loader uses — one grammar, not two.
  static Color? parseHex(Object? value) {
    if (value is! String) return null;
    var hex = value.trim();
    if (hex.startsWith('#')) hex = hex.substring(1);
    if (hex.length == 6) hex = 'FF$hex';
    if (hex.length != 8) return null;
    final argb = int.tryParse(hex, radix: 16);
    return argb == null ? null : Color(argb);
  }
}
