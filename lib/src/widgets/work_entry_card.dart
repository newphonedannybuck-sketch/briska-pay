part of '../briska_app.dart';

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
    final entry = WorkCalculator.recalculateEntry(this.entry);
    return Card(
      key: ValueKey('entry-card-${entry.id}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 54,
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: .09),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      Text(
                        _dayNames[entry.date.weekday - 1],
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .7,
                        ),
                      ),
                      Text(
                        formatCompactDate(entry.date),
                        style: const TextStyle(fontWeight: FontWeight.w800),
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
                        _entryTitle(entry),
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
                const SizedBox(width: 8),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _money(entry.totalPay),
                        textAlign: TextAlign.end,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        formatHoursLabel(entry.totalHours),
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
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
                  _EntryDetail(
                    label: 'Hours worked',
                    value: formatHoursLabel(entry.totalHours),
                  ),
                  _EntryDetail(
                    label: 'Rate',
                    value: '${_money(entry.hourlyRateUsed)}/hr',
                  ),
                  _EntryDetail(label: 'Base pay', value: _money(entry.wages)),
                  if (entry.dailyAllowance != 0)
                    _EntryDetail(
                      label: 'Daily allowance',
                      value: _money(entry.dailyAllowance),
                    ),
                  if (entry.jobUplift > 0)
                    _EntryDetail(
                      label: 'Job uplift',
                      value: _money(entry.jobUplift),
                    ),
                  _EntryDetail(
                    label: 'Estimated gross pay',
                    value: _money(entry.totalPay),
                  ),
                  if (entry.deductionAmount > 0) ...[
                    _EntryDetail(
                      label: 'Deduction',
                      value: _money(entry.deductionAmount),
                    ),
                    _EntryDetail(
                      label: 'Final pay',
                      value: _money(entry.netPay),
                    ),
                    if (entry.deductionReason.trim().isNotEmpty)
                      _EntryDetail(
                        label: 'Reason',
                        value: entry.deductionReason,
                      ),
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
                      foregroundColor: AppColors.danger,
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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

class _EntryDetail extends StatelessWidget {
  const _EntryDetail({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        text: '$label  ',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 12,
        ),
        children: [
          TextSpan(
            text: value,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
