part of '../briska_app.dart';

class ProfessionalReportsScreen extends StatefulWidget {
  const ProfessionalReportsScreen({
    required this.entries,
    required this.settings,
    super.key,
  });

  final List<WorkEntry> entries;
  final AppSettings settings;

  @override
  State<ProfessionalReportsScreen> createState() =>
      _ProfessionalReportsScreenState();
}

class _ProfessionalReportsScreenState extends State<ProfessionalReportsScreen> {
  ExportDateRangeType _periodType = ExportDateRangeType.currentMonth;

  @override
  Widget build(BuildContext context) {
    final range = ExportRangeResolver.resolve(
      type: _periodType,
      now: DateTime.now(),
      settings: widget.settings,
      entries: widget.entries,
    );
    final selectedEntries = range == null
        ? const <WorkEntry>[]
        : widget.entries.where((entry) => range.contains(entry.date)).toList();
    final summary = WorkCalculator.summarize(selectedEntries);
    final workedEntries = selectedEntries
        .where((entry) => entry.entryType == 'WorkDay')
        .toList();
    final workDays = workedEntries.length;
    final averageDailyPay = workDays == 0
        ? 0.0
        : summary.totalExpectedPay / workDays;
    final workedHours = workedEntries.fold<double>(
      0,
      (total, entry) => total + entry.totalHours,
    );
    final averageWorkDay = workDays == 0 ? 0.0 : workedHours / workDays;
    final periodLabel = range == null
        ? 'Date range unavailable'
        : formatFullDateRange(range.start, range.end);

    return AppPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageHeading(
            title: 'Reports',
            subtitle: 'Your earnings and work patterns at a glance.',
          ),
          const SizedBox(height: 18),
          Text(
            'Reporting period',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<ExportDateRangeType>(
              segments: const [
                ButtonSegment(
                  value: ExportDateRangeType.currentMonth,
                  label: Text('This month'),
                ),
                ButtonSegment(
                  value: ExportDateRangeType.previousMonth,
                  label: Text('Last month'),
                ),
                ButtonSegment(
                  value: ExportDateRangeType.currentPayPeriod,
                  label: Text('Pay period'),
                ),
              ],
              selected: {_periodType},
              showSelectedIcon: false,
              onSelectionChanged: (value) =>
                  setState(() => _periodType = value.first),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.date_range_outlined,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  periodLabel,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _ReportsSummaryPanel(
            earnings: summary.totalExpectedPay,
            hours: summary.totalHours,
            workDays: workDays,
            averageDailyPay: averageDailyPay,
          ),
          const SizedBox(height: 20),
          if (selectedEntries.isEmpty)
            const _ReportsEmptyState()
          else ...[
            const SectionHeading(title: 'Gross pay breakdown'),
            const SizedBox(height: 10),
            _ReportBreakdownCard(summary: summary),
            const SizedBox(height: 20),
            const SectionHeading(title: 'Work pattern'),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    _ReportRow(
                      icon: Icons.schedule_rounded,
                      label: 'Average work day',
                      value: formatHoursLabel(averageWorkDay),
                    ),
                    Divider(height: 26, color: Theme.of(context).dividerColor),
                    _ReportRow(
                      icon: Icons.beach_access_outlined,
                      label: 'Holidays',
                      value: summary.holidayDays.toString(),
                    ),
                    Divider(height: 26, color: Theme.of(context).dividerColor),
                    _ReportRow(
                      icon: Icons.account_balance_rounded,
                      label: 'Bank Holidays (paid / unpaid)',
                      value:
                          '${summary.bankHolidayDays} (${summary.paidBankHolidayDays} / ${summary.unpaidBankHolidayDays})',
                    ),
                    Divider(height: 26, color: Theme.of(context).dividerColor),
                    _ReportRow(
                      icon: Icons.sick_outlined,
                      label: 'Sick days (paid / unpaid)',
                      value:
                          '${summary.sickDays} (${summary.paidSickDays} / ${summary.unpaidSickDays})',
                    ),
                    Divider(height: 26, color: Theme.of(context).dividerColor),
                    _ReportRow(
                      icon: Icons.event_busy_outlined,
                      label: 'Unpaid days off',
                      value: summary.unpaidDays.toString(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReportsSummaryPanel extends StatelessWidget {
  const _ReportsSummaryPanel({
    required this.earnings,
    required this.hours,
    required this.workDays,
    required this.averageDailyPay,
  });

  final double earnings;
  final double hours;
  final int workDays;
  final double averageDailyPay;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: colors.primary,
        borderRadius: BorderRadius.circular(24),
        boxShadow: BriskaShadows.card(
          Theme.of(context).brightness == Brightness.dark,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ESTIMATED GROSS PAY',
            style: TextStyle(
              color: colors.onPrimary.withValues(alpha: .72),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 5),
          BriskaAnimatedText(
            _money(earnings),
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
              color: colors.onPrimary,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _ReportsHeroMetric(
                  label: 'Hours',
                  value: formatHoursLabel(hours),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ReportsHeroMetric(
                  label: workDays == 1 ? 'Day recorded' : 'Days recorded',
                  value: workDays.toString(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ReportsHeroMetric(
                  label: 'Daily average',
                  value: _money(averageDailyPay),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReportsHeroMetric extends StatelessWidget {
  const _ReportsHeroMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: onPrimary.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                color: onPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: onPrimary.withValues(alpha: .75),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportBreakdownCard extends StatelessWidget {
  const _ReportBreakdownCard({required this.summary});

  final WorkSummary summary;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            _ReportBreakdownRow(
              label: 'Base pay',
              value: summary.totalWages,
              total: summary.totalExpectedPay,
              color: BriskaColors.primary,
            ),
            const SizedBox(height: 16),
            _ReportBreakdownRow(
              label: 'Daily allowances',
              value: summary.totalDailyAllowance,
              total: summary.totalExpectedPay,
              color: BriskaColors.calendarHoliday,
            ),
            const SizedBox(height: 16),
            _ReportBreakdownRow(
              label: 'Job uplifts',
              value: summary.totalJobUplift,
              total: summary.totalExpectedPay,
              color: BriskaColors.warning,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportBreakdownRow extends StatelessWidget {
  const _ReportBreakdownRow({
    required this.label,
    required this.value,
    required this.total,
    required this.color,
  });

  final String label;
  final double value;
  final double total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final progress = total <= 0 ? 0.0 : (value / total).clamp(0.0, 1.0);
    return Column(
      children: [
        Row(
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              _money(value),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            color: color,
            backgroundColor: color.withValues(alpha: .12),
          ),
        ),
      ],
    );
  }
}

class _ReportsEmptyState extends StatelessWidget {
  const _ReportsEmptyState();

  @override
  Widget build(BuildContext context) {
    return const BriskaEmptyState(
      icon: Icons.insights_outlined,
      title: 'No activity in this period',
      message: 'Try another reporting period, or record a work day.',
    );
  }
}
