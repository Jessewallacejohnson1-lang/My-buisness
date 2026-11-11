-- Morning take-out, 2026-11-11: two copies of one thing.

-- Girls hockey vs East Grand Forks, Nov 21, 1 PM at Scheels: Sauk Rapids-Rice repeats Sartell's home game. Kept f42a224f (Sartell High School).
update public.club_events set status = 'rejected', review_reason = 'other' where id::text like 'f6d509de%';

-- St. Cloud boys swim JV meets: Apollo and Tech list the same co-op meet. Kept Tech's copies (with both teams): 0193103e Willmar, 189cb90d Bemidji, 3a94c455 Alexandria.
update public.club_events set status = 'rejected', review_reason = 'other'
where id::text like '98adc93f%' or id::text like 'cc78cb18%' or id::text like 'e1052c86%';
