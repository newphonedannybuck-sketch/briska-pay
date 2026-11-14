# Briska export architecture

## Creation

`ExportScreen` owns range, report type, format, options, filename and progress.
The UI offers Timesheet and Pay Summary with PDF, Excel and CSV formats.
Calendar ranges, current/previous pay periods, all records and validated custom
ranges use `ExportRangeResolver`. Schedule-specific range availability remains
in the creation screen.

`ExportGenerationService` receives captured entries, settings, identity,
options and timestamps before asynchronous work begins. It dispatches to the
existing CSV, Excel and PDF renderers. It never mutates saved work records.
The created file is registered only after generation succeeds; a failed library
write retains the file and tells the user where it was saved.

## Reports and metadata

`WorkReportSchema` owns column order, currency-aware CSV headings and shared
day-type labels. Each renderer retains its existing fallback labels, escaping,
number representation and styling. Excel uses typed date/numeric cells and the
selected currency; CSV is UTF-8 with a BOM and CRLF rows.

General totals come from `WorkCalculator.summarize`. PDF keeps work-only hours
and average workday hours distinct from all recorded hours, holiday hours and
bank-holiday hours. Rate-specific wage totals remain separate.

## Library and file operations

`ExportLibraryScreen` owns filtering, sorting and library presentation.
`ExportActions` owns per-record operation exclusion, opening, sharing,
printing, renaming, favourite updates and confirmed deletion. Screens retain
presentation eligibility and feedback; inactive screens defer feedback.
Native actions are gated again after asynchronous provider-path migration.

Rename persists the new metadata after moving the file. If persistence fails,
it attempts to restore the original filename and reports rollback failure
explicitly. Deleting a physical file requires the existing second confirmation.
Failed metadata removal leaves a retryable library record.

`ExportActionOverrides` provides the existing test/host injection points.
`ExportFileAvailability` owns filesystem checks separately from record data.
The shell serializes library mutations with all other durable data mutations.

## Filenames and storage

`ExportFilenameService` suggests
`Employee_Name_DD_Month_YYYY.extension`. Normally the date is the resolved
payday; a custom range that does not match a pay period uses the creation date.
Names are sanitized and extensions normalized. `ExportFileNamer` preserves
legacy naming compatibility and adds numbered suffixes to avoid overwrites.

Managed reports use the application-support `exports` directory. Existing
files outside provider-compatible storage are copied into that directory before
native actions, and the changed path must be persisted successfully first.
Library records remain in SharedPreferences with their existing JSON schema.

## Privacy, compatibility and verification

Generation is local. Sharing/opening hands the file to the selected platform
application. User-facing failures omit raw exceptions; debug logs retain
technical diagnostics.

The current UI has no template, destination or preview step. Legacy stored
metadata remains readable, including optional `templateId` values and older
report names.

Existing tests cover ranges and filenames, report figures and privacy options,
CSV escaping, Excel cell formats, PDF reporting hours/signatures, provider-path
persistence, rename rollback, deletion, operation queues and retained-navigation
guards. Run the relevant export tests while changing these modules, then the
full suite before completing an architectural change.
