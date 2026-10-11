import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../widgets/app_button.dart';
import '../widgets/app_text_field.dart';

const _resendCooldownSeconds = 30;
final _emailRegex = RegExp(r'^[^\s@]+@([^\s@.,]+\.)+[^\s@.,]{2,}$');

enum _VerifyStatus { verifying, success, error }

class VerificationScreen extends StatefulWidget {
  final String? token;

  const VerificationScreen({super.key, this.token});

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  _VerifyStatus _status = _VerifyStatus.verifying;
  String _message = '';

  final _resendController = TextEditingController();
  bool _resending = false;
  bool _resendSent = false;
  String? _resendError;
  int _cooldown = 0;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    _verify();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _resendController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (widget.token == null) {
      setState(() {
        _status = _VerifyStatus.error;
        _message = 'This verification link is missing its token.';
      });
      return;
    }

    try {
      await ApiService.post('/verify-email', {'token': widget.token});
      setState(() => _status = _VerifyStatus.success);
    } on ApiException catch (e) {
      setState(() {
        _status = _VerifyStatus.error;
        _message = e.message;
      });
    } catch (e) {
      setState(() {
        _status = _VerifyStatus.error;
        _message = 'This link is invalid or has expired.';
      });
    }
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _cooldown = _resendCooldownSeconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_cooldown <= 1) {
        timer.cancel();
        setState(() => _cooldown = 0);
      } else {
        setState(() => _cooldown -= 1);
      }
    });
  }

  Future<void> _handleResend() async {
    setState(() => _resendError = null);
    if (!_emailRegex.hasMatch(_resendController.text.trim())) {
      setState(() => _resendError = 'Enter a valid email address');
      return;
    }

    setState(() => _resending = true);
    try {
      // Backend returns a generic message either way (anti-enumeration), so
      // we always show the same success confirmation regardless of outcome.
      await ApiService.post('/resend-verification', {
        'email': _resendController.text.trim(),
      });
      setState(() => _resendSent = true);
      _startCooldown();
    } on ApiException catch (e) {
      setState(() => _resendError = e.message);
    } catch (e) {
      setState(() => _resendError = 'Could not send a new link. Try again.');
    } finally {
      setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F6F3),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: switch (_status) {
            _VerifyStatus.verifying => _buildVerifying(),
            _VerifyStatus.success => _buildSuccess(),
            _VerifyStatus.error => _buildError(),
          },
        ),
      ),
    );
  }

  Widget _buildVerifying() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Verifying…',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        const Text(
          'Just a moment while we confirm your email.',
          style: TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
        ),
        const SizedBox(height: 40),
        const Center(child: CircularProgressIndicator()),
      ],
    );
  }

  Widget _buildSuccess() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Email verified',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        const Text(
          'Your account is now active.',
          style: TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
        ),
        const SizedBox(height: 28),
        Container(
          height: 56,
          width: 56,
          decoration: const BoxDecoration(
            color: Color(0xFFECFDF5),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_circle_outline,
            color: Color(0xFF10B981),
            size: 28,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'You can now sign in to your account.',
          style: TextStyle(fontSize: 13.5, color: Color(0xFF6B7280)),
        ),
        const SizedBox(height: 20),
        AppButton(
          label: 'Go to sign in',
          onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
        ),
      ],
    );
  }

  Widget _buildError() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Verification failed',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        const Text(
          "We couldn't verify this link.",
          style: TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
        ),
        const SizedBox(height: 28),
        Container(
          height: 56,
          width: 56,
          decoration: const BoxDecoration(
            color: Color(0xFFFEF2F2),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.highlight_off,
            color: Color(0xFFEF4444),
            size: 28,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _message,
          style: const TextStyle(fontSize: 13.5, color: Color(0xFF6B7280)),
        ),
        const SizedBox(height: 20),
        if (_resendSent)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Column(
              children: [
                Icon(
                  Icons.mark_email_read_outlined,
                  color: Color(0xFF10B981),
                  size: 22,
                ),
                SizedBox(height: 8),
                Text(
                  "If that account exists and isn't verified yet, a new link is on its way.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: Color(0xFF374151)),
                ),
              ],
            ),
          )
        else ...[
          const Text(
            'Enter your email to get a new verification link',
            style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
          ),
          const SizedBox(height: 8),
          AppTextField(
            label: '',
            controller: _resendController,
            keyboardType: TextInputType.emailAddress,
          ),
          if (_resendError != null) ...[
            const SizedBox(height: 6),
            Text(
              _resendError!,
              style: const TextStyle(fontSize: 11.5, color: Color(0xFFEF4444)),
            ),
          ],
          const SizedBox(height: 12),
          AppButton(
            label: _cooldown > 0
                ? 'Resend in ${_cooldown}s'
                : 'Resend verification email',
            onPressed: _cooldown > 0 ? null : _handleResend,
            loading: _resending,
          ),
        ],
        const SizedBox(height: 20),
        Center(
          child: GestureDetector(
            onTap: () => Navigator.of(context).popUntil((r) => r.isFirst),
            child: const Text(
              'Back to sign in',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }
}
