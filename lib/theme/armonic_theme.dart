import 'dart:convert';

import 'package:flutter/material.dart';

import 'armonic_colors.dart';
import 'theme_file_io.dart' if (dart.library.js_interop) 'theme_file_web.dart';

const kUiFont = 'Space Grotesk';
const kMonoFont = 'IBM Plex Mono';

/// The palette in force, plus the pieces of it Material has no role for
/// (mention pink, hairline borders, the ambient glow, the mono face).
/// Widgets read it with `context.armonic`.
class ArmonicTokens extends ThemeExtension<ArmonicTokens> {
  final ArmonicColors colors;

  /// Radius of the author avatar in the message list. It rides on the theme
  /// rather than on each widget's constructor so a settings change repaints
  /// the chat without threading a parameter through every tile.
  final double chatAvatarRadius;

  const ArmonicTokens(this.colors, {this.chatAvatarRadius = 20});

  /// The design's monospace style: labels, timestamps, badges, counters.
  TextStyle mono({
    double size = 10,
    FontWeight weight = FontWeight.w500,
    Color? color,
    double letterSpacing = 0,
  }) => TextStyle(
    fontFamily: kMonoFont,
    fontSize: size,
    fontWeight: weight,
    color: color ?? colors.textFaint,
    letterSpacing: letterSpacing,
  );

  @override
  ArmonicTokens copyWith({ArmonicColors? colors, double? chatAvatarRadius}) =>
      ArmonicTokens(
        colors ?? this.colors,
        chatAvatarRadius: chatAvatarRadius ?? this.chatAvatarRadius,
      );

  @override
  ArmonicTokens lerp(ArmonicTokens? other, double t) => other ?? this;
}

extension ArmonicContext on BuildContext {
  /// Falls back to the default palette when the app-level theme isn't there
  /// (widget tests pumping a bare MaterialApp), so widgets never depend on
  /// being under [buildArmonicTheme] just to render.
  ArmonicTokens get armonic =>
      Theme.of(this).extension<ArmonicTokens>() ??
      const ArmonicTokens(ArmonicColors());
}

/// Reads the user's `theme.json` (if any) over the built-in palette.
ArmonicColors loadArmonicColors() {
  final raw = readUserThemeFile();
  if (raw == null) return const ArmonicColors();
  try {
    final parsed = jsonDecode(raw);
    if (parsed is Map<String, Object?>) return ArmonicColors.fromJson(parsed);
  } catch (e) {
    debugPrint('theme.json ignored: $e');
  }
  return const ArmonicColors();
}

/// Maps the palette onto Material so every stock widget already comes out in
/// the Armonic look; anything the roles can't express reads [ArmonicTokens].
/// Takes loose values rather than the settings object so this layer keeps
/// knowing nothing about app state (which reads `loadArmonicColors` from here).
ThemeData buildArmonicTheme(
  ArmonicColors c, {
  double fontScale = 1,
  double chatAvatarRadius = 20,
}) {
  final scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: c.accent,
    onPrimary: c.onAccent,
    primaryContainer: c.accentDeep,
    onPrimaryContainer: c.accentPale,
    secondary: c.accentSoft,
    onSecondary: c.onAccent,
    secondaryContainer: c.selection,
    onSecondaryContainer: c.accentPale,
    tertiary: c.warning,
    onTertiary: c.onMention,
    error: c.mention,
    onError: c.onMention,
    surface: c.background,
    onSurface: c.textBody,
    onSurfaceVariant: c.textSecondary,
    surfaceContainerLowest: c.backgroundRail,
    surfaceContainerLow: c.backgroundSidebar,
    surfaceContainer: c.surfaceHover,
    surfaceContainerHigh: c.panel,
    surfaceContainerHighest: c.panelHigh,
    outline: c.textFaint,
    outlineVariant: c.border,
    inverseSurface: c.textPrimary,
    onInverseSurface: c.background,
    inversePrimary: c.accentDeep,
    surfaceTint: Colors.transparent,
    shadow: Colors.black,
    scrim: Colors.black54,
  );

  final border = BorderSide(color: c.border);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: kUiFont,
    scaffoldBackgroundColor: c.background,
    canvasColor: c.background,
    dividerColor: c.border,
    hoverColor: c.surfaceHover,
    splashFactory: NoSplash.splashFactory,
    textTheme: TextTheme(
      // Section headers ("TEXTO", "EN LÍNEA — 3"): the design's letterspaced
      // mono microcopy. Everything already using labelSmall picks this up.
      labelSmall: TextStyle(
        fontFamily: kMonoFont,
        fontSize: 10,
        fontWeight: FontWeight.w500,
        letterSpacing: 1.8,
        color: c.textFaint,
      ),
      labelLarge: TextStyle(
        fontFamily: kUiFont,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: c.textPrimary,
      ),
      titleLarge: TextStyle(
        fontFamily: kUiFont,
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: c.textPrimary,
      ),
      titleMedium: TextStyle(
        fontFamily: kUiFont,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: c.textPrimary,
      ),
      bodyMedium: TextStyle(fontSize: 14.5, height: 1.45, color: c.textBody),
      bodySmall: TextStyle(fontSize: 12, color: c.textMuted),
    ).apply(fontSizeFactor: fontScale),
    appBarTheme: AppBarTheme(
      backgroundColor: c.background,
      foregroundColor: c.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: kUiFont,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: c.textPrimary,
      ),
      shape: Border(bottom: border),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
      selectedTileColor: c.selection,
      selectedColor: c.textPrimary,
      iconColor: c.textFaint,
      textColor: c.textSecondary,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10),
      horizontalTitleGap: 9,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.backgroundSidebar,
      hintStyle: TextStyle(color: c.textFaint),
      labelStyle: TextStyle(color: c.textMuted),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: border,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: BorderSide(color: c.accent),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: BorderSide(color: c.mention),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: BorderSide(color: c.mention),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.backgroundSidebar,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: border,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: c.backgroundSidebar,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(9),
        side: border,
      ),
      textStyle: TextStyle(
        fontFamily: kUiFont,
        fontSize: 13,
        color: c.textBody,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.panelHigh,
      contentTextStyle: TextStyle(
        fontFamily: kUiFont,
        fontSize: 13,
        color: c.textPrimary,
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(9),
        side: border,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        iconSize: 20,
        textStyle: TextStyle(
          fontFamily: kUiFont,
          fontSize: 15 * fontScale,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.accentSoft,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        textStyle: TextStyle(
          fontFamily: kUiFont,
          fontSize: 14 * fontScale,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.textBody,
        side: BorderSide(color: c.border),
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        textStyle: TextStyle(fontFamily: kUiFont, fontSize: 14 * fontScale),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.accent),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: c.panelHigh,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.border),
      ),
      textStyle: TextStyle(
        fontFamily: kUiFont,
        fontSize: 12,
        color: c.textBody,
      ),
    ),
    extensions: [ArmonicTokens(c, chatAvatarRadius: chatAvatarRadius)],
  );
}

/// The single ambient glow of design option 2a: one diagonal gradient from
/// the top-left corner over the whole window, everything under it flat.
class AmbientGlow extends StatelessWidget {
  const AmbientGlow({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.armonic.colors;
    if (c.glowOpacity <= 0) return const SizedBox.shrink();
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: const [0, 0.26, 0.58, 1],
            colors: [
              c.accent.withValues(alpha: c.glowOpacity),
              c.accent.withValues(alpha: c.glowOpacity * 0.42),
              c.accent.withValues(alpha: 0),
              Colors.black.withValues(alpha: c.glowOpacity * 0.8),
            ],
          ),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}
