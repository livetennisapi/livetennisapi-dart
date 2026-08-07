import 'dart:convert';

import 'package:livetennisapi/livetennisapi.dart';
import 'package:test/test.dart';

import 'fixtures.dart';

Map<String, dynamic> _json(String s) => jsonDecode(s) as Map<String, dynamic>;

void main() {
  group('forward compatibility', () {
    test('unknown fields do not break decoding', () {
      final m = Match.fromJson(
        _json('{"id": 1, "tournament": "X", "invented_next_year": {"a": 1}}'),
      );
      expect(m.id, 1);
      expect(m.tournament, 'X');
    });

    test('unknown fields are preserved in raw', () {
      final m = Match.fromJson(_json('{"id": 1, "future_field": "hello"}'));
      expect(m.raw['future_field'], 'hello');
    });

    test('missing fields become null', () {
      final m = Match.fromJson(_json('{"id": 1}'));
      expect(m.tournament, isNull);
      expect(m.score, isNull);
    });

    test('a field of an unexpected type is dropped, not coerced or thrown', () {
      // Server sent an object where an int was documented.
      final m = Match.fromJson(_json('{"id": {"nested": true}}'));
      expect(m.id, isNull);
      expect(m.raw['id'], {'nested': true});
    });
  });

  group('Score', () {
    test('games is player-major; gamesForSet returns (p1, p2)', () {
      // 6-4, 3-6, 2-1
      final s = Score.fromJson(
        _json('{"games": [[6, 3, 2], [4, 6, 1]], "sets": [1, 1]}'),
      );
      expect(s.gamesForSet(0), (6, 4));
      expect(s.gamesForSet(1), (3, 6));
      expect(s.gamesForSet(2), (2, 1));
    });

    test('gamesForSet tolerates a ragged (in-progress) grid', () {
      final s = Score.fromJson(_json('{"games": [[6, 3, 2], [4, 6]]}'));
      expect(s.gamesForSet(2), (2, null));
    });

    test('gamesForSet out of range and with no games', () {
      expect(Score.fromJson(_json('{"games": [[6], [4]]}')).gamesForSet(5),
          (null, null));
      expect(Score.fromJson(_json('{}')).gamesForSet(0), (null, null));
    });

    test('points are strings, not integers', () {
      final s = Score.fromJson(_json('{"points": ["40", "AD"]}'));
      expect(s.points, isA<List<String>>());
      expect(s.points, ['40', 'AD']);
    });

    test('server is nullable', () {
      final s = Score.fromJson(_json(nullServerScore));
      expect(s.server, isNull);
      expect(s.points, ['0', '0']);
      expect(s.gamesForSet(0), (2, 3));
    });

    test('ULTRA-only fields are null below ULTRA', () {
      final s = Score.fromJson(_json('{"sets": [1, 0]}'));
      expect(s.winProbabilityP1, isNull);
      expect(s.danger, isNull);
    });

    test('timestamp is parsed; a bad timestamp becomes null', () {
      expect(
        Score.fromJson(_json('{"timestamp": "2026-07-18T14:30:00Z"}'))
            .timestamp!
            .year,
        2026,
      );
      expect(
        Score.fromJson(_json('{"timestamp": "not a date"}')).timestamp,
        isNull,
      );
    });
  });

  group('Match', () {
    test('nested players and score become models', () {
      final m = Match.fromJson(_json(liveSinglesMatch));
      expect(m.p1, isA<Player>());
      expect(m.p1!.name, 'Lathan Skrobarcek');
      expect(m.p2!.name, 'Egor Gorin');
      expect(m.score, isA<Score>());
      expect(m.score!.server, 1);
      expect(m.score!.points, ['30', '15']);
      expect(m.score!.gamesForSet(0), (4, 6));
    });

    test('market and analysis are null below their tiers', () {
      final m = Match.fromJson(_json(liveSinglesMatch));
      expect(m.market, isNull);
      expect(m.analysis, isNull);
    });

    test('an upcoming match decodes with a null Score', () {
      final m = Match.fromJson(_json(upcomingDoublesMatch));
      expect(m.status, 'upcoming');
      expect(m.score, isNull);
      expect(m.isDoubles, isTrue);
    });
  });

  group('doubles data_completeness', () {
    test('known and of are null on a doubles team, with a note', () {
      final m = Match.fromJson(_json(upcomingDoublesMatch));
      final dc = m.p1!.dataCompleteness!;
      expect(dc.known, isNull);
      expect(dc.of, isNull);
      expect(dc.note, contains('doubles team'));
      expect(m.p1!.isDoublesTeam, isTrue);
    });

    test('the doubles tour string is preserved verbatim (UPPERCASE)', () {
      final m = Match.fromJson(_json(upcomingDoublesMatch));
      // The record's own tour, not the filter enum — kept exactly as sent.
      expect(m.p1!.tour, 'ATP');
    });

    test('a singles player keeps integer known/of', () {
      final m = Match.fromJson(_json(liveSinglesMatch));
      final dc = m.p1!.dataCompleteness!;
      expect(dc.known, 1);
      expect(dc.of, 5);
      expect(dc.note, isNull);
      expect(m.p1!.tour, 'atp');
    });
  });

  group('Player and Fixture dates', () {
    test('birthday parses as a date', () {
      final p = Player.fromJson(_json('{"id": 1, "birthday": "1987-05-22"}'));
      expect(p.birthday!.year, 1987);
    });

    test('fixture event_date parses', () {
      final f =
          Fixture.fromJson(_json('{"id": 1, "event_date": "2026-07-20"}'));
      expect(f.eventDate!.month, 7);
    });
  });

  group('Market', () {
    test('prices decode into models; missing prices is an empty list', () {
      final m = Market.fromJson(_json(
          '{"id": 1, "prices": [{"side": 1, "mid": 0.62}, {"side": 2}]}'));
      expect(m.prices.length, 2);
      expect(m.prices[0].mid, 0.62);
      expect(Market.fromJson(_json('{"id": 1}')).prices, isEmpty);
    });
  });

  group('Page', () {
    test('decodes data and meta', () {
      final page = Page.fromJson(jsonDecode(liveMatchesPage), Match.fromJson);
      expect(page.length, 1);
      expect(page.isNotEmpty, isTrue);
      expect(page[0].id, 22313);
      expect(page.meta!.count, 1);
    });

    test('meta decodes total and has_more when present', () {
      final page = Page.fromJson(
        _json('{"data": [], "meta": {"count": 0, "total": 412, '
            '"has_more": true}}'),
        Match.fromJson,
      );
      expect(page.meta!.total, 412);
      expect(page.meta!.hasMore, isTrue);
    });
  });

  group('Match 1.1 fields', () {
    test('tour, tournamentId, roundCode, eventStatus and withdrew decode', () {
      final m = Match.fromJson(_json(completedRetiredMatch));
      expect(m.tour, 'atp');
      expect(m.tournamentId, 'atp-kitzbuhel-singles');
      expect(m.roundCode, 'QF');
      expect(m.eventStatus, 'Retired');
      expect(m.winner, 1);
      expect(m.withdrew, 2);
    });

    test('the new fields are null on an older payload', () {
      final m = Match.fromJson(_json(liveSinglesMatch));
      expect(m.tour, isNull);
      expect(m.tournamentId, isNull);
      expect(m.roundCode, isNull);
      expect(m.withdrew, isNull);
    });
  });

  group('MatchTape', () {
    test('rows, point_winner and coverage meta decode', () {
      final tape = MatchTape.fromJson(_json(tapeBody));
      expect(tape.match!.id, 24101);
      expect(tape.tape.length, 3);
      // The first row is never attributable to a point.
      expect(tape.tape[0].pointWinner, isNull);
      expect(tape.tape[1].pointWinner, 1);
      expect(tape.tape[1].points, ['15', '0']);
      expect(tape.meta!.coverage, 'from_start');
      expect(tape.meta!.pointSource, 'observed');
      expect(tape.meta!.sequence, 'clean');
      expect(tape.meta!.rawRows, 5);
    });

    test('a null timestamp marks a reconstructed row', () {
      final tape = MatchTape.fromJson(_json(tapeBody));
      expect(tape.tape[1].timestamp, isNotNull);
      expect(tape.tape[2].timestamp, isNull);
    });

    test('tiebreaks keep per-set alignment, null for non-tiebreak sets', () {
      final tape = MatchTape.fromJson(_json(tapeBody));
      expect(tape.tiebreaks!.length, 2);
      expect(tape.tiebreaks![0]!.p1, 7);
      expect(tape.tiebreaks![0]!.p2, 5);
      expect(tape.tiebreaks![1], isNull);
    });

    test('tiebreaks is null when absent (no 7-6 set)', () {
      final tape = MatchTape.fromJson(_json('{"tape": []}'));
      expect(tape.tiebreaks, isNull);
      expect(tape.tape, isEmpty);
    });
  });

  group('HeadToHead', () {
    test('names, totals, surfaces and meetings decode', () {
      final h2h = HeadToHead.fromJson(_json(h2hBody));
      expect(h2h.p1Name, 'Player One');
      expect(h2h.p2Name, 'Player Two');
      expect(h2h.totals!.p1Wins, 3);
      expect(h2h.totals!.undecided, 1);
      expect(h2h.bySurface!['clay'], {'p1': 2, 'p2': 0});
      expect(h2h.meetings.length, 2);
      expect(h2h.meetings[0].era, 'current');
      expect(h2h.meetings[0].outcome, 'retired');
      expect(h2h.meetings[1].era, 'archive');
      expect(h2h.meetings[1].level, 'M');
      expect(h2h.meetings[1].winner, 2);
      expect(h2h.stats, isNull); // below ULTRA
    });
  });

  group('RankingRecord', () {
    test('a listing row carries player_name, previous_rank and roster holes',
        () {
      final page = Page.fromJson(
        _json(rankingsListingPage),
        RankingRecord.fromJson,
      );
      expect(page.length, 2);
      expect(page[0].playerName, 'Top Player');
      expect(page[0].rank, 1);
      expect(page[0].previousRank, 2);
      // A published row for a player outside the roster: no silent hole.
      expect(page[1].playerId, isNull);
      expect(page[1].playerName, 'Unrostered Player');
      // The coverage object stays reachable through meta.raw.
      final coverage = page.meta!.raw['coverage'] as Map<String, dynamic>;
      expect(coverage['oldest_available'], {'atp': '2023-01-02'});
    });

    test('UTR is a rating: rank, points and previous_rank are null', () {
      final r = RankingRecord.fromJson(_json(utrRankingRecord));
      expect(r.system, 'utr');
      expect(r.rating, 15.87);
      expect(r.rank, isNull);
      expect(r.points, isNull);
      expect(r.previousRank, isNull);
    });
  });

  group('WsToken', () {
    test('token, ws_url and channels decode; matchChannel substitutes', () {
      final t = WsToken.fromJson(_json(wsTokenBody));
      expect(t.expiresIn, 300);
      expect(t.wsUrl, 'wss://api.livetennisapi.com/connection/websocket');
      expect(t.channels!.slate, 'slate:all');
      expect(t.matchChannel(22313), 'match:22313');
    });
  });

  group('MatchStatistics', () {
    test('derived fields are typed; measured stays a raw map', () {
      final s = MatchStatistics.fromJson(_json(statisticsBody));
      expect(s.matchId, 22313);
      expect(s.coverage, 'live');
      expect(s.tiebreakGamesExcluded, 1);
      expect(s.p1!.holdPct, 83);
      expect(s.p1!.breakPointsSavedPct, 67);
      expect(s.p1!.pointsWon, 82);
      expect(s.p1!.measured!['aces'], 7);
      expect(s.p1!.measured!['first_serves_in_pct'], 60);
      // Measured fields are omitted, never zero-filled: read the keys given.
      expect(s.p2!.measured!.containsKey('first_serves_in'), isFalse);
    });

    test('freshness is per family, on different clocks', () {
      final s = MatchStatistics.fromJson(_json(statisticsBody));
      expect(s.freshness!.derived!.coverage, 'live');
      expect(s.freshness!.derived!.ageSeconds, 4);
      expect(s.freshness!.measured!.ageSeconds, 18);
      expect(s.freshness!.measuredDivergence, isNull);
    });
  });

  group('ArchiveMatch', () {
    test('winner/loser-shaped result decodes with era-honest nulls', () {
      final m = ArchiveMatch.fromJson(_json(archiveMatchBody));
      expect(m.tour, 'atp');
      expect(m.level, 'G');
      expect(m.eventDate!.year, 1984);
      expect(m.winner!.name, 'Archive Winner');
      expect(m.winner!.rank, 1);
      expect(m.winner!.playerId, 100581);
      expect(m.loser!.seed, 9);
      expect(m.score, '6-4 6-3 RET');
      expect(m.outcome, 'retired');
      expect(m.minutes, isNull);
      expect(m.stats, isNull);
    });
  });

  group('RallyMatchDetail', () {
    test('points decode; the charter notation survives verbatim', () {
      final d = RallyMatchDetail.fromJson(_json(rallyDetailBody));
      expect(d.rallyMatchId, 9001);
      expect(d.matchId, isNull); // predates our own collection
      expect(d.points, 422);
      expect(d.pointsParsed, 420);
      expect(d.rally.length, 2);
      final p = d.rally[0];
      expect(p.notation, '4f8b1f*');
      expect(p.parsed, isTrue);
      expect(p.serveDirection, 'wide');
      expect(p.rallyLength, 3);
      expect(p.shots.length, 3);
      expect(p.shots[0].stroke, 'serve');
      expect(d.meta!.total, 422);
      expect(d.meta!.hasMore, isTrue);
    });

    test('an unparsed point keeps its notation and reads parsed=false', () {
      final d = RallyMatchDetail.fromJson(_json(rallyDetailBody));
      expect(d.rally[1].parsed, isFalse);
      expect(d.rally[1].notation, '5xQ?');
      expect(d.rally[1].shots, isEmpty);
    });
  });

  group('HistoryPackage', () {
    test('a tape package decodes with files and checksums, kind null', () {
      final page = Page.fromJson(
        _json(packagesPage),
        HistoryPackage.fromJson,
      );
      expect(page.length, 1);
      final pkg = page[0];
      expect(pkg.period, '2026-07');
      expect(pkg.status, 'ready');
      expect(pkg.kind, isNull); // absent on tape packages by design
      expect(pkg.files.length, 2);
      expect(pkg.files[0].format, 'jsonl');
      expect(pkg.files[0].sha256, 'abc123');
    });
  });
}
