import 'package:flutter/material.dart';
import '../../widgets/form_controls.dart';
import '../../widgets/shared_ui.dart';

class SettingsTextField extends StatelessWidget {
  const SettingsTextField({
    super.key,
    required this.label,
    required this.value,
    required this.hint,
    required this.onChanged,
    this.keyboardType,
    this.normalizeTime = false,
    this.onFinished,
    this.maxLength,
  });

  final String label;
  final String value;
  final String hint;
  final ValueChanged<String> onChanged;
  final TextInputType? keyboardType;
  final bool normalizeTime;
  final VoidCallback? onFinished;
  final int? maxLength;

  @override
  Widget build(BuildContext context) {
    if (normalizeTime) {
      return TimeInputField(
        label: label,
        hint: hint,
        initialValue: value,
        onChanged: onChanged,
        onFinished: onFinished,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(label),
        const SizedBox(height: 8),
        SelectAllTextFormField(
          initialValue: value,
          keyboardType: keyboardType,
          maxLength: maxLength,
          decoration: InputDecoration(hintText: hint),
          onChanged: onChanged,
          onFinished: onFinished,
        ),
      ],
    );
  }
}

class SettingsFinishedTextField extends StatefulWidget {
  const SettingsFinishedTextField({
    super.key,
    required this.initialValue,
    required this.hintText,
    required this.onChanged,
    required this.onFinished,
    required this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
  });

  final String initialValue;
  final String hintText;
  final ValueChanged<String> onChanged;
  final VoidCallback onFinished;
  final TextInputAction textInputAction;
  final TextCapitalization textCapitalization;

  @override
  State<SettingsFinishedTextField> createState() =>
      _SettingsFinishedTextFieldState();
}

class _SettingsFinishedTextFieldState extends State<SettingsFinishedTextField> {
  late final FocusNode _focusNode;
  bool _edited = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode()..addListener(_handleFocusChanged);
  }

  void _finishIfEdited() {
    if (!_edited) return;
    _edited = false;
    widget.onFinished();
  }

  void _handleFocusChanged() {
    if (!_focusNode.hasFocus) _finishIfEdited();
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: widget.initialValue,
      focusNode: _focusNode,
      textCapitalization: widget.textCapitalization,
      textInputAction: widget.textInputAction,
      decoration: InputDecoration(hintText: widget.hintText),
      onChanged: (value) {
        _edited = true;
        widget.onChanged(value);
      },
      onFieldSubmitted: (_) => _finishIfEdited(),
    );
  }
}
