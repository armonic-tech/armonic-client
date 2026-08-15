import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'l10n/app_strings.dart';
import 'screens/home_screen.dart';
import 'state/instance_store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ArmonicApp());
}

class ArmonicApp extends StatelessWidget {
  const ArmonicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => InstanceStore()..load(),
      child: MaterialApp(
        title: strings.appTitle,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          colorSchemeSeed: const Color(0xFF10B981),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
