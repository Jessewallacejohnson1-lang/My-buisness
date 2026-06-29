import { parseStartTime, buildIcs } from './ics'

const eq = (a: unknown, b: unknown, msg: string) => {
  if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`FAIL ${msg}: ${JSON.stringify(a)} !== ${JSON.stringify(b)}`)
  console.log('ok', msg)
}
const has = (s: string, sub: string, msg: string) => {
  if (!s.includes(sub)) throw new Error(`FAIL ${msg}: missing ${sub}`)
  console.log('ok', msg)
}

eq(parseStartTime('7pm'), { h: 19, m: 0 }, '7pm')
eq(parseStartTime('7:00p'), { h: 19, m: 0 }, '7:00p')
eq(parseStartTime('12am'), { h: 0, m: 0 }, '12am')
eq(parseStartTime('12pm'), { h: 12, m: 0 }, '12pm')
eq(parseStartTime('19:30'), { h: 19, m: 30 }, '24h')
eq(parseStartTime('noon'), null, 'unparseable')
eq(parseStartTime(''), null, 'empty')

has(buildIcs({ title: 'Trivia, Pints', event_date: '2026-07-01', start_time: '7pm', location: 'Bad Habit' }), 'DTSTART:20260701T190000', 'timed start')
has(buildIcs({ title: 'Trivia, Pints', event_date: '2026-07-01', start_time: '7pm' }), 'SUMMARY:Trivia\\, Pints', 'comma escaped')
has(buildIcs({ title: 'Market', event_date: '2026-07-04', start_time: null }), 'DTSTART;VALUE=DATE:20260704', 'all-day')
has(buildIcs({ title: 'X', event_date: '2026-07-01', start_time: '7pm' }), 'DTEND:20260701T210000', 'timed end +2h')
has(buildIcs({ title: 'A;B', event_date: '2026-07-01', start_time: '7pm' }), 'SUMMARY:A\\;B', 'semicolon escaped')
has(buildIcs({ title: 'X', event_date: '2026-07-01', start_time: '7pm', description: 'note', url: 'http://x' }), 'DESCRIPTION:note\\nhttp://x', 'description+url joined')
console.log('all ics checks passed')
