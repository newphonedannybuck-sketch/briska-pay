# Briska 1.0 Release Candidate Test Results

Version: 1.0.0+2
Internal label: Briska 1.0 Release Candidate

## Manual Test Month

July 2026 test data, not shipped in the production app.

Rates:
- Home hourly rate: GBP 25.00
- Away hourly rate: GBP 30.00
- Away daily allowance: GBP 25.00

Records:
- 10 Home work days
- 8 Away work days
- 2 Holidays
- 1 Unpaid Day Off
- Several job uplifts
- Several daily allowances
- Whole-number, half-hour and quarter-hour entries
- Multiple repeated sites
- Entries spanning a pay-period boundary

Independent expected totals:
- Total records: 21
- Holidays: 2
- Unpaid days: 1
- Home hours: 80
- Away hours: 64.75
- Holiday hours: 16
- Total hours: 160.75
- Home wages: GBP 2,000.00
- Away wages: GBP 1,942.50
- Holiday wages: GBP 400.00
- Total wages: GBP 4,342.50
- Daily allowance total: GBP 200.00
- Job uplift total: GBP 230.00
- Grand total expected pay: GBP 4,772.50

Automated coverage:
- `test/release_candidate_dataset_test.dart` verifies these totals through the shared calculation engine.
- `test/work_calculator_test.dart` verifies Home, Away, Holiday and Unpaid Day Off rules.
- `test/pay_schedule_test.dart` verifies weekly, fortnightly, four-weekly, monthly and last-Friday pay-period behaviour, including February, leap year and after-payday cases.
- `test/backup_service_test.dart` verifies valid, legacy, missing optional data, invalid JSON and unsupported backup handling.

Manual checks still required on physical Android hardware:
- Cold launch, warm launch and app resume.
- Updating over an existing install.
- Excel files opened in Microsoft Excel, Google Sheets and an Android spreadsheet viewer.
- Biometrics on a device with and without biometric hardware.
- Large text scale and screen reader pass.
- Backup restore using a real file picker.
