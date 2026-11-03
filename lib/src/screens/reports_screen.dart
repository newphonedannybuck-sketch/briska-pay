part of '../briska_app.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({
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
    final monthEntries = _entriesInPeriod(entries, period);
    final weekEntries = _entriesInPeriod(entries, _currentWeekPeriod(now));
    final weekSummary = WorkCalculator.summarize(weekEntries);
    final monthSummary = WorkCalculator.summarize(monthEntries);
    final allSummary = WorkCalculator.summarize(entries);
    return AppPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageHeading(
            title: 'Reports',
            subtitle: 'See where your time and earnings go.',
          ),
          const SizedBox(height: 22),
          ReportCard(
            title: 'This week',
            period: 'Current week',
            hours: formatHoursLabel(weekSummary.totalHours),
            wages: _money(weekSummary.totalWages),
            allowances: _money(weekSummary.totalDailyAllowance),
            uplifts: _money(weekSummary.totalJobUplift),
            grandTotal: _money(weekSummary.totalExpectedPay),
            progress: weekSummary.totalDays.clamp(0, 7) / 7,
          ),
          const SizedBox(height: 14),
          ReportCard(
            title: 'Pay period',
            period: _payPeriodLabel(period),
            hours: formatHoursLabel(monthSummary.totalHours),
            wages: _money(monthSummary.totalWages),
            allowances: _money(monthSummary.totalDailyAllowance),
            uplifts: _money(monthSummary.totalJobUplift),
            grandTotal: _money(monthSummary.totalExpectedPay),
            progress: monthSummary.totalDays.clamp(0, 20) / 20,
          ),
          const SizedBox(height: 24),
          const SectionHeading(title: 'At a glance'),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  _ReportRow(
                    icon: Icons.schedule_rounded,
                    label: 'Average day',
                    value: allSummary.totalDays == 0
                        ? 'â€”'
                        : formatHoursLabel(
                            allSummary.totalHours / allSummary.totalDays,
                          ),
                  ),
                  Divider(height: 26, color: Theme.of(context).dividerColor),
                  _ReportRow(
                    icon: Icons.payments_outlined,
                    label: 'Average daily pay',
                    value: allSummary.totalDays == 0
                        ? 'â€”'
                        : _money(
                            allSummary.totalExpectedPay / allSummary.totalDays,
                          ),
                  ),
                  Divider(height: 26, color: Theme.of(context).dividerColor),
                  _ReportRow(
                    icon: Icons.wallet_outlined,
                    label: 'Daily allowances',
                    value: _money(allSummary.totalDailyAllowance),
                  ),
                  Divider(height: 26, color: Theme.of(context).dividerColor),
                  _ReportRow(
                    icon: Icons.beach_access_outlined,
                    label: 'Holidays',
                    value: allSummary.holidayDays.toString(),
                  ),
                  Divider(height: 26, color: Theme.of(context).dividerColor),
                  _ReportRow(
                    icon: Icons.account_balance_rounded,
                    label: 'Bank Holidays (paid / unpaid)',
                    value:
                        '${allSummary.bankHolidayDays} (${allSummary.paidBankHolidayDays} / ${allSummary.unpaidBankHolidayDays})',
                  ),
                  Divider(height: 26, color: Theme.of(context).dividerColor),
                  _ReportRow(
                    icon: Icons.sick_outlined,
                    label: 'Sick days (paid / unpaid)',
                    value:
                        '${allSummary.sickDays} (${allSummary.paidSickDays} / ${allSummary.unpaidSickDays})',
                  ),
                  Divider(height: 26, color: Theme.of(context).dividerColor),
                  _ReportRow(
                    icon: Icons.event_busy_outlined,
                    label: 'Unpaid days off',
                    value: allSummary.unpaidDays.toString(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ReportCard extends StatelessWidget {
  const ReportCard({
    required this.title,
    required this.period,
    required this.hours,
    required this.wages,
    required this.allowances,
    required this.uplifts,
    required this.grandTotal,
    required this.progress,
    super.key,
  });
  final String title, period, hours, wages, allowances, uplifts, grandTotal;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    period,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Total',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            BriskaAnimatedText(
              grandTotal,
              style: Theme.of(context).textTheme.displaySmall,
            ),
            const SizedBox(height: 24),
            Wrap(
              runSpacing: 18,
              children: [
                SizedBox(
                  width: 140,
                  child: _ValueLabel(value: hours, label: 'HOURS'),
                ),
                SizedBox(
                  width: 140,
                  child: _ValueLabel(value: wages, label: 'WAGES'),
                ),
                SizedBox(
                  width: 140,
                  child: _ValueLabel(
                    value: allowances,
                    label: 'DAILY ALLOWANCES',
                  ),
                ),
                SizedBox(
                  width: 140,
                  child: _ValueLabel(value: uplifts, label: 'JOB UPLIFTS'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 7,
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: .16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ValueLabel extends StatelessWidget {
  const _ValueLabel({required this.value, required this.label});
  final String value, label;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
      ),
      const SizedBox(height: 3),
      Text(
        label,
        style: TextStyle(
          fontSize: 9,
          letterSpacing: .7,
          fontWeight: FontWeight.w800,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  );
}

class _ReportRow extends StatelessWidget {
  const _ReportRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label, value;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 12),
      Expanded(child: Text(label)),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
    ],
  );
}

