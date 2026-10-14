# Source registry

Where Block Party learns what exists in a town and what is happening there. This glossary
covers the places side (finding every place in a town and knowing whether it is open) and
the events and news those places announce.

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

**Social page**:
A place's own public page on Facebook or Instagram. It is the place's own channel, so a
recent post there is a sign of life and its name can name the place.
_Avoid_: profile, account, socials

**Live post**:
Something a place publishes on its own channel that Block Party shows as it is, photo and
words included. Only for a place that has said yes; for every other place, Block Party
takes the facts (an event, a closure, a cancellation) and leaves the post.
_Avoid_: business post (any place can post), repost, share, posting (the app's word for an
event card)

**Town group**:
An online group where neighbours post about the town, such as a public Facebook group. It
is secondhand: neighbours passing on what they heard, not the place speaking.
_Avoid_: community group (that is a kind of place: a club or organisation)

**Tip**:
A secondhand mention that something changed, such as a closure or a cancellation, which
sends Block Party to check the place's own channel.
_Avoid_: rumour, report

**Temporary closure**:
A place shut for a stretch with an end date ("closed today, staff sick", "closed for
vacation Oct 10–17"). It ends on its own and never changes the place's verdict.
_Avoid_: closed (Closed means gone for good)

**Outreach list**:
The places verification cannot settle online, kept for confirming by phone or in person.
_Avoid_: call list

### Events and news

**Event**:
Something a neighbour can go to, at a time and a place: a council meeting, a fish fry, a
festival. The same kind of thing whoever announced it, a club, a place or the city.
_Avoid_: posting, listing, happening

**News**:
Something to know rather than go to, even when it carries dates: a road closure, a new
menu, a policy change. It goes on the town board, never the event list.
_Avoid_: event (for anything you cannot attend), announcement

**Series**:
A repeating event stored once with its rule ("every Friday 3–7, May through October").
_Avoid_: recurring event (fine in speech, but the series is the thing)

**Occurrence**:
One date of a series. Cancelling an occurrence leaves the series and its other dates alone.
_Avoid_: instance, session

**Mention**:
One source announcing an event or a piece of news. An event announced by the City, a
place's page and two neighbours is one event with four mentions.
_Avoid_: duplicate (that is two sightings of one place), copy

**Cancellation**:
An event or occurrence called off. It is shown, not deleted, so a neighbour who planned to
go finds out.
_Avoid_: closure (that is a place)

**Event size**:
How far ahead neighbours need to hear about an event: **everyday** (a council meeting, a
weekly class, a regular fish fry), **notable** (a one-off community event: a fundraiser, a
church dinner, a concert) or **big** (a town festival, a parade, an annual event people plan
around, anything with tickets or sign-ups that fill up). Not how many people go.
_Avoid_: importance, priority

**Lead time**:
How long before an event it starts showing in the Town feed, set by its size: two weeks
for everyday, four for notable, eight for big. The day it starts is its show-from day.
_Avoid_: horizon, window

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
