import 'package:flutter/material.dart';

import '../../core/theme/saga_theme.dart';

/// The standard search field: search prefix, clear suffix while text is
/// present, filled surface, borderless 12-radius, zero content padding.
/// Three screens carried this decoration verbatim.
class SagaSearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final bool showClear;
  final VoidCallback onClear;
  final ValueChanged<String> onChanged;

  const SagaSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.showClear,
    required this.onClear,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: TextStyle(color: SagaColors.fg),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(color: SagaColors.fgSubtle),
        prefixIcon: Icon(Icons.search, color: SagaColors.fgSubtle),
        suffixIcon: showClear
            ? IconButton(
                icon: Icon(Icons.clear, color: SagaColors.fgSubtle),
                tooltip: 'Clear search',
                onPressed: onClear,
              )
            : null,
        filled: true,
        fillColor: SagaColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: EdgeInsets.zero,
      ),
      onChanged: onChanged,
    );
  }
}
