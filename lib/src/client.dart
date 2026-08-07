/// The Live Tennis API client.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'errors.dart';
import 'models.dart';

/// The package version, sent in the `User-Agent` header.
const String packageVersion = '1.2.0';

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
/// first marker that matches the path wins, so the more specific markers come
/// first (`/rally` and `/history/packages` before `/history`).
const List<(String, String)> _tierRequirements = [
  ('/analysis', 'ULTRA'),
  ('/statistics', 'ULTRA'),
  ('/rally', 'ULTRA'),
  ('/charting', 'ULTRA'),
  ('/ws-token', 'ULTRA'),
  ('/webhooks', 'ULTRA'),
  ('/events', 'PRO'),
  ('/markets', 'PRO'),
  ('/prices', 'PRO'),
  ('/history/packages', 'PRO'),
  ('/h2h', 'BASIC'),
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

/// The `sequence` mode of a match tape.
enum TapeSequence {
  /// Every row committed — deliberately non-monotonic, since independent
  /// sources race and a higher-trust one may correct a lower-trust one
  /// backwards. The default.
  raw,

  /// One row per distinct score state, keeping the last assertion of each.
  /// The only mode that carries [TapeRow.pointWinner].
  clean;

  /// The wire value sent as the `sequence` query parameter.
  String get wire => name;
}

/// A ranking system accepted by [LiveTennisApi.listRankings].
///
/// Systems are never collapsed into a single "rank" — they are not
/// comparable. ATP/WTA and the ITF circuits carry rank+points; UTR carries a
/// rating with null rank and points, and has no listing mode.
enum RankingSystem {
  /// ATP rankings.
  atp('atp'),

  /// WTA rankings.
  wta('wta'),

  /// ITF junior circuit.
  itfJuniors('itf_jt'),

  /// ITF men's World Tennis Tour.
  itfMen('itf_mt'),

  /// ITF women's World Tennis Tour.
  itfWomen('itf_wt'),

  /// UTR — a rating, not a ranking (per-player mode only).
  utr('utr');

  const RankingSystem(this.wire);

  /// The wire value sent as the `system` query parameter.
  final String wire;
}

/// The family of a bulk history package.
enum PackageKind {
  /// Point-by-point match tapes. The default.
  tape,

  /// As-of ranking records (ULTRA).
  rankings;

  /// The wire value sent as the `kind` query parameter.
  String get wire => name;
}

/// The tour filter of the deep results archive, which holds ATP and WTA only.
enum ArchiveTour {
  /// ATP archive rows.
  atp,

  /// WTA archive rows.
  wta;

  /// The wire value sent as the `tour` query parameter.
  String get wire => name;
}

/// An event a webhook can subscribe to.
enum WebhookEvent {
  /// Live score frames (the default subscription).
  score('score'),

  /// Break-point alert frames.
  breakPoint('break_point');

  const WebhookEvent(this.wire);

  /// The wire value sent in the `events` array.
  final String wire;
}

/// A read-only client for the [Live Tennis API](https://livetennisapi.com).
///
/// Real-time tennis scores, players, rankings, match-winner market prices and
/// model win-probability for ATP, WTA, Challenger, ITF and juniors.
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
    // A List value becomes a repeated query parameter (?player=1&player=2),
    // which Uri.replace supports via Iterable<String> values.
    final query = <String, dynamic>{};
    params?.forEach((key, value) {
      if (value == null) return;
      if (value is List) {
        if (value.isNotEmpty) query[key] = [for (final v in value) '$v'];
      } else {
        query[key] = '$value';
      }
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

  bool _isAbuseThrottled(http.Response response) {
    if (response.statusCode != 429) return false;
    final body = _decode(response);
    return body is Map && body['error'] == 'abuse_throttled';
  }

  Never _throwFor(http.Response response, String path, Uri uri,
      {String? tierHint}) {
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
      requiredTier: tierHint ?? _requiredTierFor(path),
      retryAfter: _retryAfterSeconds(response.headers),
    );
  }

  Future<Object?> _request(
    String path, [
    Map<String, dynamic>? params,
    String? tierHint,
  ]) async {
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

      if (_shouldRetry(response.statusCode) &&
          attempt < maxRetries &&
          // An abuse_throttled 429 is a 24-hour block; retrying it only digs
          // the hole deeper, so it is surfaced immediately.
          !_isAbuseThrottled(response)) {
        await Future<void>.delayed(
          _backoff(attempt, _retryAfterSeconds(response.headers)),
        );
        continue;
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        _throwFor(response, path, uri, tierHint: tierHint);
      }
      return _decode(response);
    }
  }

  /// A mutating request (POST/DELETE). Never auto-retried: retrying a create
  /// could duplicate the resource, so a transient failure surfaces instead.
  Future<Object?> _mutate(
    String method,
    String path, {
    Object? jsonBody,
  }) async {
    final uri = _uri(path);
    final request = http.Request(method, uri);
    request.headers.addAll(_headers());
    if (jsonBody != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(jsonBody);
    }
    final streamed = await _http.send(request).timeout(timeout);
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwFor(response, path, uri);
    }
    return _decode(response);
  }

  // -- endpoints --------------------------------------------------------------

  /// Liveness probe. Needs no authentication.
  Future<Map<String, dynamic>> health() async {
    final body = await _request('/health');
    return body is Map ? Map<String, dynamic>.from(body) : <String, dynamic>{};
  }

  /// Matches by lifecycle [status], with optional filters.
  ///
  /// FREE (`status: completed` needs BASIC or any History plan). Returns each
  /// match with its latest [Match.score].
  ///
  /// - [players]: match either participant by player id, up to 50 ids
  ///   (deduplicated union). An unknown id returns an empty list, not an
  ///   error.
  /// - [country]: either participant's lowercase 3-letter country code — the
  ///   same IOC-style vocabulary [Player.country] returns (`ned`, `sui`),
  ///   **not** ISO-3166. Players with no recorded country never match.
  /// - [from] / [to]: earliest/latest play date, `YYYY-MM-DD` or ISO-8601 UTC
  ///   datetime; a bare date is a UTC day boundary and `to` includes the
  ///   whole day. An unparseable value is a 400 `bad_date`.
  ///
  /// Unknown filter values are a 400 ([BadRequestException]) — never silently
  /// ignored.
  Future<Page<Match>> listMatches({
    MatchStatus status = MatchStatus.live,
    Tour? tour,
    List<int>? players,
    String? country,
    String? from,
    String? to,
    int limit = 50,
    int offset = 0,
  }) async {
    final body = await _request(
      '/matches',
      {
        'status': status.wire,
        'tour': tour?.wire,
        'player': players,
        'country': country,
        'from': from,
        'to': to,
        'limit': limit,
        'offset': offset,
      },
      status == MatchStatus.completed ? 'BASIC' : null,
    );
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

  /// Completed matches, newest first, with a derived [Match.winner].
  /// **BASIC**, or any History plan.
  ///
  /// Each item also carries a `tape` object (in [Match.raw]) saying what
  /// point-by-point data is held for it, so a whole page can be qualified in
  /// one call. Filters are the same as [listMatches] ([players] ≤ 50 ids,
  /// [country], [from]/[to], [tour]), plus [coverage] (`from_start`,
  /// `partial`, `reconstructed`, `reconstructed_partial`, `none`) to keep
  /// only matches whose tape has that coverage — note the coverage filter is
  /// applied **after** the page is cut, so a filtered page is routinely
  /// shorter than [limit] (and may be empty) while later pages still hold
  /// matching matches; a short filtered page is not an end-of-data signal.
  Future<Page<Match>> listCompletedMatches({
    Tour? tour,
    List<int>? players,
    String? country,
    String? from,
    String? to,
    String? coverage,
    int limit = 50,
    int offset = 0,
  }) async {
    final body = await _request('/history/matches', {
      'tour': tour?.wire,
      'player': players,
      'country': country,
      'from': from,
      'to': to,
      'coverage': coverage,
      'limit': limit,
      'offset': offset,
    });
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

  /// In-play statistics for one match — aces, double faults, serve split,
  /// hold/break %, break points, service and return points. **ULTRA.**
  ///
  /// Two families that are deliberately not merged: the typed fields of each
  /// [MatchStatisticsSide] are derived from the point-by-point record, while
  /// `measured` holds upstream counts (the only source of aces and double
  /// faults). Branch on [MatchStatistics.freshness] per family, and never
  /// compare the two ages — they use different clocks. `none` coverage
  /// returns 200 with null players, not a 404.
  Future<MatchStatistics?> getMatchStatistics(int matchId) async {
    final body = await _request('/matches/$matchId/statistics');
    return body is Map
        ? MatchStatistics.fromJson(Map<String, dynamic>.from(body))
        : null;
  }

  /// The per-match tape: point-by-point score sequence + per-point model
  /// probabilities. **BASIC**, or any History plan.
  ///
  /// Works on a **live** match too — the tape is assembled from whatever has
  /// been committed so far. [TapeSequence.raw] (default) returns every
  /// committed row; [TapeSequence.clean] returns one row per distinct score
  /// state and is the only mode carrying [TapeRow.pointWinner]. Check
  /// [MatchTape.meta] coverage before backtesting, and [MatchTape.tiebreaks]
  /// for per-set tiebreak final scores.
  Future<MatchTape?> getMatchTape(
    int matchId, {
    TapeSequence sequence = TapeSequence.raw,
  }) async {
    final body = await _request(
      '/history/matches/$matchId',
      {'sequence': sequence == TapeSequence.raw ? null : sequence.wire},
    );
    return body is Map
        ? MatchTape.fromJson(Map<String, dynamic>.from(body))
        : null;
  }

  /// Head-to-head between two players, across the results archive
  /// (1968–2022) and the API's own completed matches (2023 onward).
  /// **BASIC**, or any History plan.
  ///
  /// [p1] and [p2] are name fragments (min 3 chars). A fragment matching
  /// more than one player is a 400 `ambiguous_name` whose body lists the
  /// candidates — two people summed into one record would be a wrong answer.
  /// On ULTRA the response adds a per-player `stats` block
  /// ([HeadToHead.stats]).
  Future<HeadToHead?> getHeadToHead({
    required String p1,
    required String p2,
  }) async {
    final body = await _request('/h2h', {'p1': p1, 'p2': p2});
    return body is Map
        ? HeadToHead.fromJson(Map<String, dynamic>.from(body))
        : null;
  }

  /// Deep historical results, 1968–2022, newest tournament first. **BASIC**,
  /// or any History plan.
  ///
  /// A separate id space from `/matches` — archive people are identified by
  /// name — and the archive ends where the API's own point-by-point coverage
  /// begins (2023-01). [name] is a substring match on either player (min 3
  /// chars); [from]/[to] are `YYYY-MM-DD` **tournament start** dates; [round]
  /// takes the archive round codes (`F`, `SF`, `QF`, `R16`…`R128`, `RR`,
  /// `BR`, `Q1`–`Q4`, `ER`); [level] takes the source tier codes (`G` grand
  /// slam, `M` masters, `A` tour, `F` finals, `D` Davis Cup, `C` challenger,
  /// `O` olympics, or a futures category code such as `15`).
  Future<Page<ArchiveMatch>> listArchiveMatches({
    ArchiveTour? tour,
    String? name,
    String? from,
    String? to,
    String? round,
    String? level,
    int limit = 50,
    int offset = 0,
  }) async {
    final body = await _request('/history/archive/matches', {
      'tour': tour?.wire,
      'name': name,
      'from': from,
      'to': to,
      'round': round,
      'level': level,
      'limit': limit,
      'offset': offset,
    });
    return Page.fromJson(body, ArchiveMatch.fromJson);
  }

  /// One archive result, with per-match serve statistics where the era
  /// recorded them ([ArchiveMatch.stats]; null for most rows before 1991 —
  /// never synthesised). **BASIC**, or any History plan.
  Future<ArchiveMatch?> getArchiveMatch(int archiveId) async {
    final body = await _request('/history/archive/matches/$archiveId');
    return body is Map
        ? ArchiveMatch.fromJson(Map<String, dynamic>.from(body))
        : null;
  }

  /// Archive player bios — hand, date of birth, country, height and
  /// career-high rank, ordered by name. **BASIC**, or any History plan.
  ///
  /// The id space is the corpus person id that archive rows carry as
  /// `winner.playerId` / `loser.playerId`, scoped per tour — never a roster
  /// id. [name] is a substring filter (min 3 chars).
  Future<Page<ArchivePlayerBio>> listArchivePlayers({
    String? name,
    ArchiveTour? tour,
    int limit = 50,
    int offset = 0,
  }) async {
    final body = await _request('/history/archive/players', {
      'name': name,
      'tour': tour?.wire,
      'limit': limit,
      'offset': offset,
    });
    return Page.fromJson(body, ArchivePlayerBio.fromJson);
  }

  /// One player's whole archive career (1968–2022) in one response: W-L
  /// overall / by surface / by level / by year, titles, and the summed
  /// serve-stat block with derived ratios. **BASIC**, or any History plan.
  ///
  /// Everything is a sum or a ratio of sums — nothing is modelled. [name]
  /// must resolve to one person (min 3 chars); an ambiguous fragment is a
  /// 400 with the candidates, same rule as [getHeadToHead].
  Future<ArchiveCareer?> getArchiveCareer(String name) async {
    final body = await _request('/history/archive/career', {'name': name});
    return body is Map
        ? ArchiveCareer.fromJson(Map<String, dynamic>.from(body))
        : null;
  }

  /// Rankings — two modes on one endpoint.
  ///
  /// **Listing mode (PRO):** omit [players] and pass exactly one system in
  /// [systems] — returns the full published table in rank order, the newest
  /// week at or before [asOf]. Rows carry [RankingRecord.playerName] as
  /// published and a null [RankingRecord.playerId] for players outside the
  /// roster, so the table has no silent holes. `utr` has no listing (it is a
  /// rating, not a ranking).
  ///
  /// **Per-player mode (ULTRA):** pass [players] (≤ 50 roster ids) — returns,
  /// per system, the newest record effective **on or before** [asOf], the
  /// point-in-time answer (every other ranking field in this API is the
  /// current value joined at read time).
  ///
  /// [asOf] is `YYYY-MM-DD`; omit it for the latest known record. The page's
  /// `meta` carries a `coverage` object (via [ListMeta.raw]) — read it before
  /// trusting an empty result: ITF and UTR history begins 2026-07-29 and
  /// cannot be reconstructed earlier. [RankingRecord.previousRank] gives the
  /// prior snapshot week's rank (ATP/WTA only).
  Future<Page<RankingRecord>> listRankings({
    List<int>? players,
    String? asOf,
    List<RankingSystem>? systems,
    int limit = 50,
    int offset = 0,
  }) async {
    final perPlayer = players != null && players.isNotEmpty;
    final body = await _request(
      '/rankings',
      {
        'player': players,
        'as_of': asOf,
        'system': systems == null ? null : [for (final s in systems) s.wire],
        'limit': limit,
        'offset': offset,
      },
      perPlayer ? 'ULTRA' : 'PRO',
    );
    return Page.fromJson(body, RankingRecord.fromJson);
  }

  /// Mints a short-lived connection token for the high-fan-out push
  /// WebSocket feed. **ULTRA.**
  ///
  /// The response carries the [WsToken.wsUrl] to connect to and the channel
  /// vocabulary: per-match channels ([WsToken.matchChannel]) and the
  /// `slate:all` channel with every live score frame. Frames are the same
  /// allowlist score objects the polling endpoints return. Mint a fresh token
  /// on reconnect.
  Future<WsToken?> getWsToken() async {
    final body = await _request('/ws-token');
    return body is Map
        ? WsToken.fromJson(Map<String, dynamic>.from(body))
        : null;
  }

  /// Pre-built monthly bulk packages, newest period first. **PRO**, or a
  /// package/History subscription.
  ///
  /// [kind] selects the family: tapes (default) or as-of ranking records
  /// (`rankings` needs ULTRA). [year] (`YYYY`) lists every published month of
  /// that year — the year-archive listing, which needs ULTRA, History
  /// Business, or a 1-year package. Coverage is not a contiguous run of
  /// months; treat this listing as the authoritative set.
  Future<Page<HistoryPackage>> listHistoryPackages({
    PackageKind kind = PackageKind.tape,
    String? year,
  }) async {
    final body = await _request(
      '/history/packages',
      {
        'kind': kind == PackageKind.tape ? null : kind.wire,
        'year': year,
      },
      kind == PackageKind.rankings || year != null ? 'ULTRA' : null,
    );
    return Page.fromJson(body, HistoryPackage.fromJson);
  }

  /// One monthly package's manifest — file names, sizes and SHA-256
  /// checksums. **PRO**, or a package/History subscription; `rankings` needs
  /// ULTRA.
  ///
  /// [period] is `YYYY-MM`. To download the file itself, request the same
  /// path with `?format=jsonl|csv` over plain HTTP and stream the attachment
  /// — this client returns the JSON manifest only.
  Future<HistoryPackage?> getHistoryPackage(
    String period, {
    PackageKind kind = PackageKind.tape,
  }) async {
    final body = await _request(
      '/history/packages/$period',
      {'kind': kind == PackageKind.tape ? null : kind.wire},
      kind == PackageKind.rankings ? 'ULTRA' : null,
    );
    return body is Map
        ? HistoryPackage.fromJson(Map<String, dynamic>.from(body))
        : null;
  }

  /// Charted matches with shot-by-shot data, newest first. **ULTRA.**
  ///
  /// Rally construction is the layer below the tape: the tape says what the
  /// score became after each point, this says how the point was played. Its
  /// own id space — ask this listing for the authoritative coverage rather
  /// than assuming a match is charted. [player] is a substring match on
  /// either name; [gender] is `M` or `W`; [from]/[to] are `YYYY-MM-DD`.
  Future<Page<RallyMatch>> listRallyMatches({
    String? player,
    String? from,
    String? to,
    String? surface,
    String? gender,
    int limit = 50,
    int offset = 0,
  }) async {
    final body = await _request('/rally/matches', {
      'player': player,
      'from': from,
      'to': to,
      'surface': surface,
      'gender': gender,
      'limit': limit,
      'offset': offset,
    });
    return Page.fromJson(body, RallyMatch.fromJson);
  }

  /// One charted match with its points, in play order, by **rally** id.
  /// **ULTRA.**
  ///
  /// Paged with [limit]/[offset]; the response `meta.total` is the match's
  /// full point count.
  Future<RallyMatchDetail?> getRallyMatch(
    int rallyMatchId, {
    int limit = 50,
    int offset = 0,
  }) async {
    final body = await _request(
      '/rally/matches/$rallyMatchId',
      {'limit': limit, 'offset': offset},
    );
    return body is Map
        ? RallyMatchDetail.fromJson(Map<String, dynamic>.from(body))
        : null;
  }

  /// Rally construction addressed by the API's **own** match id, resolved
  /// through the optional link. **ULTRA.**
  ///
  /// Throws [NotFoundException] with code `not_charted` when the match is
  /// held but nobody charted it — deliberately distinct from `not_found`,
  /// because most matches are not charted and a consumer walking the archive
  /// must tell them apart.
  Future<RallyMatchDetail?> getMatchRally(
    int matchId, {
    int limit = 50,
    int offset = 0,
  }) async {
    final body = await _request(
      '/history/matches/$matchId/rally',
      {'limit': limit, 'offset': offset},
    );
    return body is Map
        ? RallyMatchDetail.fromJson(Map<String, dynamic>.from(body))
        : null;
  }

  /// Career shot-level charting aggregate for one player: serve placement,
  /// return depth and outcomes, net play, clutch serving/returning, winners
  /// and errors by wing, rally-length and shot-direction tendencies.
  /// **ULTRA.**
  ///
  /// [name] (min 3 chars) is the key; a fragment matching more than one
  /// charted person is a 400 with the candidates, and [gender] (`men` |
  /// `women`) disambiguates. Every field is a raw sum over the player's
  /// charted matches — read [ChartingPlayer.matchesCharted] before comparing
  /// players, because coverage is curated, not full-slate.
  Future<ChartingPlayer?> getChartingPlayer(
    String name, {
    String? gender,
  }) async {
    final body = await _request(
      '/charting/players',
      {'name': name, 'gender': gender},
    );
    return body is Map
        ? ChartingPlayer.fromJson(Map<String, dynamic>.from(body))
        : null;
  }

  /// Every charting stat family for one charted match, both players, with
  /// the per-set split exactly as charted. **ULTRA.**
  ///
  /// [chartingMatchId] is this product's own id space (1960–2026, mostly
  /// matches with no counterpart in the live table).
  Future<ChartingMatch?> getChartingMatch(int chartingMatchId) async {
    final body = await _request('/charting/matches/$chartingMatchId');
    return body is Map
        ? ChartingMatch.fromJson(Map<String, dynamic>.from(body))
        : null;
  }

  /// The tournament catalogue — the id space [Match.tournamentId] joins,
  /// name order. FREE.
  ///
  /// [search] is a case-insensitive substring match on the tournament name.
  Future<Page<Tournament>> listTournaments({
    String? search,
    Tour? tour,
    int limit = 50,
    int offset = 0,
  }) async {
    final body = await _request('/tournaments', {
      'search': search,
      'tour': tour?.wire,
      'limit': limit,
      'offset': offset,
    });
    return Page.fromJson(body, Tournament.fromJson);
  }

  /// One tournament by its stable id — the `tournament_id` carried on match
  /// objects. FREE.
  Future<Tournament?> getTournament(String tournamentId) async {
    final body = await _request('/tournaments/$tournamentId');
    return body is Map
        ? Tournament.fromJson(Map<String, dynamic>.from(body))
        : null;
  }

  /// Bare price ticks of the match's mapped match-winner market, newest
  /// first — no market wrapper. **PRO.**
  ///
  /// Unlike other lists there is **no offset**: [limit] caps at 500 (default
  /// 100) and [minutes] bounds the lookback window (1–1440) — when the
  /// page's `meta` says `has_more`, older ticks exist; raise [limit] or
  /// narrow [minutes]. Throws [NotFoundException] when the match has no
  /// mapped market. For the market object with its ticks, use
  /// [getMarketPrices].
  Future<Page<Price>> listMatchPrices(
    int matchId, {
    int limit = 100,
    int? minutes,
  }) async {
    final body = await _request(
      '/matches/$matchId/prices',
      {'limit': limit, 'minutes': minutes},
    );
    return Page.fromJson(body, Price.fromJson);
  }

  /// Your own usage vs quota. Any tier, and the call itself is quota-exempt.
  ///
  /// Durable daily usage for the calling key: tier, limits, today's calls
  /// (current to the second) and a 30-day history. The per-minute window is
  /// on the `X-RateLimit-*` headers of every response, not here — and the
  /// daily reset instant is **not** returned; it appears only as `resets_at`
  /// on a daily-429 body ([RateLimitedException.resetsAt]).
  Future<Usage?> getUsage() async {
    final body = await _request('/usage');
    return body is Map ? Usage.fromJson(Map<String, dynamic>.from(body)) : null;
  }

  /// Registers an outbound webhook. **ULTRA, direct keys only** (a RapidAPI
  /// key gets a 403 `direct_key_required`).
  ///
  /// The API POSTs the same frames the WebSocket sends to [url] (HTTPS,
  /// publicly routable) on every live score commit; [events] defaults to
  /// `[score]` when omitted. Up to 3 webhooks per key — the 4th is a 409
  /// [ConflictException] with code `webhook_limit`. The returned
  /// [Webhook.secret] is shown **exactly once**: store it now, listings never
  /// include it. Never auto-retried, so a transient failure cannot register a
  /// duplicate.
  Future<Webhook?> createWebhook({
    required String url,
    List<WebhookEvent>? events,
  }) async {
    final body = await _mutate('POST', '/webhooks', jsonBody: {
      'url': url,
      if (events != null) 'events': [for (final e in events) e.wire],
    });
    return body is Map
        ? Webhook.fromJson(Map<String, dynamic>.from(body))
        : null;
  }

  /// Lists your webhooks. **ULTRA, direct keys only.** Never includes the
  /// signing secret — that is shown only on creation.
  Future<Page<Webhook>> listWebhooks() async {
    final body = await _request('/webhooks');
    return Page.fromJson(body, Webhook.fromJson);
  }

  /// Removes one of your webhooks. **ULTRA, direct keys only.**
  ///
  /// Returns the deleted count from the response (`1` on success), or `null`
  /// when the body carried none.
  Future<int?> deleteWebhook(int webhookId) async {
    final body = await _mutate('DELETE', '/webhooks/$webhookId');
    if (body is! Map) return null;
    final deleted = body['deleted'];
    return deleted is int ? deleted : null;
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
