/// An error the server named, or a transport failure we could not attribute.
///
/// [code] is the server's own error code where one was returned, so a failure
/// identifies itself in logs instead of surfacing as a bare status number.
class ApiException implements Exception {
  const ApiException(this.code, this.message, {this.details = const []});

  final String code;
  final String message;

  /// The server's `error.details`, kept as sent: for a rejected field, a list
  /// of `{ field }` objects naming which one, so a screen can point at it.
  final List<Map<String, dynamic>> details;

  @override
  String toString() => 'ApiException($code): $message';
}

/// The codes for a failure that sending the same request again may get
/// past: the phone could not reach the server (`NETWORK_ERROR`), the server
/// failed (`INTERNAL_ERROR`), or its answer was garbled, such as a proxy's
/// error page (`INVALID_RESPONSE`). A refusal the server named -- no such
/// entry, a value out of range -- would only be refused again, and
/// `UNKNOWN_ERROR` is a server error with no code, so it is a refusal too.
const retryableErrorCodes = {
  'NETWORK_ERROR',
  'INTERNAL_ERROR',
  'INVALID_RESPONSE',
};

/// Whether a retry can fix [error]: the one definition of "transient",
/// used by the automatic retry of loads (`apiRetryPolicy`) and by the
/// "Try again" action on failed saves (`retryCanFix`), so they agree.
bool isRetryableError(Object error) =>
    error is ApiException && retryableErrorCodes.contains(error.code);

/// A failure in words a user can act on.
///
/// The client's own transport messages are written for whoever runs the
/// server -- an address, an adb command -- and a non-JSON reply says nothing
/// a user can use, so those are replaced. The server's own messages are
/// already written for users and pass through. Anything that is not an
/// [ApiException] is a bug, and gets a plain apology rather than its
/// `toString`.
String userMessage(Object error) => switch (error) {
  ApiException(code: 'NETWORK_ERROR') =>
    "Couldn't reach FitSync. Check your connection and try again.",
  ApiException(code: 'INVALID_RESPONSE' || 'UNKNOWN_ERROR') =>
    'Something went wrong on our side. Please try again.',
  ApiException(:final message) => message,
  _ => 'Something went wrong. Please try again.',
};
