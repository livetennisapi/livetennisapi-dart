/// Immutable response models for the Live Tennis API.
///
/// Two rules, both taken from the API's own contract, govern every model here:
///
/// 1. **Never reject an unknown field.** The API ships additive changes within
///    `v1`, so a client that validates strictly would break the first time a
///    field is added. Unknown keys are ignored by the typed getters but kept in
///    [raw], so a new server-side field is still reachable without upgrading.
///
/// 2. **Never lose the payload.** Every model keeps the exact map it was decoded
///    from in [raw]. If a typed getter is ever wrong, [raw] is still the truth.
///
/// Consequently `fromJson` never throws on shape. An absent field becomes
/// `null`; a field of an unexpected type is dropped from the typed getter (and
/// preserved in [raw]) rather than crashing the decode.
library;

// -- parsing helpers ----------------------------------------------------------

int? _asInt(Object? v) => v is int
    ? v
    : v is num
        ? v.toInt()
        : null;

double? _asDouble(Object? v) => v is num ? v.toDouble() : null;

String? _asString(Object? v) => v is String ? v : null;

bool? _asBool(Object? v) => v is bool ? v : null;

/// ISO 8601 (with a `Z` or offset suffix) to [DateTime]. Anything unparseable —
/// or a non-string — becomes `null` rather than throwing.
DateTime? _asDateTime(Object? v) => v is String ? DateTime.tryParse(v) : null;

List<int>? _asIntList(Object? v) {
  if (v is! List) return null;
  return [
    for (final e in v)
      if (_asInt(e) case final n?) n
  ];
}

/// Like [_asIntList], but keeps null entries so positions survive (used where
/// the API documents per-position nullable integers).
List<int?>? _asNullableIntList(Object? v) {
  if (v is! List) return null;
  return [for (final e in v) _asInt(e)];
}

List<String>? _asStringList(Object? v) {
  if (v is! List) return null;
  return [
    for (final e in v)
      if (e is String) e
  ];
}

/// Player-major games grid: `[[games_p1...], [games_p2...]]`, each a per-set
/// list that grows as sets are played.
List<List<int>>? _asGames(Object? v) {
  if (v is! List) return null;
  return [
    for (final side in v)
      if (_asIntList(side) case final row?) row else <int>[],
  ];
}

Map<String, dynamic>? _asMap(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : null;

// -- models -------------------------------------------------------------------

/// Pagination envelope returned alongside list responses.
class ListMeta {
  /// The `limit` echoed back by the API.
  final int? limit;

  /// The `offset` echoed back by the API.
  final int? offset;

  /// The number of items in **this page** — not the total available.
  final int? count;

  /// Size of the whole filtered set, or `null` when it cannot be counted
  /// cheaply (for example `/matches?status=completed`).
  final int? total;

  /// Whether more results exist beyond this page. Prefer this over comparing
  /// [count] to [limit], where the API returns it.
  final bool? hasMore;

  /// The exact map this object was decoded from.
  final Map<String, dynamic> raw;

  /// Creates pagination metadata.
  const ListMeta({
    this.limit,
    this.offset,
    this.count,
    this.total,
    this.hasMore,
    this.raw = const {},
  });

  /// Decodes a `meta` object.
  factory ListMeta.fromJson(Map<String, dynamic> json) => ListMeta(
        limit: _asInt(json['limit']),
        offset: _asInt(json['offset']),
        count: _asInt(json['count']),
        total: _asInt(json['total']),
        hasMore: _asBool(json['has_more']),
        raw: json,
      );
}

/// A single page of a list endpoint: its [data] and the [meta] envelope.
///
/// [meta] `count` describes this page, not the grand total, so the only
/// reliable end-of-data signal is a page shorter than the requested limit.
class Page<T> {
  /// The decoded items on this page.
  final List<T> data;

  /// The pagination envelope, when the API returned one.
  final ListMeta? meta;

  /// The exact map this page was decoded from.
  final Map<String, dynamic> raw;

  /// Creates a page.
  const Page({this.data = const [], this.meta, this.raw = const {}});

  /// The number of items on this page.
  int get length => data.length;

  /// Whether this page has no items.
  bool get isEmpty => data.isEmpty;

  /// Whether this page has at least one item.
  bool get isNotEmpty => data.isNotEmpty;

  /// The item at [index].
  T operator [](int index) => data[index];

  /// Decodes a `{data, meta}` body, mapping each item with [itemFromJson].
  factory Page.fromJson(
    Object? body,
    T Function(Map<String, dynamic>) itemFromJson,
  ) {
    final map = _asMap(body) ?? const {};
    final rawData = map['data'];
    final items = <T>[
      if (rawData is List)
        for (final item in rawData)
          if (_asMap(item) case final m?) itemFromJson(m),
    ];
    final meta = _asMap(map['meta']);
    return Page(
      data: items,
      meta: meta == null ? null : ListMeta.fromJson(meta),
      raw: map,
    );
  }
}

/// A match score at a point in time.
///
/// [sets] is `[sets_p1, sets_p2]`.
///
/// [games] is `[games_p1, games_p2]` where **each side is a per-set list** — so
/// `[[6, 3, 2], [4, 6, 1]]` reads 6-4, 3-6, 2-1. It is player-major, not
/// set-major, and each side grows by one entry per set played. Indexing it the
/// other way is the single most common mistake against this API; use
/// [gamesForSet] rather than indexing by hand.
///
/// [points] are the current-game points as **strings** (`"0"`, `"15"`, `"30"`,
/// `"40"`, `"AD"`), not integers.
///
/// [server] is `1`, `2`, or `null` (for example between points), so treat it as
/// nullable. [winProbabilityP1] and [danger] are present only on the ULTRA tier.
class Score {
  /// Sets won, as `[sets_p1, sets_p2]`.
  final List<int>? sets;

  /// Player-major games grid; see the class docs and [gamesForSet].
  final List<List<int>>? games;

  /// Current-game points as strings (`"0"`, `"15"`, `"30"`, `"40"`, `"AD"`).
  final List<String>? points;

  /// Which player is serving: `1`, `2`, or `null`.
  final int? server;

  /// Whether the current game is a tiebreak.
  final bool? isTiebreak;

  /// Live model win probability for player 1. ULTRA tier only.
  final double? winProbabilityP1;

  /// Live model danger signal. ULTRA tier only.
  final double? danger;

  /// When this score was observed.
  final DateTime? timestamp;

  /// The exact map this score was decoded from.
  final Map<String, dynamic> raw;

  /// Creates a score.
  const Score({
    this.sets,
    this.games,
    this.points,
    this.server,
    this.isTiebreak,
    this.winProbabilityP1,
    this.danger,
    this.timestamp,
    this.raw = const {},
  });

  /// Decodes a score object.
  factory Score.fromJson(Map<String, dynamic> json) => Score(
        sets: _asIntList(json['sets']),
        games: _asGames(json['games']),
        points: _asStringList(json['points']),
        server: _asInt(json['server']),
        isTiebreak: _asBool(json['is_tiebreak']),
        winProbabilityP1: _asDouble(json['win_probability_p1']),
        danger: _asDouble(json['danger']),
        timestamp: _asDateTime(json['timestamp']),
        raw: json,
      );

  /// The games for one set as `(p1, p2)`, guarding the player-major layout.
  ///
  /// Returns `(null, null)` when [games] is missing or short, and tolerates a
  /// ragged grid (a set in progress can leave the two sides different lengths).
  (int?, int?) gamesForSet(int setIndex) {
    final g = games;
    if (g == null || g.length < 2) return (null, null);
    final p1 = g[0];
    final p2 = g[1];
    return (
      setIndex < p1.length ? p1[setIndex] : null,
      setIndex < p2.length ? p2[setIndex] : null,
    );
  }
}

/// How much biographical detail is known for a player.
///
/// Lets a consumer distinguish "not in the feed" from "not yet fetched". On a
/// **doubles team** per-player biography does not apply, so [known] and [of]
/// are `null` (distinct from `0`, which means the fields apply and none are
/// known) and [note] explains why.
class DataCompleteness {
  /// Number of biographical fields populated, of [of]. `null` on a doubles
  /// team, where per-player biography does not apply.
  final int? known;

  /// Number of biographical fields considered. `null` on a doubles team.
  final int? of;

  /// Names of the unpopulated fields, for example `["backhand", "hand"]`.
  final List<String>? missing;

  /// Present only when the object is not applicable (for example a doubles
  /// team), explaining why.
  final String? note;

  /// The exact map this object was decoded from.
  final Map<String, dynamic> raw;

  /// Creates a data-completeness summary.
  const DataCompleteness({
    this.known,
    this.of,
    this.missing,
    this.note,
    this.raw = const {},
  });

  /// Decodes a `data_completeness` object.
  factory DataCompleteness.fromJson(Map<String, dynamic> json) =>
      DataCompleteness(
        known: _asInt(json['known']),
        of: _asInt(json['of']),
        missing: _asStringList(json['missing']),
        note: _asString(json['note']),
        raw: json,
      );
}

/// A player, or a doubles team.
///
/// [tour] is the record's **own** tour, which is not the [Tour] filter
/// vocabulary: it is granular (`juniors_boys`, `challenger_men`) where the
/// filter is grouped, and a doubles team reports it UPPERCASE (`ATP`) where an
/// individual reports lowercase (`atp`). Treat it as an opaque string; do not
/// parse it into [Tour].
class Player {
  /// The player (or team) id.
  final int? id;

  /// Display name. For a doubles team this is the pair, for example
  /// `"Herbert / Krawietz"`.
  final String? name;

  /// The record's own, granular tour string — see the class docs. Opaque.
  final String? tour;

  /// ISO country code, or `null`.
  final String? country;

  /// Current ranking, or `null` when unranked/unknown.
  final int? ranking;

  /// Ranking points, or `null`.
  final int? rankingPoints;

  /// Ranking movement: `up`, `down`, `same`, or `null`.
  final String? rankingMovement;

  /// Playing hand: `R`, `L`, or `null`.
  final String? hand;

  /// Backhand: `1`, `2`, or `null`.
  final int? backhand;

  /// Date of birth, or `null`.
  final DateTime? birthday;

  /// Whether this record is a doubles team rather than an individual.
  final bool? isDoublesTeam;

  /// How much biography is known; `null` when the API omitted the object.
  final DataCompleteness? dataCompleteness;

  /// Bio stats (`ratings`, `season`). Populated by the single-player endpoint
  /// only; `null` on list and match payloads.
  final Map<String, dynamic>? stats;

  /// The exact map this player was decoded from.
  final Map<String, dynamic> raw;

  /// Creates a player.
  const Player({
    this.id,
    this.name,
    this.tour,
    this.country,
    this.ranking,
    this.rankingPoints,
    this.rankingMovement,
    this.hand,
    this.backhand,
    this.birthday,
    this.isDoublesTeam,
    this.dataCompleteness,
    this.stats,
    this.raw = const {},
  });

  /// Decodes a player object.
  factory Player.fromJson(Map<String, dynamic> json) {
    final completeness = _asMap(json['data_completeness']);
    return Player(
      id: _asInt(json['id']),
      name: _asString(json['name']),
      tour: _asString(json['tour']),
      country: _asString(json['country']),
      ranking: _asInt(json['ranking']),
      rankingPoints: _asInt(json['ranking_points']),
      rankingMovement: _asString(json['ranking_movement']),
      hand: _asString(json['hand']),
      backhand: _asInt(json['backhand']),
      birthday: _asDateTime(json['birthday']),
      isDoublesTeam: _asBool(json['is_doubles_team']),
      dataCompleteness:
          completeness == null ? null : DataCompleteness.fromJson(completeness),
      stats: _asMap(json['stats']),
      raw: json,
    );
  }
}

/// One price tick. [side] is `1` for player 1's outcome, `2` for player 2's.
class Price {
  /// The outcome side: `1` (p1), `2` (p2), or `null`.
  final int? side;

  /// Best bid, or `null`.
  final double? bid;

  /// Best ask, or `null`.
  final double? ask;

  /// Mid price, or `null`.
  final double? mid;

  /// Bid/ask spread, or `null`.
  final double? spread;

  /// When this tick was observed.
  final DateTime? timestamp;

  /// The exact map this tick was decoded from.
  final Map<String, dynamic> raw;

  /// Creates a price tick.
  const Price({
    this.side,
    this.bid,
    this.ask,
    this.mid,
    this.spread,
    this.timestamp,
    this.raw = const {},
  });

  /// Decodes a price object.
  factory Price.fromJson(Map<String, dynamic> json) => Price(
        side: _asInt(json['side']),
        bid: _asDouble(json['bid']),
        ask: _asDouble(json['ask']),
        mid: _asDouble(json['mid']),
        spread: _asDouble(json['spread']),
        timestamp: _asDateTime(json['timestamp']),
        raw: json,
      );
}

/// A match-winner market. PRO tier and above.
class Market {
  /// The market id.
  final int? id;

  /// The market question, or `null`.
  final String? question;

  /// Market status: `active`, `resolved`, `closed`, or `null`.
  final String? status;

  /// Traded volume, or `null`.
  final double? volume;

  /// Available liquidity, or `null`.
  final double? liquidity;

  /// When the market closes, or `null`.
  final DateTime? endDate;

  /// Recent price ticks, newest first. Empty unless the prices endpoint or a
  /// match-detail embed populated them.
  final List<Price> prices;

  /// The exact map this market was decoded from.
  final Map<String, dynamic> raw;

  /// Creates a market.
  const Market({
    this.id,
    this.question,
    this.status,
    this.volume,
    this.liquidity,
    this.endDate,
    this.prices = const [],
    this.raw = const {},
  });

  /// Decodes a market object.
  factory Market.fromJson(Map<String, dynamic> json) {
    final rawPrices = json['prices'];
    return Market(
      id: _asInt(json['id']),
      question: _asString(json['question']),
      status: _asString(json['status']),
      volume: _asDouble(json['volume']),
      liquidity: _asDouble(json['liquidity']),
      endDate: _asDateTime(json['end_date']),
      prices: <Price>[
        if (rawPrices is List)
          for (final p in rawPrices)
            if (_asMap(p) case final m?) Price.fromJson(m),
      ],
      raw: json,
    );
  }
}

/// Model analysis for a match. ULTRA tier only; either half may be `null`.
///
/// [thesis] and [profile] are kept as raw maps rather than typed objects: they
/// are the most experimental part of the surface, so leaving them as maps keeps
/// a new server-side field usable without a package upgrade. The exact shapes
/// are documented in the OpenAPI spec.
class Analysis {
  /// The directional pick and its reasoning, or `null`.
  final Map<String, dynamic>? thesis;

  /// The pre-match statistical profile, or `null`.
  final Map<String, dynamic>? profile;

  /// The exact map this analysis was decoded from.
  final Map<String, dynamic> raw;

  /// Creates a match analysis.
  const Analysis({this.thesis, this.profile, this.raw = const {}});

  /// Decodes an analysis object.
  factory Analysis.fromJson(Map<String, dynamic> json) => Analysis(
        thesis: _asMap(json['thesis']),
        profile: _asMap(json['profile']),
        raw: json,
      );
}

/// A match event. PRO tier and above.
class MatchEvent {
  /// Event type: `break`, `set_won`, `game_won`, or `momentum_run`.
  final String? type;

  /// The player the event concerns: `1`, `2`, or `null`.
  final int? player;

  /// When the event occurred.
  final DateTime? timestamp;

  /// The exact map this event was decoded from.
  final Map<String, dynamic> raw;

  /// Creates a match event.
  const MatchEvent({
    this.type,
    this.player,
    this.timestamp,
    this.raw = const {},
  });

  /// Decodes an event object.
  factory MatchEvent.fromJson(Map<String, dynamic> json) => MatchEvent(
        type: _asString(json['type']),
        player: _asInt(json['player']),
        timestamp: _asDateTime(json['timestamp']),
        raw: json,
      );
}

/// A scheduled fixture. Players are names only — not yet resolved to ids.
///
/// Note the API's `/fixtures` endpoint may currently include some finished
/// matches; this client passes them through unchanged.
class Fixture {
  /// The fixture id.
  final int? id;

  /// Scheduled date, or `null`.
  final DateTime? eventDate;

  /// The record's own, granular tour string (opaque; see [Player.tour]).
  final String? tour;

  /// Tournament name, or `null`.
  final String? tournament;

  /// Round, or `null`.
  final String? round;

  /// Surface, or `null`.
  final String? surface;

  /// Player 1's name, or `null`.
  final String? player1Name;

  /// Player 2's name, or `null`.
  final String? player2Name;

  /// Status string, or `null`.
  final String? status;

  /// The exact map this fixture was decoded from.
  final Map<String, dynamic> raw;

  /// Creates a fixture.
  const Fixture({
    this.id,
    this.eventDate,
    this.tour,
    this.tournament,
    this.round,
    this.surface,
    this.player1Name,
    this.player2Name,
    this.status,
    this.raw = const {},
  });

  /// Decodes a fixture object.
  factory Fixture.fromJson(Map<String, dynamic> json) => Fixture(
        id: _asInt(json['id']),
        eventDate: _asDateTime(json['event_date']),
        tour: _asString(json['tour']),
        tournament: _asString(json['tournament']),
        round: _asString(json['round']),
        surface: _asString(json['surface']),
        player1Name: _asString(json['player1_name']),
        player2Name: _asString(json['player2_name']),
        status: _asString(json['status']),
        raw: json,
      );
}

/// A match.
///
/// [score] is **nullable** — an upcoming match has no score yet. [market] is
/// present from PRO and [analysis] from ULTRA; both are absent (not `null`)
/// below those tiers, so treat `null` as "not entitled or not available" rather
/// than "no market exists".
class Match {
  /// The match id.
  final int? id;

  /// Tournament name.
  final String? tournament;

  /// The tour, in the **same vocabulary as the `tour` query filter** (`atp`,
  /// `wta`, `challenger`, `itf`, `juniors`) — a match selected by `?tour=X`
  /// always carries that value here. `null` when the feed never stated a tour
  /// or the event has no public tour name (exhibitions, team and mixed
  /// events). Safe to group and filter on. This is distinct from
  /// [Player.tour], which stays granular and opaque.
  final String? tour;

  /// Stable tournament identity — one id per tournament × event type, stable
  /// across seasons. Joins `GET /tournaments/{id}`. `null` on matches ingested
  /// before the catalogue covered their tournament.
  final String? tournamentId;

  /// Surface: `hard`, `clay`, `grass`, or `null`.
  final String? surface;

  /// Whether the match is indoors.
  final bool? indoor;

  /// Format: `BO3`, `BO5`, or `null`.
  final String? format;

  /// Round, or `null`.
  final String? round;

  /// The round in a controlled vocabulary (`F`, `SF`, `QF`, `R16`, `R32`,
  /// `R64`, `R128`, `RR`, `BR`, `Q`, `Q1`–`Q4`, `ER`), normalised from the
  /// free-text [round] label. `Q` is a qualifying round the feed does not
  /// number. `null` when the label is unrecognised — never guessed.
  final String? roundCode;

  /// Lifecycle status: `upcoming`, `live`, `completed`, or `cancelled`.
  final String? status;

  /// How the match ended (or paused) when it did not run its course:
  /// `Retired`, `Cancelled`, `Walk Over`, `Postponed`, or `Interrupted`
  /// (rain/darkness/medical — paused, not over). `null` means the match
  /// completed normally **or** the outcome was never resolved; the feed does
  /// not distinguish those, and the value is cleared if a suspended match
  /// resumes.
  final String? eventStatus;

  /// Whether this is a doubles match.
  final bool? isDoubles;

  /// Scheduled start time, or `null`.
  final DateTime? scheduledTime;

  /// Player (or team) 1, or `null` when the payload had no players object.
  final Player? p1;

  /// Player (or team) 2, or `null`.
  final Player? p2;

  /// The latest score, or `null` for an upcoming match.
  final Score? score;

  /// Winner of a completed match (`1`, `2`), or `null`. Derived from final sets.
  final int? winner;

  /// Which player retired or conceded the walkover (`1`, `2`). Completed
  /// matches only — present only when [eventStatus] is `Retired`/`Walk Over`
  /// and the winner is derivable; the withdrawer is the loser by the rules of
  /// the sport. `null` otherwise.
  final int? withdrew;

  /// Embedded market. PRO tier and above; `null` below.
  final Market? market;

  /// Embedded analysis. ULTRA tier only; `null` below.
  final Analysis? analysis;

  /// The exact map this match was decoded from.
  final Map<String, dynamic> raw;

  /// Creates a match.
  const Match({
    this.id,
    this.tournament,
    this.tour,
    this.tournamentId,
    this.surface,
    this.indoor,
    this.format,
    this.round,
    this.roundCode,
    this.status,
    this.eventStatus,
    this.isDoubles,
    this.scheduledTime,
    this.p1,
    this.p2,
    this.score,
    this.winner,
    this.withdrew,
    this.market,
    this.analysis,
    this.raw = const {},
  });

  /// Decodes a match object.
  factory Match.fromJson(Map<String, dynamic> json) {
    final players = _asMap(json['players']);
    final p1 = players == null ? null : _asMap(players['p1']);
    final p2 = players == null ? null : _asMap(players['p2']);
    final score = _asMap(json['score']);
    final market = _asMap(json['market']);
    final analysis = _asMap(json['analysis']);
    return Match(
      id: _asInt(json['id']),
      tournament: _asString(json['tournament']),
      tour: _asString(json['tour']),
      tournamentId: _asString(json['tournament_id']),
      surface: _asString(json['surface']),
      indoor: _asBool(json['indoor']),
      format: _asString(json['format']),
      round: _asString(json['round']),
      roundCode: _asString(json['round_code']),
      status: _asString(json['status']),
      eventStatus: _asString(json['event_status']),
      isDoubles: _asBool(json['is_doubles']),
      scheduledTime: _asDateTime(json['scheduled_time']),
      p1: p1 == null ? null : Player.fromJson(p1),
      p2: p2 == null ? null : Player.fromJson(p2),
      score: score == null ? null : Score.fromJson(score),
      winner: _asInt(json['winner']),
      withdrew: _asInt(json['withdrew']),
      market: market == null ? null : Market.fromJson(market),
      analysis: analysis == null ? null : Analysis.fromJson(analysis),
      raw: json,
    );
  }
}

/// One row of a match tape — a [Score] state plus [pointWinner].
///
/// Rows watched live carry a real [timestamp]. Rows expanded after the fact
/// from a finished-match record carry a null [timestamp] **and** null model
/// fields, because neither ever existed for them — nothing is synthesised. A
/// null timestamp is the reliable row-level marker of a reconstructed row.
class TapeRow {
  /// Sets won, as `[sets_p1, sets_p2]`.
  final List<int>? sets;

  /// Player-major games grid (see [Score.games]).
  final List<List<int>>? games;

  /// Current-game points as strings.
  final List<String>? points;

  /// Which player is serving: `1`, `2`, or `null`.
  final int? server;

  /// Whether the row is inside a tiebreak.
  final bool? isTiebreak;

  /// Model win probability for player 1 at this row, or `null`.
  final double? winProbabilityP1;

  /// Model danger signal at this row, or `null`.
  final double? danger;

  /// When the row was committed; `null` on a reconstructed row.
  final DateTime? timestamp;

  /// Who won the point this row records (`1`, `2`). Present **only** on
  /// `sequence: clean` rows, and only where the transition from the previous
  /// row is a single attributable point; `null` on gaps, torn rows and the
  /// first row, and never present on the raw sequence (raw rows are
  /// corrections, not points). Derived at read time, never guessed.
  final int? pointWinner;

  /// The exact map this row was decoded from.
  final Map<String, dynamic> raw;

  /// Creates a tape row.
  const TapeRow({
    this.sets,
    this.games,
    this.points,
    this.server,
    this.isTiebreak,
    this.winProbabilityP1,
    this.danger,
    this.timestamp,
    this.pointWinner,
    this.raw = const {},
  });

  /// Decodes a tape row.
  factory TapeRow.fromJson(Map<String, dynamic> json) => TapeRow(
        sets: _asIntList(json['sets']),
        games: _asGames(json['games']),
        points: _asStringList(json['points']),
        server: _asInt(json['server']),
        isTiebreak: _asBool(json['is_tiebreak']),
        winProbabilityP1: _asDouble(json['win_probability_p1']),
        danger: _asDouble(json['danger']),
        timestamp: _asDateTime(json['timestamp']),
        pointWinner: _asInt(json['point_winner']),
        raw: json,
      );

  /// The games for one set as `(p1, p2)` (see [Score.gamesForSet]).
  (int?, int?) gamesForSet(int setIndex) {
    final g = games;
    if (g == null || g.length < 2) return (null, null);
    final p1 = g[0];
    final p2 = g[1];
    return (
      setIndex < p1.length ? p1[setIndex] : null,
      setIndex < p2.length ? p2[setIndex] : null,
    );
  }
}

/// The final score of one set's tiebreak, as `p1`–`p2`.
class SetTiebreak {
  /// Player 1's tiebreak points.
  final int? p1;

  /// Player 2's tiebreak points.
  final int? p2;

  /// The exact map this object was decoded from.
  final Map<String, dynamic> raw;

  /// Creates a tiebreak score.
  const SetTiebreak({this.p1, this.p2, this.raw = const {}});

  /// Decodes a tiebreak score.
  factory SetTiebreak.fromJson(Map<String, dynamic> json) => SetTiebreak(
        p1: _asInt(json['p1']),
        p2: _asInt(json['p2']),
        raw: json,
      );
}

/// Coverage metadata for a tape response.
class TapeMeta {
  /// The match id.
  final int? matchId;

  /// Rows **returned** — after any `sequence: clean` collapse.
  final int? rows;

  /// How the tape came to exist: `from_start`, `partial`, `reconstructed`,
  /// `reconstructed_partial`, or `none`. `from_start` means every row was
  /// committed live from 0-0; it is about provenance, not completeness.
  final String? coverage;

  /// Where the rows came from: `observed`, `reconstructed`, `mixed`, or
  /// `null` on an empty tape.
  final String? pointSource;

  /// Rows before any collapse — equals [rows] when the sequence is `raw`.
  final int? rawRows;

  /// Distinct score states in the raw tape.
  final int? uniqueStates;

  /// Echoes the requested sequence: `raw` or `clean`.
  final String? sequence;

  /// Whether the rows were served from the immutable archive. Informational —
  /// the content contract is identical.
  final bool? fromArchive;

  /// When the response was generated.
  final DateTime? generatedAt;

  /// The exact map this object was decoded from.
  final Map<String, dynamic> raw;

  /// Creates tape metadata.
  const TapeMeta({
    this.matchId,
    this.rows,
    this.coverage,
    this.pointSource,
    this.rawRows,
    this.uniqueStates,
    this.sequence,
    this.fromArchive,
    this.generatedAt,
    this.raw = const {},
  });

  /// Decodes tape metadata.
  factory TapeMeta.fromJson(Map<String, dynamic> json) => TapeMeta(
        matchId: _asInt(json['match_id']),
        rows: _asInt(json['rows']),
        coverage: _asString(json['coverage']),
        pointSource: _asString(json['point_source']),
        rawRows: _asInt(json['raw_rows']),
        uniqueStates: _asInt(json['unique_states']),
        sequence: _asString(json['sequence']),
        fromArchive: _asBool(json['from_archive']),
        generatedAt: _asDateTime(json['generated_at']),
        raw: json,
      );
}

/// A per-match tape: the point-by-point score sequence held for one match.
///
/// The tape is **not** guaranteed to cover the whole match — read
/// [TapeMeta.coverage] and [TapeMeta.pointSource] before backtesting. It works
/// on a live match too, assembled from whatever has been committed so far.
class MatchTape {
  /// The match header.
  final Match? match;

  /// The chronological score sequence.
  final List<TapeRow> tape;

  /// Per-set tiebreak final scores, aligned to the sets of the final
  /// scoreline, from observed states only: an entry for each 7-6 set whose
  /// observed maximum tiebreak state is a valid terminal shape, `null` per set
  /// otherwise, and `null` overall when the match has no 7-6 set.
  final List<SetTiebreak?>? tiebreaks;

  /// Model profiles, oldest first (the [Analysis] `profile` shape), kept as
  /// raw maps.
  final List<Map<String, dynamic>> profiles;

  /// Coverage metadata — read it before trusting the tape.
  final TapeMeta? meta;

  /// The exact map this tape was decoded from.
  final Map<String, dynamic> raw;

  /// Creates a tape.
  const MatchTape({
    this.match,
    this.tape = const [],
    this.tiebreaks,
    this.profiles = const [],
    this.meta,
    this.raw = const {},
  });

  /// Decodes a tape body.
  factory MatchTape.fromJson(Map<String, dynamic> json) {
    final match = _asMap(json['match']);
    final rawTape = json['tape'];
    final rawTiebreaks = json['tiebreaks'];
    final rawProfiles = json['profiles'];
    final meta = _asMap(json['meta']);
    return MatchTape(
      match: match == null ? null : Match.fromJson(match),
      tape: <TapeRow>[
        if (rawTape is List)
          for (final row in rawTape)
            if (_asMap(row) case final m?) TapeRow.fromJson(m),
      ],
      tiebreaks: rawTiebreaks is! List
          ? null
          : <SetTiebreak?>[
              for (final tb in rawTiebreaks)
                if (_asMap(tb) case final m?) SetTiebreak.fromJson(m) else null,
            ],
      profiles: <Map<String, dynamic>>[
        if (rawProfiles is List)
          for (final p in rawProfiles)
            if (_asMap(p) case final m?) m,
      ],
      meta: meta == null ? null : TapeMeta.fromJson(meta),
      raw: json,
    );
  }
}

/// Win totals of a head-to-head record. Totals count meetings with a **known**
/// winner; [undecided] counts the rest (never counted in wins).
class H2HTotals {
  /// Meetings won by player 1 (as requested).
  final int? p1Wins;

  /// Meetings won by player 2 (as requested).
  final int? p2Wins;

  /// Total meetings found.
  final int? meetings;

  /// Meetings with no derivable winner.
  final int? undecided;

  /// The exact map this object was decoded from.
  final Map<String, dynamic> raw;

  /// Creates head-to-head totals.
  const H2HTotals({
    this.p1Wins,
    this.p2Wins,
    this.meetings,
    this.undecided,
    this.raw = const {},
  });

  /// Decodes a totals object.
  factory H2HTotals.fromJson(Map<String, dynamic> json) => H2HTotals(
        p1Wins: _asInt(json['p1_wins']),
        p2Wins: _asInt(json['p2_wins']),
        meetings: _asInt(json['meetings']),
        undecided: _asInt(json['undecided']),
        raw: json,
      );
}

/// One meeting of a head-to-head record, newest first.
///
/// [era] says which half of the product served the row: `archive` rows come
/// from the 1968–2022 results archive, `current` rows from the API's own
/// completed matches (2023 onward). [winner] is `1` or `2` **of this
/// head-to-head** (p1/p2 as requested), or `null` when underivable. Walkovers
/// and retirements are part of the record — filter on [outcome] to exclude
/// them.
class H2HMeeting {
  /// `archive` or `current`.
  final String? era;

  /// The meeting date (archive rows carry the tournament start date).
  final DateTime? date;

  /// Tournament name, or `null`.
  final String? tournament;

  /// Source tier code (archive rows), or `null`.
  final String? level;

  /// Round, or `null`.
  final String? round;

  /// Surface, or `null`.
  final String? surface;

  /// The final score as published, or `null`.
  final String? score;

  /// How the meeting ended (`completed`, `retired`, `walkover`, …), or `null`.
  final String? outcome;

  /// The winner of this head-to-head: `1`, `2`, or `null`.
  final int? winner;

  /// The exact map this meeting was decoded from.
  final Map<String, dynamic> raw;

  /// Creates a meeting.
  const H2HMeeting({
    this.era,
    this.date,
    this.tournament,
    this.level,
    this.round,
    this.surface,
    this.score,
    this.outcome,
    this.winner,
    this.raw = const {},
  });

  /// Decodes a meeting object.
  factory H2HMeeting.fromJson(Map<String, dynamic> json) => H2HMeeting(
        era: _asString(json['era']),
        date: _asDateTime(json['date']),
        tournament: _asString(json['tournament']),
        level: _asString(json['level']),
        round: _asString(json['round']),
        surface: _asString(json['surface']),
        score: _asString(json['score']),
        outcome: _asString(json['outcome']),
        winner: _asInt(json['winner']),
        raw: json,
      );
}

/// A head-to-head record across the results archive (1968–2022) and the API's
/// own completed matches (2023 onward).
///
/// Names are the keys — archive people have no roster ids. A name fragment
/// matching more than one player is refused with a 400 `ambiguous_name`
/// listing the candidates, because two people summed into one record would be
/// a wrong answer.
class HeadToHead {
  /// Resolved name of player 1, or `null` when no player matched.
  final String? p1Name;

  /// Resolved name of player 2, or `null` when no player matched.
  final String? p2Name;

  /// The win totals.
  final H2HTotals? totals;

  /// Per-surface win split. Keys are surface names plus `unknown`; each value
  /// is `{"p1": wins, "p2": wins}`.
  final Map<String, dynamic>? bySurface;

  /// The meetings, newest first, capped at 200.
  final List<H2HMeeting> meetings;

  /// ULTRA only: per-player serve/return/break-point aggregates over the
  /// pairing (`archive_serve` from 1991, `current` from 2023, each with
  /// `meetings_with_stats`). Kept as a raw map; `null` below ULTRA.
  final Map<String, dynamic>? stats;

  /// The exact map this record was decoded from.
  final Map<String, dynamic> raw;

  /// Creates a head-to-head record.
  const HeadToHead({
    this.p1Name,
    this.p2Name,
    this.totals,
    this.bySurface,
    this.meetings = const [],
    this.stats,
    this.raw = const {},
  });

  /// Decodes a head-to-head body.
  factory HeadToHead.fromJson(Map<String, dynamic> json) {
    final players = _asMap(json['players']);
    final p1 = players == null ? null : _asMap(players['p1']);
    final p2 = players == null ? null : _asMap(players['p2']);
    final totals = _asMap(json['totals']);
    final rawMeetings = json['meetings'];
    return HeadToHead(
      p1Name: p1 == null ? null : _asString(p1['name']),
      p2Name: p2 == null ? null : _asString(p2['name']),
      totals: totals == null ? null : H2HTotals.fromJson(totals),
      bySurface: _asMap(json['by_surface']),
      meetings: <H2HMeeting>[
        if (rawMeetings is List)
          for (final m in rawMeetings)
            if (_asMap(m) case final map?) H2HMeeting.fromJson(map),
      ],
      stats: _asMap(json['stats']),
      raw: json,
    );
  }
}

/// One side of an archive result — the winner or the loser, as recorded.
///
/// [playerId] is the corpus person id, which joins the archive players
/// endpoint **within the same tour**. It is not a roster player id.
class ArchivePlayer {
  /// Name as published, or `null`.
  final String? name;

  /// Playing hand, or `null`.
  final String? hand;

  /// 3-letter country code (same vocabulary as [Player.country]), or `null`.
  final String? country;

  /// The player's rank **at the time** of the match, as published.
  final int? rank;

  /// Seed, or `null`.
  final int? seed;

  /// The corpus person id — joins archive player bios within the same tour.
  final int? playerId;

  /// Height in centimetres, or `null`.
  final int? heightCm;

  /// Age at the time of the match, or `null`.
  final double? age;

  /// Draw entry where recorded (`WC`, `Q`, `LL`, `PR`, `SE`, …); `null` for
  /// direct acceptances.
  final String? entry;

  /// The exact map this object was decoded from.
  final Map<String, dynamic> raw;

  /// Creates an archive-side player.
  const ArchivePlayer({
    this.name,
    this.hand,
    this.country,
    this.rank,
    this.seed,
    this.playerId,
    this.heightCm,
    this.age,
    this.entry,
    this.raw = const {},
  });

  /// Decodes an archive player object.
  factory ArchivePlayer.fromJson(Map<String, dynamic> json) => ArchivePlayer(
        name: _asString(json['name']),
        hand: _asString(json['hand']),
        country: _asString(json['country']),
        rank: _asInt(json['rank']),
        seed: _asInt(json['seed']),
        playerId: _asInt(json['player_id']),
        heightCm: _asInt(json['height_cm']),
        age: _asDouble(json['age']),
        entry: _asString(json['entry']),
        raw: json,
      );
}

/// One deep-archive result (1968–2022), winner/loser-shaped: results data is
/// recorded that way at the source, so the winner is a field, never an
/// inference.
///
/// A **separate id space** from `/matches` — archive people are identified by
/// name, and the archive ends where the API's own point-by-point coverage
/// begins (2023-01), so no match is ever served from two datasets.
class ArchiveMatch {
  /// The archive row id.
  final int? id;

  /// The stable corpus key.
  final String? sourceId;

  /// `atp` or `wta`.
  final String? tour;

  /// Source tier code (`G` grand slam, `M` masters, `A` tour, `F` finals,
  /// `D` Davis Cup, `C` challenger, `O` olympics; futures tiers carry their
  /// category codes, e.g. `15`, `25`), or `null`.
  final String? level;

  /// Tournament name, or `null`.
  final String? tournament;

  /// Surface, or `null`.
  final String? surface;

  /// Draw size, or `null`.
  final int? drawSize;

  /// The **tournament start** date — per-match dates do not exist in this
  /// era's records.
  final DateTime? eventDate;

  /// Round code, or `null`.
  final String? round;

  /// Best-of format (3 or 5), or `null`.
  final int? bestOf;

  /// Match length in minutes, where recorded.
  final int? minutes;

  /// The winner, as recorded.
  final ArchivePlayer? winner;

  /// The loser, as recorded.
  final ArchivePlayer? loser;

  /// The final score as published, e.g. `"6-4 7-6(5)"`, `"6-3 RET"`, `"W/O"`.
  final String? score;

  /// Parsed from the score's own vocabulary: `completed`, `retired`,
  /// `walkover`, `default`, `abandoned`, or `null` when unparseable — never
  /// guessed.
  final String? outcome;

  /// Detail endpoint only: `{"winner": {...}, "loser": {...}}` with serve
  /// statistics where the source recorded them; `null` otherwise (most rows
  /// before 1991) — never synthesised.
  final Map<String, dynamic>? stats;

  /// The exact map this result was decoded from.
  final Map<String, dynamic> raw;

  /// Creates an archive result.
  const ArchiveMatch({
    this.id,
    this.sourceId,
    this.tour,
    this.level,
    this.tournament,
    this.surface,
    this.drawSize,
    this.eventDate,
    this.round,
    this.bestOf,
    this.minutes,
    this.winner,
    this.loser,
    this.score,
    this.outcome,
    this.stats,
    this.raw = const {},
  });

  /// Decodes an archive result object.
  factory ArchiveMatch.fromJson(Map<String, dynamic> json) {
    final winner = _asMap(json['winner']);
    final loser = _asMap(json['loser']);
    return ArchiveMatch(
      id: _asInt(json['id']),
      sourceId: _asString(json['source_id']),
      tour: _asString(json['tour']),
      level: _asString(json['level']),
      tournament: _asString(json['tournament']),
      surface: _asString(json['surface']),
      drawSize: _asInt(json['draw_size']),
      eventDate: _asDateTime(json['event_date']),
      round: _asString(json['round']),
      bestOf: _asInt(json['best_of']),
      minutes: _asInt(json['minutes']),
      winner: winner == null ? null : ArchivePlayer.fromJson(winner),
      loser: loser == null ? null : ArchivePlayer.fromJson(loser),
      score: _asString(json['score']),
      outcome: _asString(json['outcome']),
      stats: _asMap(json['stats']),
      raw: json,
    );
  }
}

/// One archive person's bio — own id space (the corpus person id that archive
/// match rows carry as `winner.playerId` / `loser.playerId`), scoped per
/// tour; never a roster id. Null fields are the era's silence, never guessed.
class ArchivePlayerBio {
  /// The corpus person id.
  final int? id;

  /// `atp` or `wta`.
  final String? tour;

  /// Name, or `null`.
  final String? name;

  /// Playing hand, or `null`.
  final String? hand;

  /// Date of birth, or `null`.
  final DateTime? dob;

  /// 3-letter country code, or `null`.
  final String? country;

  /// Height in centimetres, or `null`.
  final int? heightCm;

  /// Career-high rank, computed offline from the corpus's own weekly ranking
  /// tables, or `null`.
  final int? careerHighRank;

  /// The earliest week the career-high rank was reached, or `null`.
  final DateTime? careerHighDate;

  /// The exact map this bio was decoded from.
  final Map<String, dynamic> raw;

  /// Creates an archive bio.
  const ArchivePlayerBio({
    this.id,
    this.tour,
    this.name,
    this.hand,
    this.dob,
    this.country,
    this.heightCm,
    this.careerHighRank,
    this.careerHighDate,
    this.raw = const {},
  });

  /// Decodes an archive bio object.
  factory ArchivePlayerBio.fromJson(Map<String, dynamic> json) =>
      ArchivePlayerBio(
        id: _asInt(json['id']),
        tour: _asString(json['tour']),
        name: _asString(json['name']),
        hand: _asString(json['hand']),
        dob: _asDateTime(json['dob']),
        country: _asString(json['country']),
        heightCm: _asInt(json['height_cm']),
        careerHighRank: _asInt(json['career_high_rank']),
        careerHighDate: _asDateTime(json['career_high_date']),
        raw: json,
      );
}

/// Career aggregates over the results archive (1968–2022) — sums and ratios
/// of sums only, nothing modelled.
///
/// [serve] holds the summed serve-stat block with derived ratios; its
/// `matches_with_stats` states the coverage honestly (the corpus records
/// per-match serve statistics from 1991 only), and ratios are `null` where
/// the denominator is zero. The breakdowns are kept as raw maps/lists in the
/// documented shapes.
class ArchiveCareer {
  /// The resolved player name.
  final String? name;

  /// First archive appearance, or `null`.
  final DateTime? firstDate;

  /// Last archive appearance, or `null`.
  final DateTime? lastDate;

  /// Career wins.
  final int? wins;

  /// Career losses.
  final int? losses;

  /// Finals won (excluding abandoned finals).
  final int? titles;

  /// W-L per surface: `{"hard": {"wins": …, "losses": …}, …}`.
  final Map<String, dynamic>? bySurface;

  /// W-L per source level code.
  final Map<String, dynamic>? byLevel;

  /// Per-year W-L rows: `[{"year": …, "wins": …, "losses": …}, …]`.
  final List<Map<String, dynamic>> byYear;

  /// Summed serve statistics + derived ratios (`aces`, `first_in_pct`, …),
  /// with `matches_with_stats` stating the sample.
  final Map<String, dynamic>? serve;

  /// The exact map this aggregate was decoded from.
  final Map<String, dynamic> raw;

  /// Creates a career aggregate.
  const ArchiveCareer({
    this.name,
    this.firstDate,
    this.lastDate,
    this.wins,
    this.losses,
    this.titles,
    this.bySurface,
    this.byLevel,
    this.byYear = const [],
    this.serve,
    this.raw = const {},
  });

  /// Decodes a career aggregate body.
  factory ArchiveCareer.fromJson(Map<String, dynamic> json) {
    final player = _asMap(json['player']);
    final span = _asMap(json['span']);
    final record = _asMap(json['record']);
    final rawByYear = json['by_year'];
    return ArchiveCareer(
      name: player == null ? null : _asString(player['name']),
      firstDate: span == null ? null : _asDateTime(span['first']),
      lastDate: span == null ? null : _asDateTime(span['last']),
      wins: record == null ? null : _asInt(record['wins']),
      losses: record == null ? null : _asInt(record['losses']),
      titles: record == null ? null : _asInt(record['titles']),
      bySurface: record == null ? null : _asMap(record['by_surface']),
      byLevel: record == null ? null : _asMap(record['by_level']),
      byYear: <Map<String, dynamic>>[
        if (rawByYear is List)
          for (final y in rawByYear)
            if (_asMap(y) case final m?) m,
      ],
      serve: _asMap(json['serve']),
      raw: json,
    );
  }
}

/// One ranking record in force at the requested instant.
///
/// [system] is always explicit and the systems are never collapsed into a
/// single "rank" — they are not comparable. ATP/WTA and the ITF circuits
/// populate [rank] + [points]; UTR populates [rating] and leaves rank/points
/// `null`, because UTR is a rating and has no rank.
class RankingRecord {
  /// The roster player id; `null` on listing rows for players outside the
  /// roster (so the published table has no silent holes).
  final int? playerId;

  /// The name as the ranking publisher printed it — present on listing rows,
  /// absent on per-player records.
  final String? playerName;

  /// The ranking system: `atp`, `wta`, `itf_jt`, `itf_mt`, `itf_wt`, `utr`.
  final String? system;

  /// The tour, or `null`.
  final String? tour;

  /// The rank; `null` for UTR.
  final int? rank;

  /// The points; `null` for UTR.
  final int? points;

  /// The rank at the immediately preceding snapshot week (ATP/WTA only;
  /// `null` when no prior week is held, and always `null` for ITF/UTR).
  final int? previousRank;

  /// The circuit's own signed weekly movement (ITF systems only; `null`
  /// elsewhere).
  final int? rankMovement;

  /// The UTR rating; `null` for every other system.
  final double? rating;

  /// The publication week this record took effect.
  final DateTime? effectiveDate;

  /// When the record was observed.
  final DateTime? observedAt;

  /// The exact map this record was decoded from.
  final Map<String, dynamic> raw;

  /// Creates a ranking record.
  const RankingRecord({
    this.playerId,
    this.playerName,
    this.system,
    this.tour,
    this.rank,
    this.points,
    this.previousRank,
    this.rankMovement,
    this.rating,
    this.effectiveDate,
    this.observedAt,
    this.raw = const {},
  });

  /// Decodes a ranking record.
  factory RankingRecord.fromJson(Map<String, dynamic> json) => RankingRecord(
        playerId: _asInt(json['player_id']),
        playerName: _asString(json['player_name']),
        system: _asString(json['system']),
        tour: _asString(json['tour']),
        rank: _asInt(json['rank']),
        points: _asInt(json['points']),
        previousRank: _asInt(json['previous_rank']),
        rankMovement: _asInt(json['rank_movement']),
        rating: _asDouble(json['rating']),
        effectiveDate: _asDateTime(json['effective_date']),
        observedAt: _asDateTime(json['observed_at']),
        raw: json,
      );
}

/// The channel vocabulary of the push WebSocket feed.
class WsChannels {
  /// The per-match channel template, e.g. `match:{id}`. Use
  /// [WsToken.matchChannel] to substitute a match id.
  final String? match;

  /// The slate channel carrying every live score frame (`slate:all`).
  final String? slate;

  /// The exact map this object was decoded from.
  final Map<String, dynamic> raw;

  /// Creates a channel vocabulary.
  const WsChannels({this.match, this.slate, this.raw = const {}});

  /// Decodes a `channels` object.
  factory WsChannels.fromJson(Map<String, dynamic> json) => WsChannels(
        match: _asString(json['match']),
        slate: _asString(json['slate']),
        raw: json,
      );
}

/// A short-lived connection token for the push WebSocket feed. ULTRA only.
///
/// Frames are the same allowlist score objects the polling endpoints return.
/// Mint a fresh token on reconnect.
class WsToken {
  /// The signed connection token.
  final String? token;

  /// Token lifetime in seconds.
  final int? expiresIn;

  /// The push WebSocket URL to connect to.
  final String? wsUrl;

  /// The channel vocabulary: a per-match template and the slate channel.
  final WsChannels? channels;

  /// The exact map this token was decoded from.
  final Map<String, dynamic> raw;

  /// Creates a token.
  const WsToken({
    this.token,
    this.expiresIn,
    this.wsUrl,
    this.channels,
    this.raw = const {},
  });

  /// Decodes a token body.
  factory WsToken.fromJson(Map<String, dynamic> json) {
    final channels = _asMap(json['channels']);
    return WsToken(
      token: _asString(json['token']),
      expiresIn: _asInt(json['expires_in']),
      wsUrl: _asString(json['ws_url']),
      channels: channels == null ? null : WsChannels.fromJson(channels),
      raw: json,
    );
  }

  /// The concrete channel name for one match, from the `match:{id}` template
  /// (`null` when the template is unknown).
  String? matchChannel(int matchId) =>
      channels?.match?.replaceFirst('{id}', '$matchId');
}

/// One file of a published bulk package.
class PackageFile {
  /// `jsonl` or `csv`.
  final String? format;

  /// The file name.
  final String? filename;

  /// The file size in bytes.
  final int? bytes;

  /// The file's SHA-256 checksum.
  final String? sha256;

  /// The exact map this object was decoded from.
  final Map<String, dynamic> raw;

  /// Creates a package file entry.
  const PackageFile({
    this.format,
    this.filename,
    this.bytes,
    this.sha256,
    this.raw = const {},
  });

  /// Decodes a file entry.
  factory PackageFile.fromJson(Map<String, dynamic> json) => PackageFile(
        format: _asString(json['format']),
        filename: _asString(json['filename']),
        bytes: _asInt(json['bytes']),
        sha256: _asString(json['sha256']),
        raw: json,
      );
}

/// A published monthly bulk package.
///
/// Coverage is not a contiguous run of months and is still being extended
/// backwards — treat the packages listing as the authoritative set of months
/// that exist. The JSONL file holds one line **per match** (a whole tape
/// object per line, coverage meta included); the CSV is flattened to one row
/// per point and carries no coverage columns.
class HistoryPackage {
  /// The month, `YYYY-MM`.
  final String? period;

  /// Always `ready` — only built months are listed or served.
  final String? status;

  /// Matches in the package (players covered, on a rankings package).
  final int? matchCount;

  /// Tape rows in the package (ranking records, on a rankings package).
  final int? rowCount;

  /// The downloadable files with sizes and checksums.
  final List<PackageFile> files;

  /// When the package was built.
  final DateTime? builtAt;

  /// The package family. Present only on non-tape packages (`rankings`);
  /// absent — decoded as `null` — on tape packages, so a tape-only consumer
  /// never sees the shape change.
  final String? kind;

  /// The exact map this package was decoded from.
  final Map<String, dynamic> raw;

  /// Creates a package.
  const HistoryPackage({
    this.period,
    this.status,
    this.matchCount,
    this.rowCount,
    this.files = const [],
    this.builtAt,
    this.kind,
    this.raw = const {},
  });

  /// Decodes a package object.
  factory HistoryPackage.fromJson(Map<String, dynamic> json) {
    final rawFiles = json['files'];
    return HistoryPackage(
      period: _asString(json['period']),
      status: _asString(json['status']),
      matchCount: _asInt(json['match_count']),
      rowCount: _asInt(json['row_count']),
      files: <PackageFile>[
        if (rawFiles is List)
          for (final f in rawFiles)
            if (_asMap(f) case final m?) PackageFile.fromJson(m),
      ],
      builtAt: _asDateTime(json['built_at']),
      kind: _asString(json['kind']),
      raw: json,
    );
  }
}

/// Coverage and age for one statistics family.
class StatsFamily {
  /// `live`, `final`, `stale`, `none`, or `diverged`. `final` means the
  /// closing figures of a completed match (age `null`).
  final String? coverage;

  /// When the family was last updated.
  final DateTime? asOf;

  /// The family's age in seconds — **note the clocks differ**: the derived
  /// age is measured against the newest score row, the measured age against
  /// the wall clock. Never compare the two.
  final int? ageSeconds;

  /// The match state these statistics describe (`games_p1`, `games_p2`,
  /// `total_games`), per upstream, or `null` when unavailable.
  final Map<String, dynamic>? describes;

  /// The exact map this object was decoded from.
  final Map<String, dynamic> raw;

  /// Creates a family freshness object.
  const StatsFamily({
    this.coverage,
    this.asOf,
    this.ageSeconds,
    this.describes,
    this.raw = const {},
  });

  /// Decodes a family freshness object.
  factory StatsFamily.fromJson(Map<String, dynamic> json) => StatsFamily(
        coverage: _asString(json['coverage']),
        asOf: _asDateTime(json['as_of']),
        ageSeconds: _asInt(json['age_seconds']),
        describes: _asMap(json['describes']),
        raw: json,
      );
}

/// Per-family coverage and age of a statistics response. Branch on this
/// rather than on the top-level coverage, which only summarises the response.
class StatsFreshness {
  /// The derived family's coverage and age (age relative to the newest score
  /// row).
  final StatsFamily? derived;

  /// The measured family's coverage and age (age is wall clock).
  final StatsFamily? measured;

  /// `null` when the families agree; otherwise why the measured values were
  /// withheld, with both match states (`reason`, `games_in_statistics`,
  /// `games_in_score`, `delta_games`, `detail`).
  final Map<String, dynamic>? measuredDivergence;

  /// The exact map this object was decoded from.
  final Map<String, dynamic> raw;

  /// Creates a freshness object.
  const StatsFreshness({
    this.derived,
    this.measured,
    this.measuredDivergence,
    this.raw = const {},
  });

  /// Decodes a freshness object.
  factory StatsFreshness.fromJson(Map<String, dynamic> json) {
    final derived = _asMap(json['derived']);
    final measured = _asMap(json['measured']);
    return StatsFreshness(
      derived: derived == null ? null : StatsFamily.fromJson(derived),
      measured: measured == null ? null : StatsFamily.fromJson(measured),
      measuredDivergence: _asMap(json['measured_divergence']),
      raw: json,
    );
  }
}

/// One player's in-play statistics, in two families that are deliberately not
/// merged.
///
/// The typed fields here are **derived** — rebuilt from the point-by-point
/// record. [measured] holds the counts taken upstream, which include what no
/// point record can yield: aces, double faults, the serve split, winners and
/// unforced errors. Both families name some of the same quantities computed
/// two entirely different ways; that is a cross-check, not a duplication.
///
/// Percentages are integers, and `null` when the denominator is zero (never
/// `0`, so a present `0` is a real measured zero). Tiebreak games are
/// excluded from the derived family and counted separately.
class MatchStatisticsSide {
  /// Service games played.
  final int? serviceGamesPlayed;

  /// Service games won.
  final int? serviceGamesWon;

  /// Hold percentage; `null` when no service game was played.
  final int? holdPct;

  /// Return games played.
  final int? returnGamesPlayed;

  /// Return games won.
  final int? returnGamesWon;

  /// Break percentage; `null` when no return game was played.
  final int? breakPct;

  /// Break points faced on serve.
  final int? breakPointsFaced;

  /// Break points saved on serve.
  final int? breakPointsSaved;

  /// Break points saved, as a percentage; `null` when none were faced.
  final int? breakPointsSavedPct;

  /// Break points played on return.
  final int? breakPointsPlayed;

  /// Break points converted on return.
  final int? breakPointsConverted;

  /// Break points converted, as a percentage; `null` when none were played.
  final int? breakPointsConvertedPct;

  /// Service points played.
  final int? servicePointsPlayed;

  /// Service points won.
  final int? servicePointsWon;

  /// Service points won, as a percentage; `null` when none were played.
  final int? servicePointsWonPct;

  /// Return points played.
  final int? returnPointsPlayed;

  /// Return points won.
  final int? returnPointsWon;

  /// Return points won, as a percentage; `null` when none were played.
  final int? returnPointsWonPct;

  /// Total points played.
  final int? pointsPlayed;

  /// Total points won.
  final int? pointsWon;

  /// The **measured** family: counts taken upstream (`aces`,
  /// `double_faults`, `first_serves_in`, `winners_total`, …). Every field is
  /// optional and an absent field is **omitted, never zero-filled** — read
  /// the keys you are given, so this stays a raw map. `_of` suffixes are
  /// denominators; `_pct` suffixes are percentages recomputed from the two
  /// counts. On `diverged` coverage the values are withheld.
  final Map<String, dynamic>? measured;

  /// The exact map this side was decoded from.
  final Map<String, dynamic> raw;

  /// Creates a statistics side.
  const MatchStatisticsSide({
    this.serviceGamesPlayed,
    this.serviceGamesWon,
    this.holdPct,
    this.returnGamesPlayed,
    this.returnGamesWon,
    this.breakPct,
    this.breakPointsFaced,
    this.breakPointsSaved,
    this.breakPointsSavedPct,
    this.breakPointsPlayed,
    this.breakPointsConverted,
    this.breakPointsConvertedPct,
    this.servicePointsPlayed,
    this.servicePointsWon,
    this.servicePointsWonPct,
    this.returnPointsPlayed,
    this.returnPointsWon,
    this.returnPointsWonPct,
    this.pointsPlayed,
    this.pointsWon,
    this.measured,
    this.raw = const {},
  });

  /// Decodes a statistics side.
  factory MatchStatisticsSide.fromJson(Map<String, dynamic> json) =>
      MatchStatisticsSide(
        serviceGamesPlayed: _asInt(json['service_games_played']),
        serviceGamesWon: _asInt(json['service_games_won']),
        holdPct: _asInt(json['hold_pct']),
        returnGamesPlayed: _asInt(json['return_games_played']),
        returnGamesWon: _asInt(json['return_games_won']),
        breakPct: _asInt(json['break_pct']),
        breakPointsFaced: _asInt(json['break_points_faced']),
        breakPointsSaved: _asInt(json['break_points_saved']),
        breakPointsSavedPct: _asInt(json['break_points_saved_pct']),
        breakPointsPlayed: _asInt(json['break_points_played']),
        breakPointsConverted: _asInt(json['break_points_converted']),
        breakPointsConvertedPct: _asInt(json['break_points_converted_pct']),
        servicePointsPlayed: _asInt(json['service_points_played']),
        servicePointsWon: _asInt(json['service_points_won']),
        servicePointsWonPct: _asInt(json['service_points_won_pct']),
        returnPointsPlayed: _asInt(json['return_points_played']),
        returnPointsWon: _asInt(json['return_points_won']),
        returnPointsWonPct: _asInt(json['return_points_won_pct']),
        pointsPlayed: _asInt(json['points_played']),
        pointsWon: _asInt(json['points_won']),
        measured: _asMap(json['measured']),
        raw: json,
      );
}

/// In-play statistics for one match. ULTRA only.
///
/// `none` coverage on both families returns 200 with null players, not 404 —
/// the match exists and holding nothing for it is the honest answer. Branch
/// on [freshness] (per family) rather than the top-level [coverage], which
/// only summarises the response.
class MatchStatistics {
  /// The match id.
  final int? matchId;

  /// Summary coverage: `live`, `final`, `stale`, `none`, or `diverged`.
  final String? coverage;

  /// When the underlying record was last updated.
  final DateTime? asOf;

  /// Age behind the newest **score row**, not the wall clock.
  final int? ageSeconds;

  /// Games counted into the derived family.
  final int? gamesCounted;

  /// Tiebreak games excluded from the derived family (the live record
  /// collapses a whole tiebreak onto one entry).
  final int? tiebreakGamesExcluded;

  /// Games whose recorded outcome is neither a legal hold nor a legal break.
  final int? inconsistentGamesExcluded;

  /// The sets covered by the derived family.
  final List<int>? setsCovered;

  /// Per-family coverage and age — branch on this.
  final StatsFreshness? freshness;

  /// Present only when coverage is `none`, explaining why.
  final String? detail;

  /// Player 1's statistics, or `null` when nothing is held.
  final MatchStatisticsSide? p1;

  /// Player 2's statistics, or `null` when nothing is held.
  final MatchStatisticsSide? p2;

  /// The exact map this object was decoded from.
  final Map<String, dynamic> raw;

  /// Creates a statistics response.
  const MatchStatistics({
    this.matchId,
    this.coverage,
    this.asOf,
    this.ageSeconds,
    this.gamesCounted,
    this.tiebreakGamesExcluded,
    this.inconsistentGamesExcluded,
    this.setsCovered,
    this.freshness,
    this.detail,
    this.p1,
    this.p2,
    this.raw = const {},
  });

  /// Decodes a statistics body.
  factory MatchStatistics.fromJson(Map<String, dynamic> json) {
    final freshness = _asMap(json['freshness']);
    final players = _asMap(json['players']);
    final p1 = players == null ? null : _asMap(players['p1']);
    final p2 = players == null ? null : _asMap(players['p2']);
    return MatchStatistics(
      matchId: _asInt(json['match_id']),
      coverage: _asString(json['coverage']),
      asOf: _asDateTime(json['as_of']),
      ageSeconds: _asInt(json['age_seconds']),
      gamesCounted: _asInt(json['games_counted']),
      tiebreakGamesExcluded: _asInt(json['tiebreak_games_excluded']),
      inconsistentGamesExcluded: _asInt(json['inconsistent_games_excluded']),
      setsCovered: _asIntList(json['sets_covered']),
      freshness: freshness == null ? null : StatsFreshness.fromJson(freshness),
      detail: _asString(json['detail']),
      p1: p1 == null ? null : MatchStatisticsSide.fromJson(p1),
      p2: p2 == null ? null : MatchStatisticsSide.fromJson(p2),
      raw: json,
    );
  }
}

/// One stroke of a charted rally. Shots are numbered from the serve: serve 1,
/// return 2, the server's next ball 3.
class RallyShot {
  /// The shot number within the point.
  final int? number;

  /// The charter's raw code, e.g. `f`.
  final String? code;

  /// The stroke type (`serve`, `groundstroke`, `slice`, `volley`, …), or
  /// `null`.
  final String? stroke;

  /// The side it was struck **from**: `forehand`, `backhand`, or `null`.
  final String? wing;

  /// Where the ball was sent: `forehand_side`, `middle`, `backhand_side`, or
  /// `null`.
  final String? direction;

  /// `shallow`, `mid`, `deep`, or `null`.
  final String? depth;

  /// `approaching`, `at_net`, `baseline`, or `null`.
  final String? position;

  /// The exact map this shot was decoded from.
  final Map<String, dynamic> raw;

  /// Creates a shot.
  const RallyShot({
    this.number,
    this.code,
    this.stroke,
    this.wing,
    this.direction,
    this.depth,
    this.position,
    this.raw = const {},
  });

  /// Decodes a shot object.
  factory RallyShot.fromJson(Map<String, dynamic> json) => RallyShot(
        number: _asInt(json['number']),
        code: _asString(json['code']),
        stroke: _asString(json['stroke']),
        wing: _asString(json['wing']),
        direction: _asString(json['direction']),
        depth: _asString(json['depth']),
        position: _asString(json['position']),
        raw: json,
      );
}

/// One charted point.
///
/// [notation] is the charter's own string (the API's `raw` field), verbatim
/// and always present; the parsed fields are this product's reading of it.
/// [parsed] is `false` when the notation contained something that could not
/// be read cleanly — the recognised part is still returned, so a consumer who
/// wants only unambiguous rows filters on [parsed].
class RallyPoint {
  /// The point number within the match.
  final int? point;

  /// Sets at this point, `[p1, p2]` (entries may be null).
  final List<int?>? set;

  /// Games at this point, `[p1, p2]` (entries may be null).
  final List<int?>? games;

  /// The point score, e.g. `30-40`, or `null`.
  final String? score;

  /// The game number, or `null`.
  final int? game;

  /// Whether the point is inside a tiebreak.
  final bool? isTiebreak;

  /// The server: `1`, `2`, or `null`.
  final int? server;

  /// Who won the point: `1`, `2`, or `null`.
  final int? pointWinner;

  /// The charter's shot string, verbatim (both serves joined by `;` when the
  /// first was a fault). This is the API's `raw` field — renamed here because
  /// [raw] holds the decoded map, per this package's convention.
  final String? notation;

  /// Whether the notation was read cleanly.
  final bool? parsed;

  /// Which serve was in play: `1`, `2`, or `null`.
  final int? serveNumber;

  /// `wide`, `body`, `down_the_t`, or `null`.
  final String? serveDirection;

  /// Strokes including the serve — an ace is 1, a double fault 0.
  final int? rallyLength;

  /// How the point ended: `winner`, `forced_error`, `unforced_error`,
  /// `error` (a miss the charter did not classify — never guessed), `other`,
  /// or `null`.
  final String? outcome;

  /// Where the ending error landed: `net`, `wide`, `deep`, `wide_and_deep`,
  /// or `null`.
  final String? errorLocation;

  /// The stroke that ended the point, or `null`.
  final String? endingStroke;

  /// The wing that ended the point, or `null`.
  final String? endingWing;

  /// Whether the point was an ace.
  final bool? isAce;

  /// Whether the point was a double fault.
  final bool? isDoubleFault;

  /// Whether the server serve-and-volleyed.
  final bool? isServeAndVolley;

  /// The strokes of the rally, in order.
  final List<RallyShot> shots;

  /// The exact map this point was decoded from.
  final Map<String, dynamic> raw;

  /// Creates a charted point.
  const RallyPoint({
    this.point,
    this.set,
    this.games,
    this.score,
    this.game,
    this.isTiebreak,
    this.server,
    this.pointWinner,
    this.notation,
    this.parsed,
    this.serveNumber,
    this.serveDirection,
    this.rallyLength,
    this.outcome,
    this.errorLocation,
    this.endingStroke,
    this.endingWing,
    this.isAce,
    this.isDoubleFault,
    this.isServeAndVolley,
    this.shots = const [],
    this.raw = const {},
  });

  /// Decodes a charted point.
  factory RallyPoint.fromJson(Map<String, dynamic> json) {
    final rawShots = json['shots'];
    return RallyPoint(
      point: _asInt(json['point']),
      set: _asNullableIntList(json['set']),
      games: _asNullableIntList(json['games']),
      score: _asString(json['score']),
      game: _asInt(json['game']),
      isTiebreak: _asBool(json['is_tiebreak']),
      server: _asInt(json['server']),
      pointWinner: _asInt(json['point_winner']),
      notation: _asString(json['raw']),
      parsed: _asBool(json['parsed']),
      serveNumber: _asInt(json['serve_number']),
      serveDirection: _asString(json['serve_direction']),
      rallyLength: _asInt(json['rally_length']),
      outcome: _asString(json['outcome']),
      errorLocation: _asString(json['error_location']),
      endingStroke: _asString(json['ending_stroke']),
      endingWing: _asString(json['ending_wing']),
      isAce: _asBool(json['is_ace']),
      isDoubleFault: _asBool(json['is_double_fault']),
      isServeAndVolley: _asBool(json['is_serve_and_volley']),
      shots: <RallyShot>[
        if (rawShots is List)
          for (final s in rawShots)
            if (_asMap(s) case final m?) RallyShot.fromJson(m),
      ],
      raw: json,
    );
  }
}

/// One player of a charted match.
class RallyPlayer {
  /// The name, or `null`.
  final String? name;

  /// The hand (`R`, `L`, `U` unknown, `A` ambidextrous), or `null`.
  final String? hand;

  /// The exact map this object was decoded from.
  final Map<String, dynamic> raw;

  /// Creates a charted-match player.
  const RallyPlayer({this.name, this.hand, this.raw = const {}});

  /// Decodes a charted-match player.
  factory RallyPlayer.fromJson(Map<String, dynamic> json) => RallyPlayer(
        name: _asString(json['name']),
        hand: _asString(json['hand']),
        raw: json,
      );
}

/// A charted match with shot-by-shot data. ULTRA only.
///
/// Rally construction has its **own id space** — the charted corpus reaches
/// back decades and concentrates on the biggest events, so most charted
/// matches predate the API's own collection. [matchId] links the two only
/// when the charted match is also one the API holds.
class RallyMatch {
  /// The id this product is keyed on.
  final int? rallyMatchId;

  /// The stable source key.
  final String? sourceId;

  /// The API's own match id, when the charted match is also held there;
  /// `null` otherwise (most charted matches).
  final int? matchId;

  /// The match date, or `null`.
  final DateTime? date;

  /// Tournament name, or `null`.
  final String? tournament;

  /// Round, or `null`.
  final String? round;

  /// Surface, or `null`.
  final String? surface;

  /// `M`, `W`, or `null`.
  final String? gender;

  /// Best-of format (3 or 5), or `null`.
  final int? bestOf;

  /// The two players.
  final List<RallyPlayer> players;

  /// Charted points in this match.
  final int? points;

  /// How many of them the parser read cleanly — the per-match quality number.
  final int? pointsParsed;

  /// The exact map this match was decoded from.
  final Map<String, dynamic> raw;

  /// Creates a charted match.
  const RallyMatch({
    this.rallyMatchId,
    this.sourceId,
    this.matchId,
    this.date,
    this.tournament,
    this.round,
    this.surface,
    this.gender,
    this.bestOf,
    this.players = const [],
    this.points,
    this.pointsParsed,
    this.raw = const {},
  });

  /// Decodes a charted match object.
  factory RallyMatch.fromJson(Map<String, dynamic> json) => RallyMatch(
        rallyMatchId: _asInt(json['rally_match_id']),
        sourceId: _asString(json['source_id']),
        matchId: _asInt(json['match_id']),
        date: _asDateTime(json['date']),
        tournament: _asString(json['tournament']),
        round: _asString(json['round']),
        surface: _asString(json['surface']),
        gender: _asString(json['gender']),
        bestOf: _asInt(json['best_of']),
        players: _rallyPlayers(json['players']),
        points: _asInt(json['points']),
        pointsParsed: _asInt(json['points_parsed']),
        raw: json,
      );
}

List<RallyPlayer> _rallyPlayers(Object? v) => <RallyPlayer>[
      if (v is List)
        for (final p in v)
          if (_asMap(p) case final m?) RallyPlayer.fromJson(m),
    ];

/// A charted match with its points, in play order. ULTRA only.
///
/// Paged with `limit`/`offset`; [meta] `total` is the match's full point
/// count.
class RallyMatchDetail extends RallyMatch {
  /// The charted points on this page, in play order.
  final List<RallyPoint> rally;

  /// The pagination envelope over the points.
  final ListMeta? meta;

  /// Creates a charted match with points.
  const RallyMatchDetail({
    super.rallyMatchId,
    super.sourceId,
    super.matchId,
    super.date,
    super.tournament,
    super.round,
    super.surface,
    super.gender,
    super.bestOf,
    super.players,
    super.points,
    super.pointsParsed,
    this.rally = const [],
    this.meta,
    super.raw,
  });

  /// Decodes a charted match with its points.
  factory RallyMatchDetail.fromJson(Map<String, dynamic> json) {
    final base = RallyMatch.fromJson(json);
    final rawRally = json['rally'];
    final meta = _asMap(json['meta']);
    return RallyMatchDetail(
      rallyMatchId: base.rallyMatchId,
      sourceId: base.sourceId,
      matchId: base.matchId,
      date: base.date,
      tournament: base.tournament,
      round: base.round,
      surface: base.surface,
      gender: base.gender,
      bestOf: base.bestOf,
      players: base.players,
      points: base.points,
      pointsParsed: base.pointsParsed,
      rally: <RallyPoint>[
        if (rawRally is List)
          for (final p in rawRally)
            if (_asMap(p) case final m?) RallyPoint.fromJson(m),
      ],
      meta: meta == null ? null : ListMeta.fromJson(meta),
      raw: json,
    );
  }
}

/// A career shot-level charting aggregate for one player. ULTRA only.
///
/// Every field of [families] is a raw **sum** over the player's charted
/// matches and [matchesCharted] states the sample. Coverage is curated —
/// concentrated on the majors, not full-slate — so read the sample size
/// before comparing players.
class ChartingPlayer {
  /// The resolved player (name and identity fields), kept as a raw map.
  final Map<String, dynamic>? player;

  /// The number of charted matches summed.
  final int? matchesCharted;

  /// A human-readable coverage statement.
  final String? coverage;

  /// Per-family summed numeric columns (serve placement, return depth and
  /// outcomes, net play, clutch serving/returning, winners and errors by
  /// wing, rally-length and shot-direction tendencies), kept as a raw map.
  final Map<String, dynamic>? families;

  /// The exact map this aggregate was decoded from.
  final Map<String, dynamic> raw;

  /// Creates a charting aggregate.
  const ChartingPlayer({
    this.player,
    this.matchesCharted,
    this.coverage,
    this.families,
    this.raw = const {},
  });

  /// Decodes a charting aggregate body.
  factory ChartingPlayer.fromJson(Map<String, dynamic> json) => ChartingPlayer(
        player: _asMap(json['player']),
        matchesCharted: _asInt(json['matches_charted']),
        coverage: _asString(json['coverage']),
        families: _asMap(json['families']),
        raw: json,
      );
}

/// Every charting stat family for one charted match, both players, with the
/// per-set split exactly as charted. ULTRA only.
class ChartingMatch {
  /// The charting id — this product's own id space.
  final int? chartingMatchId;

  /// The source corpus id.
  final String? mcpId;

  /// `M`, `W`, or `null`.
  final String? gender;

  /// The two players, kept as a raw map.
  final Map<String, dynamic>? players;

  /// The stat families (rows per set 1, 2, Total), kept as a raw map.
  final Map<String, dynamic>? families;

  /// The exact map this match was decoded from.
  final Map<String, dynamic> raw;

  /// Creates a charted-match stats body.
  const ChartingMatch({
    this.chartingMatchId,
    this.mcpId,
    this.gender,
    this.players,
    this.families,
    this.raw = const {},
  });

  /// Decodes a charted-match stats body.
  factory ChartingMatch.fromJson(Map<String, dynamic> json) => ChartingMatch(
        chartingMatchId: _asInt(json['charting_match_id']),
        mcpId: _asString(json['mcp_id']),
        gender: _asString(json['gender']),
        players: _asMap(json['players']),
        families: _asMap(json['families']),
        raw: json,
      );
}
