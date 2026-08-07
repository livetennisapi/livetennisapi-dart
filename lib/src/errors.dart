/// Exception hierarchy for the Live Tennis API.
///
/// Every failed request raises a [LiveTennisApiException]. It always carries
/// the HTTP [statusCode], the machine-readable [code] from the response body
/// (for example `upgrade_required`), the parsed [body] and the response
/// [headers], so a caller can inspect the raw response. The common cases are
/// distinguishable by type alone, so most callers never need those fields:
///
/// ```dart
/// try {
///   await client.getMatchAnalysis(matchId);
/// } on UpgradeRequiredException catch (e) {
///   print(e.requiredTier); // 'ULTRA'
/// } on RateLimitedException catch (e) {
///   await Future<void>.delayed(Duration(seconds: e.retryAfter?.ceil() ?? 60));
/// }
/// ```
library;

/// Base class for every error raised by this library.
///
/// Concrete subclasses map one-to-one onto the API's error statuses. Catch this
/// type to handle any API failure uniformly, or a subtype for a specific case.
class LiveTennisApiException implements Exception {
  /// A human-readable message. Falls back to the HTTP reason phrase when the
  /// body carries no `error` code.
  final String message;

  /// The HTTP status code of the response.
  final int statusCode;

  /// The API's machine-readable error code, taken from the response body's
  /// `error` field (for example `upgrade_required`), or `null` when absent.
  final String? code;

  /// The parsed response body, or `null` when it could not be decoded.
  final Object? body;

  /// The response headers, lower-cased by the HTTP layer.
  final Map<String, String> headers;

  /// The request URL, when known.
  final String? url;

  /// Creates an API exception. Prefer [exceptionForStatus] to construct the
  /// right subtype for a status code.
  const LiveTennisApiException(
    this.message, {
    required this.statusCode,
    this.code,
    this.body,
    this.headers = const {},
    this.url,
  });

  @override
  String toString() {
    final base = '$runtimeType: [$statusCode] $message';
    return url == null ? base : '$base ($url)';
  }
}

/// 400 — a query parameter was malformed (for example an unknown `tour`).
class BadRequestException extends LiveTennisApiException {
  /// Creates a 400 exception.
  const BadRequestException(
    super.message, {
    super.statusCode = 400,
    super.code,
    super.body,
    super.headers,
    super.url,
  });
}

/// 401 — the key is missing, unknown, or disabled.
class UnauthorizedException extends LiveTennisApiException {
  /// Creates a 401 exception.
  const UnauthorizedException(
    super.message, {
    super.statusCode = 401,
    super.code,
    super.body,
    super.headers,
    super.url,
  });
}

/// 403 — the endpoint exists but your tier does not unlock it.
///
/// This is **not** an authentication failure: the key is valid, the plan is too
/// low. [requiredTier] is the lowest tier that unlocks the endpoint, inferred
/// from the endpoint rather than the response body — the API returns only
/// `{"error": "upgrade_required"}`.
class UpgradeRequiredException extends LiveTennisApiException {
  /// The lowest tier that unlocks the endpoint (for example `ULTRA`), or `null`
  /// when it could not be inferred.
  final String? requiredTier;

  /// Creates a 403 exception.
  const UpgradeRequiredException(
    super.message, {
    super.statusCode = 403,
    super.code,
    super.body,
    super.headers,
    super.url,
    this.requiredTier,
  });

  @override
  String toString() {
    final base = super.toString();
    if (requiredTier == null) return base;
    return '$base — this endpoint requires the $requiredTier tier. '
        'See https://livetennisapi.com/#pricing';
  }
}

/// 404 — no such resource, or no data for it yet.
class NotFoundException extends LiveTennisApiException {
  /// Creates a 404 exception.
  const NotFoundException(
    super.message, {
    super.statusCode = 404,
    super.code,
    super.body,
    super.headers,
    super.url,
  });
}

/// 409 — the request conflicts with the current state.
///
/// The API's known case is `webhook_limit`: the key already has the maximum
/// of 3 webhooks, so delete one before registering another. Check [code].
class ConflictException extends LiveTennisApiException {
  /// Creates a 409 exception.
  const ConflictException(
    super.message, {
    super.statusCode = 409,
    super.code,
    super.body,
    super.headers,
    super.url,
  });
}

/// 429 — the tier's rate-limit window was exceeded.
///
/// The API has two `rate_limited` windows, distinguishable by [scope]:
///
/// - **per-minute** (`scope` null): wait [retryAfter] seconds and go again.
/// - **per-day** (`scope` == `'day'`): the day's quota ([limitPerDay]) is
///   spent; [resetsAt] is the absolute instant it resets. The reset is
///   derived from the service's local midnight — do not assume any
///   particular UTC hour.
///
/// [retryAfter] is the number of seconds the API asked you to wait, parsed from
/// the `Retry-After` header. It is `null` when the header is absent or
/// unparseable.
class RateLimitedException extends LiveTennisApiException {
  /// Seconds to wait before retrying, from the `Retry-After` header, or `null`.
  final num? retryAfter;

  /// The limit scope from the body: `'day'` on a daily-quota 429, `null` on a
  /// per-minute one.
  final String? scope;

  /// The daily quota that was exhausted, from the body's `limit_per_day`;
  /// `null` on a per-minute 429.
  final int? limitPerDay;

  /// When the daily quota resets — the absolute instant from the body's
  /// `resets_at`; `null` on a per-minute 429.
  final DateTime? resetsAt;

  /// Creates a 429 exception.
  const RateLimitedException(
    super.message, {
    super.statusCode = 429,
    super.code,
    super.body,
    super.headers,
    super.url,
    this.retryAfter,
    this.scope,
    this.limitPerDay,
    this.resetsAt,
  });

  @override
  String toString() {
    final base = super.toString();
    if (resetsAt != null) return '$base — daily quota resets at $resetsAt';
    return retryAfter == null ? base : '$base — retry after ${retryAfter}s';
  }
}

/// 429 `abuse_throttled` — a 24-hour block for clients that chronically run
/// far over their cap, usually a broken retry loop.
///
/// This is not an ordinary rate limit: backing off for a few seconds will not
/// clear it, so the client never auto-retries it. Fix the loop that caused it
/// and wait until [retryAt].
class AbuseThrottledException extends RateLimitedException {
  /// The Unix epoch second the block lifts, from the body's `retry_at_epoch`.
  final int? retryAtEpoch;

  /// Creates an abuse-throttled exception.
  const AbuseThrottledException(
    super.message, {
    super.statusCode,
    super.code,
    super.body,
    super.headers,
    super.url,
    super.retryAfter,
    this.retryAtEpoch,
  });

  /// [retryAtEpoch] as a UTC [DateTime], or `null`.
  DateTime? get retryAt => retryAtEpoch == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(retryAtEpoch! * 1000, isUtc: true);

  @override
  String toString() {
    final base = 'AbuseThrottledException: [$statusCode] $message'
        '${url == null ? '' : ' ($url)'}';
    final at = retryAt;
    return at == null
        ? '$base — fix the retry loop that caused this'
        : '$base — blocked until $at; fix the retry loop that caused this';
  }
}

/// 5xx — the API failed to serve the request.
class ServerException extends LiveTennisApiException {
  /// Creates a 5xx exception.
  const ServerException(
    super.message, {
    super.statusCode = 500,
    super.code,
    super.body,
    super.headers,
    super.url,
  });
}

/// 503 — the public surface is disabled or the service is down.
class ServiceUnavailableException extends ServerException {
  /// Creates a 503 exception.
  const ServiceUnavailableException(
    super.message, {
    super.statusCode = 503,
    super.code,
    super.body,
    super.headers,
    super.url,
  });
}

/// Builds the exception subtype that matches an HTTP [statusCode].
///
/// Anything unmapped becomes a [ServerException] at or above 500, and a plain
/// [LiveTennisApiException] otherwise.
LiveTennisApiException exceptionForStatus(
  int statusCode,
  String message, {
  String? code,
  Object? body,
  Map<String, String> headers = const {},
  String? url,
  String? requiredTier,
  num? retryAfter,
}) {
  switch (statusCode) {
    case 400:
      return BadRequestException(message,
          code: code, body: body, headers: headers, url: url);
    case 401:
      return UnauthorizedException(message,
          code: code, body: body, headers: headers, url: url);
    case 403:
      return UpgradeRequiredException(message,
          code: code,
          body: body,
          headers: headers,
          url: url,
          requiredTier: requiredTier);
    case 404:
      return NotFoundException(message,
          code: code, body: body, headers: headers, url: url);
    case 409:
      return ConflictException(message,
          code: code, body: body, headers: headers, url: url);
    case 429:
      final map = body is Map ? body : const {};
      if (code == 'abuse_throttled') {
        final epoch = map['retry_at_epoch'];
        return AbuseThrottledException(message,
            code: code,
            body: body,
            headers: headers,
            url: url,
            retryAfter: retryAfter,
            retryAtEpoch: epoch is int ? epoch : null);
      }
      final limitPerDay = map['limit_per_day'];
      final resetsAt = map['resets_at'];
      return RateLimitedException(message,
          code: code,
          body: body,
          headers: headers,
          url: url,
          retryAfter: retryAfter,
          scope: map['scope'] is String ? map['scope'] as String : null,
          limitPerDay: limitPerDay is int ? limitPerDay : null,
          resetsAt:
              resetsAt is String ? DateTime.tryParse(resetsAt) : null);
    case 503:
      return ServiceUnavailableException(message,
          code: code, body: body, headers: headers, url: url);
    default:
      if (statusCode >= 500) {
        return ServerException(message,
            statusCode: statusCode,
            code: code,
            body: body,
            headers: headers,
            url: url);
      }
      return LiveTennisApiException(message,
          statusCode: statusCode,
          code: code,
          body: body,
          headers: headers,
          url: url);
  }
}
