# Briska Pay Closed Beta Guide

Version: 1.0.0+2
Internal label: Briska 1.0 Release Candidate

## What To Test

1. Install Briska Pay.
2. Complete onboarding.
3. Add Home and Away work records.
4. Add a Holiday.
5. Add an Unpaid Day Off.
6. Add a job uplift.
7. Change themes between System, Light and Dark.
8. Export an Excel file.
9. Create a backup.
10. Restore the backup.
11. Close and reopen Briska Pay.
12. Report any incorrect totals.
13. Report any confusing screens.

Do not send private wage data, names, company details, notes or full backup files unless you intentionally choose to share them.

## Bug Report Template

- App version:
- Phone model:
- Android version:
- Steps to reproduce:
- Expected result:
- Actual result:
- Screenshot:
- Was any data lost?

## Useful Checks

- Whole-number Excel cells should show `0`, `1`, `2`, not `0.`, `1.`, `2.`.
- Holiday should count as 8 hours at the Home rate.
- Unpaid Day Off should count as 0 hours and 0 wages, with only any uplift included.
- Away days should include daily allowance.
- Home days should not include daily allowance.
- Backup restore should show a preview before replacing current data.
