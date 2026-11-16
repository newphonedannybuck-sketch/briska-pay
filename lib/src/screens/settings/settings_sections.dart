import '../../../design_system/briska_cards.dart';
import 'package:flutter/material.dart';
import '../../../design_system/briska_spacing.dart';
import '../../currency.dart';
import '../../models.dart';
import '../../presentation_format.dart';
import '../../display_format.dart';
import '../../pay_schedule.dart';
import '../../widgets/form_controls.dart';
import '../../widgets/shared_ui.dart';
import 'settings_form_controls.dart';

typedef SaveSettings =
    Future<bool> Function(
      AppSettings value, {
      String? successMessage,
      required String failureMessage,
    });

/// Reads the live draft in completion callbacks so focus changes save the latest edit.
class ProfileSettingsSection extends StatelessWidget {
  const ProfileSettingsSection({
    required this.readPreferences,
    required this.onChanged,
    required this.onSave,
    required this.formRevision,

    super.key,
  });
  final AppSettings Function() readPreferences;
  final ValueChanged<AppSettings> onChanged;
  final SaveSettings onSave;
  final int formRevision;

  @override
  Widget build(BuildContext context) => BriskaCard(
    padding: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(BriskaSpacing.cardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FieldLabel('Full name'),
          const SizedBox(height: 8),
          SettingsFinishedTextField(
            key: ValueKey('fullName-$formRevision'),
            initialValue: readPreferences().fullName,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            hintText: 'Enter your full name',
            onChanged: (value) =>
                onChanged(readPreferences().copyWith(fullName: value.trim())),
            onFinished: () => onSave(
              readPreferences(),
              successMessage: 'Personal details updated.',
              failureMessage: 'Could not save personal details.',
            ),
          ),
          const SizedBox(height: 16),
          const FieldLabel('Employer / company'),
          const SizedBox(height: 8),
          SettingsFinishedTextField(
            key: ValueKey('companyName-$formRevision'),
            initialValue: readPreferences().companyName,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            hintText: 'Enter employer or company name',
            onChanged: (value) => onChanged(
              readPreferences().copyWith(companyName: value.trim()),
            ),
            onFinished: () => onSave(
              readPreferences(),
              successMessage: 'Personal details updated.',
              failureMessage: 'Could not save personal details.',
            ),
          ),
        ],
      ),
    ),
  );
}

/// Reads the live draft in completion callbacks so focus changes save the latest edit.
class PaySettingsSection extends StatelessWidget {
  const PaySettingsSection({
    required this.readPreferences,
    required this.onChanged,
    required this.onSave,
    required this.formRevision,
    required this.currencyPickerRevision,
    required this.onCurrencyChanged,
    required this.onRateChanged,
    super.key,
  });
  final AppSettings Function() readPreferences;
  final ValueChanged<AppSettings> onChanged;
  final SaveSettings onSave;
  final int formRevision;
  final int currencyPickerRevision;
  final ValueChanged<CurrencyConfig> onCurrencyChanged;
  final void Function(String, {required bool primary}) onRateChanged;

  @override
  Widget build(BuildContext context) => BriskaCard(
    padding: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(BriskaSpacing.cardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FieldLabel('Currency'),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: ValueKey(
              '${readPreferences().currency.code}-'
              '$currencyPickerRevision',
            ),
            isExpanded: true,
            initialValue: readPreferences().currency.code,
            items: CurrencyCatalog.supported
                .map(
                  (currency) => DropdownMenuItem(
                    value: currency.code,
                    child: Text('${currency.displayName} · ${currency.symbol}'),
                  ),
                )
                .toList(),
            onChanged: (code) {
              if (code != null && code != readPreferences().currency.code) {
                onCurrencyChanged(CurrencyCatalog.byCode(code));
              }
            },
          ),
          const SizedBox(height: 16),
          const FieldLabel('Primary rate'),
          const SizedBox(height: 12),
          SettingsTextField(
            key: ValueKey('primaryRateLabel-$formRevision'),
            label: 'Name',
            value: readPreferences().primaryRateLabel,
            hint: 'Standard',
            maxLength: 24,
            onChanged: (value) => onChanged(
              readPreferences().copyWith(primaryRateLabel: value.trim()),
            ),
            onFinished: () => onSave(
              readPreferences(),
              successMessage: 'Pay rates updated.',
              failureMessage: 'Rate names cannot be blank.',
            ),
          ),
          const SizedBox(height: 12),
          const FieldLabel('Hourly rate'),
          const SizedBox(height: 8),
          SelectAllTextFormField(
            key: ValueKey('homeRate-$formRevision'),
            initialValue: currencyInputValue(
              readPreferences().primaryRateValue,
            ),
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              prefixText: currencyPrefix,
              hintText: 'e.g. 20.00',
            ),
            onChanged: (value) => onRateChanged(value, primary: true),
            onFinished: () => onSave(
              readPreferences(),
              successMessage: 'Pay rates updated.',
              failureMessage: 'Could not save pay rates.',
            ),
          ),
          const SizedBox(height: 16),
          const Divider(height: 32),
          const FieldLabel('Secondary rate'),
          const SizedBox(height: 12),
          SettingsTextField(
            key: ValueKey('secondaryRateLabel-$formRevision'),
            label: 'Name',
            value: readPreferences().secondaryRateLabel,
            hint: 'Overtime',
            maxLength: 24,
            onChanged: (value) => onChanged(
              readPreferences().copyWith(secondaryRateLabel: value.trim()),
            ),
            onFinished: () => onSave(
              readPreferences(),
              successMessage: 'Pay rates updated.',
              failureMessage: 'Rate names cannot be blank.',
            ),
          ),
          const SizedBox(height: 12),
          const FieldLabel('Hourly rate'),
          const SizedBox(height: 8),
          SelectAllTextFormField(
            key: ValueKey('awayRate-$formRevision'),
            initialValue: currencyInputValue(
              readPreferences().secondaryRateValue,
            ),
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              prefixText: currencyPrefix,
              hintText: 'e.g. 25.00',
            ),
            onChanged: (value) => onRateChanged(value, primary: false),
            onFinished: () => onSave(
              readPreferences(),
              successMessage: 'Pay rates updated.',
              failureMessage: 'Could not save pay rates.',
            ),
          ),
        ],
      ),
    ),
  );
}

/// Reads the live draft in completion callbacks so focus changes save the latest edit.
class WorkDefaultsSection extends StatelessWidget {
  const WorkDefaultsSection({
    required this.readPreferences,
    required this.onChanged,
    required this.onSave,
    required this.formRevision,

    super.key,
  });
  final AppSettings Function() readPreferences;
  final ValueChanged<AppSettings> onChanged;
  final SaveSettings onSave;
  final int formRevision;

  @override
  Widget build(BuildContext context) => BriskaCard(
    padding: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(BriskaSpacing.cardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SettingsTextField(
                  key: ValueKey('defaultStart-$formRevision'),
                  label: 'Default start time',
                  value: readPreferences().defaultStartTime,
                  hint: '08:00',
                  normalizeTime: true,
                  onChanged: (value) => onChanged(
                    readPreferences().copyWith(defaultStartTime: value),
                  ),
                  onFinished: () => onSave(
                    readPreferences(),
                    failureMessage: 'Could not save work defaults.',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SettingsTextField(
                  key: ValueKey('defaultFinish-$formRevision'),
                  label: 'Default finish time',
                  value: readPreferences().defaultFinishTime,
                  hint: '16:30',
                  normalizeTime: true,
                  onChanged: (value) => onChanged(
                    readPreferences().copyWith(defaultFinishTime: value),
                  ),
                  onFinished: () => onSave(
                    readPreferences(),
                    failureMessage: 'Could not save work defaults.',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SettingsTextField(
            key: ValueKey('defaultBreak-$formRevision'),
            label: 'Default break minutes',
            value: readPreferences().defaultBreakMinutes.toString(),
            hint: '30',
            keyboardType: TextInputType.number,
            onChanged: (value) => onChanged(
              readPreferences().copyWith(
                defaultBreakMinutes: int.tryParse(value),
              ),
            ),
            onFinished: () => onSave(
              readPreferences(),
              failureMessage: 'Could not save work defaults.',
            ),
          ),
          const SizedBox(height: 16),
          const FieldLabel('Default rate'),
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
                    readPreferences().labelForRate('primary'),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ButtonSegment(
                  value: 'secondary',
                  label: Text(
                    readPreferences().labelForRate('secondary'),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              selected: {readPreferences().defaultRateType},
              onSelectionChanged: (values) => onSave(
                readPreferences().copyWith(defaultRateType: values.first),
                failureMessage: 'Could not save work defaults.',
              ),
              showSelectedIcon: false,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Reads the live draft in completion callbacks so focus changes save the latest edit.
class PayScheduleSection extends StatelessWidget {
  const PayScheduleSection({
    required this.readPreferences,
    required this.onChanged,
    required this.onSave,
    required this.formRevision,
    required this.onScheduleChanged,
    required this.onChooseAnchorDate,
    super.key,
  });
  final AppSettings Function() readPreferences;
  final ValueChanged<AppSettings> onChanged;
  final SaveSettings onSave;
  final int formRevision;
  final ValueChanged<AppSettings> onScheduleChanged;
  final VoidCallback onChooseAnchorDate;

  @override
  Widget build(BuildContext context) => BriskaCard(
    padding: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(BriskaSpacing.cardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FieldLabel('Pay period type'),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: ValueKey('payFrequency-$formRevision'),
            isExpanded: true,
            initialValue: normalisePayFrequency(readPreferences().payFrequency),
            items:
                const [
                      weeklyPayFrequency,
                      fortnightlyPayFrequency,
                      fourWeeklyPayFrequency,
                      calendarMonthlyPayFrequency,
                      customMonthlyPayFrequency,
                      lastFridayPayFrequency,
                    ]
                    .map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text(value)),
                    )
                    .toList(),
            onChanged: (value) {
              if (value == null) return;
              final allowedRules = _paydayRulesFor(value);
              final currentRule =
                  readPreferences().paydayRule == paydayFollowingWeekday
                  ? paydayNextSelectedWeekdayAfterPeriodEnd
                  : readPreferences().paydayRule;
              onScheduleChanged(
                readPreferences().copyWith(
                  payFrequency: value,
                  paydayRule: allowedRules.contains(currentRule)
                      ? currentRule
                      : paydayOnPeriodEnd,
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          ..._payScheduleControls(context),
        ],
      ),
    ),
  );
  List<Widget> _payScheduleControls(BuildContext context) {
    final type = normalisePayFrequency(readPreferences().payFrequency);
    if (fixedCyclePayFrequencies.contains(type)) {
      return [
        Text(
          'Periods repeat every ${type == weeklyPayFrequency
              ? 7
              : type == fortnightlyPayFrequency
              ? 14
              : 28} days from a known pay period start date.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
        const FieldLabel('Known pay period start date'),
        const SizedBox(height: 8),
        DatePickerTile(
          value: _dateLabel(
            _parseSettingsDate(readPreferences().payPeriodAnchorDate),
          ),
          isMissing: requiresPayPeriodAnchor(readPreferences()),
          onPressed: onChooseAnchorDate,
        ),
        if (requiresPayPeriodAnchor(readPreferences())) ...[
          const SizedBox(height: 10),
          Text(
            'Choose an anchor date so Briska Pay can calculate periods forwards and backwards accurately.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        const SizedBox(height: 16),
        ..._paydayRuleControls(type),
      ];
    }
    if (type == calendarMonthlyPayFrequency) {
      return [
        Text(
          'Period runs from the first to the last day of each month.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
        ..._paydayRuleControls(type),
      ];
    }
    if (type == customMonthlyPayFrequency) {
      return [
        const FieldLabel('Period start day'),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          initialValue: readPreferences().customPeriodStartDay.clamp(1, 31),
          items: List.generate(
            31,
            (index) =>
                DropdownMenuItem(value: index + 1, child: Text('${index + 1}')),
          ),
          onChanged: (value) => onScheduleChanged(
            readPreferences().copyWith(customPeriodStartDay: value),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'The period ends on the day before the next period begins.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
        ..._paydayRuleControls(type),
      ];
    }
    return [
      Text(
        'Period starts on the first Monday after the previous month\'s last Friday, ends on the current month\'s last Friday, and payday is the current month\'s last Friday.',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    ];
  }

  List<Widget> _paydayRuleControls(String type) {
    final allowedRules = _paydayRulesFor(type);
    final storedRule = readPreferences().paydayRule == paydayFollowingWeekday
        ? paydayNextSelectedWeekdayAfterPeriodEnd
        : readPreferences().paydayRule;
    final rule = allowedRules.contains(storedRule)
        ? storedRule
        : paydayOnPeriodEnd;
    final widgets = <Widget>[
      const FieldLabel('Payday rule'),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        isExpanded: true,
        initialValue: rule,
        items: allowedRules
            .map((value) => DropdownMenuItem(value: value, child: Text(value)))
            .toList(),
        onChanged: (value) =>
            onScheduleChanged(readPreferences().copyWith(paydayRule: value)),
      ),
    ];
    if (rule == paydayDaysAfterPeriodEnd) {
      widgets.addAll([
        const SizedBox(height: 16),
        SettingsTextField(
          label: 'Days after period end',
          value: readPreferences().paydayOffsetDays.toString(),
          hint: '0',
          keyboardType: TextInputType.number,
          onChanged: (value) => onChanged(
            readPreferences().copyWith(paydayOffsetDays: int.tryParse(value)),
          ),
          onFinished: () => onSave(
            readPreferences(),
            successMessage: 'Pay schedule updated.',
            failureMessage: 'Could not update pay schedule.',
          ),
        ),
      ]);
    }
    if (rule == paydayNextSelectedWeekdayAfterPeriodEnd) {
      widgets.addAll([
        const SizedBox(height: 16),
        const FieldLabel('Payday weekday'),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          isExpanded: true,
          initialValue: readPreferences().paydaySelectedWeekday.clamp(
            DateTime.monday,
            DateTime.sunday,
          ),
          items: List.generate(
            DateTime.daysPerWeek,
            (index) => DropdownMenuItem(
              value: index + DateTime.monday,
              child: Text(weekdayNames[index]),
            ),
          ),
          onChanged: (value) => onScheduleChanged(
            readPreferences().copyWith(
              paydaySelectedWeekday: value,
              paydayWeekday: value == null ? null : weekdayNames[value - 1],
              payDay: value == null ? null : weekdayNames[value - 1],
            ),
          ),
        ),
      ]);
    }
    if (rule == paydayFixedDaySameMonth ||
        rule == paydayFixedDayFollowingMonth) {
      widgets.addAll([
        const SizedBox(height: 16),
        const FieldLabel('Fixed calendar day'),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          initialValue: readPreferences().paydayFixedDay.clamp(1, 31),
          items: List.generate(
            31,
            (index) =>
                DropdownMenuItem(value: index + 1, child: Text('${index + 1}')),
          ),
          onChanged: (value) => onScheduleChanged(
            readPreferences().copyWith(paydayFixedDay: value),
          ),
        ),
      ]);
    }
    return widgets;
  }

  List<String> _paydayRulesFor(String type) {
    final normalised = normalisePayFrequency(type);
    if (fixedCyclePayFrequencies.contains(normalised)) {
      return const [
        paydayOnPeriodEnd,
        paydayDaysAfterPeriodEnd,
        paydayNextSelectedWeekdayAfterPeriodEnd,
      ];
    }
    if (normalised == lastFridayPayFrequency) {
      return const [paydayOnPeriodEnd];
    }
    return const [
      paydayOnPeriodEnd,
      paydayDaysAfterPeriodEnd,
      paydayNextSelectedWeekdayAfterPeriodEnd,
      paydayFixedDaySameMonth,
      paydayFixedDayFollowingMonth,
      paydayLastWorkingDaySameMonth,
      paydayLastFridayOfMonth,
    ];
  }

  DateTime? _parseSettingsDate(String value) {
    final parsed = DateTime.tryParse(value);
    return parsed == null
        ? null
        : DateTime(parsed.year, parsed.month, parsed.day);
  }

  String _dateLabel(DateTime? date) {
    if (date == null) return 'Choose date';
    return formatFullDate(date);
  }
}
