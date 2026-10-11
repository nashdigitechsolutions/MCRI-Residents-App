import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../utils/validators.dart';
import '../widgets/app_button.dart';
import '../widgets/app_text_field.dart';
import '../widgets/slide_puzzle_captcha.dart';

const _ink = Color(0xFF0A0A0A);
const _sheet = Color(0xFFF7F6F3);
const _muted = Color(0xFF6B7280);

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();

  String? _captchaToken;
  int _captchaAttempt = 0; // bump to rebuild the slider with a fresh puzzle
  bool _sent = false;
  String _sentTo = '';
  bool _submitting = false;
  String? _emailError; // validator error
  String? _error; // server / generic error

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _resetCaptcha() {
    _captchaToken = null;
    _captchaAttempt++;
  }

  Future<void> _handleSubmit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _emailError = null;
    });

    // Validate locally first so the API never sees a malformed email.
    final emailError = Validators.email(_emailController.text);
    if (emailError != null) {
      setState(() => _emailError = emailError);
      return;
    }
    if (_captchaToken == null) {
      setState(() => _error = 'Please complete the verification slider first');
      return;
    }

    final email = _emailController.text.trim();
    setState(() => _submitting = true);
    try {
      await ApiService.post('/forgot-password', {
        'email': email,
        'captchaToken': _captchaToken,
      });
      if (!mounted) return;
      setState(() {
        _sentTo = email;
        _sent = true;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      // A rejected/expired captcha shouldn't leave a stale token armed:
      // force a fresh slide before the next attempt.
      setState(() {
        _error = friendlyError(e.message);
        _resetCaptcha();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Something went wrong. Try again.';
        _resetCaptcha();
      });
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
                            key: ValueKey(_sent),
                            child: _sent ? _buildSent() : _buildForm(),
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
                    _sent ? 'Check your inbox' : 'Reset your password',
                    style: const TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      _sent
                          ? 'A reset link is on its way.'
                          : "Enter your email and we'll send you a reset link.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
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

  Widget _buildSent() {
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
            Icons.mark_email_read_outlined,
            color: Color(0xFF10B981),
            size: 28,
          ),
        ),
        const SizedBox(height: 20),
        Text.rich(
          TextSpan(
            style: const TextStyle(fontSize: 14, color: _muted, height: 1.55),
            children: [
              const TextSpan(text: 'If an account exists for '),
              TextSpan(
                text: _sentTo,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                ),
              ),
              const TextSpan(
                text: ", we've sent a link to reset your password.",
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
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppTextField(
            label: 'Email',
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            icon: Icons.mail_outline,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.email, AutofillHints.username],
            errorText: _emailError,
            onChanged: (_) {
              if (_emailError != null || _error != null) {
                setState(() {
                  _emailError = null;
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
              key: ValueKey(_captchaAttempt),
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
            label: 'Send reset link',
            onPressed: _captchaToken == null ? null : _handleSubmit,
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
