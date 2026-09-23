## Hard rules that no machine can check

The trigger table routes you to the rest. These sit here because they apply before you
have matched any row.

- **New files go in the folder their feature already owns.** `[prose]`
  `BlockParty/Features/<Feature>/`, one folder per screen, a `SomethingView` paired with a
  `SomethingModel`. Do not invent a new top-level folder, and never leave a file at the
  repo root.
- **On-brand bar** (inherited from the Expo app) `[prose]`: warm, calm, quiet, neighborly,
  hyper-local. No badges/streaks/feeds/notification-spam. **Real data only — never
  seeded/inflated counts.** Voice is a neighbor, not a brand.

**Two rules in this block, and nothing checks either of them.** Keeping that number down is the ongoing
work of this system — a rule nobody can check is a rule that gets broken.
