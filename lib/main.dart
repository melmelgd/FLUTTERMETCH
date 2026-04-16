import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'models/session_model.dart';
import 'screens/home_screen.dart';
import 'services/session_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const LguMobileApp());
}

class LguMobileApp extends StatelessWidget {
  const LguMobileApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ormoc LGU',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF020E31),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF3F4F6),
      ),
      home: const AppRouter(),
    );
  }
}

class AppRouter extends StatefulWidget {
  const AppRouter({super.key});
  @override
  State<AppRouter> createState() => _AppRouterState();
}

class _AppRouterState extends State<AppRouter> {
  bool _loading = true;
  SessionModel? _session;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = await SessionService.getSession();
    if (mounted) {
      setState(() {
        _session = session;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFF020E31),
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }
    if (_session != null) return const HomeScreen();
    return _DemoLoginScreen(onLogin: (session) async {
      await SessionService.saveSession(session);
      if (mounted) setState(() => _session = session);
    });
  }
}

class _DemoLoginScreen extends StatefulWidget {
  final Future<void> Function(SessionModel) onLogin;
  const _DemoLoginScreen({required this.onLogin});
  @override
  State<_DemoLoginScreen> createState() => _DemoLoginScreenState();
}

class _DemoLoginScreenState extends State<_DemoLoginScreen> {
  final _nameCtrl = TextEditingController(text: 'Juan Dela Cruz');
  final _idCtrl = TextEditingController(text: '1001');
  final _deptCtrl = TextEditingController(text: 'Employee');
  bool _loading = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _idCtrl.dispose();
    _deptCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() => _loading = true);
    final session = SessionModel(
      userId: int.tryParse(_idCtrl.text) ?? 0,
      firstName: _nameCtrl.text.trim().isEmpty ? 'User' : _nameCtrl.text.trim(),
      accountType:
          _deptCtrl.text.trim().isEmpty ? 'Employee' : _deptCtrl.text.trim(),
      access: 'Mobile',
    );
    await widget.onLogin(session);
    if (mounted) setState(() => _loading = false);
  }

  Widget _field(TextEditingController ctrl, String hint,
      {bool isNumber = false}) {
    return TextField(
      controller: ctrl,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      style: const TextStyle(color: Colors.white, fontSize: 16),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF020E31), Color(0xFF04185B)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: const BoxDecoration(
                      color: Colors.white, shape: BoxShape.circle),
                  child: const Center(
                      child: Text('🏛️', style: TextStyle(fontSize: 40))),
                ),
                const SizedBox(height: 20),
                const Text('Ormoc City LGU',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800)),
                const Text('Government Mobile Portal',
                    style: TextStyle(color: Colors.white60, fontSize: 14)),
                const SizedBox(height: 40),
                _field(_nameCtrl, 'First Name'),
                const SizedBox(height: 12),
                _field(_idCtrl, 'User ID', isNumber: true),
                const SizedBox(height: 12),
                _field(_deptCtrl, 'Account Type / Department'),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF020E31),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Enter Portal',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Demo mode — enter any values to test the app.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white38, fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
