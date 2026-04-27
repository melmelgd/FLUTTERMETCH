// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'models/session_model.dart';
import 'screens/home_screen.dart';
import 'screens/qr_scan_screen.dart';
import 'services/session_service.dart';
import 'services/database_service.dart';
import 'utils/app_colors.dart';

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

// ─────────────────────────────────────────────────────────────────────────────
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

    return LoginScreen(onLogin: (session) async {
      // Save session + save to local accounts table for offline re-login
      await SessionService.saveSession(session);
      if (session.fromQr) {
        await DatabaseService.saveLocalAccount(session);
      }
      if (mounted) setState(() => _session = session);
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Login Screen
// ─────────────────────────────────────────────────────────────────────────────
class LoginScreen extends StatefulWidget {
  final Future<void> Function(SessionModel) onLogin;

  const LoginScreen({super.key, required this.onLogin});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _loading = false;
  bool _showManual = false;

  // Stored accounts from previous QR scans (for offline login picker)
  List<Map<String, dynamic>> _storedAccounts = [];

  final _nameCtrl = TextEditingController(text: 'Juan Dela Cruz');
  final _idCtrl = TextEditingController(text: '1001');
  final _deptCtrl = TextEditingController(text: 'Staff');

  @override
  void initState() {
    super.initState();
    _loadStoredAccounts();
  }

  Future<void> _loadStoredAccounts() async {
    final accounts = await DatabaseService.getLocalAccounts();
    if (mounted) setState(() => _storedAccounts = accounts);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _idCtrl.dispose();
    _deptCtrl.dispose();
    super.dispose();
  }

  // ── QR scan ─────────────────────────────────────────────────────
  Future<void> _scanQr() async {
    final result = await Navigator.push<SessionModel>(
      context,
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );
    if (result == null || !mounted) return;

    setState(() => _loading = true);
    await widget.onLogin(result);
    if (mounted) setState(() => _loading = false);
  }

  // ── Re-login from stored account ─────────────────────────────────
  Future<void> _loginFromStored(Map<String, dynamic> row) async {
    setState(() => _loading = true);
    final session = SessionModel(
      userId: row['user_id'] as int,
      firstName: row['first_name'] as String? ?? '',
      accountType: row['account_type'] as String? ?? '',
      access: row['access'] as String? ?? 'Mobile',
      email: row['email'] as String?,
      passwordHash: row['password_hash'] as String?,
      fromQr: true,
    );
    await widget.onLogin(session);
    if (mounted) setState(() => _loading = false);
  }

  // ── Manual / demo login ──────────────────────────────────────────
  Future<void> _manualLogin() async {
    setState(() => _loading = true);
    final session = SessionModel(
      userId: int.tryParse(_idCtrl.text.trim()) ?? 0,
      firstName: _nameCtrl.text.trim().isEmpty ? 'User' : _nameCtrl.text.trim(),
      accountType:
          _deptCtrl.text.trim().isEmpty ? 'Staff' : _deptCtrl.text.trim(),
      access: 'Mobile',
      fromQr: false,
    );
    await widget.onLogin(session);
    if (mounted) setState(() => _loading = false);
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Logo ──────────────────────────────────────────
                Center(
                  child: Container(
                    width: 90,
                    height: 90,
                    decoration: const BoxDecoration(
                        color: Colors.white, shape: BoxShape.circle),
                    child: const Center(
                        child: Text('🏛️', style: TextStyle(fontSize: 44))),
                  ),
                ),
                const SizedBox(height: 20),
                const Center(
                  child: Text('Ormoc City LGU',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5)),
                ),
                const SizedBox(height: 4),
                const Center(
                  child: Text('Government Mobile Portal',
                      style: TextStyle(color: Colors.white60, fontSize: 14)),
                ),
                const SizedBox(height: 44),

                // ── Primary: QR Scan button ───────────────────────
                _QrScanButton(onTap: _loading ? null : _scanQr),

                // ── Stored accounts (offline re-login) ────────────
                if (_storedAccounts.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const _SectionLabel(label: 'SAVED ACCOUNTS'),
                  const SizedBox(height: 10),
                  ..._storedAccounts
                      .map((a) => _StoredAccountTile(
                            account: a,
                            onTap: _loading ? null : () => _loginFromStored(a),
                          ))
                      .toList(),
                ],

                // ── Manual fallback ───────────────────────────────
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: () => setState(() => _showManual = !_showManual),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _showManual
                            ? 'Hide manual login'
                            : 'Continue without QR (demo)',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 13),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        _showManual
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        color: Colors.white54,
                        size: 18,
                      ),
                    ],
                  ),
                ),

                if (_showManual) ...[
                  const SizedBox(height: 16),
                  _field(_nameCtrl, 'Full Name'),
                  const SizedBox(height: 10),
                  _field(_idCtrl, 'User ID', isNumber: true),
                  const SizedBox(height: 10),
                  _field(_deptCtrl, 'Department / Account Type'),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: _loading ? null : _manualLogin,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white30, width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Enter as Demo User',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 10),
                  const Center(
                    child: Text('⚠ Demo mode — not verified against server.',
                        style: TextStyle(color: Colors.white38, fontSize: 11)),
                  ),
                ],

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String hint,
      {bool isNumber = false}) {
    return TextField(
      controller: ctrl,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.09),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}

// ── QR scan hero button ───────────────────────────────────────────────────────
class _QrScanButton extends StatefulWidget {
  final VoidCallback? onTap;

  const _QrScanButton({this.onTap});

  @override
  State<_QrScanButton> createState() => _QrScanButtonState();
}

class _QrScanButtonState extends State<_QrScanButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (_, child) => Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1D4ED8), Color(0xFF2563EB)],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF3B82F6)
                    .withValues(alpha: 0.32 + _pulse.value * 0.22),
                blurRadius: 16 + _pulse.value * 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(vertical: 22),
          child: child,
        ),
        child: const Column(
          children: [
            Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 52),
            SizedBox(height: 10),
            Text('Scan QR Code to Login',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700)),
            SizedBox(height: 4),
            Text('Use the QR from the admin portal',
                style: TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

// ── Stored account tile ───────────────────────────────────────────────────────
class _StoredAccountTile extends StatelessWidget {
  final Map<String, dynamic> account;
  final VoidCallback? onTap;

  const _StoredAccountTile({required this.account, this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = account['first_name'] as String? ?? 'User';
    final role = account['account_type'] as String? ?? '';
    final email = account['email'] as String? ?? '';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF1D4ED8).withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 18),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(
                    email.isNotEmpty ? email : role,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.qr_code_rounded,
                color: Color(0xFF6EE7B7), size: 18),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded,
                color: Colors.white38, size: 20),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;

  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
          color: Colors.white38,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8),
    );
  }
}
