import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'l10n/app_strings.dart';
import 'screens/app_shell.dart';
import 'state/instance_store.dart';
import 'state/session_manager.dart';
import 'state/settings_store.dart';
import 'theme/armonic_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    BrowserContextMenu.disableContextMenu();
  }
  runApp(const ArmonicApp());
}

class ArmonicApp extends StatelessWidget {
  /// Injectable so a test can pump the app under a known palette without
  /// touching the keystore.
  final SettingsStore? settings;

  const ArmonicApp({super.key, this.settings});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => InstanceStore()..bootstrap()),
        ChangeNotifierProvider(
          create: (_) => settings ?? (SettingsStore()..load()),
        ),
        // Above the shell on purpose: sessions (and the call one of them may
        // hold) must outlive whichever instance screen is on display.
        ChangeNotifierProvider(
          create: (context) => SessionManager(
            onSessionExpired: (baseUrl) =>
                context.read<InstanceStore>().clearToken(baseUrl),
          ),
        ),
      ],
      // Watched, not read: changing a color or a font size in Settings
      // rebuilds the whole theme, which is what makes the change live.
      child: Consumer<SettingsStore>(
        builder: (context, store, _) => MaterialApp(
          title: strings.appTitle,
          debugShowCheckedModeBanner: false,
          theme: buildArmonicTheme(
            store.settings.colors,
            fontScale: store.settings.fontScale,
            chatAvatarRadius: store.settings.chatAvatarRadius,
          ),
          home: const AppShell(),
        ),
      ),
    );
  }
}
