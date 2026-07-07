# Community-Profile Onboarding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn first-run onboarding into a name → interests (photo cards) → avatar wizard that persists to Supabase, keeping the coral Map intro as the finale.

**Architecture:** Extend `OnboardingView` into a 5-step machine (`hello → name → interests → avatar → map`). New backend: a `town_profiles` table + `avatars` bucket, a `ProfileAPI` (get/upsert) and `Storage.uploadAvatar`, mirroring the hand-rolled PostgREST patterns in `CommunityAPI`. Interests stay in `UserDefaults` (synchronous matching) and are additionally persisted to Supabase (durable/cross-device), hydrated on launch.

**Tech Stack:** SwiftUI (iOS 26.5), Mapbox (unchanged), hand-rolled Supabase over URLSession, PhotosUI (`PhotosPicker`), XcodeBuildMCP for build+screenshot verification.

## Global Constraints

- iOS deployment target 26.5, Swift 5. Xcode project `Hygge.xcodeproj`, scheme `Hygge`, bundle id `Jesse.Hygge`.
- **No XCTest target.** "Verified" = **builds clean (0 warnings)** + **confirmed in the simulator via screenshots**. Every task's "test" step is a build + a screenshot, never a unit test.
- **Prefer XcodeBuildMCP** (`build_sim`, `build_run_sim`, `screenshot`) over raw `xcodebuild`/`simctl`.
- Only SPM dep is `mapbox-maps-ios`. Do **not** add dependencies. `PhotosUI` is a system framework (no SPM).
- Design tokens only — `Hue.*`, `Font.*`, `Radius.*`, `HyggeMetrics`. No raw hex/spacing a token covers. Coral (`Hue.accent`) is reserved for live/primary/tappable.
- Voice: warm, calm, neighborly, hyper-local. Real data only. No badges/streaks/gamification.
- Full **Reduce Motion** path on every animated screen (mirror `MapIntroView.runIntro`).
- Supabase project id: `lxdgwhvqjqmqliobwjpi`. Same project as the wellness app — **do not touch `profiles`, `food_logs`, `workouts`.**
- New files must be added to the `Hygge` file-system-synchronized group (they are, since the group syncs the `Hygge/` folder) — no manual `project.pbxproj` edits needed for `.swift` files under `Hygge/`.
- After any `.impeccable/` hazard: `find Hygge -type d -name .impeccable -exec rm -rf {} +` before building.

---

### Task 1: Supabase — `town_profiles` table + `avatars` bucket

**Files:**
- Apply via Supabase MCP `apply_migration` (name: `town_profiles_and_avatars`). No repo file.

**Interfaces:**
- Produces: table `public.town_profiles(user_id pk, display_name, avatar_url, interests text[], onboarded_at, created_at, updated_at)` with own-row RLS; public bucket `avatars` with folder-scoped insert/update RLS. Consumed by Task 2.

- [ ] **Step 1: Apply the migration**

```sql
create table if not exists public.town_profiles (
  user_id      uuid primary key default auth.uid()
               references auth.users(id) on delete cascade,
  display_name text,
  avatar_url   text,
  interests    text[] not null default '{}',
  onboarded_at timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
alter table public.town_profiles enable row level security;

create policy "town_profiles_select_own" on public.town_profiles
  for select using (auth.uid() = user_id);
create policy "town_profiles_insert_own" on public.town_profiles
  for insert with check (auth.uid() = user_id);
create policy "town_profiles_update_own" on public.town_profiles
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

insert into storage.buckets (id, name, public)
  values ('avatars','avatars', true) on conflict (id) do nothing;

create policy "avatars_insert_own" on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "avatars_update_own" on storage.objects for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "avatars_read" on storage.objects for select
  using (bucket_id = 'avatars');
```

- [ ] **Step 2: Verify**

Run (MCP `execute_sql`): `select count(*) from public.town_profiles;` → returns `0`.
Run: `select id, public from storage.buckets where id='avatars';` → `avatars, true`.
Run `get_advisors` (type `security`) → no new **errors** introduced by these objects (RLS is enabled).

- [ ] **Step 3: Commit** — no repo change; record in `MAP_BUILD_LOG.md` under a new "Onboarding" heading that the migration was applied (done in Task 11).

---

### Task 2: Backend — `TownProfile`, `ProfileAPI`, `Storage.uploadAvatar`

**Files:**
- Modify: `Hygge/Backend/Models.swift` (append `TownProfile`)
- Create: `Hygge/Backend/ProfileAPI.swift`
- Modify: `Hygge/Backend/Storage.swift` (add `uploadAvatar`)

**Interfaces:**
- Consumes: Task 1's table/bucket; existing `SupabaseHTTP.rest`, `AuthStore` (`userId`, `validAccessToken`), `SupabaseConfig`.
- Produces:
  - `struct TownProfile: Decodable { let userId: String; let displayName: String?; let avatarUrl: String?; let interests: [String]; let onboardedAt: String? }`
  - `struct ProfileAPI { let auth: AuthStore; func getMyProfile() async throws -> TownProfile?; func upsert(displayName: String?, avatarUrl: String?, interests: [String], onboarded: Bool) async throws }`
  - `func Storage.uploadAvatar(_ data: Data, userId: String, contentType: String = "image/jpeg") async -> String?`

- [ ] **Step 1: Append `TownProfile` to `Models.swift`**

```swift
// MARK: - Town profile (this community app's per-user identity; separate from the
// wellness app's `profiles` table). Decoded with convertFromSnakeCase.
struct TownProfile: Decodable {
    let userId: String
    let displayName: String?
    let avatarUrl: String?
    let interests: [String]
    let onboardedAt: String?
}
```

- [ ] **Step 2: Create `ProfileAPI.swift`**

```swift
//
//  ProfileAPI.swift
//  Hygge — the community-profile query layer (name · avatar · interests),
//  hand-rolled over PostgREST like CommunityAPI. Writes to `town_profiles`
//  (own-row RLS). Separate from the wellness app's `profiles` table.
//

import Foundation

struct ProfileAPI {
    let auth: AuthStore

    private func token() async throws -> String { try await auth.validAccessToken() }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        return try dec.decode(T.self, from: data)
    }

    /// The signed-in user's row, or nil if they have none yet. RLS scopes the
    /// select to the caller, so no explicit user_id filter is needed.
    func getMyProfile() async throws -> TownProfile? {
        let t = try await token()
        let (data, _) = try await SupabaseHTTP.rest("town_profiles",
            query: "select=user_id,display_name,avatar_url,interests,onboarded_at&limit=1",
            accessToken: t)
        let rows: [TownProfile] = try decode(data)
        return rows.first
    }

    /// Upsert the caller's profile. `onboarded` stamps `onboarded_at` so a
    /// reinstall/new device can skip onboarding. Idempotent (PK = user_id).
    func upsert(displayName: String?, avatarUrl: String?,
                interests: [String], onboarded: Bool) async throws {
        let t = try await token()
        guard let uid = auth.userId else { throw SupabaseError(message: "Not signed in", status: 401) }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let now = iso.string(from: Date())

        var b: [String: Any] = [
            "user_id": uid,
            "interests": interests,
            "updated_at": now,
        ]
        b["display_name"] = displayName ?? NSNull()
        b["avatar_url"]   = avatarUrl ?? NSNull()
        if onboarded { b["onboarded_at"] = now }

        let body = try JSONSerialization.data(withJSONObject: b)
        _ = try await SupabaseHTTP.rest("town_profiles", method: "POST",
            query: "on_conflict=user_id", accessToken: t, body: body,
            prefer: "resolution=merge-duplicates,return=minimal")
    }
}
```

- [ ] **Step 3: Add `uploadAvatar` to `Storage.swift`** (inside `struct Storage`, after `uploadEventImage`)

```swift
    /// Upload an avatar to the public `avatars` bucket at `{userId}/avatar-{ts}.jpg`
    /// (folder-scoped RLS). Returns the public URL, nil on any failure so the
    /// caller finishes onboarding without an avatar rather than breaking.
    func uploadAvatar(_ data: Data, userId: String, contentType: String = "image/jpeg") async -> String? {
        guard let token = try? await auth.validAccessToken() else { return nil }
        let ts = Int(Date().timeIntervalSince1970 * 1000)
        let path = "\(userId)/avatar-\(ts).jpg"

        var req = URLRequest(url: SupabaseConfig.storageURL.appendingPathComponent("object/avatars/\(path)"))
        req.httpMethod = "POST"
        req.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(contentType, forHTTPHeaderField: "Content-Type")

        guard let (_, resp) = try? await URLSession.shared.upload(for: req, from: data),
              let code = (resp as? HTTPURLResponse)?.statusCode, (200..<300).contains(code) else {
            return nil
        }
        return SupabaseConfig.url
            .appendingPathComponent("storage/v1/object/public/avatars/\(path)")
            .absoluteString
    }
```

- [ ] **Step 4: Build clean**

Run: XcodeBuildMCP `build_sim` (scheme `Hygge`, iPhone 17 simulator). Expected: **BUILD SUCCEEDED, 0 warnings**.

- [ ] **Step 5: Commit**

```bash
git add Hygge/Backend/Models.swift Hygge/Backend/ProfileAPI.swift Hygge/Backend/Storage.swift
git commit -m "feat(onboarding): TownProfile model, ProfileAPI, avatar upload"
```

---

### Task 3: Interests taxonomy — 18 categories, sections, name cache

**Files:**
- Modify: `Hygge/Backend/Interests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `Interest` gains `let section: String`.
  - `Interests.all` = 18 interests (ids/labels/keywords/sections per spec §2).
  - `Interests.sections: [(title: String, items: [Interest])]` in display order.
  - `Interests.displayName` get/set (UserDefaults key `hygge.displayName`).
  - `Interest.imageName -> String` = `"interest-\(id)"`.
  - Unchanged: `get/set`, `isOnboarded/setOnboarded`, `matches`.

- [ ] **Step 1: Replace the body of `Interests.swift`**

```swift
//
//  Interests.swift
//  Hygge — on-device interests + name for onboarding and "Suggested for you".
//  Interests/name are mirrored to Supabase (town_profiles); UserDefaults stays
//  the synchronous source for keyword matching. Matching is plain keyword-contains.
//

import Foundation

struct Interest: Identifiable, Hashable {
    let id: String
    let label: String
    let section: String
    let keywords: [String]
    /// Asset name for the onboarding photo card (seed art now; real St. Joe
    /// photo drops in under the same name later — see InterestCard.resolve).
    var imageName: String { "interest-\(id)" }
}

enum Interests {
    static let all: [Interest] = [
        // Outdoors & Nature
        Interest(id: "trails_hiking", label: "Trails & Hiking", section: "Outdoors & Nature",
                 keywords: ["hike", "hiking", "trail", "walk", "lake wobegon trail", "woodland", "nature"]),
        Interest(id: "lakes_swimming", label: "Lakes & Swimming", section: "Outdoors & Nature",
                 keywords: ["lake", "swim", "swimming", "beach", "paddle", "kayak", "canoe", "dock"]),
        Interest(id: "parks_gardens", label: "Parks & Gardens", section: "Outdoors & Nature",
                 keywords: ["park", "garden", "millstream", "picnic", "playground", "green space"]),
        Interest(id: "biking", label: "Biking", section: "Outdoors & Nature",
                 keywords: ["bike", "biking", "cycle", "cycling", "ride", "gravel"]),
        // Food & Drink
        Interest(id: "coffee", label: "Coffee Shops", section: "Food & Drink",
                 keywords: ["coffee", "café", "cafe", "espresso", "local blend", "bad habit", "latte"]),
        Interest(id: "dining", label: "Restaurants & Dining", section: "Food & Drink",
                 keywords: ["restaurant", "dinner", "lunch", "dining", "krewe", "brunch", "supper", "food", "eat"]),
        Interest(id: "farmers_market", label: "Farmers Market", section: "Food & Drink",
                 keywords: ["farmers market", "market", "produce", "vendor", "farm", "stand"]),
        Interest(id: "breweries", label: "Breweries & Taprooms", section: "Food & Drink",
                 keywords: ["brew", "brewery", "taproom", "beer", "cider", "tap", "pint"]),
        // Community & Culture
        Interest(id: "live_music", label: "Live Music", section: "Community & Culture",
                 keywords: ["music", "concert", "band", "live", "open mic", "choir", "jam", "sing"]),
        Interest(id: "art_exhibits", label: "Art & Exhibits", section: "Community & Culture",
                 keywords: ["art", "exhibit", "gallery", "paint", "craft", "pottery", "maker", "studio"]),
        Interest(id: "faith", label: "Faith & Fellowship", section: "Community & Culture",
                 keywords: ["church", "faith", "mass", "parish", "worship", "prayer", "abbey", "st. john", "fellowship"]),
        Interest(id: "festivals", label: "Festivals & Fairs", section: "Community & Culture",
                 keywords: ["festival", "fair", "fest", "parade", "joetown", "celebration", "block party"]),
        Interest(id: "books", label: "Library & Books", section: "Community & Culture",
                 keywords: ["book", "read", "library", "story", "author", "lecture", "class", "learn", "study"]),
        // Active & Wellness
        Interest(id: "fitness_yoga", label: "Fitness & Yoga", section: "Active & Wellness",
                 keywords: ["yoga", "fitness", "gym", "workout", "pilates", "stretch"]),
        Interest(id: "sports_leagues", label: "Sports & Leagues", section: "Active & Wellness",
                 keywords: ["sport", "league", "softball", "soccer", "pickleball", "hockey", "ball", "team", "game"]),
        Interest(id: "health_wellness", label: "Health & Wellness", section: "Active & Wellness",
                 keywords: ["health", "wellness", "clinic", "screening", "meditation", "care", "mental"]),
        // Families & Social
        Interest(id: "families_kids", label: "Families & Kids", section: "Families & Social",
                 keywords: ["kid", "family", "child", "parent", "youth", "story time", "playgroup", "mom", "dad"]),
        Interest(id: "volunteering", label: "Volunteering & Service", section: "Families & Social",
                 keywords: ["volunteer", "service", "donate", "charity", "food shelf", "drive", "give", "help"]),
    ]

    /// Sections in display order, each with its interests (grouping preserved).
    static let sections: [(title: String, items: [Interest])] = {
        var order: [String] = []
        var groups: [String: [Interest]] = [:]
        for i in all {
            if groups[i.section] == nil { order.append(i.section) }
            groups[i.section, default: []].append(i)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }()

    private static let interestsKey = "hygge.interests"
    private static let onboardedKey = "hygge.onboarded"
    private static let nameKey      = "hygge.displayName"

    static func get() -> [String] { UserDefaults.standard.stringArray(forKey: interestsKey) ?? [] }
    static func set(_ ids: [String]) { UserDefaults.standard.set(ids, forKey: interestsKey) }

    static var displayName: String? {
        get { UserDefaults.standard.string(forKey: nameKey) }
        set { UserDefaults.standard.set(newValue, forKey: nameKey) }
    }

    static func isOnboarded() -> Bool { UserDefaults.standard.string(forKey: onboardedKey) == "1" }
    static func setOnboarded() { UserDefaults.standard.set("1", forKey: onboardedKey) }

    /// Does `haystack` match any chosen interest? Trails always count toward the
    /// two outdoors buckets so a trail row always surfaces for outdoorsy folks.
    static func matches(_ haystack: String, _ ids: [String], isTrail: Bool = false) -> Bool {
        if ids.isEmpty { return false }
        if isTrail && (ids.contains("trails_hiking") || ids.contains("parks_gardens")) { return true }
        let text = haystack.lowercased()
        for id in ids {
            if let interest = all.first(where: { $0.id == id }),
               interest.keywords.contains(where: { text.contains($0) }) {
                return true
            }
        }
        return false
    }
}
```

- [ ] **Step 2: Build clean**

Run: XcodeBuildMCP `build_sim`. Expected: **BUILD SUCCEEDED, 0 warnings.** (The old `chip(_:)` in `OnboardingView` still compiles — `Interest` still has `id`/`label`; it's replaced in Task 9.)

- [ ] **Step 3: Commit**

```bash
git add Hygge/Backend/Interests.swift
git commit -m "feat(onboarding): expand interest taxonomy to 18 St. Joe categories + sections + name cache"
```

---

### Task 4: Interest card photos + resolver

**Files:**
- Create: `Hygge/Assets.xcassets/Interests/interest-<id>.imageset/` for all 18 ids (each with `Contents.json` + one `@2x`/`@3x` or single universal JPEG).
- Create: `Hygge/Features/Onboarding/InterestImage.swift`

**Interfaces:**
- Produces: `enum InterestImage { static func image(for id: String) -> Image }` — returns the resolved SwiftUI `Image` for a card (real-photo override if present, else seed asset, else a tinted fallback so a missing asset never crashes the grid).

- [ ] **Step 1: Generate 18 seed photos**

Use the image-generation tool. One consistent art-direction template per card:

> "Editorial documentary photograph, [SUBJECT], small Minnesota town in [season], warm natural golden-hour light, muted earthy palette, shallow depth of field, candid and calm, no text, no logos, no watermark, 4:3." 

Subjects by id: `trails_hiking`=wooded dirt trail through birches; `lakes_swimming`=calm lake with a wooden dock; `parks_gardens`=green town park with a footbridge over a stream; `biking`=gravel bike path; `coffee`=cozy café counter with latte; `dining`=warm restaurant table setting; `farmers_market`=outdoor produce market stall; `breweries`=taproom pours; `live_music`=small outdoor band/open-mic; `art_exhibits`=local art gallery wall; `faith`=stone church/abbey exterior at dusk; `festivals`=small-town street festival string lights; `books`=cozy public library reading corner; `fitness_yoga`=yoga mats in a bright studio; `sports_leagues`=community softball field; `health_wellness`=calm wellness/meditation setting; `families_kids`=family at a playground; `volunteering`=neighbors packing a food-shelf drive.

Post-process: center-crop to 4:3, downscale to ≤1200px wide, JPEG ~80%. Reject any that read as "slop" (uncanny faces, garbled text) — regenerate. Faces should be incidental/soft, never the subject (avoids uncanny AI faces).

- [ ] **Step 2: Add each as an imageset**

For each id, create `Hygge/Assets.xcassets/Interests/interest-<id>.imageset/Contents.json`:

```json
{
  "images" : [ { "filename" : "interest-<id>.jpg", "idiom" : "universal" } ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

Place the JPEG next to it. (The `Interests` folder can hold its own `Contents.json` group marker — copy the pattern from an existing asset folder if present.)

- [ ] **Step 3: Create `InterestImage.swift`**

```swift
//
//  InterestImage.swift
//  Hygge — resolves an interest card's photo. Real local photo wins if present;
//  otherwise the bundled seed art; otherwise a calm tinted fallback so a missing
//  asset never breaks the grid. Drop a real St. Joe photo named the same and it
//  takes over with zero code changes (hybrid imagery — see the design spec).
//

import SwiftUI

enum InterestImage {
    static func image(for id: String) -> Image? {
        let name = "interest-\(id)"
        // A real-photo override folder ("LocalPhotos/interest-<id>") wins if added.
        if UIImage(named: "LocalPhotos/\(name)") != nil { return Image("LocalPhotos/\(name)") }
        if UIImage(named: name) != nil { return Image(name) }
        return nil
    }
}
```

- [ ] **Step 4: Build clean + verify assets load**

Run: `find Hygge -type d -name .impeccable -exec rm -rf {} +` then XcodeBuildMCP `build_sim`. Expected: **BUILD SUCCEEDED, 0 warnings**, no "unassigned image" asset warnings.

- [ ] **Step 5: Commit**

```bash
git add Hygge/Assets.xcassets/Interests Hygge/Features/Onboarding/InterestImage.swift
git commit -m "feat(onboarding): art-directed interest card photos + hybrid resolver"
```

---

### Task 5: Onboarding chrome — progress bar + back

**Files:**
- Create: `Hygge/Features/Onboarding/OnboardingChrome.swift`

**Interfaces:**
- Produces:
  - `struct OnboardingProgressBar: View { let index: Int; let total: Int }` (0-based active segment).
  - `struct OnboardingBackButton: View { let action: () -> Void }`.
  - `struct OnboardingTopBar: View { let index: Int; let total: Int; let onBack: () -> Void }` — back chevron + progress bar in a row (matches the reference).

- [ ] **Step 1: Create `OnboardingChrome.swift`**

```swift
//
//  OnboardingChrome.swift
//  Hygge — shared top chrome for the onboarding wizard: a circular back button
//  and a slim segmented progress bar. Present only on the data-collection steps
//  (name · interests · avatar); Welcome and the Map finale are full-bleed.
//

import SwiftUI

struct OnboardingBackButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: { Haptics.selection(); action() }) {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Hue.ink)
                .frame(width: 44, height: 44)
                .background(Hue.paper, in: Circle())
                .overlay(Circle().stroke(Hue.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
    }
}

struct OnboardingProgressBar: View {
    let index: Int
    let total: Int
    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = 6
            let w = (geo.size.width - gap * CGFloat(total - 1)) / CGFloat(total)
            HStack(spacing: gap) {
                ForEach(0..<total, id: \.self) { i in
                    Capsule()
                        .fill(i <= index ? Hue.ink : Hue.hairline)
                        .frame(width: w, height: 5)
                }
            }
            .animation(.easeInOut(duration: 0.35), value: index)
        }
        .frame(height: 5)
        .accessibilityElement()
        .accessibilityLabel("Step \(index + 1) of \(total)")
    }
}

struct OnboardingTopBar: View {
    let index: Int
    let total: Int
    let onBack: () -> Void
    var body: some View {
        HStack(spacing: 14) {
            OnboardingBackButton(action: onBack)
            OnboardingProgressBar(index: index, total: total)
        }
    }
}
```

- [ ] **Step 2: Build clean.** Run XcodeBuildMCP `build_sim`. Expected: **BUILD SUCCEEDED, 0 warnings**.

- [ ] **Step 3: Commit**

```bash
git add Hygge/Features/Onboarding/OnboardingChrome.swift
git commit -m "feat(onboarding): progress bar + back chrome"
```

---

### Task 6: Name step

**Files:**
- Create: `Hygge/Features/Onboarding/NameStepView.swift`

**Interfaces:**
- Consumes: `OnboardingTopBar`.
- Produces: `struct NameStepView: View { @Binding var name: String; let onBack: () -> Void; let onContinue: () -> Void }`. Trims whitespace; continue disabled when empty; caps at 24 chars.

- [ ] **Step 1: Create `NameStepView.swift`**

```swift
//
//  NameStepView.swift
//  Hygge — "What should we call you?" One warm centered field. First data step.
//

import SwiftUI

struct NameStepView: View {
    @Binding var name: String
    let onBack: () -> Void
    let onContinue: () -> Void

    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canContinue: Bool { !trimmed.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OnboardingTopBar(index: 0, total: 3, onBack: onBack)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 8) {
                Text("Let's get you set up")
                    .font(.display(32))
                    .foregroundStyle(Hue.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("What should we call you?")
                    .font(.sans(16))
                    .foregroundStyle(Hue.ink2)
            }
            .padding(.top, 40)

            Spacer()

            TextField("", text: $name, prompt: Text("Your name").foregroundColor(Hue.ink3))
                .font(.display(34))
                .foregroundStyle(Hue.ink)
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .focused($focused)
                .onChange(of: name) { _, v in if v.count > 24 { name = String(v.prefix(24)) } }
                .onSubmit { if canContinue { onContinue() } }
                .padding(.bottom, 10)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Hue.hairline).frame(height: 1)
                }
                .padding(.horizontal, 8)

            Spacer()
            Spacer()

            ContinueButton(title: "Continue", enabled: canContinue) {
                Haptics.selection(); onContinue()
            }
        }
        .padding(24)
        .background(Hue.canvas.ignoresSafeArea())
        .onAppear {
            // Auto-focus the field (slight delay lets the transition settle).
            DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0 : 0.35)) { focused = true }
        }
    }
}

/// The shared coral pill CTA used across the wizard (enable state springs in).
struct ContinueButton: View {
    let title: String
    var enabled: Bool = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.sansSemibold(17))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(enabled ? Hue.accent : Hue.accent.opacity(0.4),
                            in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: enabled)
    }
}
```

- [ ] **Step 2: Build + screenshot (empty + typed)**

Add a temporary DEBUG preview or use the Task 9 launch arg once wired. For now: Run XcodeBuildMCP `build_sim`. Expected: **BUILD SUCCEEDED, 0 warnings**. (Visual verification happens in Task 9 when the step is reachable via `-onboarding-step name`.)

- [ ] **Step 3: Commit**

```bash
git add Hygge/Features/Onboarding/NameStepView.swift
git commit -m "feat(onboarding): name step"
```

---

### Task 7: Interest photo-card grid

**Files:**
- Create: `Hygge/Features/Onboarding/InterestCard.swift`
- Create: `Hygge/Features/Onboarding/InterestPickerView.swift`

**Interfaces:**
- Consumes: `Interests.sections`, `InterestImage.image(for:)`, `OnboardingTopBar`, `ContinueButton`.
- Produces:
  - `struct InterestCard: View { let interest: Interest; let selected: Bool; let onTap: () -> Void }`
  - `struct InterestPickerView: View { @Binding var selected: Set<String>; let name: String; let onBack: () -> Void; let onContinue: () -> Void }`

- [ ] **Step 1: Create `InterestCard.swift`**

```swift
//
//  InterestCard.swift
//  Hygge — a photo interest card (reference-faithful): image, bottom scrim +
//  label, and a top-right selection circle. Selecting rings it coral, checks it,
//  and zooms the photo a touch. Full Reduce-Motion path.
//

import SwiftUI

struct InterestCard: View {
    let interest: Interest
    let selected: Bool
    let onTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pressed = false

    var body: some View {
        Button(action: { Haptics.selection(); onTap() }) {
            ZStack(alignment: .bottomLeading) {
                photo
                scrim
                label
                checkCircle
            }
            .frame(height: 130)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .stroke(selected ? Hue.accent : Hue.hairline, lineWidth: selected ? 3 : 1)
            )
            .scaleEffect(pressed ? 0.97 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: pressed)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: selected)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in pressed = true }
            .onEnded { _ in pressed = false })
        .accessibilityElement()
        .accessibilityLabel(interest.label)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder private var photo: some View {
        if let img = InterestImage.image(for: interest.id) {
            img.resizable().scaledToFill()
                .scaleEffect(selected && !reduceMotion ? 1.05 : 1)
        } else {
            // Calm tinted fallback (no gradient slop) if a seed asset is missing.
            Rectangle().fill(Hue.paper200)
                .overlay(Image(systemName: "photo")
                    .font(.system(size: 22)).foregroundStyle(Hue.ink3))
        }
    }

    private var scrim: some View {
        LinearGradient(colors: [.clear, .black.opacity(0.55)],
                       startPoint: .center, endPoint: .bottom)
    }

    private var label: some View {
        Text(interest.label)
            .font(.sansSemibold(15))
            .foregroundStyle(.white)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
            .padding(12)
    }

    private var checkCircle: some View {
        ZStack {
            Circle()
                .fill(selected ? Hue.accent : .black.opacity(0.25))
                .overlay(Circle().stroke(.white.opacity(selected ? 0 : 0.9), lineWidth: 1.5))
                .frame(width: 26, height: 26)
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(10)
    }
}
```

- [ ] **Step 2: Create `InterestPickerView.swift`**

```swift
//
//  InterestPickerView.swift
//  Hygge — "What are you into around town?" The reference's photo-card grid,
//  grouped into sections. Gentle: pick a few (min 1). Sticky coral CTA with a
//  live count. Cards fade+rise in on first appear (capped stagger).
//

import SwiftUI

struct InterestPickerView: View {
    @Binding var selected: Set<String>
    let name: String
    let onBack: () -> Void
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    private var heading: String {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? "What are you into?" : "What are you into, \(n)?"
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                OnboardingTopBar(index: 1, total: 3, onBack: onBack).padding(.top, 8)
                VStack(alignment: .leading, spacing: 6) {
                    Text(heading)
                        .font(.display(28))
                        .foregroundStyle(Hue.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Pick a few — we'll quietly surface what fits around St. Joe.")
                        .font(.sans(15))
                        .foregroundStyle(Hue.ink2)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(Array(Interests.sections.enumerated()), id: \.offset) { _, section in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(section.title)
                                .font(.sansSemibold(13))
                                .foregroundStyle(Hue.ink3)
                                .textCase(.uppercase)
                                .tracking(0.5)
                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(section.items) { interest in
                                    InterestCard(interest: interest,
                                                 selected: selected.contains(interest.id)) {
                                        toggle(interest.id)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 4)
                .padding(.bottom, 24)
                .opacity(appeared || reduceMotion ? 1 : 0)
                .offset(y: appeared || reduceMotion ? 0 : 16)
            }

            footer
        }
        .background(Hue.canvas.ignoresSafeArea())
        .onAppear {
            guard !appeared else { return }
            withAnimation(.easeOut(duration: 0.5)) { appeared = true }
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Hue.hairline).frame(height: 1)
            ContinueButton(title: selected.isEmpty ? "Pick a few to continue" : "Continue · \(selected.count)",
                           enabled: !selected.isEmpty) {
                Haptics.selection(); onContinue()
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .background(Hue.canvas)
    }

    private func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }
}
```

- [ ] **Step 3: Build clean.** Run XcodeBuildMCP `build_sim`. Expected: **BUILD SUCCEEDED, 0 warnings**. (Visual verification in Task 9.)

- [ ] **Step 4: Commit**

```bash
git add Hygge/Features/Onboarding/InterestCard.swift Hygge/Features/Onboarding/InterestPickerView.swift
git commit -m "feat(onboarding): photo interest-card grid"
```

---

### Task 8: Avatar step

**Files:**
- Create: `Hygge/Features/Onboarding/AvatarStepView.swift`

**Interfaces:**
- Consumes: `OnboardingTopBar`, `ContinueButton`, `PhotosUI`.
- Produces: `struct AvatarStepView: View { @Binding var image: UIImage?; let name: String; let onBack: () -> Void; let onContinue: () -> Void; let onSkip: () -> Void }`.

- [ ] **Step 1: Create `AvatarStepView.swift`**

```swift
//
//  AvatarStepView.swift
//  Hygge — "Add a profile picture." Tap the circular well to pick from the
//  library; Skip is always allowed. Upload happens after this step (Task 9).
//

import SwiftUI
import PhotosUI

struct AvatarStepView: View {
    @Binding var image: UIImage?
    let name: String
    let onBack: () -> Void
    let onContinue: () -> Void
    let onSkip: () -> Void

    @State private var pick: PhotosPickerItem?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var firstName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ").first.map(String.init) ?? ""
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingTopBar(index: 2, total: 3, onBack: onBack).padding(.top, 8)

            VStack(spacing: 8) {
                Text("Add a profile picture")
                    .font(.display(30))
                    .foregroundStyle(Hue.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(firstName.isEmpty ? "So neighbors know it's you." : "So neighbors know it's you, \(firstName).")
                    .font(.sans(16))
                    .foregroundStyle(Hue.ink2)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 36)

            Spacer()

            PhotosPicker(selection: $pick, matching: .images, photoLibrary: .shared()) {
                well
            }
            .buttonStyle(.plain)

            Spacer()
            Spacer()

            ContinueButton(title: image == nil ? "Add later" : "Continue") {
                Haptics.selection(); onContinue()
            }
            Button(action: { Haptics.selection(); onSkip() }) {
                Text("Skip for now").font(.sans(14)).foregroundStyle(Hue.ink3)
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .opacity(image == nil ? 1 : 0)   // once a photo's chosen, Continue is the path
        }
        .padding(24)
        .background(Hue.canvas.ignoresSafeArea())
        .onChange(of: pick) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let ui = UIImage(data: data) {
                    await MainActor.run {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { image = ui }
                    }
                }
            }
        }
    }

    private var well: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(width: 176, height: 176)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(.white, lineWidth: 4))
                    .shadow(color: .black.opacity(0.14), radius: 16, y: 6)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Circle()
                    .fill(Hue.paper)
                    .frame(width: 176, height: 176)
                    .overlay(Circle().stroke(Hue.hairline, style: StrokeStyle(lineWidth: 2, dash: [7, 6])))
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 26)).foregroundStyle(Hue.accent)
                            Text("Add photo").font(.sansMedium(14)).foregroundStyle(Hue.ink3)
                        }
                    )
            }
        }
        .accessibilityLabel(image == nil ? "Add a profile picture" : "Change profile picture")
    }
}
```

- [ ] **Step 2: Build clean.** Run XcodeBuildMCP `build_sim`. Expected: **BUILD SUCCEEDED, 0 warnings**.

- [ ] **Step 3: Commit**

```bash
git add Hygge/Features/Onboarding/AvatarStepView.swift
git commit -m "feat(onboarding): avatar step with PhotosPicker"
```

---

### Task 9: Wire the step machine + persist + DEBUG args

**Files:**
- Modify: `Hygge/Features/Onboarding/OnboardingView.swift` (full rewrite of the step machine)

**Interfaces:**
- Consumes: `NameStepView`, `InterestPickerView`, `AvatarStepView`, `MapIntroView`, `ProfileAPI`, `Storage`, `AuthStore.shared`, `Interests`.
- Produces: unchanged `OnboardingView(onDone:)`. Honors DEBUG `-onboarding-step name|interests|avatar` and `-onboarding-filled`.

- [ ] **Step 1: Rewrite `OnboardingView.swift`**

```swift
//
//  OnboardingView.swift
//  Hygge — first-run wizard: Welcome → Name → Interests → Avatar → Map finale.
//  Collects name + interests + avatar, mirrors them to Supabase (best-effort,
//  non-blocking) and to UserDefaults (synchronous matching). Mirrors the Expo
//  onboarding, extended for community-profile capture.
//

import SwiftUI

struct OnboardingView: View {
    var onDone: () -> Void

    private enum Step { case hello, name, interests, avatar, map }
    @State private var step: Step = OnboardingView.initialStep()

    @State private var name: String = OnboardingView.initialName()
    @State private var selected: Set<String> = OnboardingView.initialInterests()
    @State private var avatar: UIImage?

    private let profiles = ProfileAPI(auth: .shared)
    private let storage = Storage(auth: .shared)

    var body: some View {
        ZStack {
            Hue.canvas.ignoresSafeArea()
            switch step {
            case .hello:     hello.transition(.opacity)
            case .name:      NameStepView(name: $name, onBack: { go(.hello) }, onContinue: { go(.interests) })
                                 .transition(stepTransition)
            case .interests: InterestPickerView(selected: $selected, name: name,
                                                 onBack: { go(.name) }, onContinue: { go(.avatar) })
                                 .transition(stepTransition)
            case .avatar:    AvatarStepView(image: $avatar, name: name,
                                            onBack: { go(.interests) },
                                            onContinue: { finishData(); go(.map) },
                                            onSkip: { finishData(); go(.map) })
                                 .transition(stepTransition)
            case .map:       MapIntroView { finish() }.transition(.opacity)
            }
        }
    }

    private var stepTransition: AnyTransition {
        .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .opacity)
    }

    private func go(_ next: Step) {
        withAnimation(.easeInOut(duration: 0.4)) { step = next }
    }

    private var hello: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            Text("Welcome to Hygge")
                .font(.display(38)).foregroundStyle(Hue.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("One calm place for everything happening in St. Joseph — a daily look at town, a shared calendar anyone can add to, and small nudges to get out and meet your neighbors.")
                .font(.sans(16)).foregroundStyle(Hue.ink2).lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(action: { go(.name) }) {
                Text("Get started")
                    .font(.sansSemibold(16)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(Hue.accent, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
            .buttonStyle(.plain)
            Button(action: { finishData(); finish() }) {
                Text("Skip for now").font(.sans(14)).foregroundStyle(Hue.ink3)
                    .frame(maxWidth: .infinity).padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
        .padding(24)
    }

    /// Commit locally at once (matching needs it synchronously), then best-effort
    /// mirror to Supabase — including the avatar upload. Never blocks the UI.
    private func finishData() {
        let ids = Array(selected)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        Interests.set(ids)
        Interests.displayName = trimmed.isEmpty ? nil : trimmed
        let img = avatar
        Task.detached {
            let uid = await AuthStore.shared.userId
            var avatarUrl: String?
            if let img, let data = img.jpegData(compressionQuality: 0.85), let uid {
                avatarUrl = await storage.uploadAvatar(data, userId: uid)
            }
            try? await profiles.upsert(displayName: trimmed.isEmpty ? nil : trimmed,
                                       avatarUrl: avatarUrl, interests: ids, onboarded: true)
        }
    }

    private func finish() {
        Interests.setOnboarded()
        onDone()
    }
}

// MARK: - DEBUG launch state (headless screenshot verification)
extension OnboardingView {
    static func initialStep() -> Step {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-onboarding-step"), i + 1 < args.count {
            switch args[i + 1] {
            case "name":      return .name
            case "interests": return .interests
            case "avatar":    return .avatar
            default:          break
            }
        }
        #endif
        return .hello
    }
    static func initialName() -> String {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-onboarding-filled") { return "Alex" }
        #endif
        return Interests.displayName ?? ""
    }
    static func initialInterests() -> Set<String> {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-onboarding-filled") {
            return ["trails_hiking", "coffee", "live_music", "farmers_market", "faith"]
        }
        #endif
        return Set(Interests.get())
    }
}
```

- [ ] **Step 2: Build clean.** `find Hygge -type d -name .impeccable -exec rm -rf {} +` then XcodeBuildMCP `build_sim`. Expected: **BUILD SUCCEEDED, 0 warnings**.

- [ ] **Step 3: Screenshot loop — every screen + state**

Boot the sim and screenshot each (DEBUG needs a signed-in session; if none, sign in once first, then relaunch with args):
```
xcrun simctl launch <udid> Jesse.Hygge -onboarding-step name
xcrun simctl launch <udid> Jesse.Hygge -onboarding-step name -onboarding-filled
xcrun simctl launch <udid> Jesse.Hygge -onboarding-step interests
xcrun simctl launch <udid> Jesse.Hygge -onboarding-step interests -onboarding-filled
xcrun simctl launch <udid> Jesse.Hygge -onboarding-step avatar -onboarding-filled
```
Screenshot each with XcodeBuildMCP `screenshot`. Verify: name field centered + underline; cards show photos with scrim + label + selection circle; selected cards ring coral with a check + count in the CTA; sections labelled; avatar well dashed then filled; back + progress bar present. Iterate on any layout/spacing/legibility issue until clean.

- [ ] **Step 4: Reduce-Motion pass** — enable in Settings > Accessibility (or `simctl ui <udid> ...`), relaunch `-onboarding-step interests -onboarding-filled`, confirm cards render in final state (no fade/zoom), CTA static, no crash.

- [ ] **Step 5: Commit**

```bash
git add Hygge/Features/Onboarding/OnboardingView.swift
git commit -m "feat(onboarding): wire name→interests→avatar→map wizard + Supabase persist + debug args"
```

---

### Task 10: Launch hydration from Supabase

**Files:**
- Modify: `Hygge/App/RootView.swift`

**Interfaces:**
- Consumes: `ProfileAPI`, `Interests`, `AuthStore`.
- Produces: on first authed appearance, hydrate local interests/name from `town_profiles` and, if `onboarded_at` is set remotely, skip onboarding (so a reinstall/new device doesn't re-onboard). Never blocks the UI; failures are silent.

- [ ] **Step 1: Add hydration to `RootView`**

Add to `RootView` (new `@State private var hydrated = false`) and attach `.task` to `gate`'s authed branch. Replace the `else if auth.isSignedIn { ... }` block's content with a wrapper that hydrates:

```swift
        } else if auth.isSignedIn {
            authedRoot
                .task(id: auth.userId) { await hydrateIfNeeded() }
        } else {
```

Add these members to `RootView`:

```swift
    @State private var hydrated = false

    @ViewBuilder private var authedRoot: some View {
        if needsOnboarding {
            OnboardingView { needsOnboarding = false }
        } else {
            MainTabsView()
        }
    }

    /// Pull the community profile once per session: mirror interests/name locally
    /// (so matching + greetings work offline) and honor a remote onboarded stamp.
    private func hydrateIfNeeded() async {
        guard !hydrated, auth.isSignedIn else { return }
        hydrated = true
        guard let profile = try? await ProfileAPI(auth: .shared).getMyProfile(),
              let profile else { return }
        if !profile.interests.isEmpty { Interests.set(profile.interests) }
        if let n = profile.displayName, !n.isEmpty { Interests.displayName = n }
        if profile.onboardedAt != nil, needsOnboarding {
            Interests.setOnboarded()
            needsOnboarding = false
        }
    }
```

(Replace the two-line `if needsOnboarding { … } else { … }` currently inline in `gate` with `authedRoot` as shown.)

- [ ] **Step 2: Build clean.** XcodeBuildMCP `build_sim`. Expected: **BUILD SUCCEEDED, 0 warnings**.

- [ ] **Step 3: Verify hydration** — complete onboarding once in the sim (writes `town_profiles`), confirm via MCP `execute_sql`: `select display_name, interests, onboarded_at, avatar_url from town_profiles;` shows the chosen name/interests/onboarded stamp (and avatar_url if a photo was picked). Delete the app, reinstall, sign in → lands on tabs (no re-onboarding); interests hydrated.

- [ ] **Step 4: Commit**

```bash
git add Hygge/App/RootView.swift
git commit -m "feat(onboarding): hydrate community profile on launch; honor remote onboarded stamp"
```

---

### Task 11: Full-flow verification + build log

**Files:**
- Modify: `MAP_BUILD_LOG.md` (append an "Onboarding" section)

- [ ] **Step 1: End-to-end run** — fresh signed-in account, walk Welcome → Name → Interests → Avatar → Map, tap "Explore the map" → lands on Today/tabs. Screenshot each transition; confirm progress bar advances, back preserves state, haptics fire, no jank.

- [ ] **Step 2: Confirm persistence** — `select * from town_profiles;` shows the row; the `avatars` bucket has `{uid}/avatar-*.jpg` when a photo was chosen; the public avatar URL resolves (open it).

- [ ] **Step 3: Append to `MAP_BUILD_LOG.md`**

Record: the migration applied (Task 1), the new files, the screenshot-verified states, the Reduce-Motion pass, and any known follow-ups (e.g. real St. Joe photos to swap into `Assets.xcassets/Interests`). Note the hybrid imagery status (seed art in place; real photos drop in by name).

- [ ] **Step 4: Commit**

```bash
git add MAP_BUILD_LOG.md
git commit -m "docs(onboarding): verification log for community-profile onboarding"
```

---

## Self-Review

**Spec coverage:**
- §1 flow/screens → Tasks 5–10. §2 taxonomy → Task 3. §3 imagery/resolver → Task 4. §4 data model (table/bucket/ProfileAPI/Storage/mirror/hydration) → Tasks 1, 2, 10. §5 motion → Tasks 6–9 (per-view). §6 a11y → in each view. §7 debug args → Task 9. §8 verification → Tasks 9, 11. §9 file list → covered. §10 tunables → defaults chosen (min 1 interest, `town_profiles`, dedicated `avatars` bucket). No gaps.

**Placeholder scan:** No TBD/TODO; every code step shows complete code; verification steps give exact commands + expected output. OK.

**Type consistency:** `ProfileAPI.getMyProfile() -> TownProfile?` and `upsert(displayName:avatarUrl:interests:onboarded:)` used identically in Tasks 2, 9, 10. `Storage.uploadAvatar(_:userId:contentType:)` defined Task 2, called Task 9. `InterestImage.image(for:) -> Image?` defined Task 4, consumed Task 7. `Interests.sections`/`displayName`/`Interest.imageName` defined Task 3, consumed Tasks 4, 7, 9. `ContinueButton`/`OnboardingTopBar` defined Tasks 6/5, reused in 7/8. Consistent.
```
