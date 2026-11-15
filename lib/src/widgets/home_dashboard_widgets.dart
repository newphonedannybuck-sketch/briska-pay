import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../home_dashboard_summary.dart';
import '../display_format.dart';
import '../presentation_format.dart';

/// Tinted, fine-bordered surfaces shared only by the Home dashboard.
class HomePanel extends StatelessWidget {
  const HomePanel({
    required this.child,
    this.tint,
    this.padding = const EdgeInsets.all(14),
    this.waves = false,
    super.key,
  });
  final Widget child;
  final Color? tint;
  final EdgeInsetsGeometry padding;
  final bool waves;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = tint ?? Theme.of(context).colorScheme.primary;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: dark ? .32 : .22)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? [
                  Color.lerp(const Color(0xFF202A27), accent, .12)!,
                  Color.lerp(
                    const Color(0xFF19221F),
                    accent,
                    tint == null ? .06 : .2,
                  )!,
                ]
              : [
                  Color.lerp(Colors.white, accent, tint == null ? .04 : .08)!,
                  Color.lerp(Colors.white, accent, tint == null ? .1 : .15)!,
                ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? .12 : .025),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: CustomPaint(
          painter: waves ? _HomeWaves(accent) : null,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class _HomeWaves extends CustomPainter {
  const _HomeWaves(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < 2; i++) {
      final path = Path()
        ..moveTo(size.width * .32, size.height)
        ..cubicTo(
          size.width * .65,
          size.height * (i == 0 ? .25 : 1.1),
          size.width * .67,
          size.height * (i == 0 ? 1.2 : -.05),
          size.width,
          size.height * .5,
        )
        ..lineTo(size.width, size.height)
        ..close();
      canvas.drawPath(path, Paint()..color = color.withValues(alpha: .09));
    }
  }

  @override
  bool shouldRepaint(_HomeWaves oldDelegate) => color != oldDelegate.color;
}

class HomeTimeOffTiles extends StatelessWidget {
  const HomeTimeOffTiles({required this.summary, super.key});
  final HomeDashboardSummary summary;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final stacked =
          constraints.maxWidth < 300 ||
          MediaQuery.textScalerOf(context).scale(1) >= 1.5;
      final tiles = [
        _TimeOffTile(
          title: 'Holidays taken',
          icon: Icons.beach_access_outlined,
          summary: summary.holidays,
          purple: true,
        ),
        _TimeOffTile(
          title: 'Bank holidays',
          icon: Icons.calendar_today_outlined,
          summary: summary.bankHolidays,
          purple: false,
        ),
      ];
      return stacked
          ? Column(
              children: [tiles.first, const SizedBox(height: 10), tiles.last],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: tiles.first),
                const SizedBox(width: 10),
                Expanded(child: tiles.last),
              ],
            );
    },
  );
}

class _TimeOffTile extends StatelessWidget {
  const _TimeOffTile({
    required this.title,
    required this.icon,
    required this.summary,
    required this.purple,
  });
  final String title;
  final IconData icon;
  final HomeTimeOffSummary summary;
  final bool purple;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = purple
        ? (dark ? const Color(0xFFCFB1FF) : const Color(0xFF7948AA))
        : (dark ? const Color(0xFFFFD28A) : const Color(0xFF996008));
    return HomePanel(
      tint: accent,
      waves: true,
      padding: const EdgeInsets.all(11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 21, color: accent),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${summary.days} ${summary.days == 1 ? 'day' : 'days'}',
                  style: const TextStyle(
                    fontSize: 21,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  summary.hasRecordedHours
                      ? 'Recorded hours: ${formatHours(summary.recordedHours)}'
                      : summary.days == 0
                      ? 'No days recorded'
                      : 'Hours not entered',
                  style: TextStyle(
                    fontSize: 9,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class HomeEarningsChart extends StatelessWidget {
  const HomeEarningsChart({
    required this.points,
    required this.start,
    required this.end,
    super.key,
  });
  final List<RecordedEarningsPoint> points;
  final DateTime start, end;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final description = points.isEmpty
        ? 'No recorded earnings in this pay period.'
        : 'Cumulative recorded gross earnings. ${points.map((point) => '${formatCompactDateWithYear(point.date)}: ${formatMoney(point.total)}').join('; ')}. No forecast.';
    return Semantics(
      label: description,
      image: true,
      child: ExcludeSemantics(
        child: SizedBox(
          height: 64,
          width: double.infinity,
          child: points.isEmpty
              ? Center(
                  child: Text(
                    'No recorded earnings yet',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                )
              : CustomPaint(
                  painter: HomeEarningsPainter(
                    points: points,
                    start: start,
                    end: end,
                    color: colors.primary,
                  ),
                ),
        ),
      ),
    );
  }
}

/// Horizontal holds and vertical changes only. The line ends at the last
/// recorded calendar date. The x-axis spans recorded dates, never a forecast.
class HomeEarningsPainter extends CustomPainter {
  const HomeEarningsPainter({
    required this.points,
    required this.start,
    required this.end,
    required this.color,
  });
  final List<RecordedEarningsPoint> points;
  final DateTime start, end;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    double day(DateTime date) =>
        DateTime.utc(date.year, date.month, date.day).millisecondsSinceEpoch /
        Duration.millisecondsPerDay;
    final low = points.fold(
      0.0,
      (value, point) => math.min(value, point.total),
    );
    final high = points.fold(
      0.0,
      (value, point) => math.max(value, point.total),
    );
    final span = high == low ? 1.0 : high - low;
    final firstDay = points.first.date;
    final lastDay = points.last.date;
    double x(DateTime date) => firstDay == lastDay
        ? size.width / 2
        : 3 +
              (size.width - 6) *
                  ((day(date) - day(firstDay)) /
                          math.max(1, day(lastDay) - day(firstDay)))
                      .clamp(0, 1);
    double y(double value) => high == low
        ? size.height / 2
        : 5 + (size.height - 10) * (high - value) / span;
    final zero = y(0);
    final path = Path()..moveTo(x(firstDay), zero);
    var previous = 0.0;
    for (final point in points) {
      path
        ..lineTo(x(point.date), y(previous))
        ..lineTo(x(point.date), y(point.total));
      previous = point.total;
    }
    final last = Offset(x(points.last.date), y(points.last.total));
    final fill = Path.from(path)
      ..lineTo(last.dx, zero)
      ..lineTo(x(firstDay), zero)
      ..close();
    canvas.drawLine(
      Offset(0, zero),
      Offset(size.width, zero),
      Paint()
        ..color = color.withValues(alpha: .18)
        ..strokeWidth = 1,
    );
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: .3), color.withValues(alpha: .025)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(last, 4, Paint()..color = color);
    canvas.drawCircle(last, 2, Paint()..color = const Color(0xFFEDFFF5));
  }

  @override
  bool shouldRepaint(HomeEarningsPainter oldDelegate) =>
      points != oldDelegate.points ||
      start != oldDelegate.start ||
      end != oldDelegate.end ||
      color != oldDelegate.color;
}
