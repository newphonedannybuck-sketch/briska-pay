import '../../widgets/detail_text.dart';
import 'package:flutter/material.dart';
import '../../models.dart';
import '../../currency.dart';
import '../../display_format.dart';
import '../../presentation_format.dart';
import '../../export_formats.dart';

class ExportedFileCard extends StatelessWidget {
  const ExportedFileCard({
    super.key,
    required this.record,
    required this.onOpen,
    required this.onShare,
    required this.onPrint,
    required this.onRename,
    required this.onFavourite,
    required this.onDelete,
  });

  final ExportedFileRecord record;
  final VoidCallback onOpen;
  final VoidCallback onShare;
  final VoidCallback? onPrint;
  final VoidCallback onRename;
  final VoidCallback onFavourite;
  final VoidCallback onDelete;

  String get _date => formatCompactDateWithYear(record.exportedAt);

  String get _size {
    return formatFileSize(record.fileSize);
  }

  ExportFormat get _format => ExportFormat.fromFileType(record.fileType);

  IconData get _icon {
    return switch (_format) {
      ExportFormat.excel => Icons.table_chart_outlined,
      ExportFormat.pdfTimesheet => Icons.picture_as_pdf_outlined,
      ExportFormat.pdfSummary => Icons.description_outlined,
      ExportFormat.csv => Icons.grid_on_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: .09),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Icon(
                      _icon,
                      color: Theme.of(context).colorScheme.primary,
                      size: 24,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        record.fileName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_format.fileType} - $_date',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  formatMoney(
                    record.totalPay,
                    CurrencyCatalog.byCode(
                      record.currencyCode,
                    ).copyWith(symbol: record.currencySymbol),
                  ),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Wrap(
                spacing: 18,
                runSpacing: 9,
                children: [
                  DetailText(label: 'Period', value: record.periodLabel),
                  DetailText(label: 'File type', value: _format.fileType),
                  DetailText(label: 'Created', value: _date),
                  DetailText(
                    label: record.workDays == 1
                        ? 'Day recorded'
                        : 'Days recorded',
                    value: record.workDays.toString(),
                  ),
                  DetailText(
                    label: 'Hours',
                    value: formatHoursLabel(record.totalHours),
                  ),
                  DetailText(label: 'File size', value: _size),
                ],
              ),
            ),
            if (!record.isAvailable) ...[
              const SizedBox(height: 10),
              const _MissingFileBadge(),
            ],
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('Open'),
                ),
                TextButton.icon(
                  onPressed: onShare,
                  icon: const Icon(Icons.share_outlined, size: 18),
                  label: const Text('Share'),
                ),
                if (onPrint != null)
                  TextButton.icon(
                    onPressed: onPrint,
                    icon: const Icon(Icons.print_outlined, size: 18),
                    label: const Text('Print'),
                  ),
                TextButton.icon(
                  onPressed: onFavourite,
                  icon: Icon(
                    record.isFavourite
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    size: 18,
                  ),
                  label: Text(record.isFavourite ? 'Favourited' : 'Favourite'),
                ),
                TextButton.icon(
                  onPressed: onRename,
                  icon: const Icon(
                    Icons.drive_file_rename_outline_rounded,
                    size: 18,
                  ),
                  label: const Text('Rename'),
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
        ),
      ),
    );
  }
}

class _MissingFileBadge extends StatelessWidget {
  const _MissingFileBadge();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.error.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      'Export file not found.',
      style: TextStyle(
        color: Theme.of(context).colorScheme.error,
        fontSize: 11,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class CompactEmptyExportLibrary extends StatelessWidget {
  const CompactEmptyExportLibrary({super.key});

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No exports yet',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Reports you create will appear here for quick access.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );
}

class RecentExportCard extends StatelessWidget {
  const RecentExportCard({
    super.key,
    required this.record,
    required this.onOpen,
    required this.onShare,
    required this.onDelete,
  });

  final ExportedFileRecord record;
  final VoidCallback onOpen;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final format = ExportFormat.fromFileType(record.fileType);
    final created = formatCompactDateWithYear(record.exportedAt);
    final range = record.startDate != null && record.endDate != null
        ? '${formatCompactDateWithYear(record.startDate!)} – '
              '${formatCompactDateWithYear(record.endDate!)}'
        : record.periodLabel;
    final size = record.fileSize == null
        ? null
        : record.fileSize! >= 1024 * 1024
        ? '${(record.fileSize! / (1024 * 1024)).toStringAsFixed(1)} MB'
        : '${(record.fileSize! / 1024).toStringAsFixed(0)} KB';
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        child: Row(
          children: [
            Icon(
              format == ExportFormat.excel
                  ? Icons.table_chart_outlined
                  : format == ExportFormat.csv
                  ? Icons.grid_on_outlined
                  : Icons.picture_as_pdf_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${record.reportType} · $range',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '$created · ${format.label}${size == null ? '' : ' · $size'}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Export actions',
              onSelected: (action) {
                switch (action) {
                  case 'open':
                    onOpen();
                  case 'share':
                    onShare();
                  case 'delete':
                    onDelete();
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'open', child: Text('Open')),
                PopupMenuItem(value: 'share', child: Text('Share')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
