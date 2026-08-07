// Recorded API response bodies, captured from the live Live Tennis API and
// used so the tests never touch the network. These are real shapes: a live
// singles match, an upcoming doubles match (score null, per-player biography
// not applicable), and error bodies.

/// A live singles match with a score: player-major games, string points, a set
/// in progress (ragged game lists), and a granular lowercase `tour`.
const String liveSinglesMatch = '''
{
  "id": 22313,
  "tournament": "UTR PTT Waco Men 02, Group C",
  "surface": null,
  "indoor": false,
  "format": "BO3",
  "round": null,
  "status": "live",
  "event_status": null,
  "is_doubles": false,
  "scheduled_time": "2026-07-23T19:20:00Z",
  "players": {
    "p1": {
      "id": 12661, "name": "Lathan Skrobarcek", "tour": "atp",
      "country": "usa", "ranking": null, "ranking_points": null,
      "ranking_movement": null, "hand": null, "backhand": null,
      "birthday": null, "is_doubles_team": false,
      "data_completeness": {
        "known": 1, "of": 5,
        "missing": ["backhand", "birthday", "hand", "ranking"]
      }
    },
    "p2": {
      "id": 12755, "name": "Egor Gorin", "tour": "atp",
      "country": "rus", "ranking": null, "is_doubles_team": false,
      "data_completeness": {"known": 1, "of": 5, "missing": ["hand"]}
    }
  },
  "score": {
    "sets": [1, 1],
    "games": [[4, 6, 4], [6, 2, 2]],
    "points": ["30", "15"],
    "server": 1,
    "is_tiebreak": false,
    "timestamp": "2026-07-24T01:54:34.123348Z"
  }
}
''';

/// A `{data, meta}` list body wrapping the live singles match.
const String liveMatchesPage = '''
{"data": [$liveSinglesMatch], "meta": {"limit": 50, "offset": 0, "count": 1}}
''';

/// An upcoming doubles match: `score` is null, `tour` is UPPERCASE, and each
/// team's `data_completeness` has null `known`/`of` plus a `note`.
const String upcomingDoublesMatch = '''
{
  "id": 22210,
  "tournament": "Kitzbuhel",
  "surface": "clay",
  "indoor": false,
  "format": "BO3",
  "round": "ATP Kitzbuhel - Semi-finals",
  "status": "upcoming",
  "event_status": null,
  "is_doubles": true,
  "scheduled_time": "2026-07-24T08:30:00Z",
  "players": {
    "p1": {
      "id": 1417, "name": "Schnaitter / Wallner", "tour": "ATP",
      "country": null, "is_doubles_team": true,
      "data_completeness": {
        "known": null, "of": null, "missing": [],
        "note": "doubles team — per-player profile fields do not apply"
      }
    },
    "p2": {
      "id": 12360, "name": "Herbert / Krawietz", "tour": "ATP",
      "is_doubles_team": true,
      "data_completeness": {
        "known": null, "of": null, "missing": [],
        "note": "doubles team — per-player profile fields do not apply"
      }
    }
  },
  "score": null
}
''';

/// A score with `server` set to null (documented as nullable, e.g. between
/// points), otherwise a normal in-progress score.
const String nullServerScore = '''
{
  "sets": [0, 0],
  "games": [[2], [3]],
  "points": ["0", "0"],
  "server": null,
  "is_tiebreak": false,
  "timestamp": "2026-07-24T01:55:09.178235Z"
}
''';

/// The 403 body the API returns for an over-tier request.
const String upgradeRequiredBody = '{"error": "upgrade_required"}';

/// The 400 body for an unrecognised query parameter.
const String badRequestBody = '{"error": "invalid_tour"}';

/// The daily-quota 429 body: scope "day", the daily limit, and an absolute
/// reset instant (derived from the service's local midnight — not a fixed
/// UTC hour).
const String dailyLimitBody = '''
{
  "error": "rate_limited",
  "limit_per_day": 100,
  "scope": "day",
  "resets_at": "2026-08-07T21:00:00Z"
}
''';

/// The abuse-throttle 429 body: a 24-hour block for chronic over-cap
/// clients, with the epoch second it lifts.
const String abuseThrottledBody = '''
{"error": "abuse_throttled", "retry_at_epoch": 1754650800}
''';

/// A completed match carrying the fields added since 1.0.0: `tour` (filter
/// vocabulary), `tournament_id`, `round_code`, `event_status` and `withdrew`.
const String completedRetiredMatch = '''
{
  "id": 24101,
  "tournament": "ATP Kitzbuhel",
  "tour": "atp",
  "tournament_id": "atp-kitzbuhel-singles",
  "surface": "clay",
  "indoor": false,
  "format": "BO3",
  "round": "ATP Kitzbuhel - Quarter-finals",
  "round_code": "QF",
  "status": "completed",
  "event_status": "Retired",
  "is_doubles": false,
  "scheduled_time": "2026-07-24T11:30:00Z",
  "players": {
    "p1": {"id": 101, "name": "Player One", "tour": "atp"},
    "p2": {"id": 102, "name": "Player Two", "tour": "atp"}
  },
  "score": {"sets": [1, 0], "games": [[6, 3], [4, 1]]},
  "winner": 1,
  "withdrew": 2
}
''';

/// A clean-sequence tape body: `point_winner` on attributable rows (null on
/// the first row), per-set `tiebreaks` aligned to the final scoreline (null
/// for the non-tiebreak set), and coverage meta.
const String tapeBody = '''
{
  "match": {"id": 24101, "tournament": "ATP Kitzbuhel", "tour": "atp"},
  "tape": [
    {"sets": [0, 0], "games": [[0], [0]], "points": ["0", "0"],
     "server": 1, "is_tiebreak": false, "point_winner": null,
     "timestamp": "2026-07-24T11:31:00Z"},
    {"sets": [0, 0], "games": [[0], [0]], "points": ["15", "0"],
     "server": 1, "is_tiebreak": false, "point_winner": 1,
     "timestamp": "2026-07-24T11:31:40Z"},
    {"sets": [0, 0], "games": [[0], [0]], "points": ["15", "15"],
     "server": 1, "is_tiebreak": false, "point_winner": 2,
     "timestamp": null}
  ],
  "tiebreaks": [{"p1": 7, "p2": 5}, null],
  "profiles": [{"win_probability_p1": 0.61, "stage": "pregame"}],
  "meta": {
    "match_id": 24101, "rows": 3, "coverage": "from_start",
    "point_source": "observed", "raw_rows": 5, "unique_states": 3,
    "sequence": "clean", "from_archive": false,
    "generated_at": "2026-08-07T10:00:00Z"
  }
}
''';

/// A head-to-head body spanning both eras, with an undecided meeting.
const String h2hBody = '''
{
  "players": {"p1": {"name": "Player One"}, "p2": {"name": "Player Two"}},
  "totals": {"p1_wins": 3, "p2_wins": 1, "meetings": 5, "undecided": 1},
  "by_surface": {"clay": {"p1": 2, "p2": 0}, "unknown": {"p1": 1, "p2": 1}},
  "meetings": [
    {"era": "current", "date": "2026-07-24", "tournament": "ATP Kitzbuhel",
     "round": "QF", "surface": "clay", "score": null, "outcome": "retired",
     "winner": 1},
    {"era": "archive", "date": "2019-05-06", "tournament": "Madrid Masters",
     "level": "M", "round": "R32", "surface": "clay",
     "score": "6-4 7-6(5)", "outcome": "completed", "winner": 2}
  ]
}
''';

/// A rankings listing page (PRO mode): rank order, `player_name` as
/// published, a roster hole (null `player_id`), and `previous_rank`.
const String rankingsListingPage = '''
{
  "data": [
    {"player_id": 501, "player_name": "Top Player", "system": "atp",
     "tour": "atp", "rank": 1, "points": 9850, "previous_rank": 2,
     "effective_date": "2026-08-03", "observed_at": "2026-08-03T00:00:00Z"},
    {"player_id": null, "player_name": "Unrostered Player", "system": "atp",
     "rank": 2, "points": 8200, "previous_rank": 1,
     "effective_date": "2026-08-03"}
  ],
  "meta": {
    "limit": 50, "offset": 0, "count": 2,
    "coverage": {"as_of": "2026-08-03", "systems_requested": ["atp"],
                 "systems_resolved": ["atp"],
                 "oldest_available": {"atp": "2023-01-02"}}
  }
}
''';

/// A UTR per-player record: rating populated, rank/points/previous_rank null.
const String utrRankingRecord = '''
{"player_id": 501, "system": "utr", "rank": null, "points": null,
 "previous_rank": null, "rating": 15.87, "effective_date": "2026-08-03"}
''';

/// A ws-token body, with the per-match channel template and `slate:all`.
const String wsTokenBody = '''
{
  "token": "eyJhbGciOi_example",
  "expires_in": 300,
  "ws_url": "wss://api.livetennisapi.com/connection/websocket",
  "channels": {"match": "match:{id}", "slate": "slate:all"}
}
''';

/// An in-play statistics body: derived fields typed, measured kept raw, and
/// per-family freshness on different clocks.
const String statisticsBody = '''
{
  "match_id": 22313,
  "coverage": "live",
  "as_of": "2026-07-24T01:54:34Z",
  "age_seconds": 4,
  "games_counted": 24,
  "tiebreak_games_excluded": 1,
  "inconsistent_games_excluded": 0,
  "sets_covered": [1, 2, 3],
  "freshness": {
    "measured_divergence": null,
    "derived": {"coverage": "live", "as_of": "2026-07-24T01:54:34Z",
                "age_seconds": 4,
                "describes": {"total_games": 24}},
    "measured": {"coverage": "live", "as_of": "2026-07-24T01:54:20Z",
                 "age_seconds": 18,
                 "describes": {"total_games": 24}}
  },
  "players": {
    "p1": {
      "service_games_played": 12, "service_games_won": 10, "hold_pct": 83,
      "return_games_played": 12, "return_games_won": 2, "break_pct": 17,
      "break_points_faced": 6, "break_points_saved": 4,
      "break_points_saved_pct": 67, "break_points_played": 5,
      "break_points_converted": 2, "break_points_converted_pct": 40,
      "service_points_played": 80, "service_points_won": 52,
      "service_points_won_pct": 65, "return_points_played": 78,
      "return_points_won": 30, "return_points_won_pct": 38,
      "points_played": 158, "points_won": 82,
      "measured": {"aces": 7, "double_faults": 2,
                   "first_serves_in": 48, "first_serves_in_of": 80,
                   "first_serves_in_pct": 60}
    },
    "p2": {
      "service_games_played": 12, "service_games_won": 10,
      "hold_pct": 83, "points_played": 158, "points_won": 76,
      "measured": {"aces": 3, "double_faults": 5}
    }
  }
}
''';

/// One archive result (winner/loser-shaped) with era-honest nulls.
const String archiveMatchBody = '''
{
  "id": 880123,
  "source_id": "1984-M-SF-1",
  "tour": "atp",
  "level": "G",
  "tournament": "Wimbledon",
  "surface": "grass",
  "draw_size": 128,
  "event_date": "1984-06-25",
  "round": "SF",
  "best_of": 5,
  "minutes": null,
  "winner": {"name": "Archive Winner", "hand": "L", "country": "usa",
             "rank": 1, "seed": 1, "player_id": 100581, "height_cm": 180,
             "age": 25.3, "entry": null},
  "loser": {"name": "Archive Loser", "hand": "R", "country": "aus",
            "rank": 11, "seed": 9, "player_id": 100443},
  "score": "6-4 6-3 RET",
  "outcome": "retired",
  "stats": null
}
''';

/// A charted match with one parsed point and one the parser could not read
/// cleanly (`parsed: false`, notation kept verbatim in the API's `raw` key).
const String rallyDetailBody = '''
{
  "rally_match_id": 9001,
  "source_id": "20190714-M-Wimbledon-F",
  "match_id": null,
  "date": "2019-07-14",
  "tournament": "Wimbledon",
  "round": "F",
  "surface": "grass",
  "gender": "M",
  "best_of": 5,
  "players": [{"name": "Charted One", "hand": "R"},
              {"name": "Charted Two", "hand": "R"}],
  "points": 422,
  "points_parsed": 420,
  "rally": [
    {"point": 1, "set": [0, 0], "games": [0, 0], "score": "0-0",
     "game": 1, "is_tiebreak": false, "server": 1, "point_winner": 1,
     "raw": "4f8b1f*", "parsed": true, "serve_number": 1,
     "serve_direction": "wide", "rally_length": 3, "outcome": "winner",
     "ending_stroke": "groundstroke", "ending_wing": "forehand",
     "is_ace": false, "is_double_fault": false,
     "is_serve_and_volley": false,
     "shots": [
       {"number": 1, "code": "4", "stroke": "serve", "direction": "wide"},
       {"number": 2, "code": "f", "stroke": "groundstroke",
        "wing": "forehand", "direction": "middle"},
       {"number": 3, "code": "f", "stroke": "groundstroke",
        "wing": "forehand", "direction": "forehand_side"}
     ]},
    {"point": 2, "score": "15-0", "server": 1, "point_winner": null,
     "raw": "5xQ?", "parsed": false, "is_tiebreak": false,
     "is_ace": false, "is_double_fault": false,
     "is_serve_and_volley": false, "shots": []}
  ],
  "meta": {"limit": 50, "offset": 0, "count": 2, "total": 422,
           "has_more": true}
}
''';

/// A packages listing: a plain tape package (no `kind` key) and the file
/// manifest with checksums.
const String packagesPage = '''
{
  "data": [
    {"period": "2026-07", "status": "ready", "match_count": 4210,
     "row_count": 1287345,
     "files": [
       {"format": "jsonl", "filename": "tapes-2026-07.jsonl.gz",
        "bytes": 73400320, "sha256": "abc123"},
       {"format": "csv", "filename": "tapes-2026-07.csv.gz",
        "bytes": 51200000, "sha256": "def456"}
     ],
     "built_at": "2026-08-01T02:00:00Z"}
  ],
  "meta": {"count": 1}
}
''';

/// A usage body: FREE-tier key with a temporary grant absent, today's calls
/// and a short history. NOTE it carries no `resets_at` — the daily reset
/// instant appears only on the daily-429 body.
const String usageBody = '''
{
  "principal": "key_ab12cd",
  "tier": "free",
  "base_tier": "free",
  "tier_expires_at": null,
  "channel": "direct",
  "limits": {"per_minute": 30, "per_day": 100},
  "today": {"calls": 41, "errors": 2, "remaining_day": 59},
  "history": [
    {"day": "2026-08-05", "calls": 97, "errors": 0},
    {"day": "2026-08-06", "calls": 100, "errors": 3}
  ],
  "as_of": "2026-08-07T09:30:00Z"
}
''';

/// A tournament row from the catalogue, with curated host city/country
/// (ISO-3166 alpha-2, unlike player country codes) and an agreed category.
const String tournamentBody = '''
{
  "id": "atp-kitzbuhel-singles",
  "name": "Kitzbuhel",
  "tour": "atp",
  "surface": "clay",
  "indoor": false,
  "city": "Kitzbuhel",
  "country": "AT",
  "category": "atp_250"
}
''';

/// A `{data, meta}` tournaments page wrapping the single row.
const String tournamentsPage = '''
{"data": [$tournamentBody], "meta": {"limit": 50, "offset": 0, "count": 1}}
''';

/// Bare price ticks from /matches/{id}/prices: no market wrapper, no offset,
/// `has_more` marks a clipped window.
const String matchPricesPage = '''
{
  "data": [
    {"side": 1, "bid": 0.61, "ask": 0.63, "mid": 0.62, "spread": 0.02,
     "price_source": "prediction_market", "synthetic": false,
     "timestamp": "2026-08-07T09:31:00Z"},
    {"side": 2, "mid": 0.38, "synthetic": true,
     "timestamp": "2026-08-07T09:30:30Z"}
  ],
  "meta": {"match_id": 22313, "count": 2, "has_more": true, "limit": 2,
           "minutes": null}
}
''';

/// The 201 body of a webhook registration — the ONLY response that carries
/// the signing secret.
const String webhookCreatedBody = '''
{
  "id": 31,
  "url": "https://example.invalid/hooks/tennis",
  "events": ["score", "break_point"],
  "enabled": true,
  "created_at": "2026-08-07T09:32:00Z",
  "last_delivery_at": null,
  "consecutive_failures": 0,
  "last_error": null,
  "secret": "whsec_example_shown_once",
  "secret_note": "Shown once. Store it now."
}
''';

/// A webhooks listing: same shape, never the secret.
const String webhooksListPage = '''
{
  "data": [
    {"id": 31, "url": "https://example.invalid/hooks/tennis",
     "events": ["score"], "enabled": true,
     "created_at": "2026-08-07T09:32:00Z",
     "last_delivery_at": "2026-08-07T09:40:11Z",
     "consecutive_failures": 0, "last_error": null}
  ],
  "meta": {"count": 1}
}
''';

/// The 409 body when a 4th webhook is registered.
const String webhookLimitBody = '{"error": "webhook_limit"}';
