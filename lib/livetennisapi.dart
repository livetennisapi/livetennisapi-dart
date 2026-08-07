/// A Dart client for the [Live Tennis API](https://livetennisapi.com).
///
/// Real-time tennis scores, players, rankings, match-winner market prices and
/// model win-probability for ATP, WTA, Challenger, ITF and juniors — over
/// REST.
///
/// ```dart
/// import 'package:livetennisapi/livetennisapi.dart';
///
/// Future<void> main() async {
///   final client = LiveTennisApi(apiKey: 'twjp_…');
///   try {
///     final page = await client.listMatches(status: MatchStatus.live);
///     for (final match in page.data) {
///       print('${match.tournament}: '
///           '${match.p1?.name} vs ${match.p2?.name}');
///     }
///   } finally {
///     client.close();
///   }
/// }
/// ```
///
/// The package depends only on `package:http` and has no Flutter dependency, so
/// it runs unchanged in pure Dart, Flutter, and on the web.
library;

export 'src/client.dart'
    show
        ArchiveTour,
        AuthHeader,
        LiveTennisApi,
        MatchStatus,
        PackageKind,
        RankingSystem,
        TapeSequence,
        Tour,
        WebhookEvent,
        defaultBaseUrl,
        packageVersion;
export 'src/errors.dart';
export 'src/models.dart';
