-- ============================================================================
-- Initial Today briefing content pool: 60 neighborly poll prompts and five
-- curated St. Joseph place spotlights. No dated briefings, featured events, or
-- votes are fabricated here; Phase 2 assigns and publishes real daily content.
-- ============================================================================

with poll_seed as (
    select seed.kind, seed.prompt, seed.options
    from jsonb_to_recordset(
        $polls$
        [
          { "kind": "poll", "prompt": "First real snow of the season. What's your move?", "options": ["Shovel immediately", "Wait and see if it melts", "Pay the neighbor kid", "Stand in it for a minute first"] },
          { "kind": "poll", "prompt": "Correct time to put the outdoor lights up:", "options": ["Before Thanksgiving", "The weekend after", "First week of December", "They never came down"] },
          { "kind": "poll", "prompt": "It's 34 and sunny in March. You are:", "options": ["In shorts", "Light jacket", "Still in the parka", "Outside doing nothing in particular"] },
          { "kind": "poll", "prompt": "Best month in St. Joe:", "options": ["September", "June", "October", "February, and I'll explain why"] },
          { "kind": "poll", "prompt": "The Lake Wobegon Trail is for:", "options": ["Walking", "Biking", "Running", "Driving past and feeling guilty"] },
          { "kind": "poll", "prompt": "Hotdish or casserole?", "options": ["Hotdish, obviously", "Casserole", "Depends who's asking", "I just call it dinner"] },
          { "kind": "poll", "prompt": "The only correct hotdish topping:", "options": ["Tater tots", "French-fried onions", "Crushed chips", "Leave it alone"] },
          { "kind": "poll", "prompt": "What are you bringing to the potluck?", "options": ["Bars", "A salad that is mostly Cool Whip", "Something from the meat market", "Ice, and no apologies"] },
          { "kind": "poll", "prompt": "How early do you claim your parade spot?", "options": ["Chairs out the night before", "An hour early", "Ten minutes, standing", "I watch from my own yard"] },
          { "kind": "poll", "prompt": "Someone waves at you from a passing car. You:", "options": ["Wave back, no idea who", "Wave and figure it out later", "Squint first, then wave", "Full two-hand wave"] },

          { "kind": "poll", "prompt": "Best sound of a St. Joe summer:", "options": ["Church bells", "A screen door", "Distant lawnmower", "Kids at the pool"] },
          { "kind": "poll", "prompt": "How do you take your sweet corn?", "options": ["Butter and salt, done", "Butter, salt, pepper", "Straight off the cob, dry", "Cut off, in a bowl"] },
          { "kind": "poll", "prompt": "Garage door: open or closed?", "options": ["Open all summer", "Closed always", "Open when I'm home", "Depends on the mess"] },
          { "kind": "poll", "prompt": "The bonfire is lit. Your seat:", "options": ["Closest to the fire", "Upwind, always", "Wherever the chair is", "Standing, poking the fire"] },
          { "kind": "poll", "prompt": "Best way to spend a 78-degree Saturday:", "options": ["On the trail", "In the yard", "On the water", "Doing absolutely nothing"] },
          { "kind": "poll", "prompt": "Farmers market strategy:", "options": ["Lap the whole thing first", "Buy the first good thing", "Straight to the one booth", "I'm here for the dog watching"] },
          { "kind": "poll", "prompt": "Screen door slams. Who is it?", "options": ["Kids", "Dog", "Wind", "Someone who should have knocked"] },
          { "kind": "poll", "prompt": "Sweet corn season: how many ears is too many?", "options": ["There is no such number", "A dozen", "Two per person", "I freeze the rest"] },
          { "kind": "poll", "prompt": "Best local swimming decision:", "options": ["Lake", "Pool", "Sprinkler", "Air conditioning"] },
          { "kind": "poll", "prompt": "The grill comes out when:", "options": ["April, no matter what", "First 60-degree day", "Memorial Day", "It never went in"] },

          { "kind": "poll", "prompt": "Snow emergency parking: how do you find out?", "options": ["City alert", "Facebook", "Neighbor tells me", "The ticket on my windshield"] },
          { "kind": "poll", "prompt": "Winter windshield method:", "options": ["Scrape the whole thing", "Scrape a porthole and go", "Remote start, wait it out", "Credit card and hope"] },
          { "kind": "poll", "prompt": "How cold before you plug the car in?", "options": ["Zero", "Ten below", "Twenty below", "I don't have a block heater"] },
          { "kind": "poll", "prompt": "The correct number of blankets in a Minnesota winter:", "options": ["Two", "Three", "Four", "However many are on the couch"] },
          { "kind": "poll", "prompt": "First 50-degree day in spring. You:", "options": ["Open every window", "Wash the car", "Sit outside doing nothing", "Start the yard work"] },
          { "kind": "poll", "prompt": "Ice-out prediction. When does it go?", "options": ["Early April", "Mid April", "Late April", "Later than you think"] },
          { "kind": "poll", "prompt": "Best winter comfort move:", "options": ["Soup", "A long shower", "Sitting by a window", "Going outside on purpose"] },
          { "kind": "poll", "prompt": "Shoveling philosophy:", "options": ["Every few inches", "Once, at the end", "Snowblower or nothing", "Whenever I get to it"] },
          { "kind": "poll", "prompt": "How do you feel about November?", "options": ["Cozy", "Bleak", "Underrated", "It's fine, it's a month"] },
          { "kind": "poll", "prompt": "The first robin means:", "options": ["Spring is here", "Nothing, it'll snow again", "Time to plan the garden", "I hadn't noticed"] },

          { "kind": "poll", "prompt": "How long have you been in St. Joe?", "options": ["Born here", "Over ten years", "A few years", "Just moved"] },
          { "kind": "poll", "prompt": "How do you get around town?", "options": ["Drive", "Walk", "Bike", "Depends on the weather"] },
          { "kind": "poll", "prompt": "Best thing about a small town:", "options": ["You know people", "It's quiet", "Everything's close", "You can leave easily"] },
          { "kind": "poll", "prompt": "Hardest thing about a small town:", "options": ["Everyone knows you", "Not enough to do", "The drive to anything", "Nothing, it's great"] },
          { "kind": "poll", "prompt": "What should St. Joe have more of?", "options": ["Places to eat", "Places to gather", "Things for kids", "Nothing, it's right"] },
          { "kind": "poll", "prompt": "How do you find out what's happening in town?", "options": ["Facebook", "Word of mouth", "A flyer somewhere", "I usually don't"] },
          { "kind": "poll", "prompt": "Do you know your neighbors' names?", "options": ["All of them", "Most", "One or two", "Not a single one"] },
          { "kind": "poll", "prompt": "Best local errand:", "options": ["The meat market", "Coffee", "Hardware store", "The post office, honestly"] },
          { "kind": "poll", "prompt": "Would you go to a town block party?", "options": ["Absolutely", "If a friend went", "I'd walk past and look", "Not my thing"] },
          { "kind": "poll", "prompt": "How far is 'too far to drive' for dinner?", "options": ["Ten minutes", "Twenty", "St. Cloud is fine", "The Cities if it's good"] },

          { "kind": "poll", "prompt": "College town energy: how do you feel about it?", "options": ["Love it", "Like it in small doses", "Neutral", "Quieter in summer, and I like that"] },
          { "kind": "poll", "prompt": "Best season to have people over:", "options": ["Summer", "Fall", "Winter", "Whenever the house is clean"] },
          { "kind": "poll", "prompt": "The right amount of small talk at the checkout:", "options": ["A full conversation", "A few sentences", "A nod", "Depends on the line behind me"] },
          { "kind": "poll", "prompt": "Church bells: do you hear them from your place?", "options": ["Every time", "If the window's open", "Faintly", "Never noticed"] },
          { "kind": "poll", "prompt": "Best time of day around here:", "options": ["Early morning", "Late afternoon", "Right after sunset", "Late at night"] },
          { "kind": "poll", "prompt": "You have a free Saturday and no plans. You:", "options": ["Make plans", "Enjoy having none", "Yard work", "Leave town"] },
          { "kind": "poll", "prompt": "Best local smell:", "options": ["Cut grass", "Bakery", "Rain on hot pavement", "Woodsmoke"] },
          { "kind": "poll", "prompt": "How do you feel about a 6 AM start?", "options": ["Best part of the day", "Only if I have to", "Absolutely not", "I'm already up"] },
          { "kind": "poll", "prompt": "Where do you take an out-of-town guest first?", "options": ["The trail", "Somewhere to eat", "A drive around", "Nowhere, we stay in"] },
          { "kind": "poll", "prompt": "What time is dinner?", "options": ["5:00", "5:30", "6:00", "Whenever"] },

          { "kind": "poll", "prompt": "Correct response to 'ope':", "options": ["'Ope' back", "Step aside", "Nothing, keep moving", "I don't say ope"] },
          { "kind": "poll", "prompt": "Long goodbye at the door: how long?", "options": ["Five minutes", "Fifteen", "Half an hour", "We're still in the driveway"] },
          { "kind": "poll", "prompt": "Duck, duck —", "options": ["Gray duck", "Goose", "I've heard both", "This debate is exhausting"] },
          { "kind": "poll", "prompt": "Pop or soda?", "options": ["Pop", "Soda", "By the brand name", "Water, I'm boring"] },
          { "kind": "poll", "prompt": "Best pie:", "options": ["Apple", "Rhubarb", "Pumpkin", "Whatever's in front of me"] },
          { "kind": "poll", "prompt": "How do you feel about a parade?", "options": ["Love a parade", "It's fine", "Too much candy", "I'm in the parade"] },
          { "kind": "poll", "prompt": "Best free thing to do around here:", "options": ["Walk the trail", "Sit by water", "Drive with the windows down", "Watch the sky"] },
          { "kind": "poll", "prompt": "You find $20 in a coat pocket. You:", "options": ["Spend it in town", "Save it", "Buy someone coffee", "Forget it again"] },
          { "kind": "poll", "prompt": "Best day of the week:", "options": ["Friday", "Saturday", "Sunday", "Thursday, quietly"] },
          { "kind": "poll", "prompt": "Honest answer: how's your week going?", "options": ["Great", "Fine", "Long", "Ask me Friday"] }
        ]
        $polls$::jsonb
    ) as seed (kind text, prompt text, options jsonb)
)
insert into public.daily_touches (kind, prompt, options, used_on)
select poll_seed.kind, poll_seed.prompt, poll_seed.options, null
from poll_seed
where poll_seed.kind = 'poll'
  and not exists (
      select 1
      from public.daily_touches existing
      where existing.prompt = poll_seed.prompt
  );

insert into public.spotlights (
    slug,
    title,
    blurb,
    image_url,
    place_id,
    active
)
values
    (
        'downtown',
        'Downtown',
        'A few walkable blocks of Minnesota Street: locally-owned coffee, a deli, a brewery taproom, and storefronts where the person behind the counter tends to know your order.',
        null,
        null,
        true
    ),
    (
        'saint-bens',
        'Saint Ben''s',
        'A Benedictine women''s liberal-arts college on the north edge of town, founded in 1887. The concerts, lectures and games here are open to neighbors.',
        null,
        null,
        true
    ),
    (
        'sacred-heart-chapel',
        'Sacred Heart Chapel',
        'The copper dome you can spot from the highway. It stands at the heart of Saint Benedict''s Monastery, and it is open for prayer and song.',
        null,
        null,
        true
    ),
    (
        'saint-johns',
        'Saint John''s',
        'Just west in Collegeville: Marcel Breuer''s soaring concrete bell banner, 2,700 acres of woods, prairie and lake, and arboretum trails open to wander.',
        null,
        null,
        true
    ),
    (
        'wobegon-trail',
        'Wobegon Trail',
        'A flat, paved rail-trail that runs right through town, named for Garrison Keillor''s fictional hometown.',
        null,
        null,
        true
    )
on conflict (slug) do nothing;
