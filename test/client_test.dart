import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:livetennisapi/livetennisapi.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

/// Builds a client whose transport is a [MockClient] running [handler], so no
/// request ever leaves the process.
LiveTennisApi clientWith(
  Future<http.Response> Function(http.Request) handler, {
  int maxRetries = 0,
  AuthHeader authHeader = AuthHeader.bearer,
}) =>
    LiveTennisApi(
      apiKey: 'twjp_test_key',
      maxRetries: maxRetries,
      authHeader: authHeader,
      httpClient: MockClient(handler),
    );

http.Response _ok(String body) =>
    http.Response(body, 200, headers: {'content-type': 'application/json'});

void main() {
  group('requests', () {
    test('listMatches decodes a page and sends the default status + auth', () {
      late http.Request seen;
      final client = clientWith((req) async {
        seen = req;
        return _ok(liveMatchesPage);
      });

      return client.listMatches().then((page) {
        expect(page.length, 1);
        expect(page[0].tournament, contains('Waco'));
        expect(seen.url.path, '/api/public/v1/matches');
        expect(seen.url.queryParameters['status'], 'live');
        expect(seen.url.queryParameters['limit'], '50');
        expect(seen.headers['Authorization'], 'Bearer twjp_test_key');
        client.close();
      });
    });

    test('the tour filter is sent as its wire value', () async {
      late http.Request seen;
      final client = clientWith((req) async {
        seen = req;
        return _ok(liveMatchesPage);
      });
      await client.listMatches(tour: Tour.challenger);
      expect(seen.url.queryParameters['tour'], 'challenger');
      client.close();
    });

    test('authHeader: xApiKey uses the X-API-Key header', () async {
      late http.Request seen;
      final client = clientWith(
        (req) async {
          seen = req;
          return _ok(liveMatchesPage);
        },
        authHeader: AuthHeader.xApiKey,
      );
      await client.listMatches();
      expect(seen.headers['X-API-Key'], 'twjp_test_key');
      expect(seen.headers.containsKey('Authorization'), isFalse);
      client.close();
    });

    test('getMatchScore decodes a null-server score', () async {
      final client = clientWith((req) async => _ok(nullServerScore));
      final score = await client.getMatchScore(22313);
      expect(score, isNotNull);
      expect(score!.server, isNull);
      expect(score.gamesForSet(0), (2, 3));
      client.close();
    });
  });

  group('errors', () {
    test('403 upgrade_required throws UpgradeRequiredException with a tier',
        () async {
      final client = clientWith(
        (req) async => http.Response(upgradeRequiredBody, 403),
      );

      try {
        await client.getMatchAnalysis(22313); // /analysis => ULTRA
        fail('expected UpgradeRequiredException');
      } on UpgradeRequiredException catch (e) {
        expect(e.statusCode, 403);
        expect(e.code, 'upgrade_required');
        expect(e.requiredTier, 'ULTRA');
        expect(e.toString(), contains('ULTRA'));
      }
      client.close();
    });

    test('403 on /history is attributed to BASIC', () async {
      final client = clientWith(
        (req) async => http.Response(upgradeRequiredBody, 403),
      );
      await expectLater(
        client.listCompletedMatches(),
        throwsA(isA<UpgradeRequiredException>()
            .having((e) => e.requiredTier, 'requiredTier', 'BASIC')),
      );
      client.close();
    });

    test('400 bad tour throws BadRequestException carrying the code', () async {
      final client = clientWith(
        (req) async => http.Response(badRequestBody, 400),
      );
      await expectLater(
        client.listMatches(),
        throwsA(isA<BadRequestException>()
            .having((e) => e.code, 'code', 'invalid_tour')),
      );
      client.close();
    });

    test('401 throws UnauthorizedException', () async {
      final client = clientWith(
        (req) async => http.Response('{"error":"unauthorized"}', 401),
      );
      await expectLater(
        client.listMatches(),
        throwsA(isA<UnauthorizedException>()),
      );
      client.close();
    });

    test('429 throws RateLimitedException with retryAfter from the header',
        () async {
      final client = clientWith(
        (req) async => http.Response(
          '{"error":"rate_limited"}',
          429,
          headers: {'retry-after': '12'},
        ),
      );
      try {
        await client.listMatches();
        fail('expected RateLimitedException');
      } on RateLimitedException catch (e) {
        expect(e.statusCode, 429);
        expect(e.retryAfter, 12);
      }
      client.close();
    });

    test('an unmapped 5xx throws ServerException', () async {
      final client = clientWith((req) async => http.Response('boom', 500));
      await expectLater(
        client.getMatch(1),
        throwsA(isA<ServerException>()),
      );
      client.close();
    });
  });

  group('retries', () {
    test('a 500 then 200 is retried and succeeds', () async {
      var calls = 0;
      final client = clientWith(
        (req) async {
          calls++;
          return calls == 1 ? http.Response('err', 500) : _ok(liveMatchesPage);
        },
        maxRetries: 2,
      );
      final page = await client.listMatches();
      expect(page.length, 1);
      expect(calls, 2);
      client.close();
    });

    test('a 400 is never retried', () async {
      var calls = 0;
      final client = clientWith(
        (req) async {
          calls++;
          return http.Response(badRequestBody, 400);
        },
        maxRetries: 3,
      );
      await expectLater(
          client.listMatches(), throwsA(isA<BadRequestException>()));
      expect(calls, 1);
      client.close();
    });
  });

  group('new filters', () {
    test('players is sent as a repeated player parameter', () async {
      late http.Request seen;
      final client = clientWith((req) async {
        seen = req;
        return _ok(liveMatchesPage);
      });
      await client.listMatches(players: [101, 102], country: 'ned');
      expect(seen.url.queryParametersAll['player'], ['101', '102']);
      expect(seen.url.queryParameters['country'], 'ned');
      client.close();
    });

    test('from/to and coverage reach /history/matches', () async {
      late http.Request seen;
      final client = clientWith((req) async {
        seen = req;
        return _ok('{"data": []}');
      });
      await client.listCompletedMatches(
        tour: Tour.juniors,
        from: '2026-08-01',
        to: '2026-08-07',
        coverage: 'from_start',
      );
      expect(seen.url.path, '/api/public/v1/history/matches');
      expect(seen.url.queryParameters['tour'], 'juniors');
      expect(seen.url.queryParameters['from'], '2026-08-01');
      expect(seen.url.queryParameters['to'], '2026-08-07');
      expect(seen.url.queryParameters['coverage'], 'from_start');
      client.close();
    });
  });

  group('1.1 endpoints', () {
    test('getMatchTape defaults to the raw sequence (no parameter)', () async {
      late http.Request seen;
      final client = clientWith((req) async {
        seen = req;
        return _ok(tapeBody);
      });
      final tape = await client.getMatchTape(24101);
      expect(seen.url.path, '/api/public/v1/history/matches/24101');
      expect(seen.url.queryParameters.containsKey('sequence'), isFalse);
      expect(tape!.tape.length, 3);
      client.close();
    });

    test('getMatchTape sequence: clean is sent on the wire', () async {
      late http.Request seen;
      final client = clientWith((req) async {
        seen = req;
        return _ok(tapeBody);
      });
      final tape =
          await client.getMatchTape(24101, sequence: TapeSequence.clean);
      expect(seen.url.queryParameters['sequence'], 'clean');
      expect(tape!.tape[1].pointWinner, 1);
      client.close();
    });

    test('getHeadToHead sends both name fragments', () async {
      late http.Request seen;
      final client = clientWith((req) async {
        seen = req;
        return _ok(h2hBody);
      });
      final h2h = await client.getHeadToHead(p1: 'player o', p2: 'player t');
      expect(seen.url.path, '/api/public/v1/h2h');
      expect(seen.url.queryParameters['p1'], 'player o');
      expect(h2h!.totals!.meetings, 5);
      client.close();
    });

    test('listRankings listing mode sends system, not player', () async {
      late http.Request seen;
      final client = clientWith((req) async {
        seen = req;
        return _ok(rankingsListingPage);
      });
      final page = await client.listRankings(systems: [RankingSystem.atp]);
      expect(seen.url.path, '/api/public/v1/rankings');
      expect(seen.url.queryParametersAll['system'], ['atp']);
      expect(seen.url.queryParameters.containsKey('player'), isFalse);
      expect(page[0].previousRank, 2);
      client.close();
    });

    test('listRankings per-player mode repeats player and passes as_of',
        () async {
      late http.Request seen;
      final client = clientWith((req) async {
        seen = req;
        return _ok('{"data": []}');
      });
      await client.listRankings(
        players: [501, 502],
        asOf: '2026-08-03',
        systems: [RankingSystem.itfMen, RankingSystem.utr],
      );
      expect(seen.url.queryParametersAll['player'], ['501', '502']);
      expect(seen.url.queryParametersAll['system'], ['itf_mt', 'utr']);
      expect(seen.url.queryParameters['as_of'], '2026-08-03');
      client.close();
    });

    test('getWsToken decodes the channel vocabulary', () async {
      final client = clientWith((req) async => _ok(wsTokenBody));
      final token = await client.getWsToken();
      expect(token!.channels!.slate, 'slate:all');
      expect(token.matchChannel(7), 'match:7');
      client.close();
    });

    test('listHistoryPackages omits the default kind and sends year',
        () async {
      late http.Request seen;
      final client = clientWith((req) async {
        seen = req;
        return _ok(packagesPage);
      });
      await client.listHistoryPackages(year: '2025');
      expect(seen.url.path, '/api/public/v1/history/packages');
      expect(seen.url.queryParameters.containsKey('kind'), isFalse);
      expect(seen.url.queryParameters['year'], '2025');
      client.close();
    });

    test('archive, rally and charting requests hit their paths', () async {
      final paths = <String>[];
      final client = clientWith((req) async {
        paths.add(req.url.path);
        return _ok('{"data": []}');
      });
      await client.listArchiveMatches(tour: ArchiveTour.wta, name: 'graf');
      await client.listArchivePlayers(name: 'graf');
      await client.listRallyMatches(gender: 'W');
      expect(paths, [
        '/api/public/v1/history/archive/matches',
        '/api/public/v1/history/archive/players',
        '/api/public/v1/rally/matches',
      ]);
      client.close();
    });
  });

  group('1.2 endpoints', () {
    test('getUsage decodes the quota summary', () async {
      late http.Request seen;
      final client = clientWith((req) async {
        seen = req;
        return _ok(usageBody);
      });
      final usage = await client.getUsage();
      expect(seen.url.path, '/api/public/v1/usage');
      expect(usage!.tier, 'free');
      expect(usage.limits!.perDay, 100);
      expect(usage.today!.remainingDay, 59);
      client.close();
    });

    test('tournaments: listing filters and single lookup by stable id',
        () async {
      final requests = <http.Request>[];
      final client = clientWith((req) async {
        requests.add(req);
        return req.url.path.endsWith('/tournaments')
            ? _ok(tournamentsPage)
            : _ok(tournamentBody);
      });
      final page = await client.listTournaments(search: 'kitz', tour: Tour.atp);
      expect(page[0].category, 'atp_250');
      expect(requests[0].url.queryParameters['search'], 'kitz');
      final t = await client.getTournament('atp-kitzbuhel-singles');
      expect(
        requests[1].url.path,
        '/api/public/v1/tournaments/atp-kitzbuhel-singles',
      );
      expect(t!.country, 'AT');
      client.close();
    });

    test('listMatchPrices sends limit/minutes and decodes bare ticks',
        () async {
      late http.Request seen;
      final client = clientWith((req) async {
        seen = req;
        return _ok(matchPricesPage);
      });
      final page = await client.listMatchPrices(22313, limit: 2, minutes: 60);
      expect(seen.url.path, '/api/public/v1/matches/22313/prices');
      expect(seen.url.queryParameters['limit'], '2');
      expect(seen.url.queryParameters['minutes'], '60');
      expect(page.length, 2);
      expect(page[0].mid, 0.62);
      expect(page.meta!.hasMore, isTrue); // clipped window, not end-of-data
      client.close();
    });

    test('createWebhook POSTs a JSON body and returns the one-time secret',
        () async {
      late http.Request seen;
      final client = clientWith((req) async {
        seen = req;
        return http.Response(webhookCreatedBody, 201,
            headers: {'content-type': 'application/json'});
      });
      final hook = await client.createWebhook(
        url: 'https://example.invalid/hooks/tennis',
        events: [WebhookEvent.score, WebhookEvent.breakPoint],
      );
      expect(seen.method, 'POST');
      expect(seen.url.path, '/api/public/v1/webhooks');
      expect(seen.headers['Content-Type'], contains('application/json'));
      expect(jsonDecode(seen.body), {
        'url': 'https://example.invalid/hooks/tennis',
        'events': ['score', 'break_point'],
      });
      expect(hook!.secret, 'whsec_example_shown_once');
      client.close();
    });

    test('createWebhook omits events so the server default applies',
        () async {
      late http.Request seen;
      final client = clientWith((req) async {
        seen = req;
        return http.Response(webhookCreatedBody, 201);
      });
      await client.createWebhook(url: 'https://example.invalid/h');
      expect(
        (jsonDecode(seen.body) as Map).containsKey('events'),
        isFalse,
      );
      client.close();
    });

    test('listWebhooks GETs the collection (no secret in rows)', () async {
      late http.Request seen;
      final client = clientWith((req) async {
        seen = req;
        return _ok(webhooksListPage);
      });
      final page = await client.listWebhooks();
      expect(seen.method, 'GET');
      expect(page[0].secret, isNull);
      client.close();
    });

    test('deleteWebhook sends DELETE and returns the deleted count',
        () async {
      late http.Request seen;
      final client = clientWith((req) async {
        seen = req;
        return _ok('{"deleted": 1}');
      });
      final deleted = await client.deleteWebhook(31);
      expect(seen.method, 'DELETE');
      expect(seen.url.path, '/api/public/v1/webhooks/31');
      expect(deleted, 1);
      client.close();
    });

    test('a 4th webhook is a 409 ConflictException with webhook_limit',
        () async {
      final client = clientWith(
        (req) async => http.Response(webhookLimitBody, 409),
      );
      await expectLater(
        client.createWebhook(url: 'https://example.invalid/h'),
        throwsA(isA<ConflictException>()
            .having((e) => e.code, 'code', 'webhook_limit')),
      );
      client.close();
    });
  });

  group('tier attribution', () {
    Future<String?> tierFor(Future<void> Function(LiveTennisApi) call) async {
      final client = clientWith(
        (req) async => http.Response(upgradeRequiredBody, 403),
      );
      try {
        await call(client);
        fail('expected UpgradeRequiredException');
      } on UpgradeRequiredException catch (e) {
        return e.requiredTier;
      } finally {
        client.close();
      }
    }

    test('rankings listing mode is PRO, per-player mode is ULTRA', () async {
      expect(
        await tierFor((c) => c.listRankings(systems: [RankingSystem.atp])),
        'PRO',
      );
      expect(await tierFor((c) => c.listRankings(players: [501])), 'ULTRA');
    });

    test('statistics, rally-by-match-id, charting and ws-token are ULTRA',
        () async {
      expect(await tierFor((c) => c.getMatchStatistics(1)), 'ULTRA');
      // /history/matches/{id}/rally must resolve to ULTRA, not BASIC.
      expect(await tierFor((c) => c.getMatchRally(1)), 'ULTRA');
      expect(await tierFor((c) => c.getChartingPlayer('federer')), 'ULTRA');
      expect(await tierFor((c) => c.getWsToken()), 'ULTRA');
      expect(await tierFor((c) => c.listWebhooks()), 'ULTRA');
    });

    test('bare match price ticks are PRO', () async {
      expect(await tierFor((c) => c.listMatchPrices(1)), 'PRO');
    });

    test('h2h and the archive are BASIC; packages are PRO', () async {
      expect(
        await tierFor((c) => c.getHeadToHead(p1: 'one', p2: 'two')),
        'BASIC',
      );
      expect(await tierFor((c) => c.listArchiveMatches()), 'BASIC');
      expect(await tierFor((c) => c.listHistoryPackages()), 'PRO');
      expect(
        await tierFor(
            (c) => c.listHistoryPackages(kind: PackageKind.rankings)),
        'ULTRA',
      );
    });

    test('listMatches(status: completed) is attributed to BASIC', () async {
      expect(
        await tierFor((c) => c.listMatches(status: MatchStatus.completed)),
        'BASIC',
      );
    });
  });

  group('429 shapes', () {
    test('a daily 429 surfaces scope, limit_per_day and resets_at', () async {
      final client = clientWith(
        (req) async => http.Response(dailyLimitBody, 429),
      );
      try {
        await client.listMatches();
        fail('expected RateLimitedException');
      } on RateLimitedException catch (e) {
        expect(e.scope, 'day');
        expect(e.limitPerDay, 100);
        expect(e.resetsAt, DateTime.utc(2026, 8, 7, 21));
        expect(e.toString(), contains('resets at'));
      }
      client.close();
    });

    test('abuse_throttled throws AbuseThrottledException with retryAtEpoch',
        () async {
      final client = clientWith(
        (req) async => http.Response(abuseThrottledBody, 429),
      );
      try {
        await client.listMatches();
        fail('expected AbuseThrottledException');
      } on AbuseThrottledException catch (e) {
        expect(e.code, 'abuse_throttled');
        expect(e.retryAtEpoch, 1754650800);
        expect(e.retryAt!.isUtc, isTrue);
        expect(e.toString(), contains('retry loop'));
      }
      client.close();
    });

    test('abuse_throttled is never auto-retried, even with retries budgeted',
        () async {
      var calls = 0;
      final client = clientWith(
        (req) async {
          calls++;
          return http.Response(abuseThrottledBody, 429);
        },
        maxRetries: 3,
      );
      await expectLater(
        client.listMatches(),
        throwsA(isA<AbuseThrottledException>()),
      );
      expect(calls, 1);
      client.close();
    });

    test('an ordinary 429 is still retried within budget', () async {
      var calls = 0;
      final client = clientWith(
        (req) async {
          calls++;
          return calls == 1
              ? http.Response('{"error":"rate_limited"}', 429,
                  headers: {'retry-after': '0'})
              : _ok(liveMatchesPage);
        },
        maxRetries: 1,
      );
      final page = await client.listMatches();
      expect(page.length, 1);
      expect(calls, 2);
      client.close();
    });
  });

  group('pagination', () {
    test('paginate walks pages and stops on a short page', () async {
      List<Map<String, dynamic>> matchList(List<int> ids) => [
            for (final id in ids) {'id': id, 'tournament': 'T'}
          ];
      final client = clientWith((req) async {
        final offset = int.parse(req.url.queryParameters['offset'] ?? '0');
        final ids = offset == 0 ? [1, 2] : [3];
        return _ok(jsonEncode({'data': matchList(ids)}));
      });

      final seen = <int?>[];
      await for (final m in client.paginate(
        ({int limit = 2, int offset = 0}) =>
            client.listMatches(limit: limit, offset: offset),
        pageSize: 2,
      )) {
        seen.add(m.id);
      }
      expect(seen, [1, 2, 3]);
      client.close();
    });
  });
}
