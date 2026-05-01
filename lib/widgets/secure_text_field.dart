import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// Password input widget that disables copy/cut and autocorrect.
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
          color: AppTheme.textPrimary, letterSpacing: 1.2),
      contextMenuBuilder: (context, editableTextState) {
        // Only allow paste — no copy or cut.
        final buttonItems = editableTextState.contextMenuButtonItems
            .where((item) =>
                item.type == ContextMenuButtonType.paste ||
                item.type == ContextMenuButtonType.selectAll)
            .toList();
        return AdaptiveTextSelectionToolbar.buttonItems(
          anchors: editableTextState.contextMenuAnchors,
          buttonItems: buttonItems,
        );
      },
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