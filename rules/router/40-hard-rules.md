## Hard rules that no machine can check

The trigger table below routes you to everything a hook or a test already catches. These
three are caught by nobody, and they are the ones that get broken.

- **A green build is not evidence that a change landed.** `[prose]` SwiftUI accepts
  modifiers that do nothing and nothing fails; three such no-ops shipped looking "subtle"
  before anyone measured them. Build → install over → launch with a debug flag →
  screenshot → **count actual pixels** in the region you changed.
- **New files go in the folder their feature already owns.** `[prose]`
  `BlockParty/Features/<Feature>/`, one folder per screen, a `SomethingView` paired with a
  `SomethingModel`. Do not invent a new top-level folder, and never leave a file at the
  repo root.
- **On-brand bar** (inherited from the Expo app) `[prose]`: warm, calm, quiet, neighborly,
  hyper-local. No badges/streaks/feeds/notification-spam. **Real data only — never
  seeded/inflated counts.** Voice is a neighbor, not a brand.

**Three rules in this block, and nothing checks any of them.** Keeping that number down is the ongoing
work of this system — a rule nobody can check is a rule that gets broken.
