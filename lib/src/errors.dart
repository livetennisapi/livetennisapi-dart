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

/// 429 — the tier's rate-limit window was exceeded.
///
/// [retryAfter] is the number of seconds the API asked you to wait, parsed from
/// the `Retry-After` header. It is `null` when the header is absent or
/// unparseable.
class RateLimitedException extends LiveTennisApiException {
  /// Seconds to wait before retrying, from the `Retry-After` header, or `null`.
  final num? retryAfter;

  /// Creates a 429 exception.
  const RateLimitedException(
    super.message, {
    super.statusCode = 429,
    super.code,
    super.body,
    super.headers,
    super.url,
    this.retryAfter,
  });

  @override
  String toString() {
    final base = super.toString();
    return retryAfter == null ? base : '$base — retry after ${retryAfter}s';
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
    case 429:
      return RateLimitedException(message,
          code: code,
          body: body,
          headers: headers,
          url: url,
          retryAfter: retryAfter);
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
