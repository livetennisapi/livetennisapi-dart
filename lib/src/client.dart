/// The Live Tennis API client.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'errors.dart';
import 'models.dart';

/// The package version, sent in the `User-Agent` header.
const String packageVersion = '1.0.0';

/// The default API base URL.
const String defaultBaseUrl = 'https://api.livetennisapi.com/api/public/v1';

const int _maxLimit = 200;

/// Which header carries the API key.
enum AuthHeader {
  /// `Authorization: Bearer <key>` (the default).
  bearer,

  /// `X-API-Key: <key>`.
  xApiKey,
}

/// The lifecycle status filter accepted by [LiveTennisApi.listMatches].
enum MatchStatus {
  /// Matches in progress.
  live,

  /// Scheduled matches that have not started.
  upcoming,

  /// Finished matches.
  completed;

  /// The wire value sent as the `status` query parameter.
  String get wire => name;
}

/// The `tour` filter accepted by [LiveTennisApi.listMatches] and
/// [LiveTennisApi.listFixtures].
///
/// Each value covers its singles **and** doubles draws — `atp` includes ATP
/// doubles, and `juniors` covers the boys' and girls' Grand Slam draws. An
/// unrecognised value is a `400` ([BadRequestException]), never a silent
/// pass-through.
///
/// This enum is for the **filter only**. A record's own `tour` field (on
/// [Player] and [Fixture]) is a granular, sometimes UPPERCASE string that does
/// not map onto this vocabulary; keep it as a raw string.
enum Tour {
  /// ATP (men's) singles and doubles.
  atp,

  /// WTA (women's) singles and doubles.
  wta,

  /// Challenger circuit.
  challenger,

  /// ITF circuit.
  itf,

  /// Junior Grand Slam draws (boys' and girls').
  juniors;

  /// The wire value sent as the `tour` query parameter.
  String get wire => name;
}

/// Endpoints that need more than the FREE floor, so a 403 can name the tier
/// instead of surfacing the API's bare `{"error": "upgrade_required"}`. The
/// first marker that matches the path wins.
const List<(String, String)> _tierRequirements = [
  ('/analysis', 'ULTRA'),
  ('/events', 'PRO'),
  ('/markets', 'PRO'),
  ('/history', 'BASIC'),
];

String? _requiredTierFor(String path) {
  for (final (marker, tier) in _tierRequirements) {
    if (path.contains(marker)) return tier;
  }
  return null;
}

num? _retryAfterSeconds(Map<String, String> headers) {
  final raw = headers['retry-after'];
  if (raw == null) return null;
  final value = num.tryParse(raw.trim());
  return (value != null && value >= 0) ? value : null;
}

/// A read-only client for the [Live Tennis API](https://livetennisapi.com).
///
/// Real-time tennis scores, players, rankings, match-winner market prices and
/// model win-probability for ATP, WTA, Challenger and ITF.
///
/// ```dart
/// final client = LiveTennisApi(apiKey: 'twjp_…');
/// try {
///   final page = await client.listMatches(status: MatchStatus.live);
///   for (final match in page.data) {
///     print('${match.tournament}: ${match.p1?.name} vs ${match.p2?.name}');
///   }
/// } finally {
///   client.close();
/// }
/// ```
///
/// The client depends only on `package:http`, with no Flutter dependency, so it
/// runs unchanged in a pure-Dart program, a Flutter app, or on the web.
///
/// Automatic retries apply to `429` and `5xx` only, honouring `Retry-After`
/// with exponential backoff and jitter; every other `4xx` is a client-side
/// mistake that cannot start working, so it is never retried. Call [close] when
/// you are done, unless you passed your own [http.Client].
class LiveTennisApi {
  /// The API key sent on every request.
  final String apiKey;

  /// The base URL. Defaults to [defaultBaseUrl].
  final Uri baseUrl;

  /// Per-request timeout. Defaults to 30 seconds.
  final Duration timeout;

  /// The maximum number of retries for `429`/`5xx`. Defaults to 2.
  final int maxRetries;

  /// Which header carries [apiKey]. Defaults to [AuthHeader.bearer].
  final AuthHeader authHeader;

  final http.Client _http;
  final bool _ownsHttpClient;
  final Random _random = Random();

  /// Creates a client.
  ///
  /// [apiKey] is your `twjp_` key. Pass an [httpClient] to inject a custom
  /// transport (for tests or connection pooling); when omitted, an internal one
  /// is created and closed by [close].
  LiveTennisApi({
    required this.apiKey,
    Uri? baseUrl,
    this.timeout = const Duration(seconds: 30),
    this.maxRetries = 2,
    this.authHeader = AuthHeader.bearer,
    http.Client? httpClient,
  })  : baseUrl = baseUrl ?? Uri.parse(defaultBaseUrl),
        _http = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null;

  /// Closes the underlying HTTP client, unless one was supplied to the
  /// constructor (in which case the caller owns its lifecycle).
  void close() {
    if (_ownsHttpClient) _http.close();
  }

  // -- transport --------------------------------------------------------------

  Map<String, String> _headers() {
    final headers = <String, String>{
      'Accept': 'application/json',
      'User-Agent': 'livetennisapi-dart/$packageVersion',
    };
    if (apiKey.isNotEmpty) {
      if (authHeader == AuthHeader.bearer) {
        headers['Authorization'] = 'Bearer $apiKey';
      } else {
        headers['X-API-Key'] = apiKey;
      }
    }
    return headers;
  }

  Uri _uri(String path, [Map<String, dynamic>? params]) {
    final query = <String, String>{};
    params?.forEach((key, value) {
      if (value != null) query[key] = '$value';
    });
    return baseUrl.replace(
      path: baseUrl.path + path,
      queryParameters: query.isEmpty ? null : query,
    );
  }

  bool _shouldRetry(int status) => status == 429 || status >= 500;

  Duration _backoff(int attempt, num? retryAfter) {
    if (retryAfter != null) {
      return Duration(milliseconds: min(retryAfter * 1000, 60000).round());
    }
    final ms = min(500 * pow(2, attempt) + _random.nextDouble() * 250, 10000.0);
    return Duration(milliseconds: ms.round());
  }

  Object? _decode(http.Response response) {
    if (response.body.isEmpty) return null;
    try {
      return jsonDecode(response.body);
    } catch (_) {
      return null;
    }
  }

  Never _throwFor(http.Response response, String path, Uri uri) {
    final body = _decode(response);
    final code = (body is Map && body['error'] is String)
        ? body['error'] as String
        : null;
    final message = (code != null && code.isNotEmpty)
        ? code
        : (response.reasonPhrase?.isNotEmpty ?? false)
            ? response.reasonPhrase!
            : 'request failed';
    throw exceptionForStatus(
      response.statusCode,
      message,
      code: code,
      body: body,
      headers: response.headers,
      url: uri.toString(),
      requiredTier: _requiredTierFor(path),
      retryAfter: _retryAfterSeconds(response.headers),
    );
  }

  Future<Object?> _request(String path, [Map<String, dynamic>? params]) async {
    final uri = _uri(path, params);

    for (var attempt = 0;; attempt++) {
      http.Response response;
      try {
        response = await _http.get(uri, headers: _headers()).timeout(timeout);
      } catch (_) {
        // Network error or timeout: retry within budget, otherwise rethrow.
        if (attempt >= maxRetries) rethrow;
        await Future<void>.delayed(_backoff(attempt, null));
        continue;
      }

      if (_shouldRetry(response.statusCode) && attempt < maxRetries) {
        await Future<void>.delayed(
          _backoff(attempt, _retryAfterSeconds(response.headers)),
        );
        continue;
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        _throwFor(response, path, uri);
      }
      return _decode(response);
    }
  }

  // -- endpoints --------------------------------------------------------------

  /// Liveness probe. Needs no authentication.
  Future<Map<String, dynamic>> health() async {
    final body = await _request('/health');
    return body is Map ? Map<String, dynamic>.from(body) : <String, dynamic>{};
  }

  /// Matches by lifecycle [status], optionally restricted to one [tour].
  ///
  /// FREE. Returns each match with its latest [Match.score].
  Future<Page<Match>> listMatches({
    MatchStatus status = MatchStatus.live,
    Tour? tour,
    int limit = 50,
    int offset = 0,
  }) async {
    final body = await _request('/matches', {
      'status': status.wire,
      'tour': tour?.wire,
      'limit': limit,
      'offset': offset,
    });
    return Page.fromJson(body, Match.fromJson);
  }

  /// Full match detail. Embeds [Match.market] at PRO and [Match.analysis] at
  /// ULTRA. FREE for the core fields.
  Future<Match?> getMatch(int matchId) async {
    final body = await _request('/matches/$matchId');
    return body is Map ? Match.fromJson(Map<String, dynamic>.from(body)) : null;
  }

  /// Current score only — the lowest-latency read available. FREE.
  Future<Score?> getMatchScore(int matchId) async {
    final body = await _request('/matches/$matchId/score');
    return body is Map ? Score.fromJson(Map<String, dynamic>.from(body)) : null;
  }

  /// Match events, newest first. **PRO.**
  Future<Page<MatchEvent>> listMatchEvents(
    int matchId, {
    int limit = 50,
    int offset = 0,
  }) async {
    final body = await _request(
      '/matches/$matchId/events',
      {'limit': limit, 'offset': offset},
    );
    return Page.fromJson(body, MatchEvent.fromJson);
  }

  /// Model analysis for a match. **ULTRA.**
  Future<Analysis?> getMatchAnalysis(int matchId) async {
    final body = await _request('/matches/$matchId/analysis');
    return body is Map
        ? Analysis.fromJson(Map<String, dynamic>.from(body))
        : null;
  }

  /// Search players by name. Ranked players come first. FREE.
  Future<Page<Player>> searchPlayers({
    String? search,
    int limit = 50,
    int offset = 0,
  }) async {
    final body = await _request('/players', {
      'search': search,
      'limit': limit,
      'offset': offset,
    });
    return Page.fromJson(body, Player.fromJson);
  }

  /// One player's bio, ranking and cached stats. FREE.
  Future<Player?> getPlayer(int playerId) async {
    final body = await _request('/players/$playerId');
    return body is Map
        ? Player.fromJson(Map<String, dynamic>.from(body))
        : null;
  }

  /// Match-winner market(s) for a match. **PRO.**
  Future<Page<Market>> listMarkets(int matchId) async {
    final body = await _request('/markets', {'match_id': matchId});
    return Page.fromJson(body, Market.fromJson);
  }

  /// Market with recent price ticks per side, newest first. **PRO.**
  Future<Market?> getMarketPrices(int matchId, {int limit = 50}) async {
    final body = await _request('/markets/$matchId/prices', {'limit': limit});
    return body is Map
        ? Market.fromJson(Map<String, dynamic>.from(body))
        : null;
  }

  /// Completed matches, newest first, with a derived [Match.winner]. **BASIC.**
  Future<Page<Match>> listCompletedMatches({
    int limit = 50,
    int offset = 0,
  }) async {
    final body = await _request(
      '/history/matches',
      {'limit': limit, 'offset': offset},
    );
    return Page.fromJson(body, Match.fromJson);
  }

  /// Upcoming scheduled fixtures, earliest first, optionally by [tour]. FREE.
  ///
  /// Note the API may currently return some finished matches here; they are
  /// passed through unchanged.
  Future<Page<Fixture>> listFixtures({
    Tour? tour,
    int limit = 50,
    int offset = 0,
  }) async {
    final body = await _request('/fixtures', {
      'tour': tour?.wire,
      'limit': limit,
      'offset': offset,
    });
    return Page.fromJson(body, Fixture.fromJson);
  }

  // -- pagination -------------------------------------------------------------

  /// Walks every page of a list endpoint, yielding each item.
  ///
  /// ```dart
  /// await for (final player in client.paginate(
  ///   ({limit = 200, offset = 0}) =>
  ///       client.searchPlayers(search: 'nadal', limit: limit, offset: offset),
  /// )) {
  ///   print(player.name);
  /// }
  /// ```
  ///
  /// Stops on the first short page, which is the only reliable end-of-data
  /// signal: [ListMeta.count] describes the page, not the total.
  Stream<T> paginate<T>(
    Future<Page<T>> Function({int limit, int offset}) fetchPage, {
    int pageSize = _maxLimit,
  }) async* {
    final limit = max(1, min(pageSize, _maxLimit));
    var offset = 0;
    while (true) {
      final page = await fetchPage(limit: limit, offset: offset);
      for (final item in page.data) {
        yield item;
      }
      if (page.data.length < limit) return;
      offset += limit;
    }
  }
}
