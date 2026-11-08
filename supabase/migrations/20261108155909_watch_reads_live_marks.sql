-- The morning report names the source that carried each game (BP app game-card 22), and the morning
-- watch runs as `watch`. On 2026-11-08 its finish was refused: "permission denied for function live_marks".
grant execute on function public.live_marks(uuid[]) to watch;
