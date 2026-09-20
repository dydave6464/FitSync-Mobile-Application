import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fitsync/core/api_client.dart';
import 'package:fitsync/core/token_store.dart';
import 'package:fitsync/features/sessions/data/session_repository.dart';
import 'package:fitsync/features/sessions/domain/shared_report.dart';

SessionRepository _repo(MockClient client) => SessionRepository(
  ApiClient(
    baseUrl: 'http://test.local',
    tokens: TokenStore(backing: InMemorySecureStore()),
    client: client,
  ),
);

void main() {
  test('a shared report reads its link and expiry', () {
    final report = SharedReport.fromJson(const {
      'url': 'https://fitsync.test/api/v1/reports/abc',
      'expiresAt': '2026-10-19T00:00:00.000Z',
    });

    expect(report.url, 'https://fitsync.test/api/v1/reports/abc');
    expect(report.expiresAt.year, 2026);
    expect(report.expiresAt.month, 10);
  });

  test('sharing posts the period and the chosen sections', () async {
    Map<String, dynamic>? sent;
    final repo = _repo(
      MockClient((request) async {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'data': {
              'url': 'https://fitsync.test/api/v1/reports/abc',
              'expiresAt': '2026-10-19T00:00:00.000Z',
            },
          }),
          201,
        );
      }),
    );

    final report = await repo.shareReport(
      period: 'month',
      include: const {'volume': true, 'bodyWeight': false},
    );

    expect(sent!['period'], 'month');
    // The sections travel as sent: a toggle the user turned off must reach the
    // server as false, not be dropped and defaulted.
    expect((sent!['include'] as Map)['volume'], true);
    expect((sent!['include'] as Map)['bodyWeight'], false);
    expect(report.url, 'https://fitsync.test/api/v1/reports/abc');
  });
}
