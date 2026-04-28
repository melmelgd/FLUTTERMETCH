import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import 'models/session_model.dart';
import 'screens/home_screen.dart';
import 'screens/qr_scanner_screen.dart';
import 'services/session_service.dart';
import 'services/theme_service.dart';
import 'utils/app_colors.dart';
import 'utils/toast_helper.dart';
import 'package:provider/provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kIsWeb) {
    databaseFactory = databaseFactoryFfiWeb;
  } else if (defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS) {
    databaseFactory = databaseFactoryFfi;
  }

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeService(),
      child: const LguMobileApp(),
    ),
  );
}

class LguMobileApp extends StatelessWidget {
  const LguMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeService = Provider.of<ThemeService>(context);
    return MaterialApp(
      title: 'Ormoc LGU',
      debugShowCheckedModeBanner: false,
      themeMode: themeService.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: AppColors.bg,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0F172A),
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
    if (!mounted) return;
    setState(() {
      _session = session;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppColors.primary,
        body: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    if (_session != null) return const HomeScreen();

    return _LoginScreen(
      onLogin: (session, rememberMe) async {
        if (rememberMe) {
          await SessionService.saveSession(session);
        } else {
          await SessionService.clearSession();
        }

        if (mounted) {
          setState(() => _session = session);
        }
      },
    );
  }
}

class _LoginScreen extends StatefulWidget {
  final Future<void> Function(SessionModel, bool rememberMe) onLogin;

  const _LoginScreen({required this.onLogin});

  @override
  State<_LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<_LoginScreen> {
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _loading = false;
  bool _rememberMe = true;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final input = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (input.isEmpty) {
      showToast(
        context,
        'Please enter your username.',
        type: ToastType.error,
      );
      return;
    }

    if (password.isEmpty) {
      showToast(
        context,
        'Please enter your password.',
        type: ToastType.error,
      );
      return;
    }

    setState(() => _loading = true);

    try {
      String displayName;
      String email;

      if (input.contains('@')) {
        email = input;
        displayName = _formatDisplayName(input.split('@')[0]);
      } else {
        displayName = _formatDisplayName(input);
        email = '${input.toLowerCase().replaceAll(' ', '.')}@ormoc.gov.ph';
      }

      final numericId = RegExp(r'\d+').firstMatch(input)?.group(0);
      final session = SessionModel(
        userId: int.tryParse(numericId ?? '') ?? 1001,
        firstName: displayName,
        email: email,
        accountType: 'Event Staff',
        access: 'Mobile',
      );
      await widget.onLogin(session, _rememberMe);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _scanLoginQr() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => QrScannerScreen(
          onScanned: (code) async {
            // In a real app, you'd validate the code with an API
            // Here we just simulate a login if any code is scanned
            return true;
          },
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() => _loading = true);
      try {
        SessionModel session;
        try {
          // Attempt to parse result as JSON
          final data = jsonDecode(result) as Map<String, dynamic>;
          session = SessionModel(
            userId: int.tryParse(data['user_id']?.toString() ?? '') ??
                int.tryParse(data['id']?.toString() ?? '') ??
                2002,
            firstName: data['full_name'] ??
                data['fullName'] ??
                data['name'] ??
                data['first_name'] ??
                'User',
            email: data['email'],
            accountType: data['account_type'] ?? 'Event Staff',
            access: 'Mobile',
          );
        } catch (_) {
          // Fallback if not JSON (original logic)
          final namePart = result.contains('@') ? result.split('@')[0] : result;
          session = SessionModel(
            userId: 2002,
            firstName: _formatDisplayName(namePart),
            email: result.contains('@') ? result : '$result@ormoc.gov.ph',
            accountType: 'Event Staff',
            access: 'Mobile',
          );
        }
        await widget.onLogin(session, _rememberMe);
      } finally {
        if (mounted) {
          setState(() => _loading = false);
        }
      }
    }
  }

  String _formatDisplayName(String username) {
    // Remove numbers at the end of the name (e.g., ludybongconag0 -> ludybongconag)
    String cleaned = username.replaceAll(RegExp(r'\d+$'), '');

    cleaned = cleaned
        .replaceAll(RegExp(r'[._-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (cleaned.isEmpty) return 'User';

    return cleaned
        .split(' ')
        .map(
          (part) => part.isEmpty
              ? part
              : '${part[0].toUpperCase()}${part.substring(1)}',
        )
        .join(' ');
  }

  void _showHelpMessage(String label) {
    showToast(
      context,
      '$label is not available in this demo yet.',
      type: ToastType.info,
    );
  }

  Widget _buildFieldLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white70,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscureText = false,
    TextInputAction textInputAction = TextInputAction.next,
    Iterable<String>? autofillHints,
    Widget? suffixIcon,
    VoidCallback? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      textInputAction: textInputAction,
      autofillHints: autofillHints,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w500,
      ),
      cursorColor: Colors.white,
      onSubmitted: (_) => onSubmitted?.call(),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
          color: Colors.white38,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        prefixIcon: Icon(icon, color: Colors.white54, size: 20),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: Colors.white.withOpacity(0.08),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: Colors.white.withOpacity(0.08),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: Colors.white.withOpacity(0.10),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF4F8DFF)),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
    );
  }

  Widget _buildBrandHeader() {
    return Column(
      children: [
        Container(
          width: 70, // Reduced from 86
          height: 70, // Reduced from 86
          padding: const EdgeInsets.all(12), // Increased padding to shrink logo inside
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.98),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.28),
                blurRadius: 26,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: ClipOval(
            child: Image.asset(
              'lib/assets/images/EM.png',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.location_city,
                color: AppColors.primary,
                size: 38,
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'City of Ormoc',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Event Management System',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withOpacity(0.78),
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildFooterLink(String label) {
    return TextButton(
      onPressed: () => _showHelpMessage(label),
      style: TextButton.styleFrom(
        foregroundColor: Colors.white60,
        padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          decoration: TextDecoration.underline,
          decorationColor: Colors.white38,
        ),
      ),
    );
  }

  Widget _buildLoginCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(26, 28, 26, 24),
      decoration: BoxDecoration(
        color: const Color(0xFF314565).withOpacity(0.90),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.22),
            blurRadius: 28,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Align(
            child: Text(
              'Welcome Back',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            child: Text(
              'Sign in to continue',
              style: TextStyle(
                color: Colors.white.withOpacity(0.62),
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 24),
          _buildFieldLabel('Username'),
          const SizedBox(height: 8),
          _buildTextField(
            controller: _usernameCtrl,
            hint: 'Enter your username',
            icon: Icons.person_outline_rounded,
            autofillHints: const [AutofillHints.username],
          ),
          const SizedBox(height: 16),
          _buildFieldLabel('Password'),
          const SizedBox(height: 8),
          _buildTextField(
            controller: _passwordCtrl,
            hint: 'Enter your password',
            icon: Icons.lock_outline_rounded,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.password],
            onSubmitted: _login,
            suffixIcon: IconButton(
              onPressed: () {
                setState(() => _obscurePassword = !_obscurePassword);
              },
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: Colors.white54,
                size: 20,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              InkWell(
                onTap: () => setState(() => _rememberMe = !_rememberMe),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: _rememberMe
                              ? const Color(0xFF3A74F7)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: _rememberMe
                                ? const Color(0xFF3A74F7)
                                : Colors.white38,
                          ),
                        ),
                        child: _rememberMe
                            ? const Icon(
                                Icons.check,
                                size: 14,
                                color: Colors.white,
                              )
                            : null,
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Remember me',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => _showHelpMessage('Password recovery'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF73A9FF),
                  padding: const EdgeInsets.symmetric(horizontal: 0),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Forgot Password?',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _loading ? null : _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3568E6),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        const Color(0xFF3568E6).withOpacity(0.65),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Sign In',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(width: 10),
                            Icon(Icons.arrow_forward_rounded, size: 20),
                          ],
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Material(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  onTap: _loading ? null : _scanLoginQr,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    width: 56,
                    height: 56,
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.qr_code_scanner_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF10284D),
              Color(0xFF17335B),
              Color(0xFF112A4B),
            ],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -140,
              left: -80,
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.05),
                ),
              ),
            ),
            Positioned(
              right: -110,
              bottom: 90,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.03),
                ),
              ),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 18,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight - 36,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildBrandHeader(),
                          const SizedBox(height: 30),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 420),
                            child: _buildLoginCard(),
                          ),
                          const SizedBox(height: 28),
                          Text(
                            '(c) 2026 City of Ormoc. All rights reserved.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.45),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            alignment: WrapAlignment.center,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            children: [
                              _buildFooterLink('Privacy Policy'),
                              Text(
                                '|',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.28),
                                  fontSize: 12,
                                ),
                              ),
                              _buildFooterLink('Terms of Service'),
                              Text(
                                '|',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.28),
                                  fontSize: 12,
                                ),
                              ),
                              _buildFooterLink('Help'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
