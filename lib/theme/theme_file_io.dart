import 'dart:io';

/// Contents of the user's theme file, or null when none exists.
///
/// Looked up in order, first hit wins:
/// 1. the file `ARMONIC_THEME` points at (explicit override),
/// 2. `theme.json` in the working directory (portable installs),
/// 3. `$XDG_CONFIG_HOME/armonic/theme.json`, falling back to
///    `~/.config/armonic/theme.json` (per-user config).
///
/// Any I/O failure reads as "no file": a broken theme must never stop the
/// app from starting.
String? readUserThemeFile() {
  final env = Platform.environment;
  final candidates = <String>[
    if (env['ARMONIC_THEME']?.isNotEmpty == true) env['ARMONIC_THEME']!,
    'theme.json',
    if (env['XDG_CONFIG_HOME']?.isNotEmpty == true)
      '${env['XDG_CONFIG_HOME']}/armonic/theme.json'
    else if (env['HOME']?.isNotEmpty == true)
      '${env['HOME']}/.config/armonic/theme.json',
  ];
  for (final path in candidates) {
    try {
      final file = File(path);
      if (file.existsSync()) return file.readAsStringSync();
    } catch (_) {
      // Unreadable candidate: fall through to the next location.
    }
  }
  return null;
}
