#!/usr/bin/env python3
"""
discover.py — build the town roster, and report what the registry is missing.

ADR-010 makes completeness the goal and says coverage is measured against an external
count of what exists, never against what we already hold. This is that external count.

It reads these sources, keeps what sits in the town's ZIP codes (ADR-019), and merges
them into one roster:

  * Overture Maps places and OpenStreetMap (Overpass), both free and storable.
  * A Google Maps sweep, one search per category, through Composio (maps.py). Google may
    show that a place exists; it never names one (ADR-016).
  * The town's own directory pages (joetown.org/explore, the chamber, an old town
    directory), and the registry itself, to subtract what we already have.

It writes no entries. Its outputs (roster.json, missing.json, same-place.json, events.md)
go to RUNS/discover-<stamp>/, linked from RUNS/latest-<town>; verify.py reads them and
drafts the entries.

Dedupe is deliberately timid (ADR-018). Sightings merge only on certainty; anything
merely SIMILAR is reported as a possible duplicate for a human to settle and is NOT
merged — a wrongly merged pair silently deletes a business from the town, which is the
one failure mode this whole script exists to prevent.

Attribution: OpenStreetMap data is ODbL. Any surface built on this roster owes
"© OpenStreetMap contributors". The `source` field on every record carries provenance so
OSM-derived rows stay identifiable.
"""

import argparse, html, json, os, re, subprocess, sys, time, unicodedata
from datetime import datetime, timezone
from difflib import SequenceMatcher
from pathlib import Path
from urllib.parse import urlparse
import urllib.request

sys.path.insert(0, str(Path(__file__).resolve().parent))
from registry import find_root, load
from run import fetch, UA

# The census's working files (cached map, Overpass and chamber answers, rosters, verdicts,
# research) live outside every checkout, so a run from any worktree finds the research
# done before. `.runs/` belongs to one checkout and is gone with it.
RUNS = Path(os.environ.get("BP_CENSUS_RUNS", "~/Documents/town-census/.runs")).expanduser()

# Overpass is a free, donated, frequently-overloaded service. 504s are routine and mean
# "busy", not "broken", so try the mirrors in turn before giving up.
# kumi first because it is the one that reliably answers this query; overpass-api.de
# 504s under load most afternoons. overpass.osm.ch is DELIBERATELY ABSENT: on
# 2026-09-23 it returned HTTP 200 with zero elements in 0.6s for a bbox the other
# mirrors answer with 200+. A mirror that returns a confident empty answer is worse
# than one that errors, because an empty roster reads as "nothing is missing".
OVERPASS_MIRRORS = [
    "https://overpass.kumi.systems/api/interpreter",
    "https://overpass-api.de/api/interpreter",
]
# Everything that could be useful to a neighbour, not just businesses (ADR-010).
OSM_KEYS = ["shop", "amenity", "office", "craft", "tourism", "healthcare",
            "leisure", "club", "historic"]
NEAR_DUPLICATE = 0.87        # SequenceMatcher ratio; above this we ASK, never merge

# ADR-013: places and events are separate things. Directory pages list both in one grid,
# so names that read like an occurrence are ROUTED to an events draft, never dropped — a
# place misfiled as an event is still a missing place (ADR-010), and only a human can
# settle "Woodfired Wednesdays".
EVENTISH = re.compile(
    r"\b(fest|festival|crawl|rocks|rocktoberfest|series|celebration|parade|"
    r"mondays|tuesdays|wednesdays|thursdays|fridays|saturdays|sundays|"
    r"days|nights|market day|reunion|fundraiser|benefit|tournament|expo|fair)\b",
    re.I)


def looks_like_event(name):
    return bool(EVENTISH.search(name))

TOWNS = {
    "st-joseph-mn": {
        "label": "St. Joseph MN",
        # ADR-019: a town is its ZIP codes. Every place whose address carries one belongs
        # here, the 56374 countryside included; anything else belongs to another town.
        "zips": ["56374"],
        # Words in an address that put it in another town despite a 56374 ZIP. The City's
        # calendar lists Saint John's events as "St. Joseph MN 56374"; its mail goes to
        # Collegeville (ADR-019). read_events.py keeps them: a St. Joseph source posted them.
        "elsewhere": ["Saint John's University", "Abbey Plaza", "Collegeville"],
        # South, west, north, east. Covers the city plus the immediate fringe, because
        # Milk & Honey is out on County Road 51 and still very much St. Joe.
        "bbox": (45.540, -94.360, 45.590, -94.280),
        # Wider box for Overture, which carries ZIP codes: it reaches the 56374 townships
        # and the ZIP filter then drops Avon, Cold Spring, St. Cloud and Waite Park.
        "overture_bbox": (45.470, -94.470, 45.660, -94.240),
        # Map sweep centre and zoom. Zoom 13 with a bare category came back mostly St.
        # Cloud (2026-10-02); naming the town in each search at zoom 14 keeps about half
        # the answers in St. Joseph and the ZIP filter drops the rest.
        "sweep_ll": "@45.5640,-94.3180,14z",
        # Floor for the silent-empty guard. Measured 202-204 elements on 2026-09-23,
        # so half that is comfortably below real data and well above a broken mirror.
        "osm_min_elements": 100,
        # Confirmed SAME place under different names (ADR-018). First entry of each group
        # is the name that survives; the rest fold into it. This is the roster-side twin
        # of an entry's `aka:` — `aka` settles a roster name against the registry, this
        # settles two roster names against each other, before either becomes an entry.
        # Most of these were settled by hand on 2026-10-02 and confirmed by Jesse. College
        # offices, teams and buildings fold into the college (Q15 of that session).
        "aliases": [
            ["Sal's Bar and Grill", "Sal's Bar", 'Sals Bar and Grill'],
            ['Amy Hedtke State Farm', 'Amy Hedtke', 'Hedtke Insurance', 'State Farm',
             'Amy Hedtke - State Farm Insurance Agent'],
            ['Bee Line Auto & Sport', 'Bee Line Service Center',
             'Bee Line Yamaha Super Store'],
            ['Bello Cucina', 'Bella Cucina', 'Bello Cucina | Italian'],
            ["Bo Diddley's Deli", "Bo-Diddley's"],
            ['Central Canvas Manufacturing', 'Central Canvas Manufacturing Inc.',
             'Central Canvas Mfg. Inc'],
            ['Central MN Realty', 'Central MN Realty - St. Joe',
             'Ann Riesner - Central MN Realty'],
            ['Clemens Perk Coffee Shop', 'Clemens'],
            ["Coborn's", "Coborn's Grocery Store", "Coborn's Pharmacy"],
            ['Consumer Directions', 'Consumer Directions Inc. (CDI)'],
            ['College of Saint Benedict',
             "College of St. Benedict & St. John's University", 'College of St Benedicts',
             'CSB Athletic Activities', 'CSB Athletics', 'CSB Events and Catering',
             'CSB Security', 'Claire Lynch Hall', 'Haehn Campus Center',
             'Ardolf Science Center', 'College of Saint Benedict Volleyball',
             'CSB Campus Ministry', 'CSB + SJU Music Department',
             'The Lounge - College of St. Benedict', 'Upper Midwest String Camp',
             'CSB Community Kitchen', 'CSB / SJU Department of Psychology',
             'CSB/ SJU History Department', 'CSB Senate',
             'Gorecki Dining and Conference Center',
             'Gorecki Center at the College of Saint Benedict',
             "Saint Benedict's College Clemens Field House",
             'Benedict and Dorothy Gorecki Gallery', 'Buhl Elizabeth a PhD',
             'CLAIRE LYNCH HALL', "CSB WOMEN'S SOCCER", 'Luetmer Apartment',
             'Square One Global', 'Well-Being Center - Student Health Services',
             "College of St. Benedict & St. John's University ESSS Department"],
            ['Benedicta Arts Center', 'Escher Auditorium',
             'CSB and SJU Fine Arts Programming'],
            ['Daisy A Day Floral & Gift', 'Daisy A Day'],
            ['Floor To Ceiling', 'Floor To Ceiling St. Joseph'],
            ['Flour & Flower Bakery', 'Flour & Flower', 'Flower + Flour Bakery'],
            ['Golden Hour Wellness', 'Golden Hour Tanning'],
            ['Circle K', 'Holiday', 'Holiday Car Wash', 'Holiday Stationstores',
             'Holiday Gas Station', 'Holiday Stationstores | Car Wash'],
            ['The House Food and Tap', 'The House'],
            ['Jupiter Moon Ice Cream', 'Jupiter Moon Ice Cream - St. Joseph'],
            ['Kidstop', 'Kids Stop'],
            ['Krewe', 'Krewe Restaurant'],
            # Two Kwik Trips since 2026: #147 on 2nd Ave NW and #575 on 20th Ave SE, so a
            # bare "Kwik Trip" names neither and is left for the street rule to place.
            ['Kwik Trip #147', 'KWIK TRIP #147'],
            ['La Playette', 'The La Playette', 'La Playette Bar', 'LaPlayette Bar'],
            ['Contardo Laser Dentistry', 'Laser Dentistry- Dr. Contardo',
             'Contardo, Michael F DDS'],
            ['Lookin Good Tint', 'Lookin Good Tint LLC', 'Lookin Good'],
            ['Magnifi Financial', 'Central Minnesota Credit Union',
             'Central Minnesota Federal Credit Union', 'Magnifi Financial Credit Union'],
            ['TireMaxx / Mid-State Wholesale Tire', 'Mid-state Wholesale Tire',
             'Tiremaxx Service Centers', 'Tiremaxx/Mid-State Wholesale Tire',
             'Tiremaxx Service Center'],
            ['The Middy', 'Main Street Pub', "Loso's Main Street Pub"],
            ['Minnesota Street Market', "Loso's Grocery"],
            ['Neighbors Route 75', 'Neighbors Route 75 Bar and Grill',
             'Stonehouse Tavern & Eatery'],
            ['Obbink Distilling', 'Obbink Distillery'],
            ['Omann Insurance', 'Omann Insurance Agency, LLC'],
            ['Pierce Insurance', 'Pierce Agency Inc.'],
            ['Roger Tamm Photography', 'R Tamm Photography'],
            ['Asteria Inn & Suites (was Rodeway Inn)', 'Asteria Inn & Suites St. Joseph',
             'Rodeway Inn', 'Super 8'],
            ['Ross Nesbit Agencies', 'Ross Nesbit Agencies St. Joseph',
             'Ross Nesbit Agencies Inc'],
            ['St. Joseph Meat Market', 'St Joseph Meat Market Inc', 'St. Joe Meat Market'],
            ['St. Joseph Off-Sale Liquor', 'St Joseph Off-Sale Liquor',
             "Hollander's Liquor", 'Hollanders Liquor', 'St. Joseph Liquor Shoppe',
             'Off Sale Liquor'],
            ['Speedway', 'J M Speedstop St. Joe'],
            ['Snap Fitness', 'Snap Fitness St. Joseph', 'St. Joseph, MN'],
            ['St. Joseph Health and Wellness Center', 'St. Joseph Health & Wellness'],
            ['St. Joseph Equine Clinic', 'St. Joseph Cold Spring Vet'],
            ['Sunset Manufacturing / Sunset Equipment', 'Sunset Manufacturing Co',
             'Sunset Equipment And Supply'],
            ["Thomsen's Garden Center", 'Thomsen Greenhouses'],
            ['Uptown Styles Hair Salon', 'uptown styles by arbor'],
            ['The Wandering Cow', 'The Wandering Cow Ice Cream',
             'Wandering Cow Ice Cream'],
            ['W|R Home & Clothing Co.', 'W|R Home Company', 'WR Home & Clothing Co.'],
            ['LeafGuard Gutters', 'Leaf Guard Gutters', 'LeafGuard Gutters of St. Cloud'],
            ['Precise Heating, A/C, Plumbing & Refrigeration', 'Precise Refrigeration',
             'Precise Refrigeration Heating',
             'Precise Heating, A/c, Plumbing & Refrigeration'],
            ['Precision Motorsports', 'Precision Propeller & Cycle'],
            ['Powerhouse Outdoor Equipment', 'Powerhouse Inc'],
            ['CentraCare Clinic - St. Joseph', 'CentraCare Clinic-St Joseph',
             'Centracare Clinic', 'St. Joe Clinic', 'Newton Thomas MD',
             'Christopher Thompson, MD', 'Sean Wherry, MD', 'Katrina Wherry, MD',
             'Dr. Thomas J. Newton, MD'],
            ['Exponential Chiropractic Healing Center', 'Jerry Wetterling DC',
             'St. Joseph Family Chiropractic', 'Brian Koltes'],
            ['Milbert, Johnson & Cotton Family Dentistry',
             'Styles & Cotton Dental Office',
             'Styles Dr, Cotton Dr & Milbert Dr...', 'Milbert Kelsey K DDS', 'Dr. Curt Cotton'],
            ['Solar Nails of St Joseph', 'J L Nails'],
            ['Home Town Title', 'Hometown Title'],
            ['City of St. Joseph (City Hall)', 'City of St. Joseph',
             'City of St. Joseph, MN', 'St Joseph City Clerk',
             'Saint Joeseph Government Building', 'St. Joseph, Minnesota',
             'St. Joseph City Office', 'St. Joseph City Clerk'],
            ['St. Joseph Township Hall', 'St. Joseph Town Hall'],
            ['St. Joseph Post Office', 'Post Office-St Joseph',
             'United States Postal Service', 'US Post Office'],
            ['St. Joseph Fire Department', 'St. Joseph Community Fire Station',
             'Saint Joseph Fire Department'],
            ['American Legion Post 328', 'American Legion'],
            ['Minnesota Association of Farm Mutual Insurance Companies',
             'Minnesota Association of Farm Mutual Insur',
             'Minnesota Assn of Farm Mutual'],
            ['Millstream Park', 'Millstream Park Pickleball Courts'],
            ['Kennedy Community School', 'Kennedy Elementary',
             'John F Kennedy Elementary School'],
            ['St. Joseph Catholic School', 'St Joseph Laboratory School',
             'St. Joseph Laboratory School'],
            ['St. Joseph Catholic Church', 'St Joseph Catholic Church',
             'St Jospeh’s Church', 'St. Joseph Parish'],
            ["Saint Benedict's Monastery", 'Sisters of the Order of Saint Benedict',
             'Sisters of St. Benedict', 'Sacred Heart Chapel'],
            ['River of Life Church', 'River of Life Church - St Joseph'],
            ['Cedar Street Salon and Spa', 'Aveda'],
            ['2nd Avenue Cuts', "Danzl's Barber Shop"],
            ['Sentry Bank', 'First State Bank of St. Joseph'],
            ['Underground Water Locating', 'James Kuebelbeck Water Loc Service'],
            ["Piper's Plumbing", "Piper's Inc of St. Cloud"],
            ['Capital Storage Rental of St Joseph', 'Ridgewood Storage'],
            ['Scenic Specialties Landscape Professionals', 'Pond Shop'],
            ['St Joseph Manufactured Home Community', 'W J Properties'],
            ['Von Meyer Publishing Inc', 'Music & Dance News'],
            ['TCC Materials', 'Tcc Materials', 'Bremix', 'Borgert Products Inc'],
            ['Collegeville Brokerage', 'Collegeville Development Group',
             'Jon Petters Collegeville Brokerage'],
            ['Hansen and Company Woodworks', 'A Cab Custom Woodworking', 'HCo 2.0'],
            ['Carlson Crossing Townhomes', 'Cloverdale Townhouses'],
            ['Insurance Advisors: St. Joseph', 'KIA Insurance Inc'],
            ['Auto Color & Industrial Supply', 'Autocolor & Bumper Supply'],
            ['St. Joseph Newsleader', 'Newsleaders of St. Joseph and Sartell-St. Stephen'],
            ['MN HEAVY TOWING', '24 HOUR SEMI TRUCK TOWING'],
            ['Adam McArthur Agency LLC',
             'Adam McArthur Agency LLC American Family Insurance'],
            ['All Occasion Floral and Gifts',
             "All Occasion Floral and Gifts featuring DJ's Flower Bar & Tea"],
            ['AMS Tax and Accounting Solutions', 'AMS Tax & Accounting Solutions PA'],
            ['BL Grafx', 'B L GrafX LLC'],
            # Campus Park Villas was renamed Cedar Trail Apartments (verify, 2026-10-02).
            ['Cedar Trails Apartments', 'Cedar Trail Apartments',
             'Campus Park Villas & Townhomes'],
            ['Chiropractic Connection, PC', 'Chiropractic Connection'],
            ['Clemens Library', 'Clemens Library and Computing Center'],
            ['Dancing Pines Retreat',
             'DANCING PINES SUITE at Dancing Pines Retreat • A Luxury Log Home & Pet Friendly.',
             'DANCING PINES SUITE near SJU, CSB Wobegon Trail',
             'Log Bear Den at Dancing Pines Retreat • A Luxury Log Home & Pet Friendly.',
             'LOG BEAR DEN near SJU, CSB Wobegon Trail. Relaxing. Romantic. Refined. Rustic.'],
            ['Edward Jones - Financial Advisor: Beau Hanowski',
             'Edward Jones - Financial Advisor: Beau Hanowski, CFP®'],
            ['St. Joseph Trailhead of Lake Wobegon Trail', 'Lake Wobegon Trail'],
            ['Leaps and Bounds Childcare & Preschool', 'Leaps and Bounds Childcare'],
            ['Lilac Retreat',
             'Lilac Retreat lake house sauna + pickleball close to St. Johns and St. Bens'],
            ['Klinefelter Park', 'Playground | Klinefelter Park'],
            ['US Army Reserve Training', 'Saint Joseph Deers Office'],
            ['Sisters & Company', 'Sisters & Co. Consignment Boutique'],
            ['St Joe Rod and Gun Club', 'St. Joe Rod and Gun Club boat launch'],
            ['Lions Park', 'St. Joseph MN Lions Park'],
            ['Charlie Walker Construction', 'Charlie Walker Construstion, Inc.'],
            # Settled by Jesse, 2026-10-05.
            ['Peaceful Village Imports Inc.', 'Peaceful Village', 'Peaceful Village Imports'],
            ['Millstream Arts Festival', 'Millstream Art Festival'],
            ['Kraemer Lake-Wildwood County Park', 'Kraemer Lake & Wildwood Park',
             'Wildwood Park Maple Sugar Shack',
             'Wildwood park picnic shelter and fishing pier'],
            ['The Whole You Wellness Collective',
             'The Whole You Wellness Collective-Trisha Kubasek LLC'],
            ['Unwind', 'Unwind: Craniosacral, Myofascial, Lactation Clinic'],
            ['Urban Oasis',
             'Urban Oasis: Cozy 2-bedroom apartment in the center of Saint Joseph'],
            ['Well & Company', 'WELL & Company St. Joseph'],
            ['Wendy Loso', 'Wendy Loso Central MN Realty'],
            # One organisation each: same phone and street, and a shared website or a
            # rename verify confirmed (2026-10-17). An agent folds into its firm (Q15).
            ['Astech Corp', 'Asphalt Surface Technologies Corp'],
            ['Ami Auction', 'AMI'],
            ['Little Shop Welding & Repair', 'Little Shop Welding, LLC'],
            ['Emerald Companies', 'Emerald Lawn Care'],
            ['Thunder Valley Classic Cars Inc.', 'Thunder Valley Performance'],
            ['TMT Integrity Flooring, LLC', 'TMT Vintage LLC'],
            ['Quill & Disc', 'Patents Minnesota'],
            ['Millstream Communications', 'Verizon Wireless Zone'],
            ['Golden Rule Real Estate', 'Dan DeMark Realtor'],
            ['Bloom Styling & Events', 'The Bloom Booth'],
            ['Kostreba Appliance Services Center', 'Omega Force Appliance Repair'],
        ],
        # Pairs confirmed DISTINCT by a human, so the duplicate report stops asking.
        # Recurring false positives train people to skim the report, which is how a real
        # duplicate gets waved through.
        "known_distinct": [
            # Jesse, 2026-09-23: "sju for mens, cbs is womens" — two colleges, two
            # athletics programmes, and they must never be merged.
            ("csb athletic activities", "sju athletic activities"),
            # Two businesses each, one owner and one phone (2026-10-02 sweep).
            ("Creekwood Acres", "TMT Integrity Flooring LLC"),
            ("Full Circle Water", "Pristine Environmental"),
            ("Kwik Trip #147", "Kwik Trip #575"),
            # Rosie's Gyps Ranch is the Krebsbachs' Gypsy Vanner ranch; KD Performance
            # Horses is the trainer working there. Overture gave the ranch KD's phone and
            # website (2026-10-17).
            ("KD Performance Horses", "Rosie's Gyps Ranch"),
            # Jesse, 2026-10-17: two places at one address, with different phones.
            ("Consumer Directions", "A New Direction"),
            # Same phone or street, different organisations (2026-10-17): one owner's
            # several businesses, tenants of one building, a shop inside a store, a
            # complex and its manager, chair-renting stylists, a successor in a spot.
            ("Clemens Perk Coffee Shop", "College of Saint Benedict"),
            ("Clemens Perk Coffee Shop", "Clemens Library"),
            ("College of Saint Benedict", "On A Lark College Store"),
            ("Saint Benedict's Monastery", "St Benedicts Art & Heritage"),
            ("Coborn's", "Caribou Coffee"),
            ("Coborn's", "Coborn's Liquor"),
            ("Sunny Mary Meadow", "The Bloom Room"),
            ("Central Canvas Manufacturing", "Rustic River Gear"),
            ("W Gohman Construction", "Artistic Stone & Concrete"),
            ("Mill Stream Village", "Collegeville Brokerage"),
            ("West Apartments", "East-west Realty"),
            ("the Perfect Fit", "St. Joseph Health and Wellness Center"),
            ("St. Joseph Health and Wellness Center", "The Whole You Wellness Collective"),
            ("St Joseph Laundromat", "St Joe Mini-Storage"),
            ("St Joseph Laundromat", "St Joe Sand & Gravel"),
            ("St Joe Mini-Storage", "St Joe Sand & Gravel"),
            ("PrairieScapes", "Steve's Landscape Service"),
            ("Frontgate Inc.", "Five Star Transport Solutions"),
            ("Grandview Buildings", "Minnesota Home Improvements"),
            ("King of Hearths", "TCC Materials"),
            ("Amcon Block & Precast", "TCC Materials"),
            ("HD Specialties LLC", "Semi Legal Service"),
            ("Uptown Styles Hair Salon", "Hair by Hanna"),
            ("Uptown Styles Hair Salon", "Hair By Mel LLC"),
            ("Hair by Hanna", "Hair By Mel LLC"),
            ("Kraemer Lake-Wildwood County Park", "Wildwood Ranch Maple Syrup"),
            ("Adara Home Health", "Home Town Title"),
            ("Kostreba Appliance Services Center", "DKT Auto & Diesel Repair"),
            ("Metro Plumbing & Heating, Inc.", "One Hour Heating & Air Conditioning"),
            ("Yamry Construction", "Charlie Walker Construction"),
            ("Riff City Guitar & Music Company", "Barrett’s Music"),
            ("Restoring Hope Individual & Family Therapy LLC", "True Freedom Physical Therapy"),
            ("K Welz Counseling and Coaching", "Angela Larcom Counseling"),
            ("Midnight Graphix", "Midnight Warehouse"),
            ("Central Lakes Mutual Insurance Co", "St. Joseph Mutual Insurance Company"),
        ],
        # Names that are not places in this town: events, kiosks, store counters, and
        # Saint John's buildings. Google gives Saint John's a St. Joseph 56374 address,
        # but its mail goes to Collegeville 56321, so ADR-019 puts it in Collegeville.
        "not_places": [
            "Saint Patrick Hall", "St John's Game Refuge", "Saint John's Arboretum",
            "Haws Field - Home of @Johnnie_Soccer", "St Cloud Area Warehouse Space For Rent",
            "Saint John's Senate", "Saint John's University", "Saint John's Abbey",
            # Watched for their events, not places in town (watch-every-place, 2026-10).
            "CSB SJU events", "Minnesota 511", "Stearns County",
            'Blue Rhino Propane Exchange',
            'Catholic Charities',
            'Coinme',
            'Flynntown Apartments',
            'Jerome Tupa Fine Art',
            'JoeTown',
            'Joetown Rocks',
            'La Jam',
            'Little Free Library',
            'McKeown Center',
            'Milk & Honey Summer Music Series',
            'Quiet, relaxing home on Lake Watab in beautiful St. Joseph, MN near SJU and CSB',
            'Redbox',
            'Rock for Alzheimers',
            'Rocktoberfest',
            "Saint John's Abbey Arboretum",
            'Shop Small Crawl',
            'St. Joe Park and Ride',
            'Stella Maris Chapel',
            'The Old Henry Kowitz Farm (1932)',
            'The Refectory',
            "Tops Cleaners @ Coborn's",
            'Truck Parking Club',
            'Vincent Court Complex',
            'Western Union',
            'Wood Fired Wednesdays',
            'Woodfired Wednesdays',
        ],
        # Place type by hand, where category and name both mislead.
        "place_types": {
            'St. Wendel Tamarack Bog Scientific & Natural Area': 'Park / historic',
            '24 North: Lofts on College Avenue': 'Business',
            'A New Direction': 'Community group',
            'American Legion Post 328': 'Community group',
            'Bee Line Auto & Sport': 'Business',
            'Benedicta Arts Center': 'School / college',
            'Boulder Ridge Apartments': 'Business',
            'Campus Park Villas & Townhomes': 'Business',
            'City of St. Joseph Archery Range': 'Park / historic',
            'Clemens Perk Coffee Shop': 'Business',
            'Creamery Lofts': 'Business',
            'Granite City Gymnastics': 'Business',
            'Granite City Reporting': 'Business',
            'Granite City Window Cleaning': 'Business',
            'Greater Minnesota Mentoring Academy': 'School / college',
            'Grey Face Rescue & Retirement': 'Community group',
            'Hollow Park Tot Lot': 'Park / historic',
            'Home Town Title': 'Business',
            'Joetown Apartments': 'Business',
            'Kidstop': 'School / college',
            'Leaps and Bounds Childcare & Preschool': 'Business',
            'Little Saints Academy': 'Business',
            'Mary and Tom Darnall Ampitheater': 'Park / historic',
            'Mid Minnesota Trailer Repair': 'Business',
            'Millstream Communications': 'Business',
            'Minnesota Association of Farm Mutual Insurance Companies': 'Business',
            'On A Lark College Store': 'Business',
            'Reading Resources, LLC': 'Business',
            'Riff City Guitar & Music Company': 'Business',
            'Roadway Sport-N-Trailer': 'Business',
            'SJU Athletic Activities': 'School / college',
            'St Benedicts Art & Heritage': 'Park / historic',
            'St Joe Rod and Gun Club': 'Community group',
            'St Joseph Farmers Market': 'Community group',
            'St. Cloud Area Chamber of Commerce': 'Community group',
            'St. Joseph Blockhouse': 'Park / historic',
            'St. Joseph Community Food Shelf': 'Community group',
            'St. Joseph Joes': 'Community group',
            'Stearns Electric Association': 'Business',
            'Stearns History Museum': 'Community group',
            'Tour Of Saints Cycling Assn': 'Community group',
            'Town & Country Excavating': 'Business',
            'Truck & Trailer 24HR Mobile Repair': 'Business',
            'US Army Reserve Training': 'Government',
            'Wacosa': 'Community group',
            'Whitby Gift Shop & Gallery': 'Business',
        },
        "directories": [
            {"id": "joetown", "url": "https://www.joetown.org/explore"},
            # Its robots.txt permits everyone and asks for Crawl-delay: 10 (ADR-014), but
            # this Mac's IP has been blocked since 2026-09-23, so the members come from
            # the list harvest_chamber.py saved (collect_chamber).
            {"id": "chamber", "url": "https://stjosephchamber.com/member-directory/",
             "collector": "chamber"},
            # An old, undated town directory (274 entries in 2026-10). Partly stale, but it
            # is the only list of the rural trades with no web presence at all. Its places
            # count as seen, never as open: verification decides.
            {"id": "lakesnwoods", "url": "https://lakesnwoods.com/StJosephBusiness.htm",
             "collector": "lakesnwoods", "stale": True},
        ],
        # Known robots refusals. Listed so they show up as work rather than vanishing.
        # The fix for a robots block is search_snippet, never a workaround (ADR-001).
        # Nothing is agent-only for this town any more. stjosephmn.gov is fetchable
        # (ADR-012) and its /9/Business page holds permits and zoning, not a business
        # list; the chamber permits robots (ADR-014) and is read from a saved list.
        "agent_only": [],
    }
}

# Link-farm and infrastructure hosts that appear on every page and are never a business.
NOISE_HOSTS = ("squarespace", "sqspcdn", "typekit", "googleapis", "gstatic",
               "fonts.", "facebook.com/sharer", "twitter.com/intent", "youtube.com",
               "instagram.com/p/", "cdn.", "w3.org", "schema.org")


def norm(name):
    """Fold a business name to a comparison key. Aggressive on purpose."""
    s = unicodedata.normalize("NFKD", html.unescape(str(name)))
    s = s.encode("ascii", "ignore").decode().lower().replace("&", " and ")
    # "Saint Joseph Meat Market" and "St. Joseph Meat Market" are one butcher. This is
    # the town's name, so it appears in a lot of business names and is worth folding.
    s = re.sub(r"\bsaint\b", "st", s)
    # Apostrophes are DELETED, not spaced. A curly one is dropped by the ascii fold
    # above while a straight one would survive to become a space, so "Sal's" and
    # "Sal’s" normalised to different keys and the same bar appeared twice.
    s = s.replace("\u2019", "").replace("'", "")
    s = re.sub(r"[^a-z0-9 ]", " ", s)
    # "and" goes with the articles: "Flour & Flower" becomes "flour and flower" while
    # "Flower + Flour" becomes "flower flour", and that single connector token was
    # enough to propose the same bakery twice. Connectors are not identity.
    s = re.sub(r"\b(the|a|an|and)\b", " ", s)
    s = re.sub(r"\b(llc|inc|co|company|corp|ltd|the)\b", " ", s)
    return re.sub(r"\s+", " ", s).strip()


def match_key(name):
    """Merge key: the normalised words, SORTED.

    Word order is not identity. joetown.org lists "Flower + Flour Bakery" and the
    registry calls the same shop "Flour & Flower Bakery"; on a plain normalised string
    those are different places and the bakery gets proposed a second time. Comparing
    the token SET catches the swap. Token-set identity is still a strong claim — every
    word has to be present — so this stays on the safe side of merging.
    """
    return " ".join(sorted(norm(name).split()))


def osm_category(tags):
    for k in OSM_KEYS:
        if k in tags:
            return f"{k}={tags[k]}"
    return None


def collect_osm(bbox, min_elements, cache=None, max_age_days=7, refresh=False):
    s, w, n, e = bbox
    # ONE key-regex pass, not one query per key. Nine separate nwr statements timed
    # every mirror out; this returns the same features in a single traversal.
    query = (f'[out:json][timeout:60];'
             f'nwr[~"^({"|".join(OSM_KEYS)})$"~"."]({s},{w},{n},{e});'
             f'out tags center;')
    # Overpass is donated infrastructure and this query takes over a minute. Cache it:
    # the roster is a monthly job, and a town's shops do not turn over in an afternoon.
    if cache and not refresh and cache.exists():
        age = (datetime.now(timezone.utc).timestamp() - cache.stat().st_mtime) / 86400
        if age < max_age_days:
            data = json.loads(cache.read_text())
            print(f"[discover] osm: using cache, {age:.1f}d old (--refresh to re-fetch)")
            return _osm_records(data, min_elements, "cache")

    last = None
    for endpoint in OVERPASS_MIRRORS:
        req = urllib.request.Request(
            endpoint, data=urllib.parse.urlencode({"data": query}).encode(),
            headers={"User-Agent": UA})
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                data = json.load(r)
            break
        except Exception as ex:
            last = f"{urlparse(endpoint).netloc}: {ex}"
    else:
        raise RuntimeError(f"all Overpass mirrors failed (last: {last})")

    recs = _osm_records(data, min_elements, urlparse(endpoint).netloc)
    if cache:
        cache.parent.mkdir(parents=True, exist_ok=True)
        cache.write_text(json.dumps(data))
    return recs


def _osm_records(data, min_elements, where):
    if len(data.get("elements", [])) < min_elements:
        # A confident empty answer is the dangerous failure: it makes MISSING smaller
        # and the registry look more complete than it is, which is the one thing
        # ADR-010 measures. Treat "implausibly few" as an outage, not as truth.
        raise RuntimeError(
            f"only {len(data.get('elements', []))} elements from "
            f"{where} (expected >= {min_elements}) — treating as an "
            f"outage rather than an empty town")
    out = []
    for el in data.get("elements", []):
        tags = el.get("tags", {})
        name = tags.get("name")
        if not name:
            continue                       # unnamed features are geometry, not places
        out.append({
            "name": name,
            "category": osm_category(tags),
            "website": tags.get("website") or tags.get("contact:website"),
            "lat": el.get("lat") or (el.get("center") or {}).get("lat"),
            "lon": el.get("lon") or (el.get("center") or {}).get("lon"),
            "source": "osm",
        })
    return out


def collect_chamber(url, cache):
    """The St. Joseph Chamber's members, from the list harvest_chamber.py saved.

    stjosephchamber.com has blocked this Mac's IP since 2026-09-23 (we ignored its
    Crawl-delay while iterating on a parser), so discovery never fetches it. It reads the
    saved list, however old, and says how old: dropping it would silently lose 31 members,
    11 of them on no other list. A fresh list goes through Firecrawl, which spends credits,
    so it waits for Jesse (harvest_chamber.py).
    """
    if urlparse(url).netloc != "stjosephchamber.com":
        raise RuntimeError(f"the chamber reader knows only stjosephchamber.com; give {url} "
                           f"the plain directory reader (no collector)")
    if not cache.exists():
        raise RuntimeError("no saved chamber list: python3 sources/scripts/harvest_chamber.py "
                           "--harvest --parse (Firecrawl credits, ask Jesse first)")
    # Age from the harvested pages: a re-parse rewrites chamber.json and its date.
    pages = cache.parent / "chamber" / "_index.md"
    age = (time.time() - (pages if pages.exists() else cache).stat().st_mtime) / 86400
    print(f"[discover] chamber: saved list, {age:.0f} days old"
          + (" (a fresh one needs harvest_chamber.py and Jesse's yes)" if age > 90 else ""))
    return json.loads(cache.read_text())

LINK = re.compile(r'<a\b[^>]*href="(https?://[^"]+)"[^>]*>(.*?)</a>', re.S | re.I)
TAGS = re.compile(r"<[^>]+>")


def collect_directory(url):
    """Anchor text on a directory page is almost always the business name."""
    # fetch() returns (status, decoded_text) — NOT bytes. Unpacking it as one value and
    # calling str() on the tuple parsed the tuple's repr, which is why anchor text came
    # back carrying the two-character sequence backslash-n and produced entries named
    # "\n \n \n". The junk filter below stays as hygiene, but this was the cause.
    _status, html_text = fetch(url)
    host = urlparse(url).netloc
    out, seen = [], set()
    for href, anchor in LINK.findall(html_text):
        if any(h in href for h in NOISE_HOSTS) or host in href:
            continue
        name = html.unescape(TAGS.sub(" ", anchor))
        # joetown.org embeds JSON in places, so some anchor text arrives with the
        # two-character sequence backslash-n rather than a real newline. Those must go
        # BEFORE the "has real letters" test below, or the n's count as letters and
        # entries named "\n \n \n \n" sail through it — which is exactly what happened.
        name = re.sub(r"\\+[nrt]", " ", name)
        name = re.sub(r"\s+", " ", name).strip()
        # Anchor text that is only whitespace, or the literal characters "\n", survives
        # tag-stripping and became three entries named "\n \n \n". Require real letters.
        if len(re.sub(r"[^A-Za-z0-9]", "", name)) < 3 or len(name) > 60:
            continue
        if name.lower() in ("read more", "learn more", "website", "click here", "home"):
            continue
        key = norm(name)
        if not key or key in seen:
            continue
        seen.add(key)
        out.append({"name": name, "category": None, "website": href,
                    "lat": None, "lon": None, "source": urlparse(url).netloc})
    return out


# --- Town census collectors (ADR-016, ADR-019) ------------------------------------------

# Google is the most complete list of what exists (ADR-010), but a registry entry never
# takes its name, address or phone from it (ADR-016). Records from these sources are
# kept apart until a non-Google source confirms the place.
GOOGLE = {"maps"}

# One map search per category, with the town named in each. Tested on St. Joseph,
# 2026-10-02: 138 categories x up to 3 pages found ~400 places with a 56374 address,
# about 90 of which no other source had.
SWEEP_CATEGORIES = [c.strip() for c in """
restaurant; bar; coffee shop; bakery; pizza; fast food; ice cream; brewery winery distillery;
grocery store; gas station; convenience store; liquor store; hair salon; barber shop;
nail salon; massage spa; tanning salon; gym fitness; yoga studio; martial arts;
dance studio; chiropractor; dentist; doctor clinic; counseling therapist; pharmacy;
eye doctor; physical therapy; veterinarian; pet grooming; dog kennel boarding;
dog breeder; auto repair; auto body shop; tire shop; car dealer; used cars; car wash;
towing; motorcycle dealer; trailer repair; truck repair; general contractor; home builder;
electrician; plumber; heating air conditioning; roofing; landscaping; lawn care;
excavating; concrete; cabinet maker woodworking; painter; flooring; windows doors;
cleaning service; real estate agent; insurance agency; bank credit union;
accountant tax preparation; lawyer; financial advisor; apartments; townhomes;
self storage; hotel motel; bed and breakfast; vacation rental; event venue; church;
school; daycare childcare; preschool; florist; gift shop; clothing boutique;
thrift store; hardware store; furniture store; appliance repair; manufacturer;
machine shop; welding; trucking company; printing; sign shop; photographer; farm;
orchard; greenhouse garden center; music store; sporting goods; bait tackle;
computer repair; cell phone store; electronics store; funeral home; nonprofit;
senior living; assisted living; storage units; well drilling; septic service;
taxidermy; auction service; consulting; marketing agency; software company;
engineering; museum; park; library; government office; post office; laundromat;
tattoo; jewelry; candles crafts; sewing alterations; upholstery; propane; feed seed;
equipment rental; snow removal; tree service; pest control; home inspection;
title company; mortgage; staffing agency; wedding; catering; food truck; meat market;
farmers market; art gallery; community center""".replace("\n", " ").split(";") if c.strip()]

# Not places at all, in any town: money kiosks, parking, little free libraries (Q15 of
# the 2026-10-02 session). Events are routed separately by EVENTISH.
NOT_A_PLACE = re.compile(
    r"\b(atm|parking|park (and|&) ride|bookcase|little free library|redbox|coinme|"
    r"western union|blue rhino|vendors)\b", re.I)

ZIP = re.compile(r"\b[A-Z]{2}\s+(\d{5})(?:-\d{4})?\b")


def zip_of(address):
    """The ZIP after the state ("St Joseph, MN 56374"). A bare street line has none:
    "30701 Pearl Dr" must not read as ZIP 30701."""
    m = ZIP.search(address or "")
    return m.group(1) if m else None


def phone_key(phone):
    d = re.sub(r"\D", "", phone or "")
    return d[-10:] if len(d) >= 10 else None


def street_key(address):
    m = re.match(r"\s*(\d+)\s+([A-Za-z0-9]+)", address or "")
    return f"{m.group(1)} {m.group(2).lower()}" if m else None


def collect_overture(bbox, cache, max_age_days=30, refresh=False):
    """Overture Maps places (Meta + Microsoft data, CDLA-Permissive-2.0, storable).

    Downloaded with `uvx overturemaps`; a town box comes back in seconds. Each place
    carries a confidence score and sometimes an open/closed flag, which verification
    reads as a signal.
    """
    s, w, n, e = bbox
    fresh = cache.exists() and (time.time() - cache.stat().st_mtime) / 86400 < max_age_days
    if refresh or not fresh:
        cache.parent.mkdir(parents=True, exist_ok=True)
        r = subprocess.run(["uvx", "overturemaps", "download", f"--bbox={w},{s},{e},{n}",
                            "-f", "geojson", "--type=place", "-o", str(cache)],
                           capture_output=True, text=True, timeout=600)
        Path(str(cache) + ".state").unlink(missing_ok=True)
        if r.returncode != 0 or not cache.exists():
            raise RuntimeError(f"overturemaps download failed: {(r.stderr or r.stdout)[-300:]}")
    out = []
    for f in json.loads(cache.read_text())["features"]:
        p = f["properties"]
        a = (p.get("addresses") or [{}])[0] or {}
        lon, lat = (f.get("geometry") or {}).get("coordinates", [None, None])[:2]
        out.append({
            "name": (p.get("names") or {}).get("primary"),
            "category": p.get("basic_category"),
            "website": (p.get("websites") or [None])[0],
            "phone": (p.get("phones") or [None])[0],
            "address": a.get("freeform") or "",
            "zip": (a.get("postcode") or "")[:5] or None,
            "locality": a.get("locality"),
            "lat": lat, "lon": lon, "source": "overture",
            "closed": p.get("operating_status") == "permanently_closed",
            "confidence": round(p.get("confidence") or 0, 2),
        })
    return out


def collect_sweep(label, lls, cache_dir, pages=3, refresh=False):
    """Search the map one category at a time and keep every place it shows (ADR-016).

    A map search stops at 60 results, so a city lists several viewpoints (`sweep_ll`
    as a list, one per neighbourhood) and every category is searched from each."""
    import maps
    out, failed = [], []
    lls = [lls] if isinstance(lls, str) else lls
    for ll, cat in ((ll, cat) for ll in lls for cat in SWEEP_CATEGORIES):
        for page in range(pages):
            try:
                res = maps.search(f"{cat} {label}", cache_dir / re.sub(r"[^0-9.,-]", "", ll)
                                  if len(lls) > 1 else cache_dir, ll=ll, start=page * 20,
                                  refresh=refresh)
            except Exception as ex:
                failed.append(f"{cat} p{page}: {ex}")
                break
            hs = maps.hits(res)
            for h in hs:
                out.append({
                    "name": h.get("title"), "category": h.get("type") if isinstance(
                        h.get("type"), str) else (h.get("type") or [None])[0],
                    "website": h.get("website"), "phone": h.get("phone"),
                    "address": h.get("address") or "", "zip": zip_of(h.get("address")),
                    "lat": (h.get("gps_coordinates") or {}).get("latitude"),
                    "lon": (h.get("gps_coordinates") or {}).get("longitude"),
                    "source": "maps", "closed": maps.is_closed(h),
                    "open_state": h.get("open_state"), "reviews": h.get("reviews"),
                })
            if len(hs) < 20:
                break
    if failed:
        print(f"[discover] sweep: {len(failed)} searches failed, rerun to retry: {failed[:3]}")
    return out


def collect_lakesnwoods(url):
    """lakesnwoods.com town pages: one table cell per business — bold name, then the
    street, the town line, Phone: and Web: lines."""
    _status, page = fetch(url)
    out = []
    for block in re.findall(r'<td width="305" valign="top">(.*?)</td>', page, re.S):
        lines = [re.sub(r"\s+", " ", html.unescape(TAGS.sub("", l)).replace("\xa0", " ")).strip()
                 for l in re.split(r"<br\s*/?>", block)]
        lines = [l for l in lines if l]
        if not lines:
            continue
        field = lambda tag: next((l.split(":", 1)[1].strip() for l in lines
                                  if l.startswith(tag + ":")), None)
        town_line = next((l for l in lines[1:4] if re.search(r",\s*MN\b", l)), "")
        street = lines[1] if len(lines) > 1 and lines[1] != town_line else ""
        # The link itself, not the "Web:" line: that line runs on into the description.
        href = re.search(r'href="(https?://[^"]+)"', block)
        out.append({"name": lines[0], "category": None, "website": href.group(1) if href else None,
                    "phone": field("Phone"), "address": street,
                    "zip": zip_of(town_line), "lat": None, "lon": None,
                    "source": urlparse(url).netloc})
    return out


def build_alias_map(groups):
    """alias key -> canonical (key, display name). Empty when a town declares none."""
    out = {}
    for group in groups or ():
        canon = group[0]
        for name in group:
            out[match_key(name)] = (match_key(canon), canon)
    return out


FIELDS = ("category", "website", "phone", "address", "lat", "lon")


def merge(records, aliases=None, known_distinct=(), stale=(), town_words=()):
    """Collapse sightings of one place into one roster record (ADR-018).

    Two sightings merge when their names fold to the same key, when they share a phone
    number and a distinctive word, or when they share a street number and street, their
    names clearly overlap and their phones don't disagree. Anything less certain is left
    for near_duplicates() to ask about. The town's own name is never a distinctive word:
    "City of Avon" and "Avon Police Department" share a phone and are two places.

    Fields come from non-Google sightings first (ADR-016); Google's own values are kept
    under `google` for the working list and are never written into an entry.
    """
    aliases = aliases or {}
    generic = GENERIC | set(town_words)
    by_key = {}
    for r in records:
        r = dict(r, name=" ".join(r["name"].split()))   # Overture names can carry spaces
        k = match_key(r["name"])
        seen_as = r["name"]
        if k in aliases:
            k, canon_name = aliases[k]
            r = dict(r, name=canon_name)   # one place, one name
        if not k:
            continue
        cur = by_key.get(k)
        if cur is None:
            cur = by_key[k] = {"name": r["name"], "key": k, "display_key": norm(r["name"]),
                               "sources": [], "google": {}, "signals": [],
                               "aliased": k in {v[0] for v in aliases.values()}}
            for f in FIELDS:
                cur[f] = None
        _absorb(cur, r)
        if match_key(seen_as) != k and seen_as not in cur.setdefault("aka", []):
            cur["aka"].append(seen_as)     # the registry entry remembers its other names

    # Second pass: shared phone, or same street spot with overlapping names. A phone from
    # a stale directory does not count: numbers get reassigned, and Synergistic Healing's
    # old number now rings McDonald's. Its addresses still count, because the street rule
    # also needs the names to overlap.
    places = list(by_key.values())
    distinct = {frozenset((match_key(a), match_key(b))) for a, b in known_distinct}
    parent = list(range(len(places)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    by_phone, by_street = {}, {}
    for i, p in enumerate(places):
        for s in p["signals"]:
            if phone_key(s.get("phone")) and s["source"] not in stale:
                by_phone.setdefault(phone_key(s["phone"]), []).append(i)
            if street_key(s.get("address")):
                by_street.setdefault(street_key(s["address"]), []).append(i)
    # A shared phone alone is not enough. Measured on St. Joseph, 2026-10-04: city hall's
    # number also answers for police, fire and the parks; one owner's number covers three
    # businesses; two Kwik Trips share the corporate line. So a phone match also needs a
    # distinctive word in common and no conflicting street address.
    pairs = []
    for g in by_phone.values():
        for x in range(len(g)):
            for y in range(x + 1, len(g)):
                a, b = places[g[x]], places[g[y]]
                if _share_word(a, b, generic) and not _streets_conflict(a, b):
                    pairs.append((g[x], g[y]))
    # One address holds several businesses, and "Consumer Directions" and "A New
    # Direction" at 1140 Elm St E overlap just enough by name: different phones say two.
    for g in by_street.values():
        for x in range(len(g)):
            for y in range(x + 1, len(g)):
                a, b = places[g[x]], places[g[y]]
                if _names_overlap(a, b) and not _phones_conflict(a, b, stale):
                    pairs.append((g[x], g[y]))
    members = {i: {places[i]["key"]} for i in range(len(places))}
    for i, j in pairs:
        a, b = find(i), find(j)
        # Check the whole of both groups, not just this pair: a bare "Kwik Trip" sits
        # next to both stores and would otherwise chain #147 and #575 together.
        if a == b or any(frozenset((x, y)) in distinct for x in members[a] for y in members[b]):
            continue
        parent[b] = a
        members[a] |= members.pop(b)
    groups = {}
    for i in range(len(places)):
        groups.setdefault(find(i), []).append(places[i])
    out = []
    for members in groups.values():
        # The survivor is an aliased canonical name if there is one, else the record a
        # non-Google source named, else the one most sources agree on.
        members.sort(key=lambda p: (not p["aliased"], set(p["sources"]) <= GOOGLE,
                                    -len(p["sources"])))
        head = members[0]
        for other in members[1:]:
            for s in other["signals"]:
                _absorb(head, s)
            head.setdefault("aka", []).append(other["name"])
        out.append(head)
    for p in out:
        p.pop("aliased", None)
    return out


def _absorb(cur, r):
    src = r["source"]
    if src not in cur["sources"]:
        cur["sources"].append(src)
    sig = {k: r.get(k) for k in ("source", "name", "phone", "address", "zip", "website",
                                 "closed", "confidence", "open_state", "reviews")
           if r.get(k) not in (None, "")}
    cur["signals"].append(sig)
    if src in GOOGLE:
        for f in FIELDS:
            if r.get(f) is not None and cur["google"].get(f) is None:
                cur["google"][f] = r[f]
        return
    if all(s["source"] in GOOGLE for s in cur["signals"][:-1]) and not cur.get("aliased"):
        # The first non-Google sighting names the place (ADR-016). Only the first: a
        # later one renamed the place to whatever it absorbed last.
        cur["name"], cur["display_key"] = r["name"], norm(r["name"])
    for f in FIELDS:
        if cur.get(f) is None and r.get(f) not in (None, ""):
            cur[f] = r[f]
            cur.setdefault("from", {})[f] = src


GENERIC = set("st saint joseph mn minnesota cloud of inc llc co company corp services service "
              "center centre group shop store the and park parks lake md dds dr pa phd".split())


def _share_word(a, b, generic=GENERIC):
    return bool((set(a["key"].split()) & set(b["key"].split())) - generic)


def _streets_conflict(a, b):
    sa = {street_key(s.get("address")) for s in a["signals"]} - {None}
    sb = {street_key(s.get("address")) for s in b["signals"]} - {None}
    return bool(sa and sb and not sa & sb)


def _phones_conflict(a, b, stale=()):
    def phones(p):
        return {phone_key(s.get("phone")) for s in p["signals"] if s["source"] not in stale}
    pa, pb = phones(a) - {None}, phones(b) - {None}
    return bool(pa and pb and not pa & pb)


def _names_overlap(a, b):
    ta, tb = set(a["key"].split()), set(b["key"].split())
    if len(ta & tb) >= 2 and (ta <= tb or tb <= ta):
        return True
    return SequenceMatcher(None, a["display_key"], b["display_key"]).ratio() >= 0.75


def near_duplicates(roster, known_distinct=(), stale=(), town_words=()):
    """Report pairs a human should look at. Never merged automatically."""
    out, keys = [], [r["key"] for r in roster]
    toks = [set(k.split()) for k in keys]
    settled = {frozenset((match_key(a), match_key(b))) for a, b in known_distinct}
    for i in range(len(keys)):
        for j in range(i + 1, len(keys)):
            a, b = keys[i], keys[j]
            # A strict subset is the shape of "Sal's Bar" against "Sal's Bar and Grill",
            # or "The Wandering Cow" against "Wandering Cow Ice Cream" — usually one
            # place written two ways, but NOT always ("Memorial Park" is not "Park"),
            # so it is reported and never merged. Needs 2+ shared words to be worth
            # raising at all.
            if frozenset((a, b)) in settled:
                continue
            if toks[i] and toks[j] and toks[i] != toks[j] and \
               (toks[i] < toks[j] or toks[j] < toks[i]) and min(len(toks[i]), len(toks[j])) >= 2:
                out.append((1.0, roster[i]["name"], roster[j]["name"]))
                continue
            if abs(len(a) - len(b)) > 12:
                continue
            ratio = SequenceMatcher(None, a, b).ratio()
            if ratio >= NEAR_DUPLICATE:
                out.append((round(ratio, 3), roster[i]["name"], roster[j]["name"]))
    out.sort(reverse=True)
    # Places that share a phone, or a street spot and a distinctive word, but were too
    # unsure to merge (ADR-018): one owner's two businesses, or one business renamed.
    # A phone shared by more than three places is a switchboard (city hall), not a clue.
    asked = {frozenset(p[1:]) for p in out}
    generic = GENERIC | set(town_words)
    for why, field, key in (("same phone", "phone", phone_key),
                            ("same street", "address", street_key)):
        groups = {}
        for i, p in enumerate(roster):
            for s in p["signals"]:
                if key(s.get(field)) and not (field == "phone" and s["source"] in stale):
                    groups.setdefault(key(s[field]), set()).add(i)
        for g in groups.values():
            if field == "phone" and len(g) > 3:
                continue
            for i in sorted(g):
                for j in sorted(g):
                    a, b = roster[i], roster[j]
                    if i >= j or frozenset((a["key"], b["key"])) in settled or \
                            frozenset((a["name"], b["name"])) in asked or \
                            (field == "address" and not _share_word(a, b, generic)):
                        continue
                    asked.add(frozenset((a["name"], b["name"])))
                    out.append((why, a["name"], b["name"]))
    return out


def entry_md(rec, added_by="agent:discover", note=""):
    """A `proposed`, `listed` draft for one place. Only non-Google fields go in (ADR-016)."""
    slug = re.sub(r"[^a-z0-9]+", "-", norm(rec["name"])).strip("-")[:40]
    url = (rec.get("website") or "TODO").split()[0]
    if url != "TODO" and not url.startswith(("http://", "https://")):
        url = "https://" + url            # Overture and directories often drop the scheme
    method = "fetch" if url != "TODO" else "submission"
    lines = [f"## {rec['name']}", "```yaml", f"id: {slug}", "status: proposed",
             "tier: listed"]
    if rec.get("category"):
        lines.append(f"category: {json.dumps(rec['category'])}")
    for k in ("place_type", "address", "phone"):
        if rec.get(k):
            lines.append(f"{k}: {json.dumps(rec[k])}")
    if rec.get("aka"):
        lines.append(f"aka: {json.dumps(sorted(set(rec['aka'])))}")
    lines += [f"added_by: {added_by}", "sources:",
              f"  - url: {url}", "    kind: website", f"    method: {method}",
              "    trust: official", "```"]
    prov = ", ".join(s for s in rec["sources"] if s not in GOOGLE) or "a Google Maps sweep"
    todo = ("" if url != "TODO" else
            " No URL was found, so this is `submission`: it waits on the owner rather "
            "than guessing an address (ADR-007).")
    lines.append(f"Notes: Proposed on {datetime.now(timezone.utc):%Y-%m-%d} from {prov}."
                 f"{todo}{note} Unreviewed — tier `listed`, so it publishes nothing until "
                 f"promoted.")
    return "\n".join(lines)


def in_town(rec, zips, elsewhere=(), aliases=None):
    """ADR-019. A sighting with a ZIP belongs to the town that lists it. One without a
    ZIP stays only if it came from a town-scoped source (the OSM box, a town directory),
    and no source with a ZIP puts the place in another town only (`elsewhere`, from
    placed_elsewhere): the chamber lists Wacosa and the St. Cloud Area Chamber as
    members. A map result with no address is a service-area business that could be
    anywhere."""
    z = rec.get("zip") or zip_of(rec.get("address"))
    if z is None:
        return rec["source"] not in GOOGLE and place_key(rec, aliases) not in elsewhere
    return z in zips


def place_key(rec, aliases=None):
    k = match_key(rec["name"])
    return (aliases or {}).get(k, (k,))[0]


def placed_elsewhere(records, zips, aliases=None):
    """Keys of places whose every sighting with a ZIP carries another town's."""
    here, away = set(), set()
    for r in records:
        z = r.get("zip") or zip_of(r.get("address"))
        if z:
            (here if z in zips else away).add(place_key(r, aliases))
    return away - here


def build_roster(town, refresh=False):
    """Every collector, filtered to the town and merged. Returns (roster, notes)."""
    cache = RUNS / "cache"
    records, notes = [], []
    collectors = [
        ("osm", lambda: collect_osm(town["bbox"], town.get("osm_min_elements", 1),
                                    cache=cache / f"osm-{town['id']}.json", refresh=refresh)),
        ("overture", lambda: collect_overture(town.get("overture_bbox", town["bbox"]),
                                              cache / f"overture-{town['id']}.geojson",
                                              refresh=refresh)),
    ]
    if town.get("sweep_ll"):
        collectors.append(("maps", lambda: collect_sweep(
            town["label"], town["sweep_ll"], cache / "maps" / town["id"], refresh=refresh)))
    for d in town["directories"]:
        if d.get("collector") == "chamber":
            fn = lambda d=d: collect_chamber(d["url"], cache / "chamber.json")
        elif d.get("collector") == "lakesnwoods":
            fn = lambda d=d: collect_lakesnwoods(d["url"])
        else:
            fn = lambda d=d: collect_directory(d["url"])
        collectors.append((d["id"], fn))
    town_key = match_key(re.sub(r"\s+[A-Z]{2}$", "", town["label"]))
    aliases = build_alias_map(town.get("aliases"))
    got_by = []
    for name, fn in collectors:
        try:
            got_by.append((name, [r for r in fn() if r.get("name")]))
        except Exception as ex:
            notes.append(f"{name}: FAILED ({ex})")
    elsewhere = placed_elsewhere([r for _, got in got_by for r in got], town["zips"], aliases)
    for name, got in got_by:
        kept = [r for r in got if in_town(r, town["zips"], elsewhere, aliases)
                # Overture's box is wider than the town, so a row with no ZIP needs the
                # town's own name as its locality (Rockville parks came in without one).
                and not (r["source"] == "overture" and not r.get("zip") and
                         match_key(r.get("locality") or "") != town_key)]
        notes.append(f"{name}: {len(kept)}" + (f" of {len(got)}" if len(kept) != len(got) else ""))
        records += kept
    # The town's own name comes back as a map result ("St Joseph"); it is not a place.
    skip = {match_key(n) for n in town.get("not_places", ())} | {
        match_key(re.sub(r"\s+[A-Z]{2}$", "", town["label"]))}
    # Lakes and rivers are geography, not places that open or close.
    records = [r for r in records if match_key(r["name"]) not in skip
               and not NOT_A_PLACE.search(f"{r['name']} {r.get('category') or ''}")
               and (r.get("category") or "") not in ("lake", "river", "body_of_water")
               and not re.search(r"\bLake$", r["name"])]
    roster = merge(records, aliases, town.get("known_distinct", ()), stale_hosts(town),
                   town_words(town))
    return roster, notes


def stale_hosts(town):
    return {urlparse(d["url"]).netloc for d in town["directories"] if d.get("stale")}


def town_words(town):
    """The town's name ("avon"), never a distinctive word between two of its places."""
    return norm(town["label"]).split()


def changes_since(old, new):
    """What a run changed against the last one: places come and gone, other names gained."""
    o, n = {p["key"]: p for p in old}, {p["key"]: p for p in new}
    out = [f"+ {n[k]['name']}" for k in n.keys() - o.keys()]
    out += [f"- {o[k]['name']}" for k in o.keys() - n.keys()]
    for k in n.keys() & o.keys():
        gained = set(n[k].get("aka", [])) - set(o[k].get("aka", []))
        if gained:
            out.append(f"= {n[k]['name']} now also: {', '.join(sorted(gained))}")
    return sorted(out, key=lambda line: line[2:])


def registry_keys(entries):
    have = {match_key(e["_name"]) for e in entries}
    have |= {match_key(e.get("id", "").replace("-", " ")) for e in entries}
    # `aka:` is how a human settles "same place, different name" permanently. No rule can
    # know that Kennedy Elementary and Kennedy Community School are one school, so the
    # entry says so and discovery stops re-proposing it every month (ADR-007: additive).
    for e in entries:
        for alias in (e.get("aka") or []):
            have.add(match_key(alias))
    return have


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--town", default="st-joseph-mn")
    ap.add_argument("--root", default=".")
    ap.add_argument("--refresh", action="store_true",
                    help="re-fetch Overpass, Overture and every map search (~240 Composio "
                         "calls); the chamber's saved list is kept either way")
    args = ap.parse_args()

    town = TOWNS.get(args.town)
    if not town:
        sys.exit(f"no discovery config for town {args.town!r}")
    town = dict(town, id=args.town)

    root = find_root(args.root)
    entries, _ = load(root)
    entries = [e for e in entries if e.get("_town") == args.town]
    have = registry_keys(entries)
    roster, notes = build_roster(town, refresh=args.refresh)

    def held(r):
        return r["key"] in have or any(match_key(a) in have for a in r.get("aka", ()))
    missing = [r for r in roster if not held(r)]
    events = [r for r in missing if looks_like_event(r["name"])]
    places = [r for r in missing if not looks_like_event(r["name"])]
    google_only = [r for r in places if set(r["sources"]) <= GOOGLE]
    dupes = near_duplicates(roster, town.get("known_distinct", ()), stale_hosts(town),
                            town_words(town))

    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    out_dir = RUNS / f"discover-{stamp}"
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "roster.json").write_text(json.dumps(roster, indent=1, ensure_ascii=False))
    (out_dir / "missing.json").write_text(json.dumps(
        sorted(places, key=lambda r: r["name"]), indent=1, ensure_ascii=False))
    (out_dir / "same-place.json").write_text(json.dumps(dupes, indent=1, ensure_ascii=False))
    (out_dir / "events.md").write_text(
        "# Looks like an EVENT, not a place (ADR-013)\n\n"
        "Routed here rather than dropped. The test is a heuristic and it is wrong in both\n"
        "directions — move anything that is really a place back into the town file.\n\n"
        + "\n".join(f"- {r['name']}  ({', '.join(r['sources'])})"
                    for r in sorted(events, key=lambda r: r["name"])))

    # A stable path beside the timestamped run, so the newest lists are findable without
    # knowing today's timestamp. The dated folders stay as the history.
    latest = RUNS / f"latest-{town['id']}"
    before = latest / "roster.json"
    changed = changes_since(json.loads(before.read_text()), roster) if before.exists() else None
    try:
        if latest.is_symlink() or latest.exists():
            latest.unlink()
        latest.symlink_to(out_dir, target_is_directory=True)
    except OSError:
        pass

    print(f"[discover] {'  '.join(notes)}")
    print(f"roster {len(roster)} | registry {len(entries)} | MISSING {len(missing)}"
          f"  ({len(places)} places, {len(google_only)} known only to Google, "
          f"{len(events)} look like events)")
    coverage = 100 * (len(roster) - len(missing)) / max(len(roster), 1)
    print(f"coverage {coverage:.0f}% of the roster is in the registry")
    for a in town.get("agent_only", []):
        print(f"  AGENT   {a['id']}: {a['url']} — {a['why']}")
    if dupes:
        print(f"  {len(dupes)} possible duplicate pair(s) — NOT merged, settle by hand "
              f"(same-place.json)")
    if changed is not None:
        print(f"since the last run: {len(changed)} change(s)" if changed else
              "since the last run: nothing changed")
        for line in changed:
            print(f"  {line}")
    print(f"next: sources/verify --town {args.town}   (roster: {out_dir / 'roster.json'})")


if __name__ == "__main__":
    main()
