// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:bcrypt/bcrypt.dart';
import 'models/session_model.dart';
import 'screens/home_screen.dart';
import 'screens/qr_scan_screen.dart';
import 'services/session_service.dart';
import 'services/database_service.dart';
import 'services/api_service.dart';
import 'utils/app_colors.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(
      [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
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
            seedColor: const Color(0xFF020E31), brightness: Brightness.light),
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
    final s = await SessionService.getSession();
    if (mounted)
      setState(() {
        _session = s;
        _loading = false;
      });
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
      await SessionService.saveSession(session);
      await DatabaseService.saveLocalAccount(session);
      if (mounted) setState(() => _session = session);
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Login Screen — 3 ways to log in:
//   Tab 0 (Scan QR)   — camera scan from admin portal
//   Tab 0 (saved)     — one-tap login from previously scanned accounts
//   Tab 1 (Email)     — online: server verify | offline: local bcrypt check
// ─────────────────────────────────────────────────────────────────────────────
class LoginScreen extends StatefulWidget {
  final Future<void> Function(SessionModel) onLogin;
  const LoginScreen({super.key, required this.onLogin});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _passVisible = false;
  bool _loading = false;
  String? _loginError;

  List<Map<String, dynamic>> _saved = [];

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSaved() async {
    final list = await DatabaseService.getLocalAccounts();
    if (mounted) setState(() => _saved = list);
  }

  void _prefillEmailAndSwitch(Map<String, dynamic> account) {
    _emailCtrl.text = account['email'] as String? ?? '';
    _tabs.animateTo(1);
    setState(() {});
  }

  // ── 1. QR scan ────────────────────────────────────────────────────
  Future<void> _scanQr() async {
    final result = await Navigator.push<SessionModel>(
        context, MaterialPageRoute(builder: (_) => const QrScanScreen()));
    if (result == null || !mounted) return;
    setState(() => _loading = true);
    await widget.onLogin(result);
    await _loadSaved();
    if (mounted) setState(() => _loading = false);
  }

  // ── 2. Email + password ────────────────────────────────────────────
  Future<void> _emailLogin() async {
    final email = _emailCtrl.text.trim();
    final password = _passCtrl.text.trim();

    if (email.isEmpty || password.isEmpty) {
      setState(() => _loginError = 'Please enter your email and password.');
      return;
    }

    setState(() {
      _loading = true;
      _loginError = null;
    });

    final connectivity = await Connectivity().checkConnectivity();
    final isOnline = connectivity != ConnectivityResult.none;

    if (isOnline) {
      await _onlineEmailLogin(email, password);
    } else {
      await _offlineEmailLogin(email, password);
    }

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _onlineEmailLogin(String email, String password) async {
    final result =
        await ApiService.loginWithEmail(email: email, password: password);
    if (!mounted) return;

    if (result.ok) {
      final session = SessionModel(
        userId: result.userId ?? 0,
        firstName: result.firstName ?? '',
        accountType: result.accountType ?? '',
        access: result.access ?? 'Mobile',
        email: result.email ?? email,
        passwordHash: _hashForEmail(email),
        fromQr: true,
      );
      await widget.onLogin(session);
      await _loadSaved();
    } else {
      setState(() => _loginError = result.error ?? 'Login failed.');
    }
  }

  Future<void> _offlineEmailLogin(String email, String password) async {
    final stored =
        await DatabaseService.getLocalAccountByEmail(email.toLowerCase());

    if (stored == null) {
      setState(() => _loginError =
          'No saved account for this email. Please scan your QR code first while online.');
      return;
    }

    final storedHash = stored['password_hash'] as String? ?? '';
    if (storedHash.isEmpty) {
      setState(() => _loginError =
          'No password stored locally. Scan QR first while online.');
      return;
    }

    // Verify against stored bcrypt hash using the bcrypt package
    final verified = BCrypt.checkpw(password, storedHash);
    if (!verified) {
      setState(() => _loginError = 'Incorrect password.');
      return;
    }

    final session = SessionModel(
      userId: stored['user_id'] as int,
      firstName: stored['first_name'] as String? ?? '',
      accountType: stored['account_type'] as String? ?? '',
      access: stored['access'] as String? ?? 'Mobile',
      email: stored['email'] as String?,
      passwordHash: storedHash,
      fromQr: true,
    );
    await widget.onLogin(session);
    await _loadSaved();
  }

  /// Returns the locally stored password hash for a given email, if any.
  String? _hashForEmail(String email) {
    for (final a in _saved) {
      if ((a['email'] as String? ?? '').toLowerCase() == email.toLowerCase()) {
        return a['password_hash'] as String?;
      }
    }
    return null;
  }

  // ── 3. One-tap saved account ───────────────────────────────────────
  Future<void> _loginFromSaved(Map<String, dynamic> row) async {
    setState(() {
      _loading = true;
      _loginError = null;
    });
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

  // ──────────────────────────────────────────────────────────────────
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
          child: Column(children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
              child: Column(children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: const BoxDecoration(
                      color: Colors.white, shape: BoxShape.circle),
                  child: const Center(
                      child: Text('🏛️', style: TextStyle(fontSize: 40))),
                ),
                const SizedBox(height: 14),
                const Text('Ormoc City LGU',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4)),
                const SizedBox(height: 4),
                const Text('Government Mobile Portal',
                    style: TextStyle(color: Colors.white60, fontSize: 13)),
              ]),
            ),

            // Tab bar
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                controller: _tabs,
                labelColor: const Color(0xFF020E31),
                unselectedLabelColor: Colors.white70,
                labelStyle:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                indicator: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                padding: const EdgeInsets.all(4),
                dividerColor: Colors.transparent,
                tabs: const [
                  Tab(
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                        Icon(Icons.qr_code_scanner_rounded, size: 16),
                        SizedBox(width: 6),
                        Text('Scan QR'),
                      ])),
                  Tab(
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                        Icon(Icons.email_rounded, size: 16),
                        SizedBox(width: 6),
                        Text('Email Login'),
                      ])),
                ],
              ),
            ),

            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [_buildQrTab(), _buildEmailTab()],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Tab 0: QR ─────────────────────────────────────────────────────
  Widget _buildQrTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _QrScanButton(onTap: _loading ? null : _scanQr),
        if (_saved.isNotEmpty) ...[
          const SizedBox(height: 28),
          const _Label(text: 'SAVED ACCOUNTS — tap to login instantly'),
          const SizedBox(height: 10),
          ..._saved.map((a) => _SavedTile(
                account: a,
                onTap: _loading ? null : () => _loginFromSaved(a),
                onEmail: () => _prefillEmailAndSwitch(a),
              )),
        ],
        const SizedBox(height: 16),
        const Center(
          child: Text(
            'First time? Ask admin to show your QR code.',
            style: TextStyle(color: Colors.white38, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ),
      ]),
    );
  }

  // ── Tab 1: Email / Password ───────────────────────────────────────
  Widget _buildEmailTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _ConnectivityBadge(),
        const SizedBox(height: 20),

        if (_loginError != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(_loginError!,
                      style:
                          const TextStyle(color: Colors.white, fontSize: 13))),
            ]),
          ),
          const SizedBox(height: 16),
        ],

        _inputField(
          controller: _emailCtrl,
          hint: 'Email address',
          icon: Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 12),

        _inputField(
          controller: _passCtrl,
          hint: 'Password',
          icon: Icons.lock_outline_rounded,
          obscure: !_passVisible,
          suffix: IconButton(
            icon: Icon(
              _passVisible
                  ? Icons.visibility_off_rounded
                  : Icons.visibility_rounded,
              color: Colors.white38,
              size: 20,
            ),
            onPressed: () => setState(() => _passVisible = !_passVisible),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ),
        const SizedBox(height: 24),

        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: _loading ? null : _emailLogin,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1D4ED8),
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.white24,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Login',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ),

        const SizedBox(height: 20),

        // Saved account shortcuts for email pre-fill
        if (_saved.isNotEmpty) ...[
          const _Label(text: 'QUICK FILL FROM SAVED ACCOUNTS'),
          const SizedBox(height: 8),
          ..._saved.map((a) {
            final email = a['email'] as String? ?? '';
            final name = a['first_name'] as String? ?? '';
            if (email.isEmpty) return const SizedBox.shrink();
            return GestureDetector(
              onTap: () => setState(() => _emailCtrl.text = email),
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.12)),
                ),
                child: Row(children: [
                  const Icon(Icons.person_outline_rounded,
                      color: Colors.white38, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text('$name — $email',
                          style: const TextStyle(
                              color: Colors.white60, fontSize: 12),
                          overflow: TextOverflow.ellipsis)),
                  const Icon(Icons.north_west_rounded,
                      color: Colors.white30, size: 14),
                ]),
              ),
            );
          }),
        ],

        const SizedBox(height: 16),
        const Center(
          child: Text(
            'Online: password verified by server.\nOffline: uses QR-scanned credential.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.5),
          ),
        ),
      ]),
    );
  }

  Widget _inputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool obscure = false,
    Widget? suffix,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38),
        prefixIcon: Icon(icon, color: Colors.white38, size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.09),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              BorderSide(color: Colors.white.withValues(alpha: 0.35), width: 1),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      ),
    );
  }
}

// ── Connectivity badge ────────────────────────────────────────────────────────
class _ConnectivityBadge extends StatefulWidget {
  @override
  State<_ConnectivityBadge> createState() => _ConnectivityBadgeState();
}

class _ConnectivityBadgeState extends State<_ConnectivityBadge> {
  bool _online = true;

  @override
  void initState() {
    super.initState();
    _check();
    Connectivity().onConnectivityChanged.listen((r) {
      if (mounted) setState(() => _online = r != ConnectivityResult.none);
    });
  }

  Future<void> _check() async {
    final r = await Connectivity().checkConnectivity();
    if (mounted) setState(() => _online = r != ConnectivityResult.none);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _online
            ? const Color(0xFF065F46).withValues(alpha: 0.40)
            : const Color(0xFF78350F).withValues(alpha: 0.40),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _online
              ? Colors.green.withValues(alpha: 0.3)
              : Colors.amber.withValues(alpha: 0.3),
        ),
      ),
      child: Row(children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _online ? const Color(0xFF4ADE80) : const Color(0xFFFBBF24),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _online
                ? 'Online — password verified by server'
                : 'Offline — uses locally stored credential',
            style: TextStyle(
              color:
                  _online ? const Color(0xFFBBF7D0) : const Color(0xFFFEF08A),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ]),
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
      vsync: this, duration: const Duration(milliseconds: 1400))
    ..repeat(reverse: true);
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
                colors: [Color(0xFF1D4ED8), Color(0xFF2563EB)]),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF3B82F6)
                    .withValues(alpha: 0.30 + _pulse.value * 0.22),
                blurRadius: 16 + _pulse.value * 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: child,
        ),
        child: const Column(children: [
          Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 52),
          SizedBox(height: 10),
          Text('Scan QR Code to Login',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
          SizedBox(height: 4),
          Text('Use the QR from the admin portal',
              style: TextStyle(color: Colors.white70, fontSize: 12)),
        ]),
      ),
    );
  }
}

// ── Saved account tile ────────────────────────────────────────────────────────
class _SavedTile extends StatelessWidget {
  final Map<String, dynamic> account;
  final VoidCallback? onTap;
  final VoidCallback? onEmail;
  const _SavedTile({required this.account, this.onTap, this.onEmail});

  @override
  Widget build(BuildContext context) {
    final name = account['first_name'] as String? ?? 'User';
    final role = account['account_type'] as String? ?? '';
    final email = account['email'] as String? ?? '';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        ),
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFF1D4ED8).withValues(alpha: 0.55),
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
              Text(email.isNotEmpty ? email : role,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                  overflow: TextOverflow.ellipsis),
            ],
          )),
          if (email.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.email_outlined,
                  color: Colors.white38, size: 18),
              tooltip: 'Use email login',
              onPressed: onEmail,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          const SizedBox(width: 6),
          const Icon(Icons.qr_code_rounded, color: Color(0xFF6EE7B7), size: 16),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right_rounded,
              color: Colors.white30, size: 20),
        ]),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label({required this.text});
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          color: Colors.white38,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.7));
}
