import '../../../design_system/briska_surfaces.dart';
import 'package:flutter/material.dart';
import '../../models.dart';
import '../../presentation_format.dart';
import '../../work_calculator.dart';
import '../../widgets/shared_ui.dart';
import '../../widgets/form_controls.dart';
import 'entry_widgets.dart';

class EntryDayTypeSelector extends StatelessWidget {
  const EntryDayTypeSelector({
    required this.entryType,
    required this.isBankHoliday,
    required this.onSelected,
    super.key,
  });
  final String entryType;
  final bool isBankHoliday;
  final ValueChanged<String> onSelected;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children:
        const [
          (EntryType.workDay, 'Work Day', Icons.work_outline),
          (EntryType.holiday, 'Holiday', Icons.beach_access_outlined),
          (
            EntryType.bankHoliday,
            'Bank Holiday',
            Icons.account_balance_rounded,
          ),
          (EntryType.sickDay, 'Sick Day', Icons.sick_outlined),
          (EntryType.unpaidDayOff, 'Unpaid Day Off', Icons.event_busy_outlined),
        ].map((option) {
          final selected =
              entryType == option.$1.storageValue ||
              (isBankHoliday && option.$1 == EntryType.bankHoliday);
          return ChoiceChip(
            showCheckmark: false,
            key: ValueKey('day-type-${option.$1.name}'),
            selected: selected,
            selectedColor: BriskaSurfaces.dayType(
              context,
              option.$1.storageValue,
            ).withValues(alpha: .17),
            side: BorderSide(
              color: selected
                  ? BriskaSurfaces.dayType(context, option.$1.storageValue)
                  : Theme.of(context).colorScheme.outlineVariant,
            ),
            avatar: Icon(
              option.$3,
              size: 18,
              color: BriskaSurfaces.dayType(context, option.$1.storageValue),
            ),
            label: Text(option.$2),
            onSelected: (_) => onSelected(option.$1.storageValue),
          );
        }).toList(),
  );
}

class WorkTimeSection extends StatelessWidget {
  const WorkTimeSection({
    required this.startTime,
    required this.finishTime,
    required this.breakInput,
    required this.calculation,
    required this.onStartChanged,
    required this.onFinishChanged,
    required this.onBreakChanged,
    super.key,
  });
  final String startTime, finishTime, breakInput;
  final WorkCalculation calculation;
  final ValueChanged<String> onStartChanged, onFinishChanged, onBreakChanged;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: TimeInputField(
              label: 'Start time',
              hint: '08:00',
              initialValue: startTime,
              onChanged: onStartChanged,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TimeInputField(
              label: 'Finish time',
              hint: '16:30',
              initialValue: finishTime,
              onChanged: onFinishChanged,
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      EntryTextField(
        label: 'Break minutes',
        hint: 'Enter minutes',
        initialValue: breakInput,
        keyboardType: TextInputType.number,
        onChanged: onBreakChanged,
      ),
      if (!calculation.isValid) ...[
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 18,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                calculation.error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ],
    ],
  );
}

class WorkPaySection extends StatelessWidget {
  const WorkPaySection({
    required this.preferences,
    required this.rateType,
    required this.editingEntryId,
    required this.selectedRate,
    required this.allowanceHasValue,
    required this.appliedAllowance,
    required this.onRateTypeChanged,
    required this.onRateChanged,
    required this.onAllowanceChanged,
    super.key,
  });
  final AppSettings preferences;
  final String rateType;
  final String? editingEntryId;
  final double selectedRate, appliedAllowance;
  final bool allowanceHasValue;
  final ValueChanged<String> onRateTypeChanged,
      onRateChanged,
      onAllowanceChanged;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const EntrySectionHeading(
        icon: Icons.payments_outlined,
        title: 'Pay details',
        subtitle: 'Rate and extras',
      ),
      const SizedBox(height: 22),
      const FieldLabel('Rate used'),
      const SizedBox(height: 9),
      SizedBox(
        width: double.infinity,
        child: SegmentedButton<String>(
          direction: MediaQuery.textScalerOf(context).scale(1) >= 1.5
              ? Axis.vertical
              : Axis.horizontal,
          segments: [
            ButtonSegment(
              value: 'primary',
              label: Text(
                preferences.labelForRate('primary'),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ButtonSegment(
              value: 'secondary',
              label: Text(
                preferences.labelForRate('secondary'),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          selected: {rateType},
          onSelectionChanged: (values) => onRateTypeChanged(values.first),
          showSelectedIcon: false,
        ),
      ),
      const SizedBox(height: 16),
      AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const FieldLabel('Hourly rate for this day'),
            const SizedBox(height: 8),
            SelectAllTextFormField(
              key: ValueKey('rate-$rateType'),
              initialValue: currencyInputValue(selectedRate),
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                prefixText: currencyPrefix,
                suffixText: '/ hour',
              ),
              onChanged: onRateChanged,
            ),
            ...[
              const SizedBox(height: 14),
              const FieldLabel('Daily allowance'),
              const SizedBox(height: 8),
              SelectAllTextFormField(
                key: ValueKey('allowance-$editingEntryId-$rateType'),
                initialValue: allowanceHasValue
                    ? currencyInputValue(appliedAllowance)
                    : '',
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  prefixText: currencyPrefix,
                  hintText: 'e.g. 25.00',
                  helperText: 'Optional. Leave blank for no allowance.',
                ),
                onChanged: onAllowanceChanged,
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 22),
    ],
  );
}
