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
  });
}
