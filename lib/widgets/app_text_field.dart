import 'package:flutter/material.dart';

import 'input_style.dart';

class AppTextField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool obscureText;
  final TextInputType keyboardType;
  final IconData? icon;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;
  final String? errorText;
  final bool enabled;
  final TextCapitalization textCapitalization;

  const AppTextField({
    super.key,
    required this.label,
    required this.controller,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
    this.icon,
    this.autofillHints,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.errorText,
    this.enabled = true,
    this.textCapitalization = TextCapitalization.none,
  });

  @override
  Widget build(BuildContext context) {
    final isEmail = keyboardType == TextInputType.emailAddress;

    return AppFieldShell(
      focusNode: focusNode,
      hasError: errorText != null,
      builder: (context, node, focused) => TextField(
        controller: controller,
        focusNode: node,
        enabled: enabled,
        obscureText: obscureText,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        textCapitalization: textCapitalization,
        autofillHints: autofillHints,
        autocorrect: !isEmail && !obscureText,
        enableSuggestions: !isEmail && !obscureText,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        cursorColor: kFieldAccent,
        style: const TextStyle(fontSize: 14.5, color: Color(0xFF0A0A0A)),
        decoration: appFieldDecoration(
          hint: label,
          icon: icon,
          focused: focused,
          errorText: errorText,
          enabled: enabled,
        ),
      ),
    );
  }
}
