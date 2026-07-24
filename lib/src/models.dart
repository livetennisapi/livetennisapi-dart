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

  /// The exact map this object was decoded from.
  final Map<String, dynamic> raw;

  /// Creates pagination metadata.
  const ListMeta({this.limit, this.offset, this.count, this.raw = const {}});

  /// Decodes a `meta` object.
  factory ListMeta.fromJson(Map<String, dynamic> json) => ListMeta(
        limit: _asInt(json['limit']),
        offset: _asInt(json['offset']),
        count: _asInt(json['count']),
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

  /// Surface: `hard`, `clay`, `grass`, or `null`.
  final String? surface;

  /// Whether the match is indoors.
  final bool? indoor;

  /// Format: `BO3`, `BO5`, or `null`.
  final String? format;

  /// Round, or `null`.
  final String? round;

  /// Lifecycle status: `upcoming`, `live`, `completed`, or `cancelled`.
  final String? status;

  /// A finer-grained status string, or `null`.
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
    this.surface,
    this.indoor,
    this.format,
    this.round,
    this.status,
    this.eventStatus,
    this.isDoubles,
    this.scheduledTime,
    this.p1,
    this.p2,
    this.score,
    this.winner,
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
      surface: _asString(json['surface']),
      indoor: _asBool(json['indoor']),
      format: _asString(json['format']),
      round: _asString(json['round']),
      status: _asString(json['status']),
      eventStatus: _asString(json['event_status']),
      isDoubles: _asBool(json['is_doubles']),
      scheduledTime: _asDateTime(json['scheduled_time']),
      p1: p1 == null ? null : Player.fromJson(p1),
      p2: p2 == null ? null : Player.fromJson(p2),
      score: score == null ? null : Score.fromJson(score),
      winner: _asInt(json['winner']),
      market: market == null ? null : Market.fromJson(market),
      analysis: analysis == null ? null : Analysis.fromJson(analysis),
      raw: json,
    );
  }
}
