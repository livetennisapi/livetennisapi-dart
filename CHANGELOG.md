# Changelog

All notable changes to this project are documented here.
This project adheres to [Semantic Versioning](https://semver.org/).

## Unreleased

### Added

- `playerStats(playerId, {from, to, surface, level, last})` for
  `GET /players/{id}/stats` (API 1.13.61). PRO returns `records`: W/L
  overall and by surface, venue, level and season, the set-based record,
  withdrawals and the last N matches. ULTRA adds `serveReturn`, the summed
  serve and return statistics. It is `null` below ULTRA. Every percentage is
  `double?`, `null` on an empty sample. A 403 names PRO as the required tier.
  `PlayerRecentMatch.scoreGames` is `List<List<int?>>?`: a `null` set is kept
  in position (its games are unknown) rather than dropped, so later sets do
  not shift left. `serveReturn` carries `matches_incomplete`, the matches
  whose measured statistics stop short of the final and are left out of
  every sum.
- **Score first.** Since 2026-10-23 every push-feed `score` frame carries
  `model` beside `score` and a state leaves twice: `pending` the instant it
  is accepted (the four model keys present and null) and `ready` once its
  model run finished, both with the same `score.sequence`. Dedup on
  `(match_id, score.sequence, model)`, and read a frame with no `model` as
  `ready`. `getWsToken(modelFields: false)` mints with `?model_fields=off`
  for the score-only channels (one `off` frame per state, model keys left
  out), which `WsToken.channels` then names, and `WsToken.modelFields`
  echoes the switch.

### Fixed

- `WsToken.matchChannel` substitutes whatever placeholder the server wrote
  between braces. The wire template is `match:{match_id}`, and the method
  only replaced `{id}`, so it handed back the template unchanged.
- `Player.heightCm` (`height_cm`) and `Player.doublesRanking`
  (`doubles_ranking`): set by `getPlayer` on paid tiers, `null` on a FREE key.

## 1.3.0 — 2026-09-02

### Added

- `Match.hasAnalysis` and `Match.hasMarket` (`has_analysis`, `has_market`):
  two booleans on every row of `listMatches` and on `getMatch`, every tier
  (API 1.9.0, shipped to production 2026-09-02). They carry the same fact
  `getMatchAnalysis` and `getMarketPrices` answer `404 no_analysis` /
  `404 no_market` about, so a slate is filtered in one call instead of one
  404 per match. Both are `bool?`: `null` when talking to an older server
  that does not send them, never a guessed `false`.
- `Match.eventStatusUpdatedAt` (`event_status_updated_at`): the instant the
  current `eventStatus` was recorded, UTC (API 2026-08-19). `null` when the
  status has never changed since the field was introduced — never backfilled.

## 1.2.1 — 2026-08-16

### Added

- `PackageKind.rally` — the charted rally corpus (shot-by-shot) as yearly
  exports (ULTRA), and `PackageKind.archive` — the results archive
  (1968–2022) as yearly exports, same entitlement as the tape packages.
  Both are yearly kinds: their `period` is the bare year `YYYY`. Additive —
  the wire default (`tape`) and existing behaviour are unchanged.

### Fixed

- README install instruction now points at `^1.0.0` — the latest version
  published on pub.dev — instead of `^1.2.0`, which is not yet on pub.dev
  and made `pub get` fail. Newer versions are tagged on GitHub and pending
  pub.dev publication; a git-dependency snippet documents the interim path.

## 1.2.0 — 2026-08-07

Full API parity: every documented public v1 REST path now has a typed method.

### Added

- `getUsage` (`/usage`, any tier and quota-exempt) → typed `Usage` with
  `UsageLimits`, `UsageToday` and a 30-day `UsageDay` history. Note the daily
  reset instant is **not** part of this response — it exists only as
  `resets_at` on a daily-429 body.
- Webhooks (ULTRA, direct keys only): `createWebhook` (POST, one-time
  `Webhook.secret`, server-default events when omitted), `listWebhooks`
  (never includes the secret) and `deleteWebhook`; `WebhookEvent` enum
  (`score`, `break_point`). Max 3 per key — the 4th raises the new
  `ConflictException` (409 `webhook_limit`). Mutating requests are never
  auto-retried, so a transient failure cannot register a duplicate webhook.
- Tournament catalogue: `listTournaments` / `getTournament` (FREE) → typed
  `Tournament` (stable id joined by `Match.tournamentId`, curated host
  city/country, category only where the catalogues agree).
- `listMatchPrices` (`/matches/{id}/prices`, PRO): bare price ticks of the
  mapped match-winner market — `limit` ≤ 500, `minutes` lookback window, no
  offset (`meta.has_more` marks a clipped window).

### Notes

- Deliberately out of scope (documented in the README): undocumented gateway
  alias routes, HTML views and static assets; package file downloads stream
  as attachments and stay with your HTTP tooling (the client returns the JSON
  manifest).

## 1.1.0 — 2026-08-07

### Added

- **History & analytics endpoints:** `getMatchTape` (point-by-point tape with
  `?sequence=raw|clean`, works on live matches), `getHeadToHead` (`/h2h`),
  the deep results archive — `listArchiveMatches`, `getArchiveMatch`,
  `listArchivePlayers`, `getArchiveCareer` (1968–2022, own id space) — and
  bulk packages via `listHistoryPackages` / `getHistoryPackage` (with `kind:
  tape|rankings` and the `year` archive listing).
- **ULTRA endpoints:** `getMatchStatistics` (derived + measured families with
  per-family freshness), rally construction — `listRallyMatches`,
  `getRallyMatch`, `getMatchRally` (by our match id; 404 `not_charted` is
  distinct from `not_found`) — shot-level charting via `getChartingPlayer` /
  `getChartingMatch`, and `getWsToken` for the push WebSocket feed
  (`WsToken` with `wsUrl`, channel vocabulary incl. `slate:all`, and a
  `matchChannel()` helper).
- **Rankings:** `listRankings` covers both modes — the rank-ordered listing
  (PRO, one `system`) and per-player as-of records (ULTRA, up to 50 ids) —
  returning typed `RankingRecord`s with `previousRank`.
- **New `Match` fields:** `tour` (filter vocabulary, groupable),
  `tournamentId`, `roundCode`, `withdrew` (who retired/conceded a walkover).
- **Tape models:** `TapeRow.pointWinner` (clean sequence only) and per-set
  tiebreak final scores (`MatchTape.tiebreaks`).
- **New list filters** on `listMatches` and `listCompletedMatches`:
  `players` (≤ 50 ids, repeated on the wire), `country` (IOC-style 3-letter
  code), `from`/`to` date bounds, and `coverage` on the history list. Unknown
  filter values are a `400`, never silently ignored.
- **Errors:** daily-quota 429s expose `resetsAt`, `scope` and `limitPerDay`
  on `RateLimitedException`; the new `AbuseThrottledException` carries
  `retryAtEpoch`/`retryAt` and is **never auto-retried** (it is a 24-hour
  block for broken retry loops — waiting a few seconds cannot clear it).
- `ListMeta.total` and `ListMeta.hasMore`.
- `scripts/truthcheck.sh` truth-pin, run in CI.

### Changed

- Tier attribution for 403s now covers the full surface (statistics, rally,
  charting, ws-token, packages, h2h, archive), including mode-dependent
  endpoints: rankings 403s name PRO in listing mode and ULTRA in per-player
  mode, and `listMatches(status: completed)` names BASIC.
- Docs and README now state the current quota grid (2026-08-06: FREE
  100/day, BASIC 1,000/day, PRO 10,000/day, ULTRA 500,000/day) and the
  five-tour coverage phrasing (ATP, WTA, Challenger, ITF and juniors).

## 1.0.0

First release.

### Added

- `LiveTennisApi` covering all 12 REST endpoints: `health`, `listMatches`,
  `getMatch`, `getMatchScore`, `listMatchEvents`, `getMatchAnalysis`,
  `searchPlayers`, `getPlayer`, `listMarkets`, `getMarketPrices`,
  `listCompletedMatches` and `listFixtures`.
- Immutable models with `fromJson`: `Match`, `Player`, `Score`,
  `DataCompleteness`, `Market`, `Price`, `Analysis`, `MatchEvent`, `Fixture`,
  `Page`, `ListMeta`.
- `Tour` and `MatchStatus` filter enums.
- Typed error hierarchy. `UpgradeRequiredException` carries `requiredTier`;
  `RateLimitedException` carries `retryAfter`.
- Retries on `429` and `5xx` only, honouring `Retry-After` with exponential
  backoff and jitter. Other `4xx` are never retried.
- `paginate()` stream for walking list endpoints.

### Notes

- **Models never reject unknown fields.** The API ships additive changes within
  `v1`, so unrecognised fields are ignored by the typed getters but preserved in
  each model's `raw` map — a new server field works without upgrading.
- `Score.games` is **player-major** (`[games_p1, games_p2]`, each a per-set
  list). Use `Score.gamesForSet()` to read it safely.
- `Score.server` and `Match.score` are nullable; `Score.points` are strings.
- `DataCompleteness.known` and `.of` are `null` on a doubles team (with a
  `note`), distinct from `0`.
- Depends only on `package:http`, with no Flutter dependency, so it runs in
  pure Dart, Flutter, and on the web.
