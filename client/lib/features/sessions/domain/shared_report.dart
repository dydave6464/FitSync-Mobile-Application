/// A link a coach can open, and the day it stops working.
///
/// The report itself never comes back to the app -- the server holds the
/// snapshot and renders it. This is only what the user needs to pass on.
class SharedReport {
  const SharedReport({required this.url, required this.expiresAt});

  final String url;
  final DateTime expiresAt;

  factory SharedReport.fromJson(Map<String, dynamic> json) => SharedReport(
        url: json['url'] as String,
        expiresAt: DateTime.parse(json['expiresAt'] as String),
      );
}
