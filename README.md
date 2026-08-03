# livetennisapi

A Dart and Flutter client for the [Live Tennis API](https://livetennisapi.com) —
real-time tennis scores, players, rankings, fixtures, match-winner market prices
and model win-probability for ATP, WTA, Challenger and ITF, over REST.

- **Pure Dart, Flutter-friendly.** Depends only on `package:http`; no Flutter
  dependency, so it runs in a server, a Flutter app, or on the web.
- **Typed and null-correct.** Immutable models with `fromJson`, a nullable
  `Score`, string points, and player-major games handled for you.
- **Forward-compatible.** The API ships additive changes within `v1`; unknown
  fields never break decoding and stay reachable via each model's `raw` map.
- **Typed errors.** `UpgradeRequiredException` (403) names the tier you need;
  `RateLimitedException` (429) carries `retryAfter`.

## Install

```yaml
dependencies:
  livetennisapi: ^1.0.0
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
      print('${match.tournament}: '
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

### Authentication

Pass your `twjp_` key to the constructor. By default it is sent as
`Authorization: Bearer <key>`; pass `authHeader: AuthHeader.xApiKey` to use the
`X-API-Key` header instead.

```dart
final client = LiveTennisApi(
  apiKey: 'twjp_your_key',
  authHeader: AuthHeader.xApiKey,
  timeout: const Duration(seconds: 20),
  maxRetries: 3,
);
```

### Tiers

Access is tiered (FREE / BASIC / PRO / ULTRA). Scores, players and fixtures are
FREE; historical results need BASIC; events and market prices need PRO; model
analysis needs ULTRA. A call above your tier throws `UpgradeRequiredException`,
whose `requiredTier` names the plan that unlocks the endpoint.

## Reading a score

`Score.games` is **player-major**: `[[games_p1...], [games_p2...]]`, each side a
per-set list that grows as the match plays. Use `gamesForSet` rather than
indexing by hand:

```dart
final (p1, p2) = score.gamesForSet(0); // games in set 1, as (p1, p2)
```

`Score.points` are strings (`"0"`, `"15"`, `"30"`, `"40"`, `"AD"`), and
`Score.server` is `1`, `2`, or `null`.

## Pagination

```dart
await for (final player in client.paginate(
  ({limit = 200, offset = 0}) =>
      client.searchPlayers(search: 'nadal', limit: limit, offset: offset),
)) {
  print(player.name);
}
```

## Endpoints

`health`, `listMatches`, `getMatch`, `getMatchScore`, `listMatchEvents` (PRO),
`getMatchAnalysis` (ULTRA), `searchPlayers`, `getPlayer`, `listMarkets` (PRO),
`getMarketPrices` (PRO), `listCompletedMatches` (BASIC), `listFixtures`.

## License

MIT — see [LICENSE](LICENSE).

## Affiliate program

Know developers who need tennis data? The [affiliate program](https://affiliates.livetennisapi.com/program) pays 51% recurring commission for the life of every referred subscription — 30-day cookie, and the people you refer get 10% off.
