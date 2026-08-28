import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'l10n/app_strings.dart';
import 'screens/app_shell.dart';
import 'state/instance_store.dart';
import 'state/session_manager.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    BrowserContextMenu.disableContextMenu();
  }
  runApp(const ArmonicApp());
}

class ArmonicApp extends StatelessWidget {
  const ArmonicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => InstanceStore()..bootstrap()),
        // Above the shell on purpose: sessions (and the call one of them may
        // hold) must outlive whichever instance screen is on display.
        ChangeNotifierProvider(
          create: (context) => SessionManager(
            onSessionExpired: (baseUrl) =>
                context.read<InstanceStore>().clearToken(baseUrl),
          ),
        ),
      ],
      child: MaterialApp(
        title: strings.appTitle,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          colorSchemeSeed: const Color(0xFF10B981),
          useMaterial3: true,
        ),
        home: const AppShell(),
      ),
    );
  }
}
