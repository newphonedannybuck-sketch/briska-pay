import 'package:flutter/material.dart';

import '../../design_system/briska_theme.dart';
import '../display_format.dart';
import '../work_calculator.dart';
import 'shared_ui.dart';

class DatePickerTile extends StatelessWidget {
  const DatePickerTile({
    super.key,
    required this.value,
    required this.isMissing,
    required this.onPressed,
  });

  final String value;
  final bool isMissing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(
        isMissing ? Icons.event_busy_outlined : Icons.event_available_outlined,
      ),
      label: Align(alignment: Alignment.centerLeft, child: Text(value)),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        foregroundColor: isMissing ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }
}

class SelectAllTextFormField extends StatefulWidget {
  const SelectAllTextFormField({
    super.key,
    this.initialValue,
    this.keyboardType,
    this.decoration,
    this.textInputAction,
    this.onChanged,
    this.onFinished,
    this.maxLength,
  });

  final String? initialValue;
  final TextInputType? keyboardType;
  final InputDecoration? decoration;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onFinished;
  final int? maxLength;

  @override
  State<SelectAllTextFormField> createState() => _SelectAllTextFormFieldState();
}

class _SelectAllTextFormFieldState extends State<SelectAllTextFormField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _selectedForFocus = false;
  bool _edited = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue ?? '');
    _focusNode = FocusNode()..addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(SelectAllTextFormField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus && oldWidget.initialValue != widget.initialValue) {
      _controller.text = widget.initialValue ?? '';
    }
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _finishIfEdited() {
    if (!_edited) return;
    _edited = false;
    widget.onFinished?.call();
  }

  void _handleFocusChanged() {
    if (!_focusNode.hasFocus) {
      _selectedForFocus = false;
      _finishIfEdited();
      return;
    }
    if (_selectedForFocus) return;
    _selectedForFocus = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_focusNode.hasFocus) return;
      Scrollable.ensureVisible(
        context,
        duration: BriskaDurations.standard,
        curve: Curves.easeOutCubic,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      focusNode: _focusNode,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      maxLength: widget.maxLength,
      decoration: widget.decoration,
      onChanged: (value) {
        _edited = true;
        widget.onChanged?.call(value);
      },
      onFieldSubmitted: (_) => _finishIfEdited(),
    );
  }
}

class TimeInputField extends StatefulWidget {
  const TimeInputField({
    super.key,
    required this.label,
    required this.hint,
    required this.initialValue,
    required this.onChanged,
    this.onFinished,
  });

  final String label;
  final String hint;
  final String initialValue;
  final ValueChanged<String> onChanged;
  final VoidCallback? onFinished;

  @override
  State<TimeInputField> createState() => _TimeInputFieldState();
}

class _TimeInputFieldState extends State<TimeInputField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text:
          WorkCalculator.normalizeTime(widget.initialValue) ??
          widget.initialValue,
    );
    _focusNode = FocusNode()..addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant TimeInputField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Parent echoes of typing must not rewrite the text or move the cursor.
    if (widget.initialValue != oldWidget.initialValue &&
        widget.initialValue != _controller.text) {
      final value =
          WorkCalculator.normalizeTime(widget.initialValue) ??
          widget.initialValue;
      _controller.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    }
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (!_focusNode.hasFocus) _normalizeCompletedInput();
  }

  void _normalizeCompletedInput() {
    final value = _controller.text;
    final normalized = WorkCalculator.normalizeTime(value);
    if (normalized != null && normalized != value) {
      _controller.value = TextEditingValue(
        text: normalized,
        selection: TextSelection.collapsed(offset: normalized.length),
      );
      widget.onChanged(normalized);
    }
  }

  TimeOfDay _initialTimeOfDay() {
    final normalized =
        WorkCalculator.normalizeTime(_controller.text) ??
        WorkCalculator.normalizeTime(widget.initialValue) ??
        WorkCalculator.normalizeTime(widget.hint) ??
        '08:00';
    final parts = normalized.split(':');
    return TimeOfDay(
      hour: int.parse(parts.first),
      minute: int.parse(parts.last),
    );
  }

  Future<void> _pickTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: _initialTimeOfDay(),
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        return MediaQuery(
          data: mediaQuery.copyWith(alwaysUse24HourFormat: true),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (!mounted || selected == null) return;
    final value = formatTime(hour: selected.hour, minute: selected.minute);
    _controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      FieldLabel(widget.label),
      const SizedBox(height: 8),
      TextField(
        controller: _controller,
        focusNode: _focusNode,
        keyboardType: TextInputType.datetime,
        decoration: InputDecoration(
          hintText: widget.hint,
          helperText: '24-hour time (e.g. 17:30)',
          suffixIcon: IconButton(
            tooltip: 'Pick time',
            icon: const Icon(Icons.schedule_rounded, size: 20),
            onPressed: _pickTime,
          ),
        ),
        onChanged: widget.onChanged,
        onEditingComplete: () {
          _normalizeCompletedInput();
          _focusNode.unfocus();
          widget.onFinished?.call();
        },
      ),
    ],
  );
}
