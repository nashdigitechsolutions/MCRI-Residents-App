import 'package:flutter/material.dart';

/// Asks for one line (or a short note) of text. Returns the text, or null
/// if cancelled.
///
/// The dialog owns its TextEditingController and disposes it in its own
/// dispose(), i.e. only after the closing animation has finished. Disposing
/// it from the caller (e.g. `showDialog(...).whenComplete(c.dispose)`) runs
/// while the TextField is still on screen animating out, which trips
/// Flutter's "_dependents.isEmpty" assertion — the red error screen.
Future<String?> showTextPrompt(
  BuildContext context, {
  required String title,
  String? message,
  String? hint,
  String confirmLabel = 'OK',
  bool obscure = false,
  int maxLines = 1,
  int? maxLength,
  bool destructive = false,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _TextPromptDialog(
      title: title,
      message: message,
      hint: hint,
      confirmLabel: confirmLabel,
      obscure: obscure,
      maxLines: maxLines,
      maxLength: maxLength,
      destructive: destructive,
    ),
  );
}

class _TextPromptDialog extends StatefulWidget {
  final String title;
  final String? message;
  final String? hint;
  final String confirmLabel;
  final bool obscure;
  final int maxLines;
  final int? maxLength;
  final bool destructive;

  const _TextPromptDialog({
    required this.title,
    this.message,
    this.hint,
    required this.confirmLabel,
    required this.obscure,
    required this.maxLines,
    this.maxLength,
    required this.destructive,
  });

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  final _controller = TextEditingController();
  bool _hidden = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Passwords are returned exactly as typed; other text is trimmed.
  void _submit() =>
      Navigator.of(context)
          .pop(widget.obscure ? _controller.text : _controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.message != null) ...[
            Text(widget.message!, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _controller,
            autofocus: true,
            obscureText: widget.obscure && _hidden,
            maxLines: widget.obscure ? 1 : widget.maxLines,
            maxLength: widget.maxLength,
            textInputAction: widget.maxLines > 1
                ? TextInputAction.newline
                : TextInputAction.done,
            onSubmitted: widget.maxLines > 1 ? null : (_) => _submit(),
            decoration: InputDecoration(
              hintText: widget.hint,
              suffixIcon: widget.obscure
                  ? IconButton(
                      icon: Icon(
                        _hidden
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () => setState(() => _hidden = !_hidden),
                    )
                  : null,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: widget.destructive
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                )
              : null,
          onPressed: _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
