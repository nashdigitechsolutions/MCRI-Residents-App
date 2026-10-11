import 'package:flutter/material.dart';

import 'input_style.dart';

int _strengthScore(String password) {
  if (password.length < 8) return 0; // anything under 8 is "Too short"
  int score = 1;
  if (password.length >= 12) score++;
  if (RegExp(r'[A-Z]').hasMatch(password)) score++;
  if (RegExp(r'[0-9]').hasMatch(password)) score++;
  if (RegExp(r'[^A-Za-z0-9]').hasMatch(password)) score++;
  return score > 4 ? 4 : score;
}

const _strengthLabels = ['Too short', 'Weak', 'Fair', 'Good', 'Strong'];
const _strengthColors = [
  Color(0xFFF87171),
  Color(0xFFF87171),
  Color(0xFFFBBF24),
  Color(0xFF34D399),
  Color(0xFF10B981),
];

class AppPasswordField extends StatefulWidget {
  final TextEditingController controller;
  final String hint;
  final bool showStrength;
  final bool showRequirements;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;
  final String? errorText;
  final bool enabled;

  const AppPasswordField({
    super.key,
    required this.controller,
    this.hint = 'Password',
    this.showStrength = false,
    this.showRequirements = false,
    this.autofillHints,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.errorText,
    this.enabled = true,
  });

  @override
  State<AppPasswordField> createState() => _AppPasswordFieldState();
}

class _AppPasswordFieldState extends State<AppPasswordField> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    // Listening to the controller (not just onChanged) keeps strength and
    // requirements live even when a password manager fills the field.
    widget.controller.addListener(_refresh);
  }

  @override
  void didUpdateWidget(covariant AppPasswordField old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_refresh);
      widget.controller.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted && (widget.showStrength || widget.showRequirements)) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.controller.text;
    final strength = _strengthScore(value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppFieldShell(
          focusNode: widget.focusNode,
          hasError: widget.errorText != null,
          builder: (context, node, focused) => TextField(
            controller: widget.controller,
            focusNode: node,
            enabled: widget.enabled,
            obscureText: !_visible,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.visiblePassword,
            textInputAction: widget.textInputAction,
            autofillHints: widget.autofillHints,
            onChanged: widget.onChanged,
            onSubmitted: widget.onSubmitted,
            cursorColor: kFieldAccent,
            style: const TextStyle(fontSize: 14.5, color: Color(0xFF0A0A0A)),
            decoration: appFieldDecoration(
              hint: widget.hint,
              icon: Icons.lock_outline,
              focused: focused,
              errorText: widget.errorText,
              enabled: widget.enabled,
              suffix: IconButton(
                splashRadius: 20,
                tooltip: _visible ? 'Hide password' : 'Show password',
                icon: Icon(
                  _visible
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 19,
                  color: focused ? kFieldAccent : kFieldHint,
                ),
                onPressed: () => setState(() => _visible = !_visible),
              ),
            ),
          ),
        ),
        if (widget.showStrength && value.isNotEmpty) ...[
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: List.generate(4, (i) {
                final filled = i < strength;
                return Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: EdgeInsets.only(right: i < 3 ? 4 : 0),
                    height: 5,
                    decoration: BoxDecoration(
                      color: filled
                          ? _strengthColors[strength]
                          : const Color(0xFFE5E7EB),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 5),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              _strengthLabels[strength],
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: strength <= 1
                    ? const Color(0xFFEF4444)
                    : const Color(0xFF6B7280),
              ),
            ),
          ),
        ],
        if (widget.showRequirements && value.isNotEmpty) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _RequirementRow(
                  label: 'At least 8 characters',
                  met: value.length >= 8,
                ),
                _RequirementRow(
                  label: 'No more than 72 characters',
                  met: value.length <= 72,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _RequirementRow extends StatelessWidget {
  final String label;
  final bool met;

  const _RequirementRow({required this.label, required this.met});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Icon(
              met ? Icons.check_circle : Icons.circle_outlined,
              key: ValueKey(met),
              size: 14,
              color: met ? const Color(0xFF10B981) : const Color(0xFFD1D5DB),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              color: met ? const Color(0xFF6B7280) : const Color(0xFF9CA3AF),
            ),
          ),
        ],
      ),
    );
  }
}
