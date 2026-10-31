-- Live scores can't go quiet (BP app docs/plans/loopholes, ticket 05). A call the live-scores edge function refuses
-- or fails now fails the cron run, so it shows in cron.job_run_details (job 'live-scores', status 'failed', the
-- reason in return_message), where the bad-morning email (ticket 03) reads it. Before, every error was swallowed:
-- a redeploy that turned verify_jwt back on left the job refused every minute with nothing to show.
-- The next minute still tries again.
create or replace function private.wake_live_scores()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status int;
  v_body text;
begin
  if not exists (select 1 from private.live_games(now())) then return; end if;
  -- The function answers at once and listens in the background, so this read waits 3 seconds at most.
  perform extensions.http_set_curlopt('CURLOPT_TIMEOUT', '3');
  select r.status, r.content into v_status, v_body
  from extensions.http(('POST', 'https://lxdgwhvqjqmqliobwjpi.supabase.co/functions/v1/live-scores',
    array[extensions.http_header('User-Agent', 'BlockPartyBot/1.0 (+https://blockpartystjoe.com)')],
    'application/json', '{}')::extensions.http_request) r;
  if v_status not between 200 and 299 then
    raise exception 'live-scores answered %: %', v_status, left(v_body, 200);
  end if;
end;
$$;
