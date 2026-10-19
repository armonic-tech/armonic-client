import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'l10n/app_strings.dart';
import 'screens/app_shell.dart';
import 'state/instance_store.dart';
import 'state/session_manager.dart';
import 'state/settings_store.dart';
import 'theme/armonic_theme.dart';
import 'util/log.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  _installErrorLogging();
  Log.i(
    'app',
    'starting on ${kIsWeb ? 'web' : defaultTargetPlatform.name}'
        '${kReleaseMode ? '' : ' (debug)'}',
  );
  if (kIsWeb) {
    BrowserContextMenu.disableContextMenu();
  }
  runApp(const ArmonicApp());
}

/// Uncaught errors would otherwise reach the console only in debug builds, or
/// not at all from async code; these hooks give every one a line with its
/// stack. The lifecycle listener is what explains a "crash" that was really
/// the OS suspending or killing the app.
void _installErrorLogging() {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    Log.e(
      'flutter',
      details.context?.toDescription() ?? 'framework error',
      details.exception,
      details.stack,
    );
    previous?.call(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    Log.e('app', 'uncaught error', error, stack);
    return true;
  };
  AppLifecycleListener(
    onStateChange: (state) => Log.i('app', 'lifecycle ${state.name}'),
  );
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
          home: const InviteDeepLink(child: AppShell()),
        ),
      ),
    );
  }
}
