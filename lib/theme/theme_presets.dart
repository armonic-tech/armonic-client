import 'dart:ui';

import 'armonic_colors.dart';

/// A ready-made palette the settings screen offers as a starting point.
class ThemePreset {
  /// Stable key, also what [strings.themePresetName] is looked up by.
  final String id;
  final ArmonicColors colors;

  const ThemePreset(this.id, this.colors);
}

/// The built-in palettes, default first. Each one is a complete
/// [ArmonicColors], so picking it replaces every token — the user can then
/// tweak individual colors on top and it becomes "custom".
const themePresets = <ThemePreset>[
  ThemePreset('armonic', ArmonicColors()),
  ThemePreset(
    'midnight',
    ArmonicColors(
      background: Color(0xFF111214),
      backgroundRail: Color(0xFF0B0C0E),
      backgroundSidebar: Color(0xFF16181C),
      panel: Color(0xFF1E2126),
      panelHigh: Color(0xFF23262C),
      surfaceHover: Color(0xFF191B1F),
      selection: Color(0xFF262A33),
      chip: Color(0xFF2A2E38),
      accent: Color(0xFF7C8CF8),
      onAccent: Color(0xFF0B0F2A),
      accentSoft: Color(0xFFA5B1FF),
      accentPale: Color(0xFFCFD6FF),
      accentDeep: Color(0xFF34395E),
      textPrimary: Color(0xFFF2F3F7),
      textBody: Color(0xFFD2D5DC),
      textSecondary: Color(0xFFA4A9B5),
      textMuted: Color(0xFF8B909C),
      textFaint: Color(0xFF676C78),
      mention: Color(0xFFFF6B6B),
      onMention: Color(0xFF2B0A0A),
      warning: Color(0xFFF5B84D),
      glowOpacity: 0.1,
    ),
  ),
  ThemePreset(
    'forest',
    ArmonicColors(
      background: Color(0xFF0B1410),
      backgroundRail: Color(0xFF07100C),
      backgroundSidebar: Color(0xFF0F1A14),
      panel: Color(0xFF15241C),
      panelHigh: Color(0xFF182A20),
      surfaceHover: Color(0xFF112019),
      selection: Color(0xFF17352A),
      chip: Color(0xFF1B3A2D),
      accent: Color(0xFF34D399),
      onAccent: Color(0xFF052A1B),
      accentSoft: Color(0xFF7FE8C0),
      accentPale: Color(0xFFBDF5DF),
      accentDeep: Color(0xFF1F5C45),
      textPrimary: Color(0xFFECFDF5),
      textBody: Color(0xFFCDE5DA),
      textSecondary: Color(0xFF9FBFB1),
      textMuted: Color(0xFF86A697),
      textFaint: Color(0xFF64857A),
      mention: Color(0xFFFF7A59),
      onMention: Color(0xFF2A0F08),
      warning: Color(0xFFF2C14E),
      glowOpacity: 0.18,
    ),
  ),
  ThemePreset(
    'ember',
    ArmonicColors(
      background: Color(0xFF16100C),
      backgroundRail: Color(0xFF100B08),
      backgroundSidebar: Color(0xFF1C1410),
      panel: Color(0xFF261A14),
      panelHigh: Color(0xFF2C1E17),
      surfaceHover: Color(0xFF201612),
      selection: Color(0xFF3A2418),
      chip: Color(0xFF40281B),
      accent: Color(0xFFF59E4B),
      onAccent: Color(0xFF2A1305),
      accentSoft: Color(0xFFFFC48A),
      accentPale: Color(0xFFFFE2C2),
      accentDeep: Color(0xFF6B3E1E),
      textPrimary: Color(0xFFFFF5EC),
      textBody: Color(0xFFE8D6C8),
      textSecondary: Color(0xFFBFA895),
      textMuted: Color(0xFFA48D7B),
      textFaint: Color(0xFF7F6C5D),
      mention: Color(0xFFFF5A8A),
      onMention: Color(0xFF2A0812),
      warning: Color(0xFFFFD166),
      glowOpacity: 0.2,
    ),
  ),
  ThemePreset(
    'grape',
    ArmonicColors(
      background: Color(0xFF100B1A),
      backgroundRail: Color(0xFF0B0714),
      backgroundSidebar: Color(0xFF150F23),
      panel: Color(0xFF1E1633),
      panelHigh: Color(0xFF231A3A),
      surfaceHover: Color(0xFF191229),
      selection: Color(0xFF2C1F4D),
      chip: Color(0xFF322455),
      accent: Color(0xFFA855F7),
      onAccent: Color(0xFF1E0838),
      accentSoft: Color(0xFFC79BFF),
      accentPale: Color(0xFFE4CFFF),
      accentDeep: Color(0xFF4C2A7A),
      textPrimary: Color(0xFFF5EEFF),
      textBody: Color(0xFFDBD0EA),
      textSecondary: Color(0xFFB0A3C6),
      textMuted: Color(0xFF978AB0),
      textFaint: Color(0xFF746A8E),
      mention: Color(0xFFFF5A8A),
      onMention: Color(0xFF2A0812),
      warning: Color(0xFFF2B04A),
      glowOpacity: 0.24,
    ),
  ),
  ThemePreset(
    'daylight',
    ArmonicColors(
      background: Color(0xFFF6F7FB),
      backgroundRail: Color(0xFFE6E9F2),
      backgroundSidebar: Color(0xFFEEF0F7),
      panel: Color(0xFFFFFFFF),
      panelHigh: Color(0xFFFFFFFF),
      surfaceHover: Color(0xFFEAEDF5),
      selection: Color(0xFFDCE6FB),
      chip: Color(0xFFE3E9F7),
      accent: Color(0xFF2F6FE4),
      onAccent: Color(0xFFFFFFFF),
      accentSoft: Color(0xFF1F5BC8),
      accentPale: Color(0xFF163F8C),
      accentDeep: Color(0xFFC9DAFB),
      textPrimary: Color(0xFF14172B),
      textBody: Color(0xFF2B3047),
      textSecondary: Color(0xFF545B78),
      textMuted: Color(0xFF6B7290),
      textFaint: Color(0xFF8A90AA),
      mention: Color(0xFFD6336C),
      onMention: Color(0xFFFFFFFF),
      warning: Color(0xFFB7791F),
      border: Color(0x14000000),
      glowOpacity: 0.06,
    ),
  ),
];

/// The preset [colors] is exactly, or null when the user has customized it.
ThemePreset? presetMatching(ArmonicColors colors) {
  for (final preset in themePresets) {
    if (preset.colors == colors) return preset;
  }
  return null;
}
