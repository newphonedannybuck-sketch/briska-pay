# Briska Export System

## Workflow

The Export page guides users through date range, report type, format, report
options, filename, destination, template, preview, and export. Export reads a
filtered snapshot and never modifies stored work records.

## Date ranges

Current and previous pay periods use Briska's shared pay-schedule service.
Calendar month/year ranges use calendar boundaries. All Records uses the
earliest and latest stored entry. Custom ranges require both dates and a start
date on or before the end date.

## Reports and formats

Timesheet, Pay Summary, Monthly Report, and Annual Summary configurations are
available. PDF uses branded A4 layouts, Excel uses typed numeric/date cells and
GBP formats, and CSV is UTF-8 with one import-friendly header. Totals come from
`WorkCalculator`.

## Filenames

Suggested names follow
`Briska_ReportType_YYYY-MM-DD_to_YYYY-MM-DD.extension`. Invalid filesystem and
path characters are removed, length is limited, and the selected extension is
applied. Managed exports never silently overwrite an existing file.

## Storage and library

Managed exports use Briska's application documents directory and the existing
SharedPreferences persistence layer. Records retain report/range metadata and
favourite status. Open, share, print, rename, favourite, and confirmed deletion
operate on the managed file.

Destinations unsupported by scoped platform storage fall back to managed
application storage. Briska never requests unrestricted storage permission.

## Templates

Four built-in templates are always available: Employer Timesheet, Personal
Records, Monthly Summary, and Annual Overview. Applying one updates report,
format, and options without changing work data.

## Privacy and errors

Reports are generated locally and are not uploaded. User-facing errors omit raw
exceptions; debug builds retain technical diagnostics.

## Testing

Unit tests cover pay-period and calendar resolution, invalid ranges, filename
generation/sanitisation, duplicate numbering, and templates. Existing tests
cover PDF generation, Excel numeric formatting, CSV escaping, totals, storage,
and responsive export-library UI.
