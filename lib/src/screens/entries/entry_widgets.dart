import 'package:flutter/material.dart';
import '../../../design_system/briska_colors.dart';
import '../../../design_system/briska_theme.dart';
import '../../display_format.dart';
import '../../presentation_format.dart';
import '../../work_calculator.dart';
import '../../widgets/shared_ui.dart';
import '../../widgets/form_controls.dart';

class EntrySaveBar extends StatelessWidget {
  const EntrySaveBar({
    super.key,
    required this.calculation,
    required this.keyboardOpen,
    required this.onSave,
    required this.label,
  });

  final WorkCalculation calculation;
  final bool keyboardOpen;
  final VoidCallback? onSave;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact =
        keyboardOpen ||
        MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final saveButton = BriskaPrimaryButton(
      onPressed: onSave,
      icon: Icons.check_rounded,
      label: label,
    );
    final amount = calculation.isValid
        ? formatMoney(calculation.totalPay)
        : '--';
    return Material(
      color: theme.colorScheme.surface,
      shape: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: compact
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!keyboardOpen) ...[
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      spacing: 12,
                      children: [
                        Text(
                          'Estimated gross pay',
                          style: theme.textTheme.bodySmall,
                        ),
                        Text(amount, style: theme.textTheme.titleMedium),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  saveButton,
                ],
              )
            : Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Estimated gross pay',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(amount, style: theme.textTheme.titleLarge),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  SizedBox(width: 170, child: saveButton),
                ],
              ),
      ),
    );
  }
}

class EntrySectionHeading extends StatelessWidget {
  const EntrySectionHeading({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: .09),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: colors.primary, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: colors.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class OptionalCurrencyField extends StatefulWidget {
  const OptionalCurrencyField({
    required this.initialValue,
    required this.onChanged,
    super.key,
  });

  final double initialValue;
  final ValueChanged<double> onChanged;

  @override
  State<OptionalCurrencyField> createState() => _OptionalCurrencyFieldState();
}

class _OptionalCurrencyFieldState extends State<OptionalCurrencyField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _selectedForFocus = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialValue == 0
          ? ''
          : widget.initialValue.toStringAsFixed(2),
    );
    _focusNode = FocusNode()..addListener(_handleFocus);
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocus)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocus() {
    if (!_focusNode.hasFocus) {
      _selectedForFocus = false;
      _formatValue();
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

  void _formatValue() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      widget.onChanged(0);
      return;
    }
    final value = double.tryParse(text);
    if (value == null) return;
    _controller.value = TextEditingValue(
      text: value.toStringAsFixed(2),
      selection: TextSelection.collapsed(
        offset: value.toStringAsFixed(2).length,
      ),
    );
    widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        prefixText: currencyPrefix,
        hintText: 'Enter amount (optional)',
      ),
      onChanged: (text) => widget.onChanged(
        text.trim().isEmpty ? 0 : (double.tryParse(text) ?? -1),
      ),
      onEditingComplete: () {
        _formatValue();
        _focusNode.unfocus();
      },
    );
  }
}

class CalculationLine extends StatelessWidget {
  const CalculationLine({
    super.key,
    required this.label,
    required this.value,
    this.emphasize = false,
    this.foregroundColor,
  });

  final String label;
  final String value;
  final bool emphasize;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final color = foregroundColor ?? Theme.of(context).colorScheme.onSurface;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: TextStyle(
              color: color,
              fontSize: emphasize ? 17 : 14,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class EarningsSummaryCard extends StatelessWidget {
  const EarningsSummaryCard({
    super.key,
    required this.calculation,
    required this.rate,
    required this.allowance,
    required this.uplift,
  });

  final WorkCalculation calculation;
  final double rate;
  final double allowance;
  final double uplift;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: BriskaColors.hero,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Estimated gross pay',
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          BriskaAnimatedText(
            formatMoney(calculation.totalPay),
            style: Theme.of(
              context,
            ).textTheme.displaySmall?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 24),
          CalculationLine(
            label: 'Hours',
            value: formatHoursLabel(calculation.totalHours),
            foregroundColor: Colors.white,
          ),
          const SizedBox(height: 8),
          CalculationLine(
            label: 'Rate',
            value: '${formatMoney(rate)} / hour',
            foregroundColor: Colors.white,
          ),
          const SizedBox(height: 8),
          CalculationLine(
            label: 'Allowance',
            value: formatMoney(allowance),
            foregroundColor: Colors.white,
          ),
          const SizedBox(height: 8),
          CalculationLine(
            label: 'Uplift',
            value: formatMoney(uplift),
            foregroundColor: Colors.white,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Divider(
              color: Colors.white.withValues(alpha: .2),
              height: 1,
            ),
          ),
          CalculationLine(
            label: 'Estimated gross pay',
            value: formatMoney(calculation.totalPay),
            emphasize: true,
            foregroundColor: Colors.white,
          ),
        ],
      ),
    );
  }
}

class EntryTextField extends StatelessWidget {
  const EntryTextField({
    super.key,
    required this.label,
    required this.hint,
    this.initialValue,
    this.onChanged,
    this.keyboardType,
  });
  final String label, hint;
  final String? initialValue;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      FieldLabel(label),
      const SizedBox(height: 8),
      SelectAllTextFormField(
        initialValue: initialValue,
        keyboardType: keyboardType,
        decoration: InputDecoration(hintText: hint),
        onChanged: onChanged,
      ),
    ],
  );
}
