# Premium green UI

The future-release redesign lives on `feature/briska-premium-ui`, based on
`7b659e9`. It retains the five-tab navigation, manual appearance preference,
Poppins typography and existing Briska branding.

## Design and scope

- `lib/design_system/`: semantic light/dark colours, restrained bordered
  surfaces, consistent spacing/radii, financial typography, input focus states,
  buttons, navigation, dialogs and sheets.
- `lib/src/premium_home_screen.dart` and `lib/src/app/briska_shell.dart`:
  clearer earnings hierarchy, responsive pay-period labels, full-width anchored
  Add Day action and separate space for the existing banner and navigation.
- `lib/src/screens/` and `lib/src/widgets/`: consistent entries, calendar,
  Add/Edit Day, reports, export/library, settings, onboarding, security,
  startup/recovery, support, about, legal and confirmation surfaces.
- `lib/screens/loading_screen.dart`: quieter theme-aware startup presentation
  with the existing timing and reduced-motion behaviour.
- `lib/src/export/export_actions.dart`: dialog scrolling and theme-aware
  destructive-action colours; export handlers and outputs are unchanged.

The Save action stays above the software-keyboard inset. Narrow forms stack
their totals and actions; financial values scale to available width. Larger
text, wrapped labels, semantic headings and visible focus states improve
readability. The calendar retains its horizontally scrollable minimum-sized
cells and now explains that gesture when needed.

Calculations, models, persistence/migrations, backup formats, security guards,
advertising consent, currency formatting and generated export data remain in
their existing implementations. Holiday and Bank Holiday hours remain blank
by default. No existing behavioural tests were changed or weakened.

## Review and verification

Final verification on 15 November 2026: Flutter analysis reported no issues;
all 661 existing tests passed. The separate two-theme rendering harness also
passed. The initial full run exposed the same startup overflow in two
large-text/landscape checks; making that surface scrollable resolved both.

Run the normal checks from the repository root:

```powershell
flutter analyze --no-pub
flutter test --reporter expanded
```

To reproduce the actual Flutter screen renders with isolated sample data:

```powershell
flutter test tool/ui_preview_test.dart --reporter expanded
```

PNG files are written to the ignored `build/ui-preview/` directory. They cover
both themes, all five tabs, entry forms, secondary screens, PIN/rename/delete
dialogs, narrow phones, landscape, 2x text and a large INR amount. The focused
Holiday capture simulates a 280-pixel keyboard inset; it does not draw a native
keyboard. The preview uses in-memory settings and never reads installed app
data. A local `build/ui-preview/index.html` gallery accompanies this review.

Screenshots were visually inspected using the Flutter widget renderer, not an
Android emulator or physical device. Native keyboard, live advertising and
platform share/print sheets still need device review before a future release.
No APK/AAB was built or uploaded for this redesign.

The pre-existing version/build and Gradle edits, plus `refactor11_failure.txt`,
were preserved byte-for-byte and excluded from the redesign commits. Main,
signing, package identifiers and the submitted Play release were not changed.
