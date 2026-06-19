# Barcode Scanner — Real-World QA Checklist

The scanner (`app/components/FoodScanner.tsx`) uses `@zxing/browser` against the
device camera, then looks the barcode up in Open Food Facts (`lookupBarcode` in
`lib/food-search.ts`). Automated tests can't prove a camera reads a real UPC under
store lighting — this is the manual pass to run before trusting it in the wild.

Run it on a **real phone** (not desktop webcam), over **HTTPS or localhost** —
`getUserMedia` requires a secure context, and mobile is where it'll actually be used.

## Why these three stores
Coborn's (regional Midwest), Walmart (national brands + Great Value store brand),
and Costco (Kirkland store brand + bulk packaging) together cover the cases that
break barcode flows: national brands that are well-indexed, store brands that
often aren't, and oversized/wrapped packaging that's hard to frame.

## Per-store run (repeat at each)
Scan **8–10 items** spanning these categories. Record the result of each.

| Category | Example | Expect |
|---|---|---|
| National packaged brand | Cheerios, Coke | Found · correct name + macros · score with breakdown |
| Store brand | Great Value, Kirkland | May be **Not Found** → fallback card (not an error) |
| Fresh/produce (PLU sticker) | banana, apple | Likely Not Found → fallback → "Search by name" finds whole food |
| Bulk / oversized pack | Costco multipacks | Reads despite large barcode; framing works |
| Refrigerated/shiny wrap | yogurt, cheese | Glare doesn't block the read |
| Small item | gum, candy bar | Small barcode still detected |

## What to verify on each scan
- [ ] **Detection** — beam locks on within ~3s in normal store lighting; the
      "caught" check animation fires once (no double-scans).
- [ ] **Back camera** is used on the phone (not selfie cam).
- [ ] **Found item**: name, brand, and per-100g macros match the package.
- [ ] **Score is defendable**: open "Why this score" — every line is a reason you'd
      accept (NOVA processing, Nutri-Score, additives, etc.). Flag any score that
      can't be explained by its breakdown.
- [ ] **Not-found is graceful**: shows the "Not in the database yet" card with the
      barcode, **Enter manually**, and **Search by name** — never a red error.
- [ ] **Manual fallback works**: "Enter manually" → fill name + per-serving macros
      → Continue → lands on the normal result/portion screen → logs correctly.
- [ ] **Portion units**: serving / grams / oz available; the logged calories match
      the portion picked.
- [ ] **Logged correctly**: item appears in `/meal-log` under the right meal with
      the right calories; daily total updates.

## Edge cases to force
- [ ] Deny camera permission → clear "Camera unavailable" message, recoverable.
- [ ] Airplane mode mid-lookup → "check your connection" error, retry works.
- [ ] Scan an unknown/damaged barcode → no crash; cancel returns cleanly.
- [ ] Same item twice → two distinct log entries (no silent dedupe surprise).

## Pass bar
- [ ] ≥ 90% of **national brands** scan and resolve correctly.
- [ ] 100% of **not-found** items land on the fallback (zero dead-end errors).
- [ ] Every store-brand miss is recoverable via manual entry in < 30s.

## Log results here
| Date | Store | Items scanned | Found | Not found→fallback OK | Misreads | Notes |
|------|-------|---------------|-------|----------------------|----------|-------|
|      |       |               |       |                      |          |       |
