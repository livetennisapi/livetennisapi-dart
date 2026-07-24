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
