# Briska Pay

Flutter app for recording work and absence days, calculating expected pay,
reviewing pay periods, and creating local reports and backups.

## Run and verify

Use the Flutter SDK selected for this checkout and the committed `pubspec.lock`.

```powershell
flutter pub get
flutter run
flutter analyze
flutter test
# Focused verification while changing a feature:
flutter test test/settings_persistence_test.dart
# Format the Dart files changed by the task:
dart format path/to/changed_file.dart
```

Run focused existing tests during development; run the full suite before
completing a substantial change. Test fixtures replace storage, authentication,
advertising and file actions. Do not reset installed app data to test refactors.

## Source map

- `lib/main.dart`: entry point, root theme state and `MaterialApp`.
- `lib/design_system/`: canonical theme, colours, spacing and card primitives.
- `lib/screens/loading_screen.dart`: optional animated loading screen.
- `lib/src/app/`: shell, serialized data mutations, route transitions, retained
  tabs and settings-operation contracts.
- `lib/src/screens/`: independently importable screens. The `entries/`,
  `settings/` and `export/` subfolders hold their presentation components.
- `lib/src/widgets/`: shared layout, form controls, report rows and detail text.
- `lib/src/premium_home_screen.dart`: composed dashboard, pay-period pager,
  activity and entry details.
- `lib/src/export/`: generation dispatch, guarded file actions, report schema,
  feedback and filesystem availability.
- `lib/features/export/`: report options, date-range resolution and filename
  suggestions.
- `lib/src/ads/`: consent/SDK adapters, optional startup coordination and banner.
- `lib/src/models.dart` and `models/`: settings, work entries and export records.
- `test/`: calculation, persistence, export, security and navigation regressions.

`lib/src/briska_app.dart` is a public compatibility barrel for existing callers
and tests. It contains no implementation or `part` files. Production modules
import their dependencies directly; there are no application import cycles.

## State and persistence

`BriskaShell` owns navigation, lifecycle integration, lock sessions, startup
gates and restore eligibility. `AppDataController` holds the current data
snapshots and **one mutation queue** shared by entries, settings, export records,
reset and restore. A queued operation includes validation, snapshot creation,
persistence and the UI commit. Failed operations do not poison the queue.
Generation checks reject callbacks from editors belonging to replaced data.

`SettingsScreen` owns its draft, validation, revision tracking and rollback.
Extracted sections read the live draft when callbacks complete, preserving focus
and save timing. `AddWorkDayScreen` owns editor controllers, historical values,
dirty-state checks and submission; its sections only present values/callbacks.

`LocalStorage` owns SharedPreferences serialization and the restore journal.
`BriskaBackupService` validates backup content and produces safety backups.
The shell keeps authentication/session checks around restoration. Stored keys,
JSON fields, legacy migrations and backup formats remain compatible.

`AppLockService` owns PIN/device authentication. `AdvertisingStartup` starts
optional SDK work early and bounds optional operations; the unlocked shell
decides when consent forms may appear. `RetainedTabs` preserves visited tab
state and disables focus/semantics/tickers on inactive tabs. Lock, recovery,
onboarding and data-generation changes still dispose the appropriate tab state.

## Calculations and exports

`WorkCalculator` owns shift/pay calculations and general summaries;
`pay_schedule.dart` owns period/payday resolution. PDF totals reuse equivalent
summary fields but retain their distinct work-only hours, rate totals and
absence-hour definitions.

See [Export architecture](docs/EXPORT_SYSTEM.md) for the creation, library and
file-action boundaries. CSV/Excel/PDF renderers retain format-specific escaping,
numeric cells, rounding and layouts.

## Compatibility decisions

- `CurrencyFormatter.current` remains the UI default, updated by the shell only
  at the established settings/load/restore boundaries. Export requests receive
  explicit settings/currency snapshots. A broad currency-state redesign would
  change a tested cross-screen contract and is outside this structural change.
- Export record data is independent of filesystem APIs. The
  `ExportFileAvailability` extension owns the existing synchronous
  `isAvailable` behavior and is re-exported by `models.dart` for compatibility.
- `ExportScreen.libraryOnly` delegates to `ExportLibraryScreen`; the legacy
  constructor flag and `onPreferencesChanged` callback remain supported for
  existing callers and persistence-failure tests. The production library route
  uses the dedicated screen directly.
- Stored report/range names and the optional `templateId` field are retained.
  Unused template/destination UI scaffolding has been removed.
