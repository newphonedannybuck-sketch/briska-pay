# Custom pay rates

Briska stores rate identity as `primary` or `secondary`; user-facing names are settings, not business identifiers. New users start with **Standard** and **Overtime**. Existing settings migrate Home to the primary rate and Away to the secondary rate, preserving both values. Existing entries migrate in the same way.

Historical entries retain their saved `hourlyRateUsed`, wages, allowance, uplift, and total. They display the current custom label for their generic rate type, so renaming a rate never recalculates historical pay.

Daily Allowance is independent of rate selection and is applied only when manually entered.
