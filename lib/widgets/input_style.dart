import 'package:mcri_residents_app/theme/app_theme.dart';
import 'package:flutter/material.dart';

const kFieldAccent = AppColors.primary;
const kFieldHint = AppColors.subtle;
const kFieldBorder = AppColors.border;
const kFieldError = AppColors.dangerDark;

/// Wraps a text field in a rounded container that lifts with a soft
/// glow while focused. Shared by AppTextField and AppPasswordField so
/// they always look identical.
class AppFieldShell extends StatefulWidget {
  final FocusNode? focusNode;
  final bool hasError;
  final Widget Function(BuildContext context, FocusNode node, bool focused)
  builder;

  const AppFieldShell({
    super.key,
    this.focusNode,
    this.hasError = false,
    required this.builder,
  });

  @override
  State<AppFieldShell> createState() => _AppFieldShellState();
}

class _AppFieldShellState extends State<AppFieldShell> {
  late final FocusNode _node;
  late final bool _ownsNode;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _ownsNode = widget.focusNode == null;
    _node = widget.focusNode ?? FocusNode();
    _node.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (mounted) setState(() => _focused = _node.hasFocus);
  }

  @override
  void dispose() {
    _node.removeListener(_onFocusChange);
    if (_ownsNode) _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final glow = widget.hasError ? kFieldError : kFieldAccent;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: [
          BoxShadow(
            color: _focused
                ? glow.withValues(alpha: 0.16)
                : Colors.black.withValues(alpha: 0.03),
            blurRadius: _focused ? 18 : 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: widget.builder(context, _node, _focused),
    );
  }
}

/// The single decoration both fields use.
InputDecoration appFieldDecoration({
  required String hint,
  required bool focused,
  IconData? icon,
  Widget? suffix,
  String? errorText,
  bool enabled = true,
  ColorScheme? colors,
}) {
  // Same look as the profile form: floating label, 12px corners, theme
  // surface fill (so dark mode works), hairline outline → orange on focus.
  final border0 = colors?.outlineVariant ?? kFieldBorder;
  OutlineInputBorder border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: color, width: width),
      );

  return InputDecoration(
    labelText: hint,
    floatingLabelStyle: TextStyle(
      color: focused ? kFieldAccent : (colors?.onSurfaceVariant ?? kFieldHint),
      fontWeight: FontWeight.w600,
    ),
    labelStyle: TextStyle(
      color: colors?.onSurfaceVariant ?? kFieldHint,
      fontSize: 14,
    ),
    errorText: errorText,
    errorStyle: const TextStyle(fontSize: 12, color: kFieldError, height: 1.3),
    prefixIcon: icon == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Icon(
              icon,
              size: 19,
              color: focused ? kFieldAccent : kFieldHint,
            ),
          ),
    suffixIcon: suffix,
    filled: true,
    fillColor: enabled
        ? (colors?.surface ?? Colors.white)
        : (colors?.surfaceContainerHighest ?? AppColors.fieldDisabled),
    contentPadding: EdgeInsets.symmetric(
      horizontal: icon == null ? 22 : 14,
      vertical: 16,
    ),
    border: border(border0),
    enabledBorder: border(border0),
    disabledBorder: border(border0),
    focusedBorder: border(kFieldAccent, 1.5),
    errorBorder: border(kFieldError),
    focusedErrorBorder: border(kFieldError, 1.5),
  );
}
