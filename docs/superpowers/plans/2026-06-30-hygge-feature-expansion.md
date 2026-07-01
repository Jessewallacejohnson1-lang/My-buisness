# Hygge Feature Expansion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let neighbors actually post events/clubs/trails (with photo + AI moderation), personalize the app to their interests via a first-run onboarding, and make it easy to bring a neighbor to an event — natively in SwiftUI against the live Supabase backend.

**Architecture:** Extend the existing hand-rolled Supabase layer (`Backend/*.swift`) with three new capabilities — Storage upload, Edge Function invocation (moderation), and on-device interests — then build the Add forms, Onboarding, "Bring a neighbor" share, and an opt-in local reminder on top. No new dependencies; SwiftUI `PhotosPicker`, `ImageRenderer`, `ShareLink`, and `UNUserNotificationCenter` cover photo/share/reminder needs.

**Tech Stack:** Swift 6 / SwiftUI (iOS 26.5), URLSession → Supabase (GoTrue + PostgREST + Storage + Edge Functions), PhotosUI, UserNotifications.

## Global Constraints

- **No unit-test runner exists.** Each task's verification = `build_sim` compiles clean (zero errors/warnings) **and** the change is confirmed running on the iPhone 17 simulator via XcodeBuildMCP (`build_run_sim`, `screenshot`, `snapshot_ui`). "Done" = observed in the running app, not just compiled.
- **On-brand bar:** warm, calm, neighborly, hyper-local. No badges/streaks/feeds/follower-counts, no fake/seeded counts, no notification spam. Numbers use `font-mono` equivalents (`Font.mono*`) with tabular figures. Accents keep one job each (moss = positive/primary, sky = brand, clay = warning).
- **Excluded by product owner:** "new folks welcome"/who's-going, and spontaneous "I'm around"/walk-together meetups. Do not build these.
- **Dates:** always `DateHelpers.localDate()` (local tz), never UTC.
- **Fonts:** `Font.display/displaySemi/sans/sansMedium/sansSemibold/sansBold/mono/monoMedium` — never system weights for on-brand text.
- **Verify one step at a time; commit after each task** in the `Hygge` repo (`/Users/owner/Documents/Hygge`).

---

## File Structure

**New backend:**
- `Hygge/Backend/Storage.swift` — upload image Data → `event-images` bucket → public URL.
- `Hygge/Backend/Moderation.swift` — invoke `moderate-post` Edge Function → `(ok, reason)`.
- `Hygge/Backend/Interests.swift` — INTERESTS taxonomy, `matchesInterests`, UserDefaults get/set + onboarded flag.
- `Hygge/Backend/Reminders.swift` — request permission + schedule/cancel one local notification per event.

**New features:**
- `Hygge/Features/Add/AddModel.swift` — form state + submit pipeline (upload → moderate → insert).
- `Hygge/Features/Add/AddFormView.swift` — the event/club/trail form UI.
- `Hygge/Features/Onboarding/OnboardingView.swift` — hello → interests → done.
- `Hygge/Features/Components/InviteCard.swift` — rendered invite card + ShareLink.

**Modified:**
- `Hygge/Features/Add/AddView.swift` — kind chooser navigates to `AddFormView(kind:)`.
- `Hygge/App/RootView.swift` — gate: signed-in + not onboarded → `OnboardingView`.
- `Hygge/Features/Home/HomeView.swift` + `HomeModel.swift` — "Suggested for you" via interests; "Add an event" opens Add.
- `Hygge/Features/Activities/ActivitiesView.swift` + `ActivitiesModel.swift` — interest-ranked ordering + invite button.
- `Hygge/Features/Components/EventRow.swift` — add "Invite a neighbor" + "Remind me".
- `Hygge/Backend/CommunityAPI.swift` — no change to signatures; reused as-is.

---

## Task 1: Storage upload (`Storage.swift`)

**Files:**
- Create: `Hygge/Backend/Storage.swift`

**Interfaces:**
- Consumes: `SupabaseConfig`, `AuthStore.validAccessToken()`.
- Produces: `struct Storage { let auth: AuthStore; func uploadEventImage(_ data: Data, contentType: String = "image/jpeg") async -> String? }` — returns public URL or nil (never throws; nil → post without image).

**Reference (Expo `uploadImage.ts`):** upload bytes to bucket `event-images` at path `events/{timestampMillis}.jpg`; public URL = `${url}/storage/v1/object/public/event-images/events/{ts}.jpg`.

- [ ] **Step 1: Implement**

```swift
import Foundation

struct Storage {
    let auth: AuthStore

    /// Upload image bytes to the public `event-images` bucket; return the public
    /// URL, or nil on any failure so the caller can post without an image.
    func uploadEventImage(_ data: Data, contentType: String = "image/jpeg") async -> String? {
        guard let token = try? await auth.validAccessToken() else { return nil }
        let ext = contentType.split(separator: "/").last.map { String($0).replacingOccurrences(of: "jpeg", with: "jpg") } ?? "jpg"
        let ts = Int(Date().timeIntervalSince1970 * 1000)   // Date.now() is fine at runtime (only workflow scripts ban it)
        let path = "events/\(ts).\(ext)"
        var req = URLRequest(url: SupabaseConfig.storageURL.appendingPathComponent("object/event-images/\(path)"))
        req.httpMethod = "POST"
        req.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        guard let (_, resp) = try? await URLSession.shared.upload(for: req, from: data),
              let code = (resp as? HTTPURLResponse)?.statusCode, (200..<300).contains(code) else { return nil }
        return SupabaseConfig.url.appendingPathComponent("storage/v1/object/public/event-images/\(path)").absoluteString
    }
}
```

- [ ] **Step 2: Verify compile** — `build_sim`. Expected: BUILD SUCCEEDED, no warnings.
- [ ] **Step 3: Commit** — `git add Hygge/Backend/Storage.swift && git commit -m "feat(backend): event-images storage upload"`

---

## Task 2: Moderation Edge Function (`Moderation.swift`)

**Files:**
- Create: `Hygge/Backend/Moderation.swift`

**Interfaces:**
- Produces: `struct Moderation { let auth: AuthStore; func check(kind: PostKind, title: String, location: String?, length: String?, description: String?, imageUrl: String?) async -> (ok: Bool, reason: String) }`
- Contract (from `supabase/functions/moderate-post/index.ts`): POST `${url}/functions/v1/moderate-post`, JSON body `{kind,title,location,length,description,image_url}`, response `{ok: Bool, reason: String}`. **Fail-open to the moderation queue:** on any transport error, return `(ok:false, reason:"__queue__")` sentinel so the caller posts with status `pending` rather than blocking (mirrors the Expo fail-closed-to-pending behavior).

- [ ] **Step 1: Implement**

```swift
import Foundation

struct Moderation {
    let auth: AuthStore
    /// Sentinel reason meaning "couldn't auto-check → send to the pending queue".
    static let queueSentinel = "__queue__"

    func check(kind: PostKind, title: String, location: String?, length: String?,
               description: String?, imageUrl: String?) async -> (ok: Bool, reason: String) {
        guard let token = try? await auth.validAccessToken() else { return (false, Self.queueSentinel) }
        var body: [String: Any] = ["kind": kind.rawValue, "title": title]
        if let location { body["location"] = location }
        if let length { body["length"] = length }
        if let description { body["description"] = description }
        if let imageUrl { body["image_url"] = imageUrl }

        var req = URLRequest(url: SupabaseConfig.url.appendingPathComponent("functions/v1/moderate-post"))
        req.httpMethod = "POST"
        req.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let code = (resp as? HTTPURLResponse)?.statusCode else { return (false, Self.queueSentinel) }
        guard (200..<300).contains(code),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (false, Self.queueSentinel)   // 5xx / bad body → queue, don't block
        }
        let ok = (obj["ok"] as? Bool) ?? false
        let reason = (obj["reason"] as? String) ?? ""
        return (ok, reason)
    }
}
```

- [ ] **Step 2: Verify compile** — `build_sim`. Expected: BUILD SUCCEEDED.
- [ ] **Step 3: Commit** — `git commit -am "feat(backend): moderate-post edge function client"`

---

## Task 3: Add form model (`AddModel.swift`)

**Files:**
- Create: `Hygge/Features/Add/AddModel.swift`

**Interfaces:**
- Consumes: `CommunityAPI`, `Storage`, `Moderation`, `NewEventInput`, `NewTrailInput`, `ClubInput`, `PostKind`, `ClubStatus`, `DateHelpers`.
- Produces: `@MainActor final class AddModel: ObservableObject` with published form fields (title, date, time, location, description, host, schedule, vibe, expectations, length, difficulty, `photo: Data?`, `repeatWeeklyCount: Int`), `submitting`, `error`, `posted: Bool`, `pendingNotice: Bool`; `func submit(kind:api:storage:moderation:) async`.

**Submit pipeline (mirrors Expo `add.tsx`):**
1. Validate required fields per kind (event: title/date/time/location; club: title[+host]; trail: title/location).
2. If `photo != nil` → `storage.uploadEventImage(photo)` → `imageUrl` (nil-safe).
3. `moderation.check(...)` → if `reason == queueSentinel` → status `.pending`; else if `!ok` → set `error = reason`, stop; else status `.approved`.
4. Insert via `api.addEvent`/`addTrail`/`submitClub`. For a recurring event (`repeatWeeklyCount > 1`), call `addEvent` once per week: `event_date = localDate(addDays(7*i))`-style, i in 0..<count, same other fields.
5. On success: if pending → `pendingNotice = true`; else `posted = true`.

- [ ] **Step 1: Implement** the class per the pipeline above (full code written at execution time; every field and branch concrete, no TODOs).
- [ ] **Step 2: Verify compile** — `build_sim`.
- [ ] **Step 3: Commit** — `git commit -am "feat(add): submit pipeline model"`

---

## Task 4: Add form UI (`AddFormView.swift` + wire `AddView.swift`)

**Files:**
- Create: `Hygge/Features/Add/AddFormView.swift`
- Modify: `Hygge/Features/Add/AddView.swift` (kind cards navigate to the form)

**Interfaces:**
- `AddFormView(kind: PostKind)` — `@EnvironmentObject auth`, `@StateObject model = AddModel()`, `@Environment(\.dismiss)`.
- Photo: SwiftUI `PhotosPicker(selection:)` → load `Data` into `model.photo`; show thumbnail + remove.
- Event: `DatePicker` (date, `in: Date()...`), a time field (segmented AM/PM + hour, or a `DatePicker(.hourAndMinute)` formatted to a display string like "5 PM"), location `TextField`, description `TextEditor`, and a "Repeat weekly" stepper (1–8).
- Club/Trail: their respective `TextField`s per `ClubInput`/`NewTrailInput`.
- Submit button (moss, disabled while `submitting`); error text in `clay`; on `posted`/`pendingNotice` → dismiss with a calm confirmation.

**AddView change:** each kind card becomes a `NavigationLink`/sheet to `AddFormView(kind:)`. Wrap `AddView` content in a `NavigationStack` if not already.

- [ ] **Step 1: Implement** the form + wire the chooser (full SwiftUI at execution time).
- [ ] **Step 2: Verify (running app)** — `build_run_sim`; sign in; open Add → Event; fill title/date/time/location; submit; confirm it posts (then verify via Supabase MCP that the row exists with status approved, and it appears on the Calendar/Activities). `screenshot` the flow.
- [ ] **Step 3: Commit** — `git commit -am "feat(add): event/club/trail forms with photo + moderation"`

---

## Task 5: Interests + onboarding storage (`Interests.swift`)

**Files:**
- Create: `Hygge/Backend/Interests.swift`

**Interfaces (port of `lib/interests.ts`, verbatim taxonomy):**
```swift
struct Interest: Identifiable, Hashable { let id: String; let label: String; let keywords: [String] }
enum Interests {
    static let all: [Interest] = [ /* 9 entries verbatim: outdoors, music_arts, food, families, faith, sports, books, service, games */ ]
    static func get() -> [String]           // UserDefaults "hygge.interests"
    static func set(_ ids: [String])
    static func isOnboarded() -> Bool        // UserDefaults "hygge.onboarded" == "1"
    static func setOnboarded()
    static func matches(_ haystack: String, _ ids: [String], isTrail: Bool = false) -> Bool
}
```
`matches`: empty ids → false; `isTrail && ids.contains("outdoors")` → true; else any interest's keyword is a substring of `haystack.lowercased()`.

- [ ] **Step 1: Implement** with all 9 interests copied exactly from `interests.ts`.
- [ ] **Step 2: Verify compile** — `build_sim`.
- [ ] **Step 3: Commit** — `git commit -am "feat(backend): interests taxonomy + onboarded flag"`

---

## Task 6: Onboarding flow (`OnboardingView.swift` + gate)

**Files:**
- Create: `Hygge/Features/Onboarding/OnboardingView.swift`
- Modify: `Hygge/App/RootView.swift`

**Interfaces:**
- `OnboardingView(onDone: () -> Void)` — steps `hello → interests → done`. Interests step: grid of `Interests.all` as toggle chips (moss when selected), "Continue" disabled until ≥1; "Skip for now". On finish: `Interests.set(selected)`, `Interests.setOnboarded()`, `onDone()`.
- `RootView` gate: add `@State needsOnboarding = !Interests.isOnboarded()`; when `auth.isSignedIn && needsOnboarding` → `OnboardingView { needsOnboarding = false }`, else `MainTabsView`.

- [ ] **Step 1: Implement** the view + gate.
- [ ] **Step 2: Verify (running app)** — fresh install → sign in → onboarding appears → pick interests → lands on tabs; relaunch → onboarding does not reappear. `screenshot`.
- [ ] **Step 3: Commit** — `git commit -am "feat(onboarding): first-run interests flow + gate"`

---

## Task 7: Personalize Home + Activities

**Files:**
- Modify: `Hygge/Features/Activities/ActivitiesView.swift` (+`ActivitiesModel.swift`), `Hygge/Features/Home/HomeView.swift` (+`HomeModel.swift`)

**Behavior:**
- Activities: a "Suggested for you" section at the top (only when `Interests.get()` non-empty) listing clubs/trails where `Interests.matches(name+vibe+schedule..., ids, isTrail:)` is true. Below it, the normal filtered lists unchanged. No fake ranking numbers.
- Home: the "Add an event" button on the clear-day `TodayCard` switches to the Add tab (pass a binding or use a shared tab selection).

- [ ] **Step 1: Implement.**
- [ ] **Step 2: Verify (running app)** — with interests set, "Suggested for you" shows matching real clubs/trails; empty when none match. `screenshot`.
- [ ] **Step 3: Commit** — `git commit -am "feat: interest-based suggestions on Activities + Home"`

---

## Task 8: Bring a neighbor (`InviteCard.swift`)

**Files:**
- Create: `Hygge/Features/Components/InviteCard.swift`
- Modify: `Hygge/Features/Components/EventRow.swift` (add invite affordance)

**Interfaces:**
- `InviteCard(title:date:time:location:)` — a warm SwiftUI card (linen, Spectral title, mono date) rendered to `UIImage` via `ImageRenderer` for sharing.
- `ShareLink` on an "Invite a neighbor" button in `EventRow`, sharing the rendered image + a plain-text line: `"Come to \(title) with me — \(prettyDate) at \(location). (via Hygge)"`. No deep link/app graph; just the OS share sheet.

- [ ] **Step 1: Implement** card + `ShareLink`.
- [ ] **Step 2: Verify (running app)** — tap "Invite a neighbor" on an event → iOS share sheet opens with the card image + text. `screenshot`.
- [ ] **Step 3: Commit** — `git commit -am "feat: bring-a-neighbor invite share"`

---

## Task 9: One opt-in event reminder (`Reminders.swift`)

**Files:**
- Create: `Hygge/Backend/Reminders.swift`
- Modify: `Hygge/Features/Components/EventRow.swift` (a "Remind me" toggle)

**Interfaces:**
- `enum Reminders { static func requestAuth() async -> Bool; static func schedule(eventId: String, title: String, date: String, startTime: String?) async; static func cancel(eventId: String) }`
- Parse `startTime` display strings ("5 PM", "10 AM", "3 PM") + `event_date` (YYYY-MM-DD, local) into a fire `Date` **45 minutes before** start; if unparseable or in the past, no-op. Notification id = `"event-\(eventId)"`. Body: `"\(title) starts soon in St. Joe."`
- **Only reminder in the app.** No other local/push notifications anywhere (on-brand).

- [ ] **Step 1: Implement** `Reminders` + a "Remind me" toggle on `EventRow` that requests auth on first use and schedules/cancels.
- [ ] **Step 2: Verify (running app)** — toggle "Remind me" → permission prompt → toggle persists; confirm a pending notification via `snapshot_ui`/logs (or schedule 1 min out temporarily to observe delivery). `screenshot`.
- [ ] **Step 3: Commit** — `git commit -am "feat: opt-in event reminder (the app's only notification)"`

---

## Self-Review

- **Spec coverage:** Add forms (T1–4) ✓ · onboarding/interests (T5–7) ✓ · bring-a-neighbor (T8) ✓ · recurring events (folded into T3/T4 as weekly multi-insert) ✓ · one reminder (T9) ✓. Excluded features intentionally absent ✓.
- **Type consistency:** `Storage`/`Moderation`/`Interests`/`Reminders` are constructed where used; `AddModel.submit` consumes `CommunityAPI` + `Storage` + `Moderation`; reuses existing `NewEventInput`/`NewTrailInput`/`ClubInput`/`PostKind`/`ClubStatus` unchanged.
- **No fake data / on-brand:** all counts real; only one notification; suggestions are filters, not scores.
- **Verification adapted:** no test runner → compile (`build_sim`) + run/observe (`build_run_sim`, `screenshot`, `snapshot_ui`) + DB confirmation via Supabase MCP for inserts.
