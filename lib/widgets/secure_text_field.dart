import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// Secure password / PIN input.
///
/// Security properties:
///   - Text is obscured by default with a toggle.
///   - Auto-correct and suggestions are disabled.
///   - The long-press context menu retains only Paste.
///     Copy, Cut, Select All and every other action are removed so the
///     password can never be placed on the system clipboard.
class SecureTextField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hintText;
  final String? errorText;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final Widget? prefixIcon;

  const SecureTextField({
    super.key,
    required this.controller,
    this.focusNode,
    this.hintText = '',
    this.errorText,
    this.textInputAction = TextInputAction.done,
    this.onSubmitted,
    this.autofocus = false,
    this.prefixIcon,
  });

  @override
  State<SecureTextField> createState() => _SecureTextFieldState();
}

class _SecureTextFieldState extends State<SecureTextField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      obscureText: _obscure,
      enableSuggestions: false,
      autocorrect: false,
      textInputAction: widget.textInputAction,
      onSubmitted: widget.onSubmitted,
      style: const TextStyle(
        color: AppTheme.textPrimary,
        letterSpacing: 1.2,
      ),
      // Keep only Paste — no Copy, Cut, Select All, or Share.
      contextMenuBuilder: _pasteOnlyMenu,
      decoration: InputDecoration(
        hintText: widget.hintText,
        errorText: widget.errorText,
        prefixIcon: widget.prefixIcon,
        suffixIcon: IconButton(
          icon: Icon(
            _obscure
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            color: AppTheme.textSecondary,
            size: 20,
          ),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
    );
  }
}

// ─── Shared context-menu builders ─────────────────────────────────────────────

/// Builds a context menu that contains only the Paste action.
/// Used on every editable text field in the app to prevent data leakage
/// via the system clipboard.
Widget _pasteOnlyMenu(
  BuildContext context,
  EditableTextState editableTextState,
) {
  final pasteItems = editableTextState.contextMenuButtonItems
      .where((item) => item.type == ContextMenuButtonType.paste)
      .toList();

  // If the clipboard is empty there is nothing to show — return an empty box
  // rather than an awkward empty menu.
  if (pasteItems.isEmpty) return const SizedBox.shrink();

  return AdaptiveTextSelectionToolbar.buttonItems(
    anchors: editableTextState.contextMenuAnchors,
    buttonItems: pasteItems,
  );
}

/// Public accessor so non-password text fields in the app can reuse the same
/// paste-only policy without duplicating the builder closure.
Widget pasteOnlyContextMenu(
  BuildContext context,
  EditableTextState editableTextState,
) =>
    _pasteOnlyMenu(context, editableTextState);