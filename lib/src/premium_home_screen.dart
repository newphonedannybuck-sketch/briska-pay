import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../design_system/briska_radius.dart';
import '../design_system/briska_theme.dart';
import 'presentation_format.dart';
import 'widgets/shared_ui.dart';
import 'display_format.dart';
import 'models.dart';
import 'pay_schedule.dart';
import 'home_dashboard_summary.dart';
import 'work_calculator.dart';
import 'widgets/home_dashboard_widgets.dart';

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

    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Theme(
      data: theme.copyWith(
        colorScheme: theme.colorScheme.copyWith(
          surface: dark ? const Color(0xFF232625) : Colors.white,
          onSurface: dark ? const Color(0xFFF1F3F2) : const Color(0xFF202622),
          onSurfaceVariant: dark
              ? const Color(0xFFB6BDB9)
              : const Color(0xFF616963),
          outlineVariant: dark
              ? const Color(0xFF363C38)
              : const Color(0xFFE0E4E1),
        ),
      ),
      child: ColoredBox(
        color: dark ? const Color(0xFF171A18) : const Color(0xFFF7F8F7),
        child: AppPage(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DashboardHeader(greeting: _greetingFor(now)),
              const SizedBox(height: 14),
              _Entrance(
                child: _PayPeriodPager(
                  entries: entries,
                  settings: settings,
                  today: today,
                  nextPayday: nextPayday,
                  onConfigurePayday: onConfigurePayday,
                ),
              ),
              const SizedBox(height: 10),
              SectionHeading(
                title: 'Recent activity',
                action: 'View all',
                onTap: onViewEntries,
              ),
              const SizedBox(height: 4),
              if (recentEntries.isEmpty)
                const _EmptyActivity()
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
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _ActivityCard(
                            entry: item.value,
                            settings: settings,
                            onEdit: onEditEntry ?? (_) {},
                          ),
                        ),
                      ),
                    ),
              const SizedBox(height: 20),
              const SectionHeading(title: 'Quick actions'),
              const SizedBox(height: 14),
              _Entrance(
                delay: const Duration(milliseconds: 110),
                child: _QuickActions(
                  onOpenCalendar: onOpenCalendar,
                  onOpenReports: onOpenReports,
                  onOpenExport: onOpenExport,
                ),
              ),
              const SizedBox(height: 24),
              const SizedBox(
                key: ValueKey('home-final-bottom-clearance'),
                height: 80,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({required this.greeting});
  final String greeting;
  @override
  Widget build(BuildContext context) {
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Briska Pay',
          style: TextStyle(
            fontSize: 24,
            height: 1.15,
            fontWeight: FontWeight.w700,
            letterSpacing: -.5,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          greeting,
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
    final logo = ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.asset(
        'assets/branding/briska-bp-in-app.png',
        width: 44,
        height: 44,
        semanticLabel: 'Briska Pay. Track your hours. Know your pay.',
      ),
    );
    return MediaQuery.textScalerOf(context).scale(1) >= 1.5
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [logo, const SizedBox(height: 8), text],
          )
        : Row(
            children: [
              logo,
              const SizedBox(width: 12),
              Expanded(child: text),
            ],
          );
  }
}

class _PayPeriodPager extends StatefulWidget {
  const _PayPeriodPager({
    required this.entries,
    required this.settings,
    required this.today,
    required this.nextPayday,
    required this.onConfigurePayday,
  });

  final List<WorkEntry> entries;
  final AppSettings settings;
  final DateTime today;
  final DateTime nextPayday;
  final VoidCallback onConfigurePayday;

  @override
  State<_PayPeriodPager> createState() => _PayPeriodPagerState();
}

class _PayPeriodPagerState extends State<_PayPeriodPager> {
  late List<PayPeriodRange> _periods;
  late int _page;
  late final PageController _controller;
  double _contentHeight = 290;

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
    final selected = _periods[_page];
    final summary = HomeDashboardSummary(widget.entries, selected);
    final monthly =
        normalisePayFrequency(widget.settings.payFrequency) ==
        calendarMonthlyPayFrequency;
    final label = monthly
        ? formatMonthYear(selected.start)
        : '${formatCompactDateWithYear(selected.start)} – ${formatCompactDateWithYear(selected.end)}';
    void move(int index) => _controller.animateToPage(
      index,
      duration: BriskaDurations.standard,
      curve: Curves.easeOutCubic,
    );
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Previous pay period',
                onPressed: _page > 0 ? () => move(_page - 1) : null,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Next pay period',
                onPressed: _page < _periods.length - 1
                    ? () => move(_page + 1)
                    : null,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: _contentHeight,
          child: PageView.builder(
            controller: _controller,
            itemCount: _periods.length,
            onPageChanged: (value) => setState(() => _page = value),
            itemBuilder: (context, index) {
              final period = _periods[index];
              return OverflowBox(
                minHeight: 0,
                maxHeight: double.infinity,
                alignment: Alignment.topCenter,
                child: _MeasureEarnings(
                  onHeight: (height) {
                    if (mounted &&
                        index == _page &&
                        (_contentHeight - height).abs() > .5) {
                      setState(() => _contentHeight = height);
                    }
                  },
                  child: _EarningsHero(
                    title: index == _periods.length - 1
                        ? 'Current pay period'
                        : 'Previous pay period',
                    summary: HomeDashboardSummary(widget.entries, period),
                    periodStart: period.start,
                    periodEnd: period.end,
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        _NextPaydayCard(
          payday: widget.nextPayday,
          today: widget.today,
          onConfigure: widget.onConfigurePayday,
        ),
        const SizedBox(height: 10),
        HomeTimeOffTiles(
          key: const ValueKey('home-time-off-tiles'),
          summary: summary,
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

// Measure the natural page height so text and metrics can reflow at any width.
class _MeasureEarnings extends SingleChildRenderObjectWidget {
  const _MeasureEarnings({required this.onHeight, required super.child});
  final ValueChanged<double> onHeight;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _EarningsSize(onHeight);
  @override
  void updateRenderObject(BuildContext context, _EarningsSize renderObject) {
    renderObject.onHeight = onHeight;
    renderObject.markNeedsLayout();
  }
}

class _EarningsSize extends RenderProxyBox {
  _EarningsSize(this.onHeight);
  ValueChanged<double> onHeight;
  @override
  void performLayout() {
    super.performLayout();
    final height = size.height;
    WidgetsBinding.instance.addPostFrameCallback((_) => onHeight(height));
  }
}

class _EarningsHero extends StatelessWidget {
  const _EarningsHero({
    required this.summary,
    required this.periodStart,
    required this.periodEnd,
    required this.title,
  });
  final HomeDashboardSummary summary;
  final DateTime periodStart, periodEnd;
  final String title;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final pay = summary.pay;
    return HomePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Estimated gross pay',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.stacked_line_chart_rounded,
                      color: colors.primary,
                      size: 15,
                    ),
                    const SizedBox(width: 4),
                    const Flexible(
                      child: Text(
                        'Recorded earnings',
                        style: TextStyle(fontSize: 9),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatMoney(pay.totalExpectedPay),
              maxLines: 1,
              style: TextStyle(
                color: colors.onSurface,
                fontSize: 40,
                height: 1.15,
                fontWeight: FontWeight.w700,
                letterSpacing: -1.2,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 10,
            runSpacing: 4,
            children: [
              Text(
                title,
                style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
              ),
              if (summary.earnings.isNotEmpty)
                Text(
                  '${formatCompactDate(summary.earnings.first.date)} – ${formatCompactDate(summary.earnings.last.date)} recorded',
                  style: TextStyle(fontSize: 9, color: colors.onSurfaceVariant),
                ),
            ],
          ),
          const SizedBox(height: 8),
          HomeEarningsChart(
            points: summary.earnings,
            start: periodStart,
            end: periodEnd,
          ),
          Divider(height: 16, color: colors.primary.withValues(alpha: .2)),
          LayoutBuilder(
            builder: (context, constraints) {
              final large = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
              final width = large
                  ? constraints.maxWidth
                  : (constraints.maxWidth - 16) / 3;
              return Wrap(
                spacing: 8,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: width,
                    child: _HeroMetric(
                      key: const ValueKey('home-hours-metric'),
                      icon: Icons.schedule_outlined,
                      label: pay.totalHours == 1 ? 'Hour' : 'Hours',
                      value: formatHours(pay.totalHours),
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _HeroMetric(
                      key: const ValueKey('home-days-recorded-metric'),
                      icon: Icons.calendar_today_outlined,
                      label: summary.daysWorked == 1
                          ? 'Day worked'
                          : 'Days worked',
                      value: summary.daysWorked.toString(),
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _HeroMetric(
                      key: const ValueKey('home-uplift-metric'),
                      icon: Icons.payments_outlined,
                      label: 'Uplift',
                      value: formatMoney(pay.totalJobUplift),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
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
  const _HeroMetric({
    required this.label,
    required this.value,
    required this.icon,
    super.key,
  });
  final String label, value;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 19, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 6),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 21,
                  height: 1.1,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
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
  final DateTime payday, today;
  final VoidCallback onConfigure;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final days = calendarDayNumber(payday) - calendarDayNumber(today);
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: .17),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Text(
        paydayCountdownLabel(days),
        style: TextStyle(
          color: colors.primary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    final details = Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.calendar_today_outlined,
            size: 25,
            color: colors.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Next payday',
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
              ),
              Text(
                formatCompactDate(payday),
                semanticsLabel: formatFullDate(payday),
                style: const TextStyle(
                  fontSize: 23,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    return Semantics(
      button: true,
      label: 'Configure pay schedule',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onConfigure,
          borderRadius: BorderRadius.circular(16),
          child: HomePanel(
            waves: true,
            padding: const EdgeInsets.all(12),
            child: MediaQuery.textScalerOf(context).scale(1) >= 1.5
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [details, const SizedBox(height: 8), badge],
                  )
                : Row(
                    children: [
                      Expanded(child: details),
                      const SizedBox(width: 8),
                      badge,
                    ],
                  ),
          ),
        ),
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
    required this.onOpenCalendar,
    required this.onOpenReports,
    required this.onOpenExport,
  });

  final VoidCallback onOpenCalendar;
  final VoidCallback onOpenReports;
  final VoidCallback onOpenExport;

  @override
  Widget build(BuildContext context) {
    final useGrid = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final actions = [
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
      color: primary ? colors.primary : colors.surface,
      borderRadius: BorderRadius.circular(BriskaRadii.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(BriskaRadii.lg),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
          child: Column(
            children: [
              Icon(icon, color: primary ? colors.onPrimary : colors.primary),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: accessibleText ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: primary ? colors.onPrimary : colors.onSurface,
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
    builder: (context) => _EntryDetailsSheet(entry: source, settings: settings),
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
                    '${settings.labelForRate(entry.rateType)} · ${formatMoney(entry.hourlyRateUsed)}/hr',
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
          formatMoney(value),
          key: ValueKey(
            'entry-details-${label.toLowerCase().replaceAll(' ', '-')}',
          ),
          style: TextStyle(
            color: prominent ? Theme.of(context).colorScheme.primary : null,
            fontSize: prominent ? 18 : null,
            fontWeight: strong || prominent ? FontWeight.w700 : FontWeight.w600,
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

String _fullMonth(DateTime date) => fullMonthNames[date.month - 1];

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
    final item = entry;
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
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final stacked =
                  constraints.maxWidth < 300 ||
                  MediaQuery.textScalerOf(context).scale(1) >= 1.5;
              final details = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _entryTitle(item),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${formatHoursLabel(item.totalHours)} · ${item.type == EntryType.workDay ? settings.labelForRate(item.rateType) : _entryDayTypeLabel(item)}',
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ],
              );
              final amount = FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  formatMoney(item.grossPay),
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              );
              final badge = Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${item.date.day}',
                      style: const TextStyle(
                        fontSize: 20,
                        height: 1.1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      _shortMonth(item.date).toUpperCase(),
                      style: const TextStyle(fontSize: 10),
                    ),
                  ],
                ),
              );
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  badge,
                  const SizedBox(width: 12),
                  Expanded(
                    child: stacked
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              details,
                              const SizedBox(height: 8),
                              amount,
                            ],
                          )
                        : details,
                  ),
                  if (!stacked) ...[
                    const SizedBox(width: 10),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: constraints.maxWidth * .3,
                      ),
                      child: amount,
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _EmptyActivity extends StatelessWidget {
  const _EmptyActivity();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your work starts here',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        SizedBox(height: 6),
        Text('Add your first day to see your earnings and activity.'),
      ],
    ),
  );
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

String _shortMonth(DateTime date) => shortMonthNames[date.month - 1];

String _weekday(DateTime date) => weekdayNames[date.weekday - 1];

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
