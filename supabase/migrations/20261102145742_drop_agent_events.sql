-- The agent log's table, dropped with Jesse's yes (2026-11-02). Its writer, the log-agent-event
-- function, was deleted the same morning; nothing ever read it. Its 210 rows were saved off git
-- first, in ~/Documents/backups/2026-11-02-agent-events.json.
drop table public.agent_events;
