# UI primitives — the Hygge base layer

The shared component foundation for the app. These are
[react-native-reusables](https://github.com/founded-labs/react-native-reusables)
(shadcn-for-RN) primitives, tuned to the Hygge design system: they map shadcn's
variant API onto Hygge tokens via `cn()` (`@/lib/utils`) and the aliases in
`tailwind.config.js`. **Build new and reshaped UI on these**, not hand-rolled
`View` / `Text`.

Pull more from the registry on demand (the `@rnr` source in `components.json`):

```bash
cd apps/mobile && npx @react-native-reusables/cli@latest add <name>
```

## Non-negotiables (the house rules these encode)

- **Tokens, never raw hex.** Surfaces `bg-paper*`/`bg-card`/`bg-background`; text
  `text-ink`/`text-ink-2`/`text-ink-3` (or the `*-foreground` aliases); borders
  always `border-border` (= `border-black/[0.07]`). Accents have one job each —
  `moss`/`primary` = positive·primary·done, `sky`/`ring` = brand·focus,
  `honey` = warmth (sparingly), `clay`/`destructive` = warning. Never decorative.
- **System font + numeric weight.** The app ships no bundled UI font — text is the
  platform system font (SF Pro / Roboto), which carries every weight, so weight now
  comes from the numeric utilities `font-medium` / `font-semibold` / `font-bold`
  (RN renders them natively). The one custom face is the logo, Atkinson Hyperlegible,
  used **only** inside `HyggeLogoBadge` — never through a utility class.
- **Numbers** ride the same system font; add `tabular-nums` where digit columns must
  line up (calendars, timelines).
- **One elevation.** `CARD_SHADOW` (theme.ts) is the *only* shadow in the system —
  the card lift. Buttons, inputs, chips, switches are **flat**: fill + the hairline
  border. Don't add `shadow-*` to a control.
- **Radius scale** (`theme.ts` `RADIUS` ⇄ tailwind `borderRadius`), named by px:
  `rounded-sm8` (8) · `rounded-md12` (12, controls) · `rounded-lg16` (16, cards) ·
  `rounded-xl20` (20, sheets/hero). Pills are `rounded-full`.
- **Contrast** is baked into the ink ramp (ink 13.8:1, ink-2 6.3:1, ink-3 3.8:1 on
  paper). Don't reach below `text-ink-3` for readable text.

## Canonical specs

### Button — `./button.tsx`

Flat, `rounded-md12`, text is `font-semibold`. Pressed dims the fill
(`active:bg-*/90`); `disabled` → `opacity-50`; web gets a `ring` focus ring. The
three shapes you'll actually reach for:

| Shape | Call | Looks like |
|---|---|---|
| **Primary** | `<Button>` *(variant `default`)* | moss fill, paper text — the one strong CTA ("Post", "Join") |
| **Secondary** | `<Button variant="secondary">` (filled paper-200) or `variant="outline"` (bordered) | quiet, ink text |
| **Pill** | `<Button size="pill" variant=…>` | `rounded-full` filter/toggle chip — `default` when selected, `outline`/`ghost` when not |

Sizes: `default` (h-11) · `sm` (h-9) · `lg` (h-12) · `pill` (h-9, full) · `icon`
(11×11). Also `ghost` / `link` / `destructive` variants. Put label text in a
`<Text>` child — the button injects the right text class via context.

```tsx
<Button onPress={submit}><Text>Post</Text></Button>
<Button variant="outline" size="pill"><Text>Events</Text></Button>
```

### Card — `./card.tsx`

The canonical surface: `bg-card`, `border-border`, `rounded-lg16`, lifted by
`CARD_SHADOW` (applied via `style`, so it matches every hand-built card). Keep the
outer `<Card>` **un-clipped** — to round an image to the corner, nest a clipped
child; don't put `overflow-hidden` on the Card or it eats the shadow. Parts:
`CardHeader` / `CardTitle` (`font-semibold`) / `CardDescription` (ink-3) /
`CardContent` / `CardFooter`, all padded `px-5`.

```tsx
<Card>
  <CardHeader><CardTitle>Trivia Night</CardTitle>
    <CardDescription>Bad Habit Brewing · Thu</CardDescription></CardHeader>
  <CardContent>{/* … */}</CardContent>
</Card>
```

### Sheet (bottom sheet / day sheet)

There's no `Sheet` primitive yet — sheets in this app are hand-built (see the
calendar day sheet / `ExpandedWeek`). The spec when you build one: paper surface,
`rounded-t-xl20` top corners, hairline top border, a small grabber, content padded
`px-5`. Pull `@rnr`'s dialog/popover if a managed sheet is needed, then retune to
this spec.

### Heading & label type

- **Headings** use `<Text variant="h1…h4">` → system font, `font-bold` (h1/h2) /
  `font-semibold` (h3/h4). H1 is the hero scale.
- **Body / UI** is the default `<Text>` → system font, regular.
- **Field label** — `<Label>` (`./label.tsx`): `text-sm font-semibold`, ink.
  Pair with `<Input>` / `<Textarea>` (`rounded-md12`, flat, ink-3 placeholder).
- **Numbers** — the same system font; add `tabular-nums` for aligned digit columns.

### Badge / Separator / Skeleton

- **Badge** (`rounded-full`, `font-semibold`): use `secondary` / `outline` for
  neutral labels; reserve `default` (moss) for positive/"going"/done status, since
  moss is semantic.
- **Separator** — `bg-border` hairline; `orientation="vertical"` for inline rules.
- **Skeleton** — `bg-accent` (paper-100) block on `rounded-md12`; pulses on web.

## Migrating a screen onto these primitives

The screens were built before this layer, mostly from inline-styled `View`/`Text`.
Migrate incrementally — behavior identical, typecheck + `expo export` clean at each
step (see CLAUDE.md "How to work a task").

1. **Find the repeated shapes.** A bordered/elevated box → `Card`. A moss CTA →
   `<Button>`. A filter chip row → `<Button size="pill">`. A text field →
   `Input`/`Textarea` + `Label`.
2. **Swap one cluster, keep the rest.** Replace the inline `View`/`Pressable` with
   the primitive; drop the now-duplicated `style={{ borderRadius, backgroundColor,
   shadow… }}` — the primitive carries it. Keep surrounding layout untouched.
3. **Translate inline style → class.** `backgroundColor: C.moss700` → the Primary
   button. `borderRadius: 12` → `rounded-md12` (16 → `rounded-lg16`, etc.).
   `color: C.ink2` → `text-ink-2`. A number's aligned digits → add `tabular-nums`
   (same system font). Inline `CARD_SHADOW` → just use `Card`.
4. **Verify in the running app**, not from memory — screenshot the touched flow,
   diff against the design tokens, clear the on-brand bar. Then commit that step.

Tokens to translate against live in `src/theme.ts` (JS: `C`, `F`, `RADIUS`,
`CARD_SHADOW`, `GRAPH`) and `tailwind.config.js` (the matching classes). They
mirror each other — change both together.
