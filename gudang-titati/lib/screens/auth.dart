import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState, AuthException;
import '../state.dart';
import '../theme.dart';
import 'shell.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: sb.auth.onAuthStateChange,
      builder: (c, snap) {
        final session = sb.auth.currentSession;
        if (session == null) return const LoginPage();
        return HomeShell(key: ValueKey(session.user.id));
      },
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController();
  final pass = TextEditingController();
  bool loading = false;
  String? error;

  @override
  void dispose() {
    email.dispose();
    pass.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await sb.auth.signInWithPassword(email: email.text.trim(), password: pass.text);
    } on AuthException {
      error = 'Email atau password salah';
    } catch (_) {
      error = 'Tidak bisa terhubung. Periksa internet.';
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: navy,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Icon(Icons.warehouse_outlined, size: 48, color: navy),
                const SizedBox(height: 6),
                const Text('GUDANG TITATI', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: navy)),
                Text('Bakso TITATI Wonogiri Opik Jon', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[700])),
                const SizedBox(height: 18),
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: pass,
                  obscureText: true,
                  onSubmitted: (_) => _login(),
                  decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
                ),
                if (error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(error!, style: const TextStyle(color: red))),
                const SizedBox(height: 16),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: blue, minimumSize: const Size.fromHeight(50)),
                  onPressed: loading ? null : _login,
                  child: loading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Masuk'),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
