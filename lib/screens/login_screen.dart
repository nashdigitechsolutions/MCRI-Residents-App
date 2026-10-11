import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../widgets/app_button.dart';
import '../widgets/app_text_field.dart';
import '../widgets/password_field.dart';
import 'signup_screen.dart';
import 'forgot_password_screen.dart';

final _emailRegex = RegExp(r'^[^\s@]+@([^\s@.,]+\.)+[^\s@.,]{2,}$');

const _ink = Color(0xFF0A0A0A);
const _accent = Color(0xFF3355FF);
const _sheet = Color(0xFFF7F6F3);
const _muted = Color(0xFF6B7280);

// Keys inside the dedicated biometric store
const _kBioEnabled = 'bio_enabled';
const _kBioDeclined = 'bio_declined';
const _kBioEmail = 'bio_email';
const _kBioPassword = 'bio_password';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  // A separate store (own Android prefs file / iOS account name) so that a
  // storage.deleteAll() in AuthProvider.logout() cannot wipe the biometric
  // credentials.
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      sharedPreferencesName: 'mcri_biometric_store',
      preferencesKeyPrefix: 'mcri_bio_',
    ),
    iOptions: IOSOptions(accountName: 'mcri_biometric_store'),
  );
  final _localAuth = LocalAuthentication();

  bool _submitting = false;
  String? _error;
  bool _needsVerification = false;
  bool _failedAttempt = false;

  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  bool _usePassword = false; // user chose "use password / another account"
  String? _savedEmail;

  bool get _showBiometricView =>
      _biometricAvailable && _biometricEnabled && !_usePassword;

  @override
  void initState() {
    super.initState();
    _initBiometrics();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ───────────────────────── Biometrics ─────────────────────────

  Future<void> _initBiometrics() async {
    try {
      final supported = await _localAuth.isDeviceSupported();
      final canCheck = await _localAuth.canCheckBiometrics;
      final enabled = (await _storage.read(key: _kBioEnabled)) == 'true';
      final email = await _storage.read(key: _kBioEmail);
      final hasPassword = (await _storage.read(key: _kBioPassword)) != null;

      debugPrint(
        '[bio] supported=$supported canCheck=$canCheck '
        'enabled=$enabled hasEmail=${email != null} '
        'hasPassword=$hasPassword',
      );

      if (!mounted) return;
      final usable = enabled && email != null && hasPassword;
      setState(() {
        _biometricAvailable = supported && canCheck;
        _biometricEnabled = usable;
        _savedEmail = email;
      });

      if (_showBiometricView) {
        // Wait for the first frame / route transition before prompting;
        // some Android devices drop the prompt if it fires too early.
        await Future<void>.delayed(const Duration(milliseconds: 450));
        if (mounted && _showBiometricView) _handleBiometricLogin();
      }
    } catch (e) {
      debugPrint('[bio] init failed: $e');
    }
  }

  Future<void> _handleBiometricLogin() async {
    if (_submitting) return;
    try {
      final ok = await _localAuth.authenticate(
        localizedReason: 'Sign in to your portal',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
      debugPrint('[bio] authenticate result=$ok');
      if (!ok) return;

      final email = await _storage.read(key: _kBioEmail);
      final password = await _storage.read(key: _kBioPassword);
      if (email == null || password == null) {
        await _clearBiometricCreds();
        if (mounted) {
          setState(() {
            _biometricEnabled = false;
            _error = 'Saved credentials not found. Please sign in again.';
          });
        }
        return;
      }
      await _performLogin(email, password, fromBiometric: true);
    } catch (e) {
      debugPrint('[bio] authenticate failed: $e');
      if (mounted) {
        setState(() => _error = 'Biometric authentication unavailable.');
      }
    }
  }

  Future<void> _clearBiometricCreds() async {
    await _storage.delete(key: _kBioEmail);
    await _storage.delete(key: _kBioPassword);
    await _storage.write(key: _kBioEnabled, value: 'false');
  }

  /// Asked BEFORE logging in: a successful login swaps this screen out
  /// (main.dart watches AuthProvider), so no dialog could be shown after.
  Future<bool> _askToEnableBiometric({required bool replacing}) async {
    if (!_biometricAvailable) return false;
    if (_biometricEnabled && !replacing) return false;
    if ((await _storage.read(key: _kBioDeclined)) == 'true') return false;
    if (!mounted) return false;

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          replacing
              ? 'Switch biometric sign-in to this account?'
              : 'Use biometrics next time?',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'Sign in faster with your fingerprint or face. Your details are '
          'stored encrypted on this device only.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'never'),
            child: const Text("Don't ask again"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'no'),
            child: const Text('Not now'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _ink),
            onPressed: () => Navigator.pop(ctx, 'yes'),
            child: const Text('Enable'),
          ),
        ],
      ),
    );

    if (result == 'never') {
      await _storage.write(key: _kBioDeclined, value: 'true');
    }
    if (result != 'yes') return false;

    try {
      final ok = await _localAuth.authenticate(
        localizedReason: 'Confirm to enable biometric sign-in',
        biometricOnly: true,
      );
      debugPrint('[bio] enable-confirm result=$ok');
      return ok;
    } catch (e) {
      debugPrint('[bio] enable-confirm failed: $e');
      return false;
    }
  }

  // ───────────────────────── Login ─────────────────────────

  Future<void> _handleGoogleLogin() async {
    final uri = Uri.parse('https://api.mcriresidents.online/api/auth/google');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _handleSubmit() async {
    setState(() {
      _error = null;
      _needsVerification = false;
      _failedAttempt = false;
    });

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (!_emailRegex.hasMatch(email)) {
      setState(() => _error = 'Enter a valid email address');
      return;
    }
    if (password.isEmpty) {
      setState(() => _error = 'Password is required');
      return;
    }

    final replacing =
        _biometricEnabled &&
        email.toLowerCase() != (_savedEmail ?? '').toLowerCase();
    final saveBiometric = await _askToEnableBiometric(replacing: replacing);
    await _performLogin(email, password, saveBiometric: saveBiometric);
  }

  Future<void> _performLogin(
    String email,
    String password, {
    bool saveBiometric = false,
    bool fromBiometric = false,
  }) async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final auth = context.read<AuthProvider>();
      await auth.login(email, password);

      // Triggers the OS "Save password?" prompt (Samsung Pass / Google /
      // iCloud Keychain); the user can accept or decline there.
      TextInput.finishAutofillContext(shouldSave: true);

      if (saveBiometric) {
        try {
          await _storage.write(key: _kBioEmail, value: email);
          await _storage.write(key: _kBioPassword, value: password);
          await _storage.write(key: _kBioEnabled, value: 'true');
          debugPrint('[bio] credentials saved');
        } catch (e) {
          debugPrint('[bio] save failed: $e');
        }
      }
      // No navigation needed — main.dart swaps to MainShell automatically.
    } on ApiException catch (e) {
      TextInput.finishAutofillContext(shouldSave: false);
      if (!mounted) return;
      if (e.statusCode == 403) {
        setState(() => _needsVerification = true);
      } else {
        setState(() {
          _error = e.message;
          _failedAttempt = true;
        });
        // Saved password is stale (changed elsewhere): drop it.
        if (fromBiometric && e.statusCode == 401) {
          await _clearBiometricCreds();
          if (mounted) {
            setState(() {
              _biometricEnabled = false;
              _usePassword = true;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('[login] failed: $e');
      if (mounted) {
        setState(() => _error = 'Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ───────────────────────── UI ─────────────────────────

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    final heroHeight = topInset + (_showBiometricView ? 250.0 : 230.0);

    return Scaffold(
      backgroundColor: _ink,
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Column(
              children: [
                _buildHero(heroHeight, topInset),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - heroHeight,
                  ),
                  child: Container(
                    width: double.infinity,
                    padding: EdgeInsets.fromLTRB(
                      24,
                      28,
                      24,
                      28 + MediaQuery.of(context).padding.bottom,
                    ),
                    decoration: const BoxDecoration(
                      color: _sheet,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(32),
                      ),
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          child: KeyedSubtree(
                            key: ValueKey(
                              '$_showBiometricView$_needsVerification',
                            ),
                            child: _needsVerification
                                ? _buildVerificationNotice()
                                : _showBiometricView
                                ? _buildBiometricView()
                                : _buildForm(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHero(double height, double topInset) {
    final bio = _showBiometricView;
    return Container(
      height: height,
      width: double.infinity,
      padding: EdgeInsets.only(top: topInset),
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0.9, -1.0),
          radius: 1.3,
          colors: [Color(0xFF1C2B73), _ink],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            height: 76,
            width: 76,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Image.asset(
              'lib/assets/logo.png',
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const Center(
                child: Text(
                  'M',
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            bio ? 'Welcome back' : 'Sign in to your portal',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            bio
                ? 'Verify it\u2019s you to continue.'
                : 'Welcome back! Please enter your details.',
            style: TextStyle(
              fontSize: 13.5,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBiometricView() {
    final email = _savedEmail ?? '';
    final initial = email.isNotEmpty ? email[0].toUpperCase() : '?';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Saved account chip
        Container(
          padding: const EdgeInsets.fromLTRB(8, 8, 18, 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: _ink,
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  email,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        Material(
          color: _ink,
          shape: const CircleBorder(),
          elevation: 8,
          shadowColor: _accent.withValues(alpha: 0.4),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: _submitting ? null : _handleBiometricLogin,
            child: SizedBox(
              height: 84,
              width: 84,
              child: _submitting
                  ? const Padding(
                      padding: EdgeInsets.all(28),
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(
                      Icons.fingerprint,
                      size: 42,
                      color: Colors.white,
                    ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Tap to unlock',
          style: TextStyle(fontSize: 13, color: _muted),
        ),
        if (_error != null) ...[const SizedBox(height: 16), _errorBox()],
        const SizedBox(height: 28),
        TextButton(
          onPressed: () => setState(() {
            _usePassword = true;
            _error = null;
          }),
          child: const Text(
            'Use password or another account',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: _accent,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVerificationNotice() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFBEB),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFFDE68A)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.error_outline, size: 18, color: Color(0xFFB45309)),
                  SizedBox(width: 8),
                  Text(
                    'Email verification required',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF78350F),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                "Your account exists, but your email hasn't been verified yet. Check your inbox for the verification link we sent.",
                style: TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFF92400E),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const SignupScreen())),
                child: const Text(
                  'Need a new link? Go to signup',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF78350F),
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => setState(() => _needsVerification = false),
          child: const Text('Back to sign in'),
        ),
      ],
    );
  }

  Widget _errorBox() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _error!,
            style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13),
          ),
          if (_failedAttempt) ...[
            const SizedBox(height: 4),
            GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
              ),
              child: const Text(
                'Reset your password',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFDC2626),
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildForm() {
    // AutofillGroup + autofillHints lets Samsung Pass, Google Autofill and
    // iCloud Keychain offer saved logins and the save prompt.
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppTextField(
            label: 'Email',
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            icon: Icons.mail_outline,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.username, AutofillHints.email],
          ),
          const SizedBox(height: 14),
          AppPasswordField(
            controller: _passwordController,
            hint: 'Password',
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.password],
            onSubmitted: (_) => _handleSubmit(),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
              ),
              child: const Text(
                'Forgot password?',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: _accent,
                ),
              ),
            ),
          ),
          if (_error != null) ...[const SizedBox(height: 12), _errorBox()],
          const SizedBox(height: 20),
          AppButton(
            label: 'Sign in',
            onPressed: _handleSubmit,
            loading: _submitting,
          ),
          if (_biometricAvailable && _biometricEnabled) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _submitting
                    ? null
                    : () {
                        setState(() {
                          _usePassword = false;
                          _error = null;
                        });
                        _handleBiometricLogin();
                      },
                icon: const Icon(Icons.fingerprint, size: 22),
                label: const Text('Use biometrics'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _ink,
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: Color(0xFFE5E7EB)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: const StadiumBorder(),
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          const Row(
            children: [
              Expanded(child: Divider()),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'or',
                  style: TextStyle(fontSize: 11.5, color: Color(0xFF9CA3AF)),
                ),
              ),
              Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: 20),
          AppButton(
            label: 'Continue with Google',
            onPressed: _handleGoogleLogin,
            isPrimary: false,
          ),
          const SizedBox(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                "Don't have an account yet? ",
                style: TextStyle(fontSize: 13, color: _muted),
              ),
              GestureDetector(
                onTap: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const SignupScreen())),
                child: const Text(
                  'Sign up',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
