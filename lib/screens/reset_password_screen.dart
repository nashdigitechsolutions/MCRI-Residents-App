import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_service.dart';
import '../utils/validators.dart';
import '../widgets/app_button.dart';
import '../widgets/password_field.dart';
import '../widgets/slide_puzzle_captcha.dart';

const _ink = Color(0xFF0A0A0A);
const _sheet = Color(0xFFF7F6F3);
const _muted = Color(0xFF6B7280);

class ResetPasswordScreen extends StatefulWidget {
  final String? token;

  const ResetPasswordScreen({super.key, this.token});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _passwordController = TextEditingController();
  Timer? _redirectTimer;

  String? _captchaToken;
  bool _submitting = false;
  String? _error; // server / generic error
  String? _passwordError; // validator error
  bool _success = false;

  @override
  void dispose() {
    _redirectTimer?.cancel();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _passwordError = null;
    });

    if (widget.token == null) {
      setState(
        () => _error = 'This reset link is missing its token \u2014 please use the link from your email.',
      );
      return;
    }

    final passwordError = Validators.newPassword(_passwordController.text);
    if (passwordError != null) {
      setState(() => _passwordError = passwordError);
      return;
    }
    if (_captchaToken == null) {
      setState(() => _error = 'Please complete the verification slider first');
      return;
    }

    setState(() => _submitting = true);
    try {
      await ApiService.post('/reset-password', {
        'token': widget.token,
        'newPassword': _passwordController.text,
      });

      // Lets Samsung Pass / Google / iCloud Keychain update the saved
      // password for this account.
      TextInput.finishAutofillContext(shouldSave: true);

      if (!mounted) return;
      setState(() => _success = true);
      _redirectTimer = Timer(const Duration(milliseconds: 1600), () {
        if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
      });
    } on ApiException catch (e) {
      TextInput.finishAutofillContext(shouldSave: false);
      if (mounted) {
        setState(() => _error = friendlyError(e.message));
      }
    } catch (e) {
      TextInput.finishAutofillContext(shouldSave: false);
      if (mounted) {
        setState(
          () => _error =
              'Could not reset your password. The link may have expired.',
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ───────────────────────── UI ─────────────────────────

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    final heroHeight = topInset + 190.0;

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
                    _success ? 'Password updated' : 'Reset your password',
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
                        ? "You're all set."
                        : 'Choose a new password for your account.',
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
            color: Color(0xFFECFDF5),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_circle_outline,
            color: Color(0xFF10B981),
            size: 30,
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'Taking you to sign in\u2026',
          style: TextStyle(fontSize: 14, color: _muted),
        ),
      ],
    );
  }

  Widget _buildForm() {
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.token == null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: const Text(
                'No reset token found in this link. Request a new one if you opened this screen directly.',
                style: TextStyle(fontSize: 12.5, color: Color(0xFF92400E)),
              ),
            ),
          AppPasswordField(
            controller: _passwordController,
            hint: 'New password',
            showStrength: true,
            showRequirements: true,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.newPassword],
            errorText: _passwordError,
            onChanged: (_) {
              if (_passwordError != null || _error != null) {
                setState(() {
                  _passwordError = null;
                  _error = null;
                });
              }
            },
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: SlidePuzzleCaptcha(
              onVerified: (token) => setState(() => _captchaToken = token),
              onReset: () => setState(() => _captchaToken = null),
            ),
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
            label: 'Reset password',
            onPressed: (_captchaToken == null || widget.token == null)
                ? null
                : _handleSubmit,
            loading: _submitting,
          ),
          const SizedBox(height: 22),
          Center(
            child: GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              child: const Text(
                'Back to sign in',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _muted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
