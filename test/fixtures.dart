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
