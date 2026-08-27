/// An error the server named, or a transport failure we could not attribute.
///
/// [code] is the server's own error code where one was returned, so a failure
/// identifies itself in logs instead of surfacing as a bare status number.
class ApiException implements Exception {
  const ApiException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'ApiException($code): $message';
}
