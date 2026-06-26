-- seed-trails.sql — real trails within ~15 miles of St. Joseph, MN.
-- Admin-curated reference data (factual, verifiable — not fake social proof).
-- Run once in the Supabase SQL editor. Re-running adds duplicates, so run only once.
-- Sources: Stearns County Parks, Lake Wobegon Trail, CSB/SJU OutdoorU, Visit Greater St. Cloud, AllTrails.

with me as (
  select id from auth.users where email = 'jessewallacejohnson1@icloud.com' limit 1
)
insert into public.club_events (kind, status, club_id, submitted_by, title, location, length, difficulty, description)
select 'trail', 'approved', null, me.id, v.title, v.location, v.length, v.difficulty, v.description
from me, (values
  (
    'Lake Wobegon Trail',
    'Lake Wobegon Trail, St. Joseph, MN',
    '49 mi · paved', 'Easy',
    'A flat, paved rail-trail that runs right through town — gentle grades the whole way, perfect for walking, biking, or a stroller. The St. Joseph trailhead on the north edge of town connects you west toward Avon, Albany and beyond.'
  ),
  (
    'Saint John''s Abbey Arboretum',
    'Saint John''s Abbey Arboretum, Collegeville, MN',
    '20+ mi of trails · varies', 'Easy–Moderate',
    'Over 2,500 acres of woods, prairie and lakes with six marked hikes through the Collegeville hills — from the short Boardwalk Loop to the 3-mile Chapel Trail up to the Stella Maris Chapel. Quiet, well-shaded, and beautiful in every season. No pets.'
  ),
  (
    'Quarry Park & Nature Preserve',
    'Quarry Park and Nature Preserve, Waite Park, MN',
    'Loops 2.3–5.9 mi', 'Easy–Intermediate',
    '684 acres of old granite quarries, woods and prairie. Loop trails wind past dramatic rock walls and spring-fed quarry swimming holes. A vehicle permit is required; open 8am to a half-hour after sunset.'
  ),
  (
    'Beaver Island Trail',
    'Beaver Island Trail, St. Cloud, MN',
    '5+ mi · paved', 'Easy',
    'A paved riverside path along the Mississippi from St. Cloud State University down to River Bluffs Regional Park, following an old rail line. Flat and easy — a favorite for walking, running and biking.'
  ),
  (
    'Munsinger & Clemens Gardens',
    'Munsinger Gardens, St. Cloud, MN',
    'Stroll', 'Easy',
    'Cobbled walking paths along the Mississippi through one of Minnesota''s prettiest public gardens — shaded Munsinger woods down by the river and the formal Clemens fountains and roses just up the hill. An easy, lovely walk.'
  ),
  (
    'Mississippi River County Park',
    'Mississippi River County Park, Rice, MN',
    '1.3 mi', 'Easy–Intermediate',
    '209 quiet acres with more than a mile of river frontage and easy wooded trails. No permit needed — a calm spot for a short walk along the Mississippi, with pine forest over a third of the park.'
  ),
  (
    'Warner Lake County Park',
    'Warner Lake County Park, MN',
    '2 mi loop', 'Easy',
    'A 241-acre park wrapped around little Warner Lake, with an easy two-mile multi-use loop through woods and open green space, plus a swimming beach and dog area. A relaxed half-hour walk.'
  )
) as v(title, location, length, difficulty, description);
