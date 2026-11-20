-- Game-card 31: "SJU Soccer vs Milwaukee School" (Nov 14) doubles "SJU Soccer vs Milwaukee Engineering"
-- (59760caf-fef8-4b63-85be-dc34e32add2a, kept): same day and time, same opponent, Milwaukee School of Engineering.
update public.club_events set status = 'rejected', review_reason = 'other'
where id = '10743206-3ddc-4eb5-adcd-33199c0f45e3';
