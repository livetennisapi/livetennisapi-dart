# Changelog

All notable changes to this project are documented here.
This project adheres to [Semantic Versioning](https://semver.org/).

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
