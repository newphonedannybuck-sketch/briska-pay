import '../../design_system/briska_surfaces.dart';
import '../../design_system/briska_cards.dart';
import 'detail_text.dart';
import 'package:flutter/material.dart';
import '../models.dart';
import '../display_format.dart';
import '../presentation_format.dart';
import '../work_calculator.dart';

class WorkEntryCard extends StatelessWidget {
  const WorkEntryCard({
    required this.entry,
    this.compact = false,
    this.onEdit,
    this.onDelete,
    this.settings = const AppSettings(),
    super.key,
  });
  final WorkEntry entry;
  final bool compact;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    return BriskaCard(
      tint: BriskaSurfaces.dayType(context, entry.entryType),
      padding: EdgeInsets.zero,
      key: ValueKey('entry-card-${entry.id}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 58,
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: BriskaSurfaces.dayType(
                      context,
                      entry.entryType,
                    ).withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      Text(
                        shortWeekdayNames[entry.date.weekday - 1],
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: .7,
                        ),
                      ),
                      Text(
                        formatCompactDate(entry.date),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entryTitle(entry),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        entry.entryType == 'WorkDay'
                            ? '${WorkCalculator.normalizeTime(entry.startTime) ?? entry.startTime} - '
                                  '${WorkCalculator.normalizeTime(entry.finishTime) ?? entry.finishTime}  -  '
                                  '${settings.labelForRate(entry.rateType)}'
                            : entry.entryType == 'Holiday'
                            ? 'Paid holiday - ${settings.labelForRate('primary')}'
                            : entry.type == EntryType.bankHoliday
                            ? '${entry.isPaidBankHoliday ? 'Paid' : 'Unpaid'} Bank Holiday${entry.isPaidBankHoliday ? ' - ${settings.labelForRate('primary')}' : ''}'
                            : entry.entryType == 'SickDay'
                            ? '${entry.isPaidSickDay ? 'Paid' : 'Unpaid'} sick day${entry.isPaidSickDay ? ' - ${settings.labelForRate('primary')}' : ''}'
                            : 'Unpaid day off',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      formatMoney(entry.totalPay),
                      maxLines: 1,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  formatHoursLabel(entry.totalHours),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _StatusPill(
                  icon: entry.entryType == 'Holiday'
                      ? Icons.beach_access_outlined
                      : entry.type == EntryType.bankHoliday
                      ? Icons.account_balance_rounded
                      : entry.entryType == 'SickDay'
                      ? Icons.sick_outlined
                      : entry.entryType == 'UnpaidDayOff'
                      ? Icons.event_busy_outlined
                      : Icons.work_outline_rounded,
                  label: entry.entryType == 'Holiday'
                      ? 'Type: Holiday'
                      : entry.type == EntryType.bankHoliday
                      ? 'Type: Bank Holiday (${entry.isPaidBankHoliday ? 'Paid' : 'Unpaid'})'
                      : entry.entryType == 'SickDay'
                      ? 'Type: Sick Day (${entry.isPaidSickDay ? 'Paid' : 'Unpaid'})'
                      : entry.entryType == 'UnpaidDayOff'
                      ? 'Type: Unpaid'
                      : 'Type: Work day',
                ),
                _StatusPill(
                  icon: Icons.payments_outlined,
                  label: 'Rate: ${settings.labelForRate(entry.rateType)}',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: .055),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  DetailText(
                    label: 'Hours worked',
                    value: formatHoursLabel(entry.totalHours),
                  ),
                  DetailText(
                    label: 'Rate',
                    value: '${formatMoney(entry.hourlyRateUsed)}/hr',
                  ),
                  DetailText(
                    label: 'Base pay',
                    value: formatMoney(entry.wages),
                  ),
                  if (entry.dailyAllowance != 0)
                    DetailText(
                      label: 'Daily allowance',
                      value: formatMoney(entry.dailyAllowance),
                    ),
                  if (entry.jobUplift > 0)
                    DetailText(
                      label: 'Job uplift',
                      value: formatMoney(entry.jobUplift),
                    ),
                  DetailText(
                    label: 'Estimated gross pay',
                    value: formatMoney(entry.totalPay),
                  ),
                  if (entry.deductionAmount > 0) ...[
                    DetailText(
                      label: 'Deduction',
                      value: formatMoney(entry.deductionAmount),
                    ),
                    DetailText(
                      label: 'Final pay',
                      value: formatMoney(entry.netPay),
                    ),
                    if (entry.deductionReason.trim().isNotEmpty)
                      DetailText(label: 'Reason', value: entry.deductionReason),
                  ],
                ],
              ),
            ),
            if (!compact) ...[
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 6,
                runSpacing: 6,
                children: [
                  TextButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Edit'),
                  ),
                  TextButton.icon(
                    onPressed: onDelete,
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('Delete'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      label: label,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.hasBoundedWidth
              ? constraints.maxWidth
              : 180.0;
          return ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: colorScheme.primary.withValues(alpha: .18),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 15, color: colorScheme.primary),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,

                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
