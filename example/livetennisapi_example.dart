// A runnable example for the Live Tennis API client.
//
// Run it with your key in the environment:
//
//   LIVETENNISAPI_KEY=twjp_your_key dart run example/livetennisapi_example.dart
//
// It lists live matches, prints scores decoded from the live feed, and drills
// into a doubles match (where per-player biography does not apply) and a match
// with no server set — the two shapes that most often trip up a client.

import 'dart:io';

import 'package:livetennisapi/livetennisapi.dart';

Future<void> main() async {
  final apiKey = Platform.environment['LIVETENNISAPI_KEY'];
  if (apiKey == null || apiKey.isEmpty) {
    stderr.writeln('Set LIVETENNISAPI_KEY to run this example.');
    exitCode = 1;
    return;
  }

  final client = LiveTennisApi(apiKey: apiKey);
  try {
    final health = await client.health();
    print('health: $health\n');

    final live = await client.listMatches(status: MatchStatus.live, limit: 50);
    print('${live.length} live matches (meta count: ${live.meta?.count})\n');

    for (final m in live.data.take(5)) {
      print('  ${_line(m)}');
    }
    print('');

    // A doubles match: known/of are null and a note explains why.
    final upcoming =
        await client.listMatches(status: MatchStatus.upcoming, limit: 100);
    final doubles = _firstWhere(upcoming.data, (m) => m.isDoubles == true);
    if (doubles != null) {
      final dc = doubles.p1?.dataCompleteness;
      print('doubles match #${doubles.id}: ${doubles.tournament}');
      print('  team: ${doubles.p1?.name} vs ${doubles.p2?.name}');
      print('  p1.tour (own field, note the case): ${doubles.p1?.tour}');
      print('  p1.isDoublesTeam: ${doubles.p1?.isDoublesTeam}');
      print('  p1.dataCompleteness: known=${dc?.known} of=${dc?.of} '
          'note=${dc?.note}');
      print('  score (upcoming => null): ${doubles.score}\n');
    } else {
      print('no doubles match found right now\n');
    }

    // A match with no server currently set (null between points), if any.
    final noServer = _firstWhere(
      live.data,
      (m) => m.score != null && m.score!.server == null,
    );
    if (noServer != null) {
      print('null-server match #${noServer.id}: '
          'server=${noServer.score!.server} '
          'points=${noServer.score!.points}\n');
    } else {
      print('no live match with a null server right now '
          '(Score.server is decoded as nullable regardless)\n');
    }

    // Search is FREE and returns full biographies.
    final players = await client.searchPlayers(search: 'alcaraz', limit: 1);
    final p = players.isNotEmpty ? players[0] : null;
    if (p != null) {
      print('player: ${p.name} (#${p.id}) rank ${p.ranking}, '
          'tour ${p.tour}, born ${p.birthday}');
    }
  } on LiveTennisApiException catch (e) {
    stderr.writeln('API error: $e');
    exitCode = 1;
  } finally {
    client.close();
  }
}

String _line(Match m) {
  final s = m.score;
  if (s == null) {
    return '${m.tournament}: ${m.p1?.name} vs ${m.p2?.name} [no score yet]';
  }
  final lastSet = (s.games?[0].length ?? 1) - 1;
  final (g1, g2) = s.gamesForSet(lastSet < 0 ? 0 : lastSet);
  final serving = s.server == null ? '—' : 'p${s.server}';
  return '${m.tournament}: ${m.p1?.name} vs ${m.p2?.name} '
      '[sets ${s.sets ?? '-'}, this set ${g1 ?? '-'}-${g2 ?? '-'}, '
      'pts ${s.points ?? '-'}, serving $serving]';
}

T? _firstWhere<T>(List<T> items, bool Function(T) test) {
  for (final item in items) {
    if (test(item)) return item;
  }
  return null;
}
