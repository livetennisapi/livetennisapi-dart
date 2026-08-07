# Changelog

All notable changes to this project are documented here.
This project adheres to [Semantic Versioning](https://semver.org/).

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
