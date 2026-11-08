// The Event card's keys (private.event_cards, BP app codebase-health-2): every read that sends a card sends all
// of them, so a story fails when a read is missing one. A new card field is added here and in the card source.
export const CARD_KEYS = ['all_day', 'cancelled', 'category', 'club_name', 'created_at', 'description', 'end_at',
  'event_date', 'friends_going', 'friends_going_at', 'game', 'going', 'going_count', 'heart_count', 'hearted', 'host_picture', 'id', 'image_url', 'live_kind', 'location',
  'place_picture', 'recurrence', 'source_name', 'source_url', 'start_time', 'title', 'what'];
