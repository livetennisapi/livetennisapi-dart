# livetennisapi

[![CI](https://github.com/livetennisapi/livetennisapi-dart/actions/workflows/ci.yml/badge.svg)](https://github.com/livetennisapi/livetennisapi-dart/actions/workflows/ci.yml)
[![pub package](https://img.shields.io/pub/v/livetennisapi.svg)](https://pub.dev/packages/livetennisapi)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A Dart and Flutter client for the [Live Tennis API](https://livetennisapi.com) —
real-time tennis scores, players, rankings, match history, head-to-heads,
match-winner market prices and model win-probability for ATP, WTA, Challenger,
ITF and juniors, over REST.

- **Pure Dart, Flutter-friendly.** Depends only on `package:http`; no Flutter
  dependency, so it runs in a server, a Flutter app, or on the web.
- **Typed and null-correct.** Immutable models with `fromJson`, a nullable
  `Score`, string points, and player-major games handled for you.
- **Forward-compatible.** The API ships additive changes within `v1`; unknown
  fields never break decoding and stay reachable via each model's `raw` map.
- **Typed errors.** `UpgradeRequiredException` (403) names the tier you need;
  `RateLimitedException` (429) carries `retryAfter` — and `resetsAt` when the
  daily quota is spent.

## Install

```yaml
dependencies:
  livetennisapi: ^1.2.0
```

## Usage

```dart
import 'package:livetennisapi/livetennisapi.dart';

Future<void> main() async {
  final client = LiveTennisApi(apiKey: 'twjp_your_key');
  try {
    final page = await client.listMatches(status: MatchStatus.live);
    for (final match in page.data) {
      final s = match.score;
      final (g1, g2) = s?.gamesForSet(0) ?? (null, null);
      print('${match.tournament} [${match.tour}]: '
          '${match.p1?.name} vs ${match.p2?.name} '
          '(${g1 ?? '-'}-${g2 ?? '-'}, serving: ${s?.server ?? '—'})');
    }
  } on UpgradeRequiredException catch (e) {
    print('Needs the ${e.requiredTier} tier');
  } on RateLimitedException catch (e) {
    print('Slow down; retry after ${e.retryAfter}s');
  } finally {
    client.close();
  }
}
```

Get a free key at [livetennisapi.com/subscribe/free](https://livetennisapi.com/subscribe/free)
— self-serve, no card.

### Authentication

Pass your `twjp_` key to the constructor. By default it is sent as
`Authorization: Bearer <key>` (preferred); pass
`authHeader: AuthHeader.xApiKey` to use the `X-API-Key` header instead. (The
API also accepts `?token=` for header-less contexts such as raw WebSocket
connections; this client always uses headers.)

```dart
final client = LiveTennisApi(
  apiKey: 'twjp_your_key',
  authHeader: AuthHeader.xApiKey,
  timeout: const Duration(seconds: 20),
  maxRetries: 3,
);
```

## Endpoints

Full parity with the documented public v1 REST surface:

| Method | Endpoint | Tier |
|---|---|---|
| `health` | `/health` | none |
| `getUsage` | `/usage` | any (quota-exempt) |
| `listMatches` | `/matches` | FREE (`status: completed` BASIC+) |
| `getMatch` | `/matches/{id}` | FREE (+`market` PRO, +`analysis` ULTRA) |
| `getMatchScore` | `/matches/{id}/score` | FREE |
| `listMatchEvents` | `/matches/{id}/events` | PRO |
| `getMatchAnalysis` | `/matches/{id}/analysis` | ULTRA |
| `getMatchStatistics` | `/matches/{id}/statistics` | ULTRA |
| `searchPlayers`, `getPlayer` | `/players`, `/players/{id}` | FREE |
| `listFixtures` | `/fixtures` | FREE |
| `listTournaments`, `getTournament` | `/tournaments`, `/tournaments/{id}` | FREE |
| `listMarkets`, `getMarketPrices` | `/markets`, `/markets/{id}/prices` | PRO |
| `listMatchPrices` | `/matches/{id}/prices` | PRO |
| `listRankings` | `/rankings` | PRO (listing) / ULTRA (per-player) |
| `listCompletedMatches` | `/history/matches` | BASIC, or any History plan |
| `getMatchTape` | `/history/matches/{id}` | BASIC, or any History plan |
| `getHeadToHead` | `/h2h` | BASIC, or any History plan |
| `listArchiveMatches`, `getArchiveMatch` | `/history/archive/matches` | BASIC, or any History plan |
| `listArchivePlayers` | `/history/archive/players` | BASIC, or any History plan |
| `getArchiveCareer` | `/history/archive/career` | BASIC, or any History plan |
| `listHistoryPackages`, `getHistoryPackage` | `/history/packages` | PRO+ (`kind: rankings` / `year` ULTRA) |
| `listRallyMatches`, `getRallyMatch` | `/rally/matches` | ULTRA |
| `getMatchRally` | `/history/matches/{id}/rally` | ULTRA |
| `getChartingPlayer` | `/charting/players` | ULTRA |
| `getChartingMatch` | `/charting/matches/{id}` | ULTRA |
| `getWsToken` | `/ws-token` | ULTRA |
| `createWebhook`, `listWebhooks`, `deleteWebhook` | `/webhooks` | ULTRA (direct keys only) |

A call above your tier throws `UpgradeRequiredException`, whose `requiredTier`
names the plan that unlocks the endpoint.

**Webhooks:** up to 3 per key (a 4th is a 409 `ConflictException`,
`webhook_limit`); the signing secret is returned **once**, on creation.
Webhook registration is never auto-retried, so a transient failure cannot
create a duplicate. `getUsage` reports quota state but not the daily reset
instant — that arrives only as `resetsAt` on a daily 429.

**Deliberately excluded:** anything outside the documented public v1 JSON
contract — undocumented gateway alias routes, server-rendered HTML views, and
static assets (fonts, images). Package file downloads
(`/history/packages/{period}?format=`) stream as attachments; this client
returns the JSON manifest and leaves the download to your HTTP tooling.

## Quotas

| Tier | Requests/min | Requests/day | Price |
|---|---|---|---|
| FREE | 30 | 100 | $0 |
| BASIC | 60 | 1,000 | $9.99/mo |
| PRO | 300 | 10,000 | $29.99/mo |
| ULTRA | 600 | 500,000 | $99.99/mo |

The FREE tier is 100 requests/day, so poll no faster than every 15 minutes on
a free key; for an always-on dashboard, BASIC is the recommended floor. Every
response carries `X-RateLimit-Limit` / `-Remaining` / `-Reset` headers. When
the **daily** quota is spent, the thrown `RateLimitedException` has
`scope == 'day'` and `resetsAt` — the absolute reset instant (derived from
the service's local midnight, so don't assume a fixed UTC hour). An
`AbuseThrottledException` (24-hour block for broken retry loops) is never
auto-retried; fix the loop and wait until `retryAt`.

## Reading a score

`Score.games` is **player-major**: `[[games_p1...], [games_p2...]]`, each side a
per-set list that grows as the match plays. Use `gamesForSet` rather than
indexing by hand:

```dart
final (p1, p2) = score.gamesForSet(0); // games in set 1, as (p1, p2)
```

`Score.points` are strings (`"0"`, `"15"`, `"30"`, `"40"`, `"AD"`), and
`Score.server` is `1`, `2`, or `null`.

## History, head-to-head and the tape

```dart
// The point-by-point tape — works on live matches too. The clean sequence
// carries pointWinner per attributable row, plus per-set tiebreak scores.
final tape = await client.getMatchTape(24101, sequence: TapeSequence.clean);
print('${tape?.meta?.coverage}: ${tape?.tape.length} rows');

// Head-to-head across the archive (1968–2022) and current matches (2023→).
final h2h = await client.getHeadToHead(p1: 'alcaraz', p2: 'sinner');
print('${h2h?.p1Name} ${h2h?.totals?.p1Wins}–${h2h?.totals?.p2Wins} '
    '${h2h?.p2Name}');

// Point-in-time rankings (ULTRA per-player mode), with previousRank.
final ranks = await client.listRankings(
  players: [501],
  asOf: '2026-08-03',
  systems: [RankingSystem.atp],
);
```

Tape coverage is honest, not guessed — read `MatchTape.meta` (`coverage`,
`pointSource`) before backtesting, and note archive people live in their own
id space, keyed by name.

## Pagination

```dart
await for (final player in client.paginate(
  ({limit = 200, offset = 0}) =>
      client.searchPlayers(search: 'nadal', limit: limit, offset: offset),
)) {
  print(player.name);
}
```

## Links

- Docs: [docs.livetennisapi.com](https://docs.livetennisapi.com)
- Free API key: [livetennisapi.com/subscribe/free](https://livetennisapi.com/subscribe/free)
- Discord: [discord.gg/f8WUZHgDm6](https://discord.gg/f8WUZHgDm6)
- GitHub org: [github.com/livetennisapi](https://github.com/livetennisapi)

## License

MIT — see [LICENSE](LICENSE).

## Affiliate program

Know developers who need tennis data? The [affiliate program](https://affiliates.livetennisapi.com/program) pays 51% recurring commission for the life of every referred subscription — 30-day cookie, and the people you refer get 10% off.
