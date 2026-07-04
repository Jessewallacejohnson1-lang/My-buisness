# Design References: Today Home Screen

**Screen:** The primary Today home screen for a warm, calm, hyper-local community/town app.
**Needs:** (1) Premium date/today bar at top, (2) vertical timeline of day's events with a visible time axis, (3) event cards with time, title, location, going count.
**Design language:** Linen off-white surfaces, charcoal ink, editorial serif + clean grotesk + monospace for numbers, generous whitespace, calm minimal, color semantic only. Kinfolk/Monocle feel.

---

## Reference 1 — Things 3 (Cultured Code): Today View

**Source:** https://culturedcode.com/things/features/ | App Store screenshots: https://apps.apple.com/us/app/things-3/id904237743

**Layout pattern:** Full-bleed white surface. The date and day-of-week sit as a large typographic header at the very top — not a navigation bar. Below it, calendar events from iOS Calendar appear first as a separate section (grey-tinted, time-stamped, reads like a mini agenda), then To-Dos follow. The screen is split into two named sections: "This Morning" and "This Evening," each introduced by a lightweight section label — no ruled lines, just a label and whitespace. Items are left-aligned, single-line, with a circular checkbox on the left. No explicit time rail — the time is implicit in the section heading. Typography is a clean grotesk, oversized and airy. Whitespace is generous to the point of feeling like a handwritten page.

**Why it works for this screen:** Things 3 solved the same problem Hygge has — a "today" that feels like the beginning of something, not a notification tray. Calendar events at the top mirror what Hygge needs (the day's events as a true agenda preview). The two-section structure (Morning / Evening) could adapt directly to how Hygge groups community events by time of day. The typography-as-date-header pattern — where the date is large and editorial, not a utility bar — is exactly the treatment to extract. Won two Apple Design Awards specifically for this restraint.

**Hygge adaptation:** Replace the checkbox list with event cards. Adopt the section-label pattern ("This Afternoon / This Evening") as a lightweight divider between time clusters. Use DM Serif Display for the day-of-week + date numeral in the header, Outfit for section labels, Geist Mono for the time stamps on events. The surface stays paper-white; the date header gets no background — it floats on linen.

---

## Reference 2 — Timepage by Moleskine (Bonobo Labs): Timeline + Day View

**Source:** https://bonobolabs.com/timepage/ | MacStories review: https://www.macstories.net/reviews/timepage-a-beautiful-and-clever-calendar-app/

**Layout pattern:** The Timeline is the default screen — a vertically scrolling list of upcoming days. Along the left edge runs a persistent date spine: month + year label, then day-of-week abbreviations stacked vertically, with today highlighted (colored, slightly bolder) while other days sit in muted contrast. Each day is a self-contained block, visually separated from the next by spacing rather than a ruled line. Within a day block, events are listed as compact rows with time and title. In Day View (tapped from the Timeline), events become colored cards — the card color matches the calendar it belongs to. The Hourly mode renders a time axis on the left with event cards spanning the corresponding time range, creating a true hour-by-hour column. The date at the top of the Day View is large, plain, and sits flush-left. Weather data integrates unobtrusively at the bottom of each day block.

**Why it works for this screen:** Timepage is the strongest existing reference for the "spine + day cards" pattern. The left-side date/day-of-week column is precisely the time rail Hygge needs. The card-per-event approach in Hourly mode shows exactly how to give each community event visual weight while keeping the time axis readable. The app's design philosophy — built from the ground up for Moleskine, whose brand sits in the same Kinfolk/editorial space as Hygge — is the closest brand-adjacent reference available. The weather integration at the bottom of each day block is also directly relevant to Hygge's WeatherBar concept.

**Hygge adaptation:** Take the left-time-spine pattern (time labels as ink-3 monospace, hairline vertical rule in black/7%) and apply it to a single-day view showing today only. Cards become Hygge event cards — paper-white with a hairline border, no calendar color coding (Hygge uses color semantically, not decoratively). The date header above the spine uses DM Serif Display at a large scale.

---

## Reference 3 — Structured: Daily Planner (Leo Mehlig): Day Timeline

**Source:** https://structured.app/ | App Store: https://apps.apple.com/us/app/structured-daily-planner-todo/id1499198946 | Getting started: https://help.structured.app/en/articles/380546

**Layout pattern:** The entire screen is a vertical time axis. The left side runs a continuous column of hour labels (in small, light type — intentionally recessive). The right side fills with colored time-blocks — rectangular cards that span exactly the time they occupy, anchored top and bottom to their start and end times on the axis. An "inbox" of unscheduled tasks sits at the bottom. At the top: a horizontal week-strip (7 day pills, the active day highlighted) for quick date switching, then the timeline begins immediately below. There is no separate header bar — the date context comes entirely from the week strip. The overall aesthetic is clean and geometric, with blocks of restrained color (not pastels, but not aggressive primaries either).

**Why it works for this screen:** Structured nails the time-anchored vertical layout with more clarity than any calendar app — because it was designed for daily planning, not date navigation. The left time-column pattern is immediately readable: your eye runs down the time labels and finds the events anchored to them naturally. For Hygge, this is the most directly extractable pattern for the event timeline section. The implicit now-line (a horizontal rule at the current time of day) is also a strong signal to borrow — it tells the user exactly where they are in the day without a label.

**Hygge adaptation:** Strip the color-block system (Hygge has no decorative color). Replace color blocks with paper-white cards with a hairline border. Keep the left time-column in Geist Mono, ink-3. Keep the now-line (a 1px moss-600 horizontal rule at current time, the only color on the screen, and it earns it — it means "now"). Shrink the week-strip at top to a minimal date pill showing only today's full date.

---

## Reference 4 — Fantastical (Flexibits): Day View + DayTicker

**Source:** https://flexibits.com/fantastical | Calendar views help: https://flexibits.com/fantastical-ios/help/calendar-views | ScreensDesign breakdown: https://screensdesign.com/showcase/fantastical-calendar

**Layout pattern:** Fantastical's day view occupies the full screen: a compact mini-calendar or week-strip at top (collapsible) shows the month context, then immediately below is the agenda for the selected day. On the left side of each event row: the start time in small type. Event title follows, bold, left-aligned. Location and calendar color dot follow on a second line. The now-line is a colored horizontal rule that scrolls with the view — always visible in the viewport. The "DayTicker" (compact header mode) is a horizontal scroll of upcoming days where each day's events appear as tiny colored pills, showing density at a glance without full cards. The header itself shows the weekday name and date numeral prominently, with the month year in smaller type above or beside it.

**Why it works for this screen:** Fantastical is the benchmark for time-anchored agendas on iOS. Its pattern of left-aligned time stamps + right-side event content with the now-line is the most widely recognized and understood convention — users come to Hygge already fluent in it. The DayTicker is specifically useful as a precedent for how to give the "today" date header prominence without losing the event list below. The now-line as the only colored element on an otherwise mono screen is a clean semantic-color move that maps directly to Hygge's rule: color only for meaning.

**Hygge adaptation:** Adopt the left-time / right-content split. The time stamps in Geist Mono (ink-3, small) on the left; event title in Outfit medium (ink) on the right; location and going count below the title in smaller Outfit (ink-2) and Geist Mono respectively. The now-line in moss-600 (1px) — it means "currently happening." The header: day-of-week in small Outfit caps (ink-2), date numeral large in DM Serif Display (ink), and a discreet weather line in Geist Mono below.

---

## Reference 5 — Gentler Streak (Gentler Stories): Home Screen Today Treatment

**Source:** https://gentler.app/ | Pixso breakdown: https://pixso.net/articles/gentler/ | Mobbin screen: https://mobbin.com/explore/screens/2d19f058-33ac-42d7-800a-003b0a57c98c | 60fps animation: https://60fps.design/apps/gentler-streak

**Layout pattern:** The home screen opens with a large, personalized status greeting — effectively a "good morning, here is where you stand today" — occupying the top third of the screen. This is not a navigation bar. It is editorial: a headline-size statement in warm, round type, with a supporting line in smaller type. Below it, data visualizations (the "Activity Path" ring and key metrics) occupy the middle. At the bottom, contextual suggestions for the day. The date is not displayed as a traditional date header — instead it's implied by the greeting ("Today" or the day name) set in large type. The color palette is warm teal/sage and off-white. The surface is not stark white but a slightly warm off-white, almost paper-like. Every number (step count, heart rate) is displayed in a larger, slightly bolder monospace-feeling style.

**Why it works for this screen:** Gentler Streak won Apple's Design Award for the best wellness app UI — and what it nailed is exactly what Hygge needs in its today header: a top section that feels like a warm greeting rather than a toolbar. The "today begins here" feeling — where the top of the screen is a statement about the day, not a navigation element — is the editorial gesture that separates premium apps from utility apps. The warm off-white surface, the generous top padding, and the data in a readable mono-adjacent style are directly on-brand for Hygge.

**Hygge adaptation:** Borrow the editorial top-third pattern. In Hygge: the top section is "MONDAY" in small Outfit caps (ink-3) + "30" in large DM Serif Display (ink) + "June" in medium Outfit (ink-2). Below that, a one-line weather summary in Geist Mono (ink-2). That entire block is the "greeting." Then the timeline begins. No navigation bar, no search box, no avatar row — just date and weather as the opening statement.

---

## Reference 6 — Agenda: Notes meets Calendar (Agenda BV): Date-as-Spine Timeline

**Source:** https://agenda.com/ | App Store: https://apps.apple.com/us/app/agenda-notes-meets-calendar/id1370289240 | Paperless X review: https://beingpaperless.com/agenda/

**Layout pattern:** Agenda's organizing principle is a continuous vertical timeline where the date runs down the left as a persistent label — day of week + date numeral stacked in a small column — and content (notes, calendar events) occupies the right. Each day is a block in the scroll, separated by the date label rather than a rule. Notes tied to calendar events show the event name as a small colored header above the note body. There is no top-of-screen "today" bar — instead the timeline itself scrolls to today automatically, and today's date label is set in a highlighted style (solid circle or bold) within the left column. The result is that scrolling through the timeline is like scanning a journal: the date labels are the spine of the page, and everything else is content.

**Why it works for this screen:** Agenda won Apple's Design Award for exactly this pattern — it made the date the editorial anchor of the interface rather than a toolbar decoration. The left-date-column-as-spine is a direct and transferable pattern for Hygge's event timeline: time stamps on the left are the spine; events on the right are content. The app proves that a timeline can feel warm and journal-like rather than sterile and calendar-like when you let the date labels breathe (generous vertical rhythm, left-flush, no background fills, no grid lines).

**Hygge adaptation:** Use the left-column-as-spine pattern for the event timeline section specifically. The left column carries only time (not date, since the screen shows one day): times in Geist Mono (ink-3) at each event's start. A hairline vertical rule (1px, black/7%) runs the full height of the timeline column, with a small dot or node at each event's time position. Event cards sit to the right, flush against the rail, paper-white with a hairline border. This is the literal "time spine" pattern.

---

## Reference 7 — Apple Calendar (Apple): Agenda View Today Bar

**Source:** https://support.apple.com/guide/iphone/view-your-calendar-iph3ffe32e08/ | iOS 26 review: https://9to5mac.com/2026/03/05/ios-26-gives-apples-calendar-app-a-convenient-new-advantage/

**Layout pattern:** Apple Calendar's agenda view (list view) puts today's date prominently — day-of-week in caps, date numeral large — at the visible top as a sticky header that stays put as events scroll beneath. Each event row shows: time (left, small, recessive) + title (right, medium weight) + calendar color dot. Past events are visually dimmed (grey). The now-line is a red horizontal rule — the only red element in the otherwise mono interface. Today's date numeral in the month mini-calendar at top is circled in the system accent color. The typography is San Francisco — system default — but the sizing relationships (large date at top, small recessive time labels on left, medium event title) are the transferable conventions.

**Why it works for this screen:** Apple Calendar's agenda view establishes the shared iOS convention that millions of users already know: time label left, title right, now-line mid-screen. It is the "baseline literacy" pattern — every iOS user can read it without learning. For Hygge, this means the time-spine layout has zero learning curve. The sticky "today" date header at top is also the clearest possible precedent for a floating date bar that doesn't disappear when the user scrolls.

**Hygge adaptation:** Adopt the sticky date header behavior (date stays pinned at top while timeline scrolls beneath). Replace the system typography with DM Serif Display for the date numeral, Outfit for day-of-week and section labels, Geist Mono for times. Replace the red now-line with moss-600 (earning its color: it means "now / in progress"). Remove the calendar color dots — Hygge has no multi-calendar context, so the dots are noise.

---

## Synthesized Recommendation for Hygge's Today Screen

The pattern that best serves this screen combines three moves from the references above:

**1. Editorial date header (top third, not a nav bar)**
Day-of-week in small Outfit uppercase (ink-3), tracking wide. Immediately below it: the date numeral in DM Serif Display at ~72sp (ink), flush-left, no background, no capsule. A discreet weather line in Geist Mono (ink-2) below the numeral — temperature + conditions in one line. This block occupies roughly 120-140pt at the top, has generous top padding (safe area + 24pt), and no border or separator below it. It reads like a newspaper dateline. (Source: Gentler Streak editorial top-section + Things 3 typographic date header)

**2. Left-time-spine timeline (middle, scrollable)**
A thin vertical hairline rule (1px, black/7%) runs the full height of the event list, positioned ~56pt from the left edge of the screen. At each event's start time, a small filled circle node (6pt, ink) sits on the rule. Time stamps in Geist Mono (12sp, ink-3) are left-aligned outside the rule. Event cards are right of the rule, with 12pt gap from it. Cards are paper-white, 1px hairline border (black/7%), 12pt corner radius, internal padding 12pt. Each card shows: event title in Outfit medium (ink, 16sp), location in Outfit regular (ink-2, 13sp), and going count in Geist Mono (ink-2, 12sp) with a small moss dot if the user is going. (Source: Agenda date-as-spine + Structured left time column + Timepage hourly card view)

**3. Now-line as the only semantic color**
A 1px horizontal rule in moss-600 crosses the timeline at the current time position, labeled with the current time in Geist Mono (moss-700, 11sp) on the left. It scrolls with the list. This is the only non-ink, non-surface color on the screen outside of semantic going-status dots. Everything else is ink on linen. (Source: Fantastical + Apple Calendar now-line conventions)

**What to skip:** Fantastical's DayTicker pill-row, Things 3's checkboxes, and Structured's color-block system. All assume task management or multi-calendar contexts. Hygge's events are read-only community cards — the interaction is "tap to RSVP," not "mark done."

**Three-tap rule check:** User opens app → sees today's date + weather (0 taps) + first event immediately below (0 taps) → taps card to RSVP (1 tap). The layout puts the most time-proximate event at the top of the scrollable list, so zero scrolling is needed for the current moment. That is one tap to value.
