# Source registry

Where Block Party learns what exists in a town and what is happening there. This glossary
covers the places side: finding every place in a town and knowing whether it is open.

## Language

### Places

**Town**:
The area whose ZIP codes are listed for it. Every place with one of those ZIP codes
belongs to it, the countryside included.
_Avoid_: city limits, area

**Place**:
Something in a town a neighbour can visit or deal with: a business, church, park, school,
club or public office. A place is the organisation (or the park itself), not the building
it sits in.
_Avoid_: business (when any place is meant), listing, location

**Entry**:
The registry's record of one place. Its id never changes, through renames and moves alike.
_Avoid_: row, record, source (a source is one URL inside an entry)

**Rename**:
The same organisation carrying on under a new name. It stays the same place, and the old
name is kept as a past name.
_Avoid_: rebrand

**Successor**:
A different organisation that takes over a place's spot. It is a new place, and the place
it replaced is closed.
_Avoid_: rename, new owner

### Finding and checking

**Discovery**:
Finding every place that exists in a town, measured against outside sources rather than
against what the registry already holds.
_Avoid_: scrubbing, scraping, crawling

**Sweep**:
A discovery pass through a map service one category at a time ("restaurant",
"electrician", "farm"), with the town named in every search.
_Avoid_: scan, crawl

**Duplicate**:
Two sightings of the same place, from different sources or under different names.
_Avoid_: match, copy

**Same place? list**:
The pairs of sightings too uncertain to merge automatically, left for Jesse to settle once.

**Verification**:
Deciding from evidence whether a known place is operating now.
_Avoid_: scrubbing, checking

**Verdict**:
The outcome of verification for one place: Open, Renamed, Moved, Closed or Unknown.

**Unknown**:
The verdict for missing or conflicting evidence. It is never a guess in either direction.

**Outreach list**:
The places verification cannot settle online, kept for confirming by phone or in person.
_Avoid_: call list

### The registry

**Registry**:
The set of town files: Block Party's human-owned answer to where it looks for local
information, and how.

**Source**:
One URL inside an entry, together with how to read it. An entry can have several.

**Runtime state**:
What happened the last time a source was read. It belongs to the runner, never to the
town files.

**Sync**:
The one-way copy of registry fields from the town files into the database. When the two
disagree, the town file wins.

**Snapshot**:
The saved text of a source at the moment it was read, kept only when it changed.

**Dry-run**:
A run that reads sources for real but writes nothing to production. The default.
