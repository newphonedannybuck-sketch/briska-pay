part of '../briska_app.dart';

class LegacyHomeScreen extends StatelessWidget {
  const LegacyHomeScreen({
    required this.entries,
    required this.settings,
    required this.onViewEntries,
    required this.onAddEntry,
    required this.onOpenCalendar,
    required this.onOpenReports,
    required this.onOpenExport,
    required this.onConfigurePayday,
    super.key,
  });

  final List<WorkEntry> entries;
  final AppSettings settings;
  final VoidCallback onViewEntries;
  final VoidCallback onAddEntry;
  final VoidCallback onOpenCalendar;
  final VoidCallback onOpenReports;
  final VoidCallback onOpenExport;
  final VoidCallback onConfigurePayday;

  @override
  Widget build(BuildContext context) {
    if (kDebugMode) debugPrint('HomeScreen build');
    final now = DateTime.now();
    final period = getCurrentPayPeriodForSettings(
      date: now,
      settings: settings,
    );
    final periodEntries = _entriesInPeriod(entries, period);
    final periodSummary = WorkCalculator.summarize(periodEntries);
    final today = DateTime(now.year, now.month, now.day);
    final todaySummary = WorkCalculator.summarize(
      entries.where(
        (entry) =>
            entry.date.year == today.year &&
            entry.date.month == today.month &&
            entry.date.day == today.day,
      ),
    );
    final nextPayday = period.payday.isBefore(today)
        ? getCurrentPayPeriodForSettings(
            date: period.end.add(const Duration(days: 1)),
            settings: settings,
          ).payday
        : period.payday;
    final userName = settings.fullName.trim().isEmpty
        ? 'there'
        : settings.fullName.trim().split(RegExp(r'\s+')).first;
    return AppPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _greetingFor(now),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      userName,
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const BriskaLogo(size: 40),
                  const SizedBox(height: 8),
                  Text(
                    'Briska Pay',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'Track your hours. Know your pay.',
                    style: TextStyle(color: Colors.transparent, fontSize: 1),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          EntranceAnimation(
            child: PayPeriodCard(entries: entries, settings: settings),
          ),
          const SizedBox(height: 16),
          EntranceAnimation(
            delay: Duration(milliseconds: 70),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final cards = [
                  MiniSummaryCard(
                    icon: Icons.schedule_rounded,
                    label: 'Hours',
                    value: periodSummary.totalDays == 0
                        ? '0h'
                        : formatHoursLabel(periodSummary.totalHours),
                    detail: 'Pay period',
                  ),
                  MiniSummaryCard(
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'Next payday',
                    value: nextPayday.day.toString(),
                    detail: _monthNames[nextPayday.month - 1],
                  ),
                  MiniSummaryCard(
                    icon: Icons.work_history_outlined,
                    label: 'Work days',
                    value: periodSummary.entries
                        .where((entry) => entry.entryType == 'WorkDay')
                        .length
                        .toString(),
                    detail: todaySummary.totalExpectedPay == 0
                        ? 'Today'
                        : '+${_money(todaySummary.totalExpectedPay)}',
                  ),
                  MiniSummaryCard(
                    icon: Icons.sick_outlined,
                    label: 'Sick days',
                    value: periodSummary.sickDays.toString(),
                    detail:
                        '${periodSummary.paidSickDays} paid · ${periodSummary.unpaidSickDays} unpaid',
                  ),
                ];
                if (constraints.maxWidth < 520) {
                  return Row(
                    children: [
                      for (final item in cards) ...[
                        Expanded(child: item),
                        if (item != cards.last) const SizedBox(width: 8),
                      ],
                    ],
                  );
                }
                return Row(
                  children: [
                    for (final item in cards) ...[
                      Expanded(child: item),
                      if (item != cards.last) const SizedBox(width: 16),
                    ],
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 32),
          SectionHeading(
            title: 'Recent work',
            action: 'View all',
            onTap: onViewEntries,
          ),
          const SizedBox(height: 16),
          if (entries.isEmpty)
            const EmptyWorkState()
          else
            ...entries
                .take(3)
                .toList()
                .asMap()
                .entries
                .map(
                  (item) => EntranceAnimation(
                    delay: Duration(milliseconds: 120 + (item.key * 55)),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: WorkEntryCard(
                        entry: item.value,
                        compact: true,
                        settings: settings,
                      ),
                    ),
                  ),
                ),
          const SizedBox(height: 72),
        ],
      ),
    );
  }
}

String _greetingFor(DateTime date) {
  if (date.hour < 12) return 'Good morning';
  if (date.hour < 17) return 'Good afternoon';
  return 'Good evening';
}

class PayPeriodCard extends StatelessWidget {
  const PayPeriodCard({
    required this.entries,
    required this.settings,
    super.key,
  });

  final List<WorkEntry> entries;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final period = getCurrentPayPeriodForSettings(
      date: now,
      settings: settings,
    );
    final periodStart = period.start;
    final periodEnd = period.end;
    final today = DateTime(now.year, now.month, now.day);
    final nextPaydayPeriod = period.payday.isBefore(today)
        ? getCurrentPayPeriodForSettings(
            date: periodEnd.add(const Duration(days: 1)),
            settings: settings,
          )
        : period;
    final nextPayday = nextPaydayPeriod.payday;
    final periodDays = periodEnd.difference(periodStart).inDays + 1;
    final elapsedDays = now.difference(periodStart).inDays + 1;
    final progress = (elapsedDays / periodDays).clamp(0.0, 1.0);
    final daysToPayday = nextPayday.difference(today).inDays;
    final periodEntries = _entriesInPeriod(entries, period);
    final summary = WorkCalculator.summarize(periodEntries);
    final todaySummary = WorkCalculator.summarize(
      entries.where(
        (entry) =>
            entry.date.year == today.year &&
            entry.date.month == today.month &&
            entry.date.day == today.day,
      ),
    );
    final colorScheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 360;
        return Card(
          child: Padding(
            padding: EdgeInsets.all(compact ? 16 : 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Current Pay',
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withValues(alpha: .08),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${periodStart.day} ${_monthNames[periodStart.month - 1]} - '
                          '${periodEnd.day} ${_monthNames[periodEnd.month - 1]}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colorScheme.primary,
                            fontSize: compact ? 11 : 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (summary.entries.isNotEmpty) ...[
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: BriskaAnimatedText(
                      _money(summary.totalExpectedPay),
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: compact ? 34 : 40,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    todaySummary.totalExpectedPay == 0
                        ? 'No earnings recorded today'
                        : '+${_money(todaySummary.totalExpectedPay)} today',
                    style: TextStyle(
                      color: todaySummary.totalExpectedPay == 0
                          ? colorScheme.onSurfaceVariant
                          : colorScheme.secondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ] else ...[
                  Row(
                    children: [
                      Icon(
                        Icons.work_outline_rounded,
                        color: colorScheme.primary,
                        size: 28,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          'No work recorded yet',
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            fontSize: compact ? 18 : 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Add your first work day to see hours and estimated pay.',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Pay Period Progress',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '${elapsedDays.clamp(1, periodDays)} of $periodDays days',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    color: colorScheme.primary,
                    backgroundColor: colorScheme.primary.withValues(alpha: .12),
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: EdgeInsets.all(compact ? 14 : 16),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: .06),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.account_balance_wallet_outlined,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Next Payday',
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${_weekdayName(nextPayday)}, ${nextPayday.day} '
                              '${_fullMonthNames[nextPayday.month - 1]}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colorScheme.onSurface,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          daysToPayday == 0 ? 'Today' : '$daysToPayday days',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class MiniSummaryCard extends StatelessWidget {
  const MiniSummaryCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
    super.key,
  });

  final IconData icon;
  final String label;
  final String? value;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary, size: 20),
            const SizedBox(height: 16),
            Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            if (value == null)
              Text('No entries', style: Theme.of(context).textTheme.titleMedium)
            else ...[
              BriskaAnimatedText(
                value!,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontSize: 18),
              ),
              Text(
                detail!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
