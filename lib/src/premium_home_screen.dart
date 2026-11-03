import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../design_system/briska_colors.dart';
import '../design_system/briska_cards.dart';
import '../design_system/briska_radius.dart';
import '../design_system/briska_spacing.dart';
import '../design_system/briska_theme.dart';
import 'currency.dart';
import 'display_format.dart';
import 'models.dart';
import 'pay_schedule.dart';
import 'work_calculator.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    required this.entries,
    required this.settings,
    required this.onViewEntries,
    required this.onAddEntry,
    required this.onOpenCalendar,
    required this.onOpenReports,
    required this.onOpenExport,
    required this.onConfigurePayday,
    this.onEditEntry,
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
  final ValueChanged<WorkEntry>? onEditEntry;

  @override
  Widget build(BuildContext context) {
    if (kDebugMode) debugPrint('HomeScreen build');
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final period = getCurrentPayPeriodForSettings(
      date: now,
      settings: settings,
    );
    final nextPayday = period.payday.isBefore(today)
        ? getCurrentPayPeriodForSettings(
            date: period.end.add(const Duration(days: 1)),
            settings: settings,
          ).payday
        : period.payday;
    final recentEntries = [...entries]
      ..sort((a, b) {
        final byDate = b.date.compareTo(a.date);
        return byDate != 0 ? byDate : b.id.compareTo(a.id);
      });

    return _DashboardPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DashboardHeader(
            greeting: _greetingFor(now),
            supportingText: entries.isEmpty
                ? 'Add your first day to start tracking your pay.'
                : 'Welcome back.',
          ),
          const SizedBox(height: 28),
          _Entrance(
            child: _PayPeriodPager(
              entries: entries,
              settings: settings,
              today: today,
            ),
          ),
          const SizedBox(height: 18),
          _Entrance(
            delay: const Duration(milliseconds: 70),
            child: _NextPaydayCard(
              payday: nextPayday,
              today: today,
              onConfigure: onConfigurePayday,
            ),
          ),
          const SizedBox(height: 30),
          const _SectionTitle(title: 'Quick actions'),
          const SizedBox(height: 14),
          _Entrance(
            delay: const Duration(milliseconds: 110),
            child: _QuickActions(
              onAddEntry: onAddEntry,
              onOpenCalendar: onOpenCalendar,
              onOpenReports: onOpenReports,
              onOpenExport: onOpenExport,
            ),
          ),
          const SizedBox(height: 30),
          _SectionTitle(
            title: 'Recent activity',
            action: 'View all',
            onAction: onViewEntries,
          ),
          const SizedBox(height: 14),
          if (recentEntries.isEmpty)
            _EmptyActivity(onAddEntry: onAddEntry)
          else
            ...recentEntries
                .take(5)
                .toList()
                .asMap()
                .entries
                .map(
                  (item) => _Entrance(
                    delay: Duration(milliseconds: 150 + item.key * 45),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _ActivityCard(
                        entry: item.value,
                        settings: settings,
                        onEdit: onEditEntry ?? (_) {},
                      ),
                    ),
                  ),
                ),
          const SizedBox(
            key: ValueKey('home-final-bottom-clearance'),
            height: 80,
          ),
        ],
      ),
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({
    required this.greeting,
    required this.supportingText,
  });

  final String greeting;
  final String supportingText;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(greeting, style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 6),
            Text(
              supportingText,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(width: 16),
      Semantics(
        label: 'Briska Pay. Track your hours. Know your pay.',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.asset(
            'assets/branding/briska-bp-in-app.png',
            width: 44,
            height: 44,
            fit: BoxFit.cover,
          ),
        ),
      ),
    ],
  );
}

class _PayPeriodPager extends StatefulWidget {
  const _PayPeriodPager({
    required this.entries,
    required this.settings,
    required this.today,
  });

  final List<WorkEntry> entries;
  final AppSettings settings;
  final DateTime today;

  @override
  State<_PayPeriodPager> createState() => _PayPeriodPagerState();
}

class _PayPeriodPagerState extends State<_PayPeriodPager> {
  late List<PayPeriodRange> _periods;
  late int _page;
  late final PageController _controller;

  @override
  void initState() {
    super.initState();
    _periods = _buildPeriods();
    _page = _periods.length - 1;
    _controller = PageController(initialPage: _page);
  }

  @override
  void didUpdateWidget(_PayPeriodPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selectedPeriod = _periods[_page];
    final scheduleChanged = _payScheduleChanged(
      oldWidget.settings,
      widget.settings,
    );
    final updatedPeriods = _buildPeriods();
    final preservedPage = _indexOfPeriod(updatedPeriods, selectedPeriod);
    final updatedPage = scheduleChanged || preservedPage < 0
        ? updatedPeriods.length - 1
        : preservedPage;
    _periods = updatedPeriods;
    _page = updatedPage;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _controller.hasClients) {
        _controller.jumpToPage(updatedPage);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<PayPeriodRange> _buildPeriods() => getAvailablePayPeriodsForSettings(
    date: widget.today,
    settings: widget.settings,
    entryDates: widget.entries.map((entry) => entry.date),
  );

  int _indexOfPeriod(List<PayPeriodRange> periods, PayPeriodRange selected) =>
      periods.indexWhere(
        (period) =>
            period.start == selected.start && period.end == selected.end,
      );

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(10) / 10;
    final pagerHeight = 335.0 + ((textScale - 1).clamp(0, 3) * 350);
    return Column(
      children: [
        SizedBox(
          height: pagerHeight,
          child: PageView.builder(
            controller: _controller,
            itemCount: _periods.length,
            onPageChanged: (value) => setState(() => _page = value),
            itemBuilder: (context, index) {
              final period = _periods[index];
              final summary = WorkCalculator.summarize(
                widget.entries.where((entry) => period.contains(entry.date)),
              );
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: _EarningsHero(
                  title: index == _periods.length - 1
                      ? 'CURRENT PAY PERIOD'
                      : 'PREVIOUS PAY PERIOD',
                  summary: summary,
                  periodStart: period.start,
                  periodEnd: period.end,
                  today: widget.today,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            _periods.length,
            (index) => Container(
              width: index == _page ? 14 : 5,
              height: 5,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(
                  alpha: index == _page ? 1 : .25,
                ),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
        ),
      ],
    );
  }

  bool _payScheduleChanged(AppSettings previous, AppSettings next) =>
      previous.payFrequency != next.payFrequency ||
      previous.payDay != next.payDay ||
      previous.payPeriodAnchorDate != next.payPeriodAnchorDate ||
      previous.paydayRule != next.paydayRule ||
      previous.paydayOffsetDays != next.paydayOffsetDays ||
      previous.paydayFixedDay != next.paydayFixedDay ||
      previous.paydaySelectedWeekday != next.paydaySelectedWeekday ||
      previous.paydayWeekday != next.paydayWeekday ||
      previous.customPeriodStartDay != next.customPeriodStartDay;
}

class _EarningsHero extends StatelessWidget {
  const _EarningsHero({
    required this.summary,
    required this.periodStart,
    required this.periodEnd,
    required this.today,
    this.title = 'CURRENT PAY PERIOD',
  });

  final WorkSummary summary;
  final DateTime periodStart;
  final DateTime periodEnd;
  final DateTime today;
  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final periodProgress = calculateCalendarPeriodProgress(
      periodStart: periodStart,
      periodEnd: periodEnd,
      today: today,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 360;
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colors.primary,
                Color.lerp(colors.primary, BriskaColors.dark, .3)!,
              ],
            ),
            borderRadius: BorderRadius.circular(BriskaRadii.xl),
            boxShadow: [
              BoxShadow(
                color: colors.primary.withValues(alpha: .22),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          padding: EdgeInsets.all(compact ? 20 : 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
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
                        color: Colors.white.withValues(alpha: .14),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${_shortDate(periodStart)} – ${_shortDate(periodEnd)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                'Estimated gross pay',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .76),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 5),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  _money(summary.totalExpectedPay),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 38 : 48,
                    height: 1.05,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1.2,
                  ),
                ),
              ),
              const SizedBox(height: 17),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _HeroMetric(
                      key: const ValueKey('home-hours-metric'),
                      label: summary.totalHours == 1 ? 'Hour' : 'Hours',
                      value: formatHours(summary.totalHours),
                    ),
                    const SizedBox(width: 22),
                    _HeroMetric(
                      key: const ValueKey('home-days-recorded-metric'),
                      label: summary.totalDays == 1
                          ? 'Day recorded'
                          : 'Days recorded',
                      value: summary.totalDays.toString(),
                    ),
                    const SizedBox(width: 22),
                    _HeroMetric(
                      key: const ValueKey('home-uplift-metric'),
                      label: 'Uplift',
                      value: _money(summary.totalJobUplift),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 8,
                runSpacing: 4,
                children: [
                  const Text(
                    'Time through pay period',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    periodProgress.displayText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: periodProgress.progress,
                  minHeight: 6,
                  color: Colors.white,
                  backgroundColor: Colors.white.withValues(alpha: .2),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class CalendarPeriodProgress {
  const CalendarPeriodProgress({
    required this.totalDays,
    required this.elapsedDays,
    required this.completedDays,
    required this.progress,
    required this.isAvailable,
  });

  final int totalDays;
  final int elapsedDays;
  final int completedDays;
  final double progress;
  final bool isAvailable;

  String get displayText =>
      isAvailable ? '$completedDays of $totalDays days' : 'Unavailable';
}

int calendarDayNumber(DateTime value) => DateTime.utc(
  value.year,
  value.month,
  value.day,
).difference(DateTime.utc(1970, 1, 1)).inDays;

CalendarPeriodProgress calculateCalendarPeriodProgress({
  required DateTime periodStart,
  required DateTime periodEnd,
  required DateTime today,
}) {
  final startDay = calendarDayNumber(periodStart);
  final endDay = calendarDayNumber(periodEnd);
  final todayDay = calendarDayNumber(today);
  if (endDay < startDay) {
    return const CalendarPeriodProgress(
      totalDays: 0,
      elapsedDays: 0,
      completedDays: 0,
      progress: 0,
      isAvailable: false,
    );
  }

  final totalDays = endDay - startDay + 1;
  final elapsedDays = todayDay - startDay + 1;
  final completedDays = elapsedDays.clamp(0, totalDays);
  return CalendarPeriodProgress(
    totalDays: totalDays,
    elapsedDays: elapsedDays,
    completedDays: completedDays,
    progress: completedDays / totalDays,
    isAvailable: true,
  );
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Text(
        value,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
      Text(
        label,
        style: TextStyle(
          color: Colors.white.withValues(alpha: .68),
          fontSize: 12,
        ),
      ),
    ],
  );
}

class _NextPaydayCard extends StatelessWidget {
  const _NextPaydayCard({
    required this.payday,
    required this.today,
    required this.onConfigure,
  });

  final DateTime? payday;
  final DateTime today;
  final VoidCallback onConfigure;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (payday == null) {
      return _PremiumCard(
        child: Row(
          children: [
            const _DashboardIcon(icon: Icons.event_busy_outlined),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No payday configured',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 3),
                  Text('Set your pay schedule to see a countdown.'),
                ],
              ),
            ),
            TextButton(onPressed: onConfigure, child: const Text('Configure')),
          ],
        ),
      );
    }
    final days = payday!.difference(today).inDays;
    final countdown = paydayCountdownLabel(days);
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final paydayDetails = Row(
      children: [
        const _DashboardIcon(icon: Icons.account_balance_wallet_outlined),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Next payday',
                style: TextStyle(
                  color: colors.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                formatWeekdayDate(payday!),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      ],
    );
    final countdownChip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        countdown,
        style: TextStyle(
          color: colors.primary,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    return _PremiumCard(
      child: largeText
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                paydayDetails,
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerRight, child: countdownChip),
              ],
            )
          : Row(
              children: [
                Expanded(child: paydayDetails),
                const SizedBox(width: 10),
                countdownChip,
              ],
            ),
    );
  }
}

@visibleForTesting
String paydayCountdownLabel(int days) => days == 0
    ? 'Today'
    : days == 1
    ? 'Tomorrow'
    : 'In $days days';

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.onAddEntry,
    required this.onOpenCalendar,
    required this.onOpenReports,
    required this.onOpenExport,
  });

  final VoidCallback onAddEntry;
  final VoidCallback onOpenCalendar;
  final VoidCallback onOpenReports;
  final VoidCallback onOpenExport;

  @override
  Widget build(BuildContext context) {
    final useGrid = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final actions = [
      (Icons.add_rounded, 'Add Day', onAddEntry, true),
      (Icons.calendar_month_outlined, 'Calendar', onOpenCalendar, false),
      (Icons.insights_outlined, 'Reports', onOpenReports, false),
      (Icons.ios_share_outlined, 'Export', onOpenExport, false),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = constraints.maxWidth < 360 ? 8.0 : 12.0;
        if (useGrid) {
          final buttonWidth = (constraints.maxWidth - gap) / 2;
          return Wrap(
            key: const ValueKey('quick-actions-grid'),
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final action in actions)
                SizedBox(
                  width: buttonWidth,
                  child: _QuickActionButton(
                    icon: action.$1,
                    label: action.$2,
                    onTap: action.$3,
                    primary: action.$4,
                  ),
                ),
            ],
          );
        }
        return Row(
          key: const ValueKey('quick-actions-row'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final action in actions) ...[
              Expanded(
                child: _QuickActionButton(
                  icon: action.$1,
                  label: action.$2,
                  onTap: action.$3,
                  primary: action.$4,
                ),
              ),
              if (action != actions.last) SizedBox(width: gap),
            ],
          ],
        );
      },
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.primary,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final accessibleText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    return Material(
      color: primary ? colors.primary : colors.primary.withValues(alpha: .075),
      borderRadius: BorderRadius.circular(BriskaRadii.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(BriskaRadii.lg),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
          child: Column(
            children: [
              Icon(icon, color: primary ? Colors.white : colors.primary),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: accessibleText ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: primary ? Colors.white : colors.onSurface,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<bool> _showEntryDetails(
  BuildContext context,
  WorkEntry source,
  AppSettings settings,
) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => _EntryDetailsSheet(
      entry: WorkCalculator.recalculateEntry(source),
      settings: settings,
    ),
  );
  return result ?? false;
}

class _EntryDetailsSheet extends StatelessWidget {
  const _EntryDetailsSheet({required this.entry, required this.settings});

  final WorkEntry entry;
  final AppSettings settings;

  bool get _isWork => entry.type == EntryType.workDay;
  bool get _isHoliday => entry.type == EntryType.holiday;
  bool get _isBankHoliday => entry.type == EntryType.bankHoliday;
  bool get _isSick => entry.type == EntryType.sickDay;
  bool get _isUnpaid => entry.type == EntryType.unpaidDayOff;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final notes = entry.notes.trim();
    final reason = entry.deductionReason.trim();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Entry Details',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(BriskaRadii.lg),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _entryDayTypeLabel(entry),
                    key: const ValueKey('entry-details-day-type'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _longDate(entry.date),
                    key: const ValueKey('entry-details-date'),
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                  if (_isBankHoliday || _isSick) ...[
                    const SizedBox(height: 8),
                    Text(
                      _isBankHoliday
                          ? (entry.isPaidBankHoliday ? 'Paid' : 'Unpaid')
                          : (entry.isPaidSickDay ? 'Paid' : 'Unpaid'),
                      key: const ValueKey('entry-details-pay-status'),
                      style: TextStyle(
                        color: colors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_isWork) ...[
              if (entry.siteName.trim().isNotEmpty)
                _DetailRow(label: 'Site / Job', value: entry.siteName.trim()),
              _DetailRow(
                label: 'Rate Used',
                value: settings.labelForRate(entry.rateType),
              ),
              _DetailRow(label: 'Time', value: _timeRange(entry)),
              if (entry.breakMinutes > 0)
                _DetailRow(
                  label: 'Break',
                  value: '${entry.breakMinutes} minutes',
                ),
            ],
            if (_isWork ||
                _isHoliday ||
                (_isBankHoliday && entry.isPaidBankHoliday) ||
                (_isSick && entry.isPaidSickDay)) ...[
              _DetailRow(
                label: 'Paid Hours',
                value: formatHoursLabel(entry.totalHours),
              ),
              _DetailRow(
                label: _isWork ? 'Hourly Rate' : 'Rate',
                value:
                    '${settings.labelForRate(entry.rateType)} · ${_money(entry.hourlyRateUsed)}/hr',
              ),
            ],
            if (_isBankHoliday && !entry.isPaidBankHoliday)
              const _DetailRow(label: 'Paid Hours', value: '0h'),
            if (_isUnpaid)
              const _DetailRow(label: 'Status', value: 'Unpaid Day Off'),
            const SizedBox(height: 8),
            _FinancialDetails(entry: entry),
            if (entry.deductionAmount > 0 && reason.isNotEmpty)
              _DetailRow(label: 'Deduction Reason', value: reason),
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Notes', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              Text(notes, key: const ValueKey('entry-details-notes')),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Close'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(context, true),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit Entry'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FinancialDetails extends StatelessWidget {
  const _FinancialDetails({required this.entry});

  final WorkEntry entry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(BriskaRadii.lg),
      ),
      child: Column(
        children: [
          if (entry.wages != 0)
            _MoneyRow(label: 'Base Wages', value: entry.wages),
          if (entry.dailyAllowance != 0)
            _MoneyRow(label: 'Daily Allowance', value: entry.dailyAllowance),
          if (entry.jobUplift != 0)
            _MoneyRow(label: 'Job Uplift', value: entry.jobUplift),
          const Divider(height: 20),
          _MoneyRow(label: 'Gross Pay', value: entry.grossPay, strong: true),
          if (entry.deductionAmount > 0) ...[
            _MoneyRow(label: 'Deduction', value: entry.deductionAmount),
            const Divider(height: 20),
          ],
          _MoneyRow(label: 'Net Pay', value: entry.netPay, prominent: true),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 116,
          child: Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

class _MoneyRow extends StatelessWidget {
  const _MoneyRow({
    required this.label,
    required this.value,
    this.strong = false,
    this.prominent = false,
  });
  final String label;
  final double value;
  final bool strong;
  final bool prominent;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: strong || prominent
                  ? FontWeight.w700
                  : FontWeight.w500,
            ),
          ),
        ),
        Text(
          _money(value),
          key: ValueKey(
            'entry-details-${label.toLowerCase().replaceAll(' ', '-')}',
          ),
          style: TextStyle(
            color: prominent ? Theme.of(context).colorScheme.primary : null,
            fontSize: prominent ? 18 : null,
            fontWeight: strong || prominent ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

String _entryDayTypeLabel(WorkEntry entry) => switch (entry.type) {
  EntryType.workDay => 'Work Day',
  EntryType.holiday => 'Holiday',
  EntryType.bankHoliday => 'Bank Holiday',
  EntryType.sickDay => 'Sick Day',
  EntryType.unpaidDayOff => 'Unpaid Day Off',
};

String _longDate(DateTime date) =>
    '${_weekday(date)}, ${date.day} '
    '${_fullMonth(date)} ${date.year}';

String _fullMonth(DateTime date) => const [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
][date.month - 1];

String _timeRange(WorkEntry entry) {
  final start =
      WorkCalculator.normalizeTime(entry.startTime) ?? entry.startTime;
  final finish =
      WorkCalculator.normalizeTime(entry.finishTime) ?? entry.finishTime;
  final overnight =
      start.isNotEmpty && finish.isNotEmpty && finish.compareTo(start) < 0;
  return '$start – $finish${overnight ? ' (+1 day)' : ''}';
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({
    required this.entry,
    required this.settings,
    required this.onEdit,
  });

  final WorkEntry entry;
  final AppSettings settings;
  final ValueChanged<WorkEntry> onEdit;

  @override
  Widget build(BuildContext context) {
    final item = WorkCalculator.recalculateEntry(entry);
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'Open details for ${_entryTitle(item)}',
      child: InkWell(
        key: ValueKey('recent-activity-${entry.id}'),
        borderRadius: BorderRadius.circular(BriskaRadii.lg),
        onTap: () async {
          final edit = await _showEntryDetails(context, entry, settings);
          if (edit) {
            await Future<void>.delayed(const Duration(milliseconds: 250));
            if (context.mounted) onEdit(entry);
          }
        },
        child: _PremiumCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Text(
                    item.date.day.toString(),
                    style: TextStyle(
                      color: colors.primary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _entryTitle(item),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${_weekday(item.date)}, ${item.date.day} '
                      '${_shortMonth(item.date)}  •  '
                      '${formatHoursLabel(item.totalHours)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 104,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _money(item.totalPay),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Estimated gross pay',
                      maxLines: 2,
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: colors.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyActivity extends StatelessWidget {
  const _EmptyActivity({required this.onAddEntry});

  final VoidCallback onAddEntry;

  @override
  Widget build(BuildContext context) => BriskaEmptyState(
    icon: Icons.work_outline_rounded,
    title: 'Your work starts here',
    message: 'Add your first day to see your earnings and activity.',
    actionLabel: 'Add Day',
    onAction: onAddEntry,
  );
}

class _PremiumCard extends StatelessWidget {
  const _PremiumCard({
    required this.child,
    this.padding = const EdgeInsets.all(BriskaSpacing.lg),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return BriskaCard(padding: padding, child: child);
  }
}

class _DashboardIcon extends StatelessWidget {
  const _DashboardIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: 46,
    height: 46,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primary.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(15),
    ),
    child: Icon(icon, color: Theme.of(context).colorScheme.primary),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.action, this.onAction});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(title, style: Theme.of(context).textTheme.titleLarge),
      ),
      if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
    ],
  );
}

class _DashboardPage extends StatelessWidget {
  const _DashboardPage({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final horizontal = width < 360
        ? 16.0
        : width < 480
        ? 20.0
        : BriskaSpacing.pageHorizontal;
    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(
          horizontal,
          BriskaSpacing.lg,
          horizontal,
          BriskaSpacing.pageBottom,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _Entrance extends StatelessWidget {
  const _Entrance({required this.child, this.delay = Duration.zero});

  final Widget child;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      duration: BriskaDurations.standard + delay,
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 0, end: 1),
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 10 * (1 - value)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

String _greetingFor(DateTime date) {
  if (date.hour < 12) return 'Good morning';
  if (date.hour < 17) return 'Good afternoon';
  return 'Good evening';
}

String _money(double value) => CurrencyFormatter.format(value);

String _shortDate(DateTime date) => formatCompactDate(date);

String _shortMonth(DateTime date) => const [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
][date.month - 1];

String _weekday(DateTime date) => const [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
][date.weekday - 1];

String _entryTitle(WorkEntry entry) {
  if (entry.entryType == 'Holiday') return 'Holiday';
  if (entry.type == EntryType.bankHoliday) return 'Bank Holiday';
  if (entry.entryType == 'UnpaidDayOff') return 'Unpaid day off';
  if (entry.entryType == 'SickDay') {
    return entry.isPaidSickDay ? 'Paid Sick Day' : 'Unpaid Sick Day';
  }
  final site = entry.siteName.trim();
  return site.isEmpty ? 'Work day' : site;
}
