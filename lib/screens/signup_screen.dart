import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../widgets/app_button.dart';
import '../widgets/app_text_field.dart';
import '../widgets/password_field.dart';

final _emailRegex = RegExp(r'^[^\s@]+@([^\s@.,]+\.)+[^\s@.,]{2,}$');

const _ink = Color(0xFF0A0A0A);
const _accent = Color(0xFF3355FF);
const _sheet = Color(0xFFF7F6F3);
const _muted = Color(0xFF6B7280);

/// Per-field validation. Returns a map of field -> message (empty = valid).
Map<String, String> _validate({
  required String username,
  required String email,
  required String password,
  required String confirmPassword,
}) {
  final errors = <String, String>{};
  final name = username.trim();
  if (name.length < 3 || name.length > 50) {
    errors['username'] = 'Username must be 3\u201350 characters';
  }
  if (!_emailRegex.hasMatch(email.trim())) {
    errors['email'] = 'Enter a valid email address';
  }
  if (password.length < 8 || password.length > 72) {
    errors['password'] = 'Password must be 8\u201372 characters';
  }
  if (password != confirmPassword) {
    errors['confirm'] = 'Passwords do not match';
  }
  return errors;
}

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _submitting = false;
  String? _error; // server / generic error
  bool _success = false;
  String _submittedEmail = '';
  Map<String, String> _fieldErrors = {};

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _clearFieldError(String key) {
    if (_fieldErrors.containsKey(key) || _error != null) {
      setState(() {
        _fieldErrors = Map.of(_fieldErrors)..remove(key);
        _error = null;
      });
    }
  }

  Future<void> _handleGoogleLogin() async {
    final uri = Uri.parse('https://api.mcriresidents.online/api/auth/google');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _handleSubmit() async {
    FocusScope.of(context).unfocus();
    setState(() => _error = null);

    final errors = _validate(
      username: _usernameController.text,
      email: _emailController.text,
      password: _passwordController.text,
      confirmPassword: _confirmController.text,
    );
    setState(() => _fieldErrors = errors);
    if (errors.isNotEmpty) return;

    setState(() => _submitting = true);
    try {
      final auth = context.read<AuthProvider>();
      final email = _emailController.text.trim();
      await auth.signup(
        email,
        _passwordController.text,
        _usernameController.text.trim(),
      );
      // Lets Samsung Pass / Google / iCloud Keychain offer to save the new
      // credentials (the user can accept or decline in the OS prompt).
      TextInput.finishAutofillContext(shouldSave: true);
      if (!mounted) return;
      setState(() {
        _submittedEmail = email;
        _success = true;
      });
    } on ApiException catch (e) {
      TextInput.finishAutofillContext(shouldSave: false);
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      TextInput.finishAutofillContext(shouldSave: false);
      if (mounted) setState(() => _error = 'Could not create your account');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ───────────────────────── UI ─────────────────────────

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    final heroHeight = topInset + (_success ? 210.0 : 190.0);

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
                            key: ValueKey(_success),
                            child: _success ? _buildSuccess() : _buildForm(),
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
    return Container(
      height: height,
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0.9, -1.0),
          radius: 1.3,
          colors: [Color(0xFF1C2B73), _ink],
        ),
      ),
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsets.only(top: topInset),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    height: 64,
                    width: 64,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(19),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 22,
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
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _success ? 'Check your inbox' : 'Create your account',
                    style: const TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _success
                        ? "We've issued a secure verification link."
                        : "Join your residence's portal in a minute.",
                    style: TextStyle(
                      fontSize: 13.5,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: topInset + 6,
            left: 8,
            child: IconButton(
              tooltip: 'Back',
              icon: const Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 20,
                color: Colors.white,
              ),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccess() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 64,
          width: 64,
          decoration: const BoxDecoration(
            color: Color(0xFFFFFBEB),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.mark_email_read_outlined,
            color: Color(0xFFB45309),
            size: 28,
          ),
        ),
        const SizedBox(height: 20),
        Text.rich(
          TextSpan(
            style: const TextStyle(fontSize: 14, color: _muted, height: 1.55),
            children: [
              const TextSpan(text: 'A confirmation email was sent to '),
              TextSpan(
                text: _submittedEmail,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                ),
              ),
              const TextSpan(
                text: '. Please click the link inside to activate your resident portal account.',
              ),
            ],
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),
        AppButton(
          label: 'Back to sign in',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ],
    );
  }

  Widget _buildForm() {
    final mismatchLive =
        _confirmController.text.isNotEmpty &&
        _passwordController.text != _confirmController.text;

    // AutofillGroup + hints: the email is what the password manager stores
    // as the account name (login uses email), and both password fields are
    // marked newPassword so Samsung Pass / Google / Keychain can suggest a
    // strong generated password.
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppTextField(
            label: 'Username',
            controller: _usernameController,
            icon: Icons.person_outline,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.nickname],
            errorText: _fieldErrors['username'],
            onChanged: (_) => _clearFieldError('username'),
          ),
          const SizedBox(height: 14),
          AppTextField(
            label: 'Email',
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            icon: Icons.mail_outline,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.username, AutofillHints.email],
            errorText: _fieldErrors['email'],
            onChanged: (_) => _clearFieldError('email'),
          ),
          const SizedBox(height: 14),
          AppPasswordField(
            controller: _passwordController,
            hint: 'Create a password',
            showStrength: true,
            showRequirements: true,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.newPassword],
            errorText: _fieldErrors['password'],
            onChanged: (_) {
              _clearFieldError('password');
              // keep the live "don't match" state in sync
              if (_confirmController.text.isNotEmpty) setState(() {});
            },
          ),
          const SizedBox(height: 14),
          AppPasswordField(
            controller: _confirmController,
            hint: 'Confirm password',
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.newPassword],
            errorText:
                _fieldErrors['confirm'] ??
                (mismatchLive ? "Passwords don't match yet" : null),
            onChanged: (_) {
              _clearFieldError('confirm');
              setState(() {});
            },
            onSubmitted: (_) => _handleSubmit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Text(
                _error!,
                style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13),
              ),
            ),
          ],
          const SizedBox(height: 22),
          AppButton(
            label: 'Create account',
            onPressed: _handleSubmit,
            loading: _submitting,
          ),
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
                'Already have an account? ',
                style: TextStyle(fontSize: 13, color: _muted),
              ),
              GestureDetector(
                onTap: () => Navigator.of(context).maybePop(),
                child: const Text(
                  'Sign in',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _accent,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
