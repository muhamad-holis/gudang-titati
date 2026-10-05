import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import 'config.dart';
import 'screens/auth.dart';
import 'state.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (cloudReady) {
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseKey);
  }
  runApp(ChangeNotifierProvider(create: (_) => AppState(), child: const MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GUDANG TITATI',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: cloudReady ? const AuthGate() : const SetupMissingPage(),
    );
  }
}

class SetupMissingPage extends StatelessWidget {
  const SetupMissingPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: navy,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: const Text(
              'Aplikasi belum terhubung ke server.\n\nIsi GitHub Secrets SUPABASE_URL dan SUPABASE_ANON_KEY, lalu build ulang APK.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
