// Fixed stories for team_activities and activity_has_event (supabase/migrations/*_team_activities.sql):
// each local school's approved activities, and which of them a game belongs to, run in PGlite under the
// live read rules (BP app docs/plans/school-activities, ticket 01). Run: `npm install && npm test` here.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { realDatabase } from './fixture.mjs';

const db = await realDatabase();
await db.exec(`
  insert into public.teams (id, name, short_name, local) values
    ('apollo', 'Apollo', 'Apollo', true), ('tech', 'Tech', 'Tech', true),
    ('cathedral', 'Cathedral', 'Cathedral', true), ('apollo-cathedral', 'Apollo-Cathedral', 'Apollo-Cathedral', true),
    ('rocori', 'ROCORI', 'ROCORI', true), ('sartell', 'Sartell', 'Sartell', true),
    ('sauk-rapids-rice', 'Sauk Rapids-Rice', 'Sauk Rapids-Rice', true),
    ('saint-benedict', 'Saint Benedict', 'Saint Benedict', true), ('saint-johns', 'Saint John''s', 'Saint John''s', true),
    ('albany', 'Albany', 'Albany', false)
  on conflict (id) do nothing;
`);
// The activities of `school` that a game of `sport` between `teams` belongs to, as anyone reads them.
async function activitiesOf(school, sport, teams) {
  await db.exec('set role anon');
  const { rows } = await db.query(
    `select a.name from public.team_activities a,
       jsonb_populate_record(null::public.club_events, jsonb_build_object('title', 'game', 'sport', $2::text, 'team_ids', $3::text[])) e
     where a.team_id = $1 and public.activity_has_event(a, e) order by a.sort`,
    [school, sport, teams]);
  await db.exec('reset role');
  return rows.map((r) => r.name);
}

test('a gendered game is the school activity of that sport and gender', async () => {
  assert.deepEqual(await activitiesOf('apollo', 'Girls Soccer', ['apollo', 'albany']), ['Girls Soccer']);
  assert.deepEqual(await activitiesOf('rocori', 'Boys Soccer', ['albany', 'rocori']), ['Soccer (boys)']);
  assert.deepEqual(await activitiesOf('rocori', 'Girls Swim', ['rocori', 'albany']), ['Swimming & Diving - Girls']);
});

test('a sport that says its level is still that sport', async () => {
  assert.deepEqual(await activitiesOf('apollo', 'Girls Soccer · JV', ['apollo', 'albany']), ['Girls Soccer']);
  assert.deepEqual(await activitiesOf('rocori', 'Girls Swim · Middle school', ['rocori', 'albany']), ['Swimming & Diving - Girls']);
  assert.deepEqual(await activitiesOf('apollo', 'Volleyball · C-squad', ['apollo', 'albany']), ['Volleyball (girls)']);
});

test("a school's own calendar names its activity's games, whatever team plays them", async () => {
  await db.exec('set role anon');
  const { rows } = await db.query(
    `select a.team_id, a.name from public.team_activities a,
       jsonb_populate_record(null::public.club_events, jsonb_build_object('title', 'game', 'sport', 'Boys Swim · JV',
         'team_ids', array['st-cloud-rocori', 'albany']::text[], 'activity_team', 'apollo')) e
     where public.activity_has_event(a, e) order by 1, 2`);
  await db.exec('reset role');
  assert.deepEqual(rows, [{ team_id: 'apollo', name: 'Boys Swim & Dive' },
                          { team_id: 'cathedral', name: 'Boys Swim & Dive' },
                          { team_id: 'kennedy', name: 'Boys Swimming 7-12' },
                          { team_id: 'rocori', name: 'Swimming & Diving - Boys' },
                          { team_id: 'tech', name: 'Boys Swim & Dive' }], 'the St. Cloud-ROCORI co-op is all five (school-search 08)');
});

test("a game's words for a sport meet the school's: Dance Team is Dance, Rugby is SJU Rugby", async () => {
  assert.deepEqual(await activitiesOf('apollo', 'Dance Team', ['apollo', 'albany']), ['Dance']);
  assert.deepEqual(await activitiesOf('saint-johns', 'Rugby', ['saint-johns', 'albany']), ['SJU Rugby']);
  assert.deepEqual(await activitiesOf('saint-johns', 'Swimming and Diving', ['saint-johns', 'albany']), ['Swimming and Diving']);
});

test("a game naming no gender is the school's own row for that sport", async () => {
  assert.deepEqual(await activitiesOf('cathedral', 'Volleyball', ['cathedral', 'albany']), ['Volleyball (girls)']);
  assert.deepEqual(await activitiesOf('apollo', 'Volleyball', ['apollo', 'albany']), ['Volleyball (girls)']);
});

test("Kennedy's grade 7-12 rows take Apollo's games, and only the right ones", async () => {
  assert.deepEqual(await activitiesOf('kennedy', 'Girls Swim', ['apollo', 'albany']), ['Girls Swimming 7-12']);
  assert.deepEqual(await activitiesOf('kennedy', 'Volleyball', ['apollo', 'albany']), []);
  assert.deepEqual(await activitiesOf('kennedy', 'Volleyball', ['kennedy', 'albany']), ['Volleyball 6-8 (girls)']);
});

// Every school's activities a calendar event belongs to, as "team: name".
async function activitiesFor(fields) {
  await db.exec('set role anon');
  const { rows } = await db.query(
    `select a.team_id || ': ' || a.name as x from public.team_activities a,
       jsonb_populate_record(null::public.club_events, $1::jsonb) e
     where public.activity_has_event(a, e) order by a.team_id, a.sort`,
    [JSON.stringify({ title: 'event', ...fields })]);
  await db.exec('reset role');
  return rows.map((r) => r.x);
}

test("Bound's Nordic Ski Racing is the schools' Nordic Skiing, by gender, Apollo's for its co-op (school-search 02, 08)", async () => {
  assert.deepEqual(await activitiesFor({ activity_team: 'apollo', activity_name: 'Nordic Ski Racing, Boys' }),
                   ['apollo: Boys Nordic Skiing', 'kennedy: Boys/Girls Nordic Skiing', 'rocori: Nordic Ski Racing - Boys',
                    'tech: Boys Nordic Skiing']);
  assert.deepEqual(await activitiesFor({ activity_team: 'apollo', activity_name: 'Girls Nordic Ski' }),
                   ['apollo: Girls Nordic Skiing', 'kennedy: Boys/Girls Nordic Skiing', 'rocori: Nordic Ski Racing - Girls',
                    'tech: Girls Nordic Skiing']);
  assert.deepEqual(await activitiesFor({ activity_team: 'sauk-rapids-rice', activity_name: 'Nordic Ski Racing, Boys' }),
                   ['sauk-rapids-rice: Nordic Skiing (boys)']);
});

test("Kennedy's own calendar lands on its activity, a joint concert on each it names (school-search 02)", async () => {
  const kennedy = (activity_name) => activitiesFor({ activity_team: 'kennedy', activity_name });
  assert.deepEqual(await kennedy('Band/Choir/Orchestra'), ['kennedy: Band', 'kennedy: Choir', 'kennedy: Orchestra']);
  assert.deepEqual(await kennedy('Orchestra'), ['kennedy: Orchestra']);
  assert.deepEqual(await kennedy('Knowledge Bowl'), ['kennedy: Knowledge Bowl 6-8']);
  assert.deepEqual(await kennedy('Spelling Bee'), ['kennedy: Spelling Bee']);
  assert.deepEqual(await kennedy('PTO'), ['kennedy: PTO (Kennedy Community School Parent Teacher Organization)']);
  assert.deepEqual(await kennedy('Musical/One Act'), ['kennedy: Musical/One Act 6-8']);
  assert.deepEqual(await kennedy('Band/Spelling Bee/Rugby'), ['kennedy: Band', 'kennedy: Spelling Bee']);
});

test("Tech's own calendar and the music department's page land on their ensemble's row (nothing-scheduled 01)", async () => {
  assert.deepEqual(await activitiesFor({ activity_team: 'tech', activity_name: 'Choir' }), ['tech: Choir'],
                   'Tech Choir Concert: its Choir, not its Chamber Choir');
  assert.deepEqual(await activitiesFor({ activity_team: 'tech', activity_name: 'Band' }), ['tech: Band'],
                   'Tech Band Concert: its Band, not its Jazz or Pep Band');
  assert.deepEqual(await activitiesFor({ activity_team: 'saint-johns', activity_name: 'Guitar Ensemble' }),
                   ["saint-johns: Guitar Ensemble"], 'Guitar Ensemble & Studio Concert, Gertken Organ Studio, SJU');
  assert.deepEqual(await activitiesFor({ activity_team: 'saint-johns', activity_name: 'All-College Choir' }),
                   ["saint-johns: All-College Choir"]);
  assert.deepEqual(await activitiesFor({ activity_team: 'saint-benedict', activity_name: "Women's Choir" }),
                   ["saint-benedict: Women's Choir"]);
  assert.deepEqual(await activitiesFor({ activity_team: 'saint-johns', activity_name: "Men's Chorus" }),
                   ["saint-johns: Men's Chorus"]);
});

test("Kennedy's Adapted Floor Hockey takes St. Cloud's games from Apollo's feed, as Apollo's own does (school-search 02, 07)", async () => {
  assert.deepEqual(await activitiesFor({ sport: 'Adapted Floor Hockey', team_ids: ['maple-grove', 'st-cloud'], activity_team: 'apollo' }),
                   ['apollo: Adapted Hockey (Adapted Floor Hockey)', 'kennedy: Boys/Girls Adapted Floor Hockey',
                    'sartell: Adapted Floor Hockey', 'sauk-rapids-rice: Adapted Sports: Floor Hockey', 'tech: Adapted Hockey'],
                   'St. Cloud Area Crush is Apollo, Tech, Sartell and Sauk Rapids-Rice (school-search 08)');
});

test("Adapted Floor Hockey is each school's adapted hockey, whatever it calls it (school-search 07)", async () => {
  assert.deepEqual(await activitiesFor({ sport: 'Adapted Floor Hockey', activity_team: 'tech' }), ['tech: Adapted Hockey']);
  assert.deepEqual(await activitiesFor({ sport: 'Adapted Floor Hockey', activity_team: 'sauk-rapids-rice' }),
                   ['sauk-rapids-rice: Adapted Sports: Floor Hockey']);
  assert.deepEqual(await activitiesFor({ sport: 'Adapted Soccer', activity_team: 'sauk-rapids-rice' }),
                   ['sauk-rapids-rice: Adapted Sports: Soccer']);
  assert.deepEqual(await activitiesFor({ sport: 'Adapted Floor Hockey', activity_team: 'sartell' }), ['sartell: Adapted Floor Hockey']);
});

test("a middle school coed meet is the school's own sport (school-search 07)", async () => {
  assert.deepEqual(await activitiesFor({ activity_team: 'sauk-rapids-rice', activity_name: 'MS Coed Wrestling' }),
                   ['sauk-rapids-rice: Wrestling']);
  assert.deepEqual(await activitiesFor({ sport: 'MS Coed Wrestling', team_ids: ['alexandria', 'sauk-rapids-rice'] }),
                   ['sauk-rapids-rice: Wrestling']);
});

test("an activity's bracket list names what it covers, unless the school has that activity itself (school-search 07)", async () => {
  const srr = (activity_name) => activitiesFor({ activity_team: 'sauk-rapids-rice', activity_name });
  const theatre = 'sauk-rapids-rice: Theatre (Fall Musical, One-Act Play, Spring Play)';
  assert.deepEqual(await srr('One Act Play'), [theatre]);
  assert.deepEqual(await srr('Musical'), [theatre]);
  assert.deepEqual(await srr('Band'), ['sauk-rapids-rice: Band']);
  assert.deepEqual(await activitiesFor({ activity_team: 'sartell', activity_name: 'One Act Play' }), ['sartell: One Act Play']);
  assert.deepEqual(await activitiesFor({ activity_team: 'tech', activity_name: 'Spanish' }), ['tech: Language Clubs (French, Spanish)']);
  assert.deepEqual(await activitiesFor({ activity_team: 'tech', activity_name: 'Language Clubs' }), ['tech: Language Clubs (French, Spanish)']);
  assert.deepEqual(await activitiesOf('rocori', 'Boys Soccer', ['albany', 'rocori']), ['Soccer (boys)'], 'a bracket of one stays out');
  assert.deepEqual(await activitiesFor({ activity_team: 'cathedral', activity_name: 'Art Club' }), ['cathedral: Art Club']);
  assert.deepEqual(await activitiesFor({ activity_team: 'sartell', activity_name: 'Orchestra' }), ['sartell: Orchestra']);
  assert.deepEqual(await activitiesFor({ sport: 'Musical', team_ids: ['sauk-rapids-rice'] }), [], 'a game never reads a bracket');
});

test("a co-op's game lands on every member school's activity, and the school's own games stay (school-search 08)", async () => {
  // As Apollo's Bound feed writes St. Cloud's girls hockey: the co-op, the opponent, the host.
  assert.deepEqual(await activitiesFor({ sport: 'Hockey, Girls', team_ids: ['st-cloud', 'fergus-falls', 'apollo'] }),
                   ['apollo: Girls Hockey', 'cathedral: Girls Hockey', 'tech: Girls Hockey']);
  assert.deepEqual(await activitiesFor({ sport: 'Boys Hockey · JV', team_ids: ['st-cloud', 'roseau'] }),
                   ['apollo: Boys Hockey', 'tech: Boys Hockey'], "Cathedral's boys hockey is its own team");
  assert.deepEqual(await activitiesFor({ sport: 'Gymnastics, Girls', team_ids: ['willmar', 'st-cloud-srr'] }),
                   ['apollo: Girls Gymnastics', 'cathedral: Gymnastics', 'sauk-rapids-rice: Gymnastics', 'tech: Girls Gymnastics']);
  assert.deepEqual(await activitiesFor({ sport: 'Girls Hockey', team_ids: ['thief-river-falls', 'sartell-sauk-rapids'] }),
                   ['sartell: Hockey - Girls', 'sauk-rapids-rice: Hockey - Girls']);
  assert.deepEqual(await activitiesFor({ sport: 'Boys Hockey', team_ids: ['river-lakes', 'windom'] }), ['rocori: Hockey - Boys']);
  // A tournament Apollo's feed lists under Apollo alone stays Apollo's, as before.
  assert.deepEqual(await activitiesFor({ sport: 'Wrestling', team_ids: ['apollo'] }), ['apollo: Wrestling', 'kennedy: Wrestling 7-12']);
  // An ungendered co-op meet is each member's Wrestling, never its Girls Wrestling.
  assert.deepEqual(await activitiesFor({ sport: 'Wrestling', team_ids: ['st-cloud', 'alexandria'] }),
                   ['apollo: Wrestling', 'cathedral: Wrestling', 'kennedy: Wrestling 7-12', 'tech: Wrestling']);
  assert.deepEqual(await activitiesFor({ sport: 'Girls Wrestling', team_ids: ['st-cloud', 'alexandria'] }),
                   ['apollo: Wrestling', 'apollo: Girls Wrestling', 'cathedral: Wrestling', 'cathedral: Girls Wrestling',
                    'kennedy: Wrestling 7-12', 'tech: Wrestling'], 'girls wrestle on the same co-op');
});

test("Sartell's Nordic co-op takes Cathedral's meets (school-search 08; Apollo's for Tech and ROCORI above)", async () => {
  assert.deepEqual(await activitiesFor({ activity_team: 'cathedral', activity_name: 'Nordic Ski Racing, Boys' }),
                   ['cathedral: Boys Nordic Skiing', 'sartell: Nordic Ski (boys)']);
});

test('a sport the school lists no activity for, or a game it is not in, belongs to none', async () => {
  assert.deepEqual(await activitiesOf('rocori', 'Rugby', ['rocori', 'albany']), []);
  assert.deepEqual(await activitiesOf('apollo', 'Girls Soccer', ['tech', 'albany']), []);
  assert.deepEqual(await activitiesOf('apollo', null, ['apollo', 'albany']), []);
});

test('anyone can read the approved list, nobody can change it, and Kennedy has a page', async () => {
  await db.exec('set role anon');
  const { rows } = await db.query(`select team_id, count(*)::int n from public.team_activities group by 1 order by 1`);
  assert.deepEqual(Object.fromEntries(rows.map((r) => [r.team_id, r.n])), {
    apollo: 67, 'apollo-cathedral': 1, cathedral: 50, kennedy: 43, rocori: 49, 'saint-benedict': 46,
    'saint-johns': 43, sartell: 76, 'sauk-rapids-rice': 49, tech: 65,
  });
  await assert.rejects(db.exec(`insert into public.team_activities (team_id, name, kind, sort) values ('apollo', 'Fake', 'club', 99)`));
  assert.equal((await db.query(`select local from public.teams where id = 'kennedy'`)).rows[0].local, true);
  await db.exec('reset role');
});
