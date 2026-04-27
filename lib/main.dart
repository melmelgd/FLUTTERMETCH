// lib/main.dart
//
// Login flow:
//   Tab 0 — Scan QR  (stores email + password_hash locally)
//   Tab 0 — Saved accounts  (one-tap login, works offline)
//   Tab 1 — Email + Password
//              Online  → calls login.php  (server bcrypt verify)
//              Offline → looks up stored hash, verifies locally via bcrypt pkg
//              If offline and no saved account → shows clear error, no login
//
// Logo: put your image at assets/images/logo.png (or .jpg)
//       and declare the assets folder in pubspec.yaml.

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

// ─── Change this to match your actual logo file ───────────────────────────────
// Supported: .png / .jpg / .jpeg / .gif / .webp
// File must be inside assets/images/ and declared in pubspec.yaml
const String kLogoAsset = 'assets/images/logo.jpg';

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
    if (mounted) {
      setState(() {
        _session = s;
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
      await SessionService.saveSession(session);
      // Always save/update local account so offline login works next time
      await DatabaseService.saveLocalAccount(session);
      if (mounted) setState(() => _session = session);
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  LOGIN SCREEN
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

  // Email/password
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _passVisible = false;
  bool _loading = false;
  String? _loginError;

  // Connectivity
  bool _isOnline = true;

  // Saved accounts
  List<Map<String, dynamic>> _saved = [];

  @override
  void initState() {
    super.initState();
    _checkConnectivity();
    _loadSaved();

    // Listen for connectivity changes
    Connectivity().onConnectivityChanged.listen((result) {
      if (mounted) {
        setState(
            () => _isOnline = result.any((r) => r != ConnectivityResult.none));
      }
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkConnectivity() async {
    final result = await Connectivity().checkConnectivity();
    if (mounted)
      setState(
          () => _isOnline = result.any((r) => r != ConnectivityResult.none));
  }

  Future<void> _loadSaved() async {
    final list = await DatabaseService.getLocalAccounts();
    if (mounted) setState(() => _saved = list);
  }

  // Pre-fill email field and switch to Email tab
  void _prefillEmail(String email) {
    _emailCtrl.text = email;
    setState(() => _loginError = null);
    _tabs.animateTo(1);
  }

  // ─────────────────────────────────────────────────────────────────
  //  1. QR SCAN
  // ─────────────────────────────────────────────────────────────────
  Future<void> _scanQr() async {
    final result = await Navigator.push<SessionModel>(
        context, MaterialPageRoute(builder: (_) => const QrScanScreen()));
    if (result == null || !mounted) return;
    setState(() {
      _loading = true;
      _loginError = null;
    });
    await widget.onLogin(result);
    await _loadSaved();
    if (mounted) setState(() => _loading = false);
  }

  // ─────────────────────────────────────────────────────────────────
  //  2. ONE-TAP SAVED ACCOUNT (always works offline)
  // ─────────────────────────────────────────────────────────────────
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

  // ─────────────────────────────────────────────────────────────────
  //  3. EMAIL + PASSWORD LOGIN
  //     Online  → server verifies via login.php
  //     Offline → bcrypt verify against locally stored hash
  //     Offline + no saved account → error, cannot login
  // ─────────────────────────────────────────────────────────────────
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

    if (_isOnline) {
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
      // Preserve the locally stored hash (if any) so offline still works
      final existingHash = await _localHashForEmail(email);
      final session = SessionModel(
        userId: result.userId ?? 0,
        firstName: result.firstName ?? '',
        accountType: result.accountType ?? '',
        access: result.access ?? 'Mobile',
        email: result.email ?? email,
        passwordHash:
            existingHash, // keep old QR hash; server doesn't return it
        fromQr: true,
      );
      await widget.onLogin(session);
      await _loadSaved();
    } else {
      setState(() => _loginError = result.error ?? 'Login failed.');
    }
  }

  Future<void> _offlineEmailLogin(String email, String password) async {
    // ── Step 1: look up saved account ────────────────────────────────
    final stored =
        await DatabaseService.getLocalAccountByEmail(email.toLowerCase());

    if (stored == null) {
      setState(() => _loginError = 'No saved account found for this email.\n'
          'You must scan your QR code at least once while online.');
      return;
    }

    final storedHash = stored['password_hash'] as String? ?? '';
    if (storedHash.isEmpty) {
      setState(() => _loginError = 'No password saved for this account.\n'
          'Please scan your QR code while online first.');
      return;
    }

    // ── Step 2: bcrypt verify (same algorithm PHP uses) ───────────────
    bool verified = false;
    try {
      verified = BCrypt.checkpw(password, storedHash);
    } catch (_) {
      setState(() => _loginError = 'Could not verify password locally.');
      return;
    }

    if (!verified) {
      setState(() => _loginError = 'Incorrect password.');
      return;
    }

    // ── Step 3: build session from local data ─────────────────────────
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

  /// Returns the locally stored password hash for an email, or null.
  Future<String?> _localHashForEmail(String email) async {
    final row =
        await DatabaseService.getLocalAccountByEmail(email.toLowerCase());
    return row == null ? null : row['password_hash'] as String?;
  }

  // ─────────────────────────────────────────────────────────────────
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
          child: Column(
            children: [
              // ── Top offline banner ────────────────────────────────
              if (!_isOnline) const _OfflineBanner(),

              // ── Logo + title ──────────────────────────────────────
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 24, 24, 16),
                child: Column(children: [
                  // ── LOGO IMAGE ─────────────────────────────────────
                  // Loads assets/images/logo.png (or .jpg).
                  // Falls back to a placeholder if file not found.
                  _LogoImage(assetPath: kLogoAsset, size: 88),
                  const SizedBox(height: 14),
                  const Text('Ormoc City LGU',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4)),
                  const SizedBox(height: 3),
                  const Text('Government Mobile Portal',
                      style: TextStyle(color: Colors.white60, fontSize: 13)),
                ]),
              ),

              // ── Tab bar ───────────────────────────────────────────
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
                  labelStyle: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13),
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

              // ── Tab content ───────────────────────────────────────
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    _buildQrTab(),
                    _buildEmailTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Tab 0: QR + saved accounts ────────────────────────────────────
  Widget _buildQrTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _QrScanButton(onTap: _loading ? null : _scanQr),
          const SizedBox(height: 24),
          if (_saved.isNotEmpty) ...[
            const _SectionLabel(
                label: 'SAVED ACCOUNTS — tap to login instantly'),
            const SizedBox(height: 8),
            ..._saved.map((a) => _SavedAccountTile(
                  account: a,
                  onTap: _loading ? null : () => _loginFromSaved(a),
                  onUseEmail: (email) => _prefillEmail(email),
                )),
          ],
          const SizedBox(height: 16),
          const Center(
            child: Text(
              'First time? Ask your admin to show your QR code.',
              style: TextStyle(color: Colors.white38, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  // ── Tab 1: Email + password ───────────────────────────────────────
  Widget _buildEmailTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Offline / Online status card ────────────────────────
          _StatusCard(isOnline: _isOnline),
          const SizedBox(height: 20),

          // ── Offline notice: only saved accounts can login ────────
          if (!_isOnline && _saved.isEmpty)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF78350F).withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
              ),
              child: const Row(children: [
                Icon(Icons.wifi_off_rounded,
                    color: Color(0xFFFBBF24), size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'You are offline and have no saved accounts.\n'
                    'Connect to internet or scan your QR code first.',
                    style: TextStyle(
                        color: Color(0xFFFEF08A), fontSize: 12, height: 1.5),
                  ),
                ),
              ]),
            ),

          if (!_isOnline && _saved.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Available offline accounts:',
                    style: TextStyle(
                        color: Colors.white60,
                        fontSize: 11,
                        fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  ..._saved.map((a) {
                    final email = a['email'] as String? ?? '';
                    final name = a['first_name'] as String? ?? '';
                    if (email.isEmpty) return const SizedBox.shrink();
                    return GestureDetector(
                      onTap: () => setState(() => _emailCtrl.text = email),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: const Color(0xFF1D4ED8)
                                  .withValues(alpha: 0.5),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                name.isNotEmpty ? name[0].toUpperCase() : '?',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name,
                                    style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600)),
                                Text(email,
                                    style: const TextStyle(
                                        color: Colors.white38, fontSize: 11),
                                    overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                          const Icon(Icons.north_west_rounded,
                              color: Colors.white30, size: 14),
                        ]),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          // ── Error message ────────────────────────────────────────
          if (_loginError != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline,
                      color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_loginError!,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 13, height: 1.4)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],

          // ── Email field ──────────────────────────────────────────
          _InputField(
            controller: _emailCtrl,
            hint: 'Email address',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 12),

          // ── Password field ───────────────────────────────────────
          _InputField(
            controller: _passCtrl,
            hint: 'Password',
            icon: Icons.lock_outline_rounded,
            obscure: !_passVisible,
            suffix: GestureDetector(
              onTap: () => setState(() => _passVisible = !_passVisible),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Icon(
                  _passVisible
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: Colors.white38,
                  size: 20,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ── Login button ─────────────────────────────────────────
          SizedBox(
            height: 52,
            child: ElevatedButton(
              // Disable button when offline and no saved accounts
              onPressed: (_loading || (!_isOnline && _saved.isEmpty))
                  ? null
                  : _emailLogin,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1D4ED8),
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.white12,
                disabledForegroundColor: Colors.white30,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(
                      _isOnline ? 'Login' : 'Login Offline',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700),
                    ),
            ),
          ),

          const SizedBox(height: 16),
          Center(
            child: Text(
              _isOnline
                  ? 'Online — password verified by server'
                  : 'Offline — only saved accounts can login',
              style: TextStyle(
                  color: _isOnline
                      ? Colors.white38
                      : const Color(0xFFFBBF24).withValues(alpha: 0.7),
                  fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

/// Loads logo from assets. Shows placeholder shield if asset not found.
class _LogoImage extends StatelessWidget {
  final String assetPath;
  final double size;
  const _LogoImage({required this.assetPath, required this.size});

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: Image.asset(
        assetPath,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) {
          // Fallback placeholder when asset is missing
          return Container(
            width: size,
            height: size,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Icon(Icons.account_balance_rounded,
                  color: AppColors.primary, size: size * 0.55),
            ),
          );
        },
      ),
    );
  }
}

/// Red offline banner at the very top of the screen.
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFF7F1D1D),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_off_rounded, color: Colors.white70, size: 14),
          SizedBox(width: 6),
          Text(
            'OFFLINE MODE — Only saved accounts can login',
            style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3),
          ),
        ],
      ),
    );
  }
}

/// Online/offline status card shown at the top of the Email tab.
class _StatusCard extends StatelessWidget {
  final bool isOnline;
  const _StatusCard({required this.isOnline});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isOnline
            ? const Color(0xFF065F46).withValues(alpha: 0.40)
            : const Color(0xFF7F1D1D).withValues(alpha: 0.60),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isOnline
              ? Colors.green.withValues(alpha: 0.3)
              : Colors.red.withValues(alpha: 0.4),
        ),
      ),
      child: Row(children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isOnline ? const Color(0xFF4ADE80) : const Color(0xFFFC8181),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isOnline ? 'Online' : 'Offline',
                style: TextStyle(
                  color: isOnline
                      ? const Color(0xFFBBF7D0)
                      : const Color(0xFFFCA5A5),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                isOnline
                    ? 'Password will be verified by the server.'
                    : 'Only accounts saved from a previous QR scan can login.',
                style: TextStyle(
                  color: isOnline
                      ? const Color(0xFFBBF7D0).withValues(alpha: 0.7)
                      : const Color(0xFFFCA5A5).withValues(alpha: 0.8),
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        Icon(
          isOnline ? Icons.cloud_done_rounded : Icons.wifi_off_rounded,
          color: isOnline ? const Color(0xFF4ADE80) : const Color(0xFFFC8181),
          size: 20,
        ),
      ]),
    );
  }
}

/// Animated QR scan button.
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
                    .withValues(alpha: 0.28 + _pulse.value * 0.22),
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

/// Saved account tile with one-tap login + email pre-fill shortcut.
class _SavedAccountTile extends StatelessWidget {
  final Map<String, dynamic> account;
  final VoidCallback? onTap;
  final void Function(String email) onUseEmail;

  const _SavedAccountTile({
    required this.account,
    this.onTap,
    required this.onUseEmail,
  });

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
          border: Border.all(color: Colors.white.withValues(alpha: 0.13)),
        ),
        child: Row(children: [
          // Avatar
          Container(
            width: 44,
            height: 44,
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
          // Info
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
                style: TextStyle(color: Colors.white54, fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          )),
          // Email shortcut
          if (email.isNotEmpty)
            GestureDetector(
              onTap: () => onUseEmail(email),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.email_outlined,
                    color: Colors.white54, size: 16),
              ),
            ),
          const SizedBox(width: 8),
          const Icon(Icons.qr_code_rounded, color: Color(0xFF6EE7B7), size: 15),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right_rounded,
              color: Colors.white30, size: 20),
        ]),
      ),
    );
  }
}

/// Reusable text input field.
class _InputField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final TextInputType keyboardType;
  final bool obscure;
  final Widget? suffix;

  const _InputField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.keyboardType = TextInputType.text,
    this.obscure = false,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
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

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});
  @override
  Widget build(BuildContext context) => Text(label,
      style: const TextStyle(
          color: Colors.white38,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8));
}
