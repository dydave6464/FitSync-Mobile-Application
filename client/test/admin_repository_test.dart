import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fitsync/core/api_client.dart';
import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/token_store.dart';
import 'package:fitsync/features/admin/data/admin_repository.dart';

/// A repository whose every request is answered by [respond], with the
/// requests it sent collected in [sent].
AdminRepository _repo(
  List<http.Request> sent,
  http.Response Function(http.Request) respond,
) => AdminRepository(
  ApiClient(
    tokens: TokenStore(backing: InMemorySecureStore()),
    client: MockClient((request) async {
      sent.add(request);
      return respond(request);
    }),
  ),
);

http.Response _ok(Object data) => http.Response(
  jsonEncode({'data': data}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

http.Response _error(int status, String code, String message) => http.Response(
  jsonEncode({
    'error': {'code': code, 'message': message},
  }),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Map<String, dynamic> _detailJson({String? suspendedAt}) => {
  'id': 7,
  'fullName': 'Juan Dela Cruz',
  'email': 'juan@example.com',
  'joinedOn': '2026-11-05',
  'emailVerified': true,
  'signInMethods': ['password', 'google'],
  'lastActiveOn': '2026-11-06',
  'pro': {'isPro': true, 'source': 'paid', 'until': '2026-12-05T03:00:00.000Z'},
  'suspendedAt': suspendedAt,
};

void main() {
  test('me reads the admin from /admin/me with the stored token', () async {
    final tokens = TokenStore(backing: InMemorySecureStore());
    await tokens.write('admin-tok');
    late http.Request sent;
    final api = ApiClient(
      tokens: tokens,
      client: MockClient((request) async {
        sent = request;
        return http.Response(
          jsonEncode({
            'data': {
              'admin': {
                'id': 3,
                'email': 'admin@fitsync.ph',
                'fullName': 'Ana Reyes',
              },
            },
          }),
          200,
        );
      }),
    );

    final admin = await AdminRepository(api).me();

    expect(sent.method, 'GET');
    expect(sent.url.path, '/api/v1/admin/me');
    expect(sent.headers['Authorization'], 'Bearer admin-tok');
    expect(admin.id, 3);
    expect(admin.email, 'admin@fitsync.ph');
    expect(admin.fullName, 'Ana Reyes');
  });

  test('a refused admin token surfaces as UNAUTHENTICATED', () async {
    final api = ApiClient(
      tokens: TokenStore(backing: InMemorySecureStore()),
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {
              'code': 'UNAUTHENTICATED',
              'message': 'Sign in again to continue.',
            },
          }),
          401,
        ),
      ),
    );

    await expectLater(
      AdminRepository(api).me(),
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'UNAUTHENTICATED'),
      ),
    );
  });

  test('overview reads every figure from /admin/overview', () async {
    final sent = <http.Request>[];
    final repo = _repo(
      sent,
      (_) => _ok({
        'today': '2026-11-07',
        'activeUsers': {'count': 14, 'previousCount': 11},
        'proMembers': 3,
        'proRevenue': {'thisMonthPhp': 498.0, 'lastMonthPhp': 249},
        'adRevenue': {'thisMonthPhp': 0, 'lastMonthPhp': 0.0},
        'signups': {
          'total': 12,
          'days': [
            {'date': '2026-10-09', 'count': 0},
            {'date': '2026-10-10', 'count': 2},
          ],
        },
      }),
    );

    final overview = await repo.overview();

    expect(sent.single.method, 'GET');
    expect(sent.single.url.path, '/api/v1/admin/overview');
    expect(overview.today, '2026-11-07');
    expect(overview.activeUsers, 14);
    expect(overview.previousActiveUsers, 11);
    expect(overview.proMembers, 3);
    expect(overview.proRevenueThisMonth, 498.0);
    expect(overview.proRevenueLastMonth, 249.0);
    expect(overview.adRevenueThisMonth, 0.0);
    expect(overview.adRevenueLastMonth, 0.0);
    expect(overview.signupsTotal, 12);
    expect(overview.signupDays.map((d) => (d.date, d.count)), [
      ('2026-10-09', 0),
      ('2026-10-10', 2),
    ]);
  });

  test('users sends search, filter and page as strings', () async {
    final sent = <http.Request>[];
    final repo = _repo(
      sent,
      (_) => _ok({
        'users': [
          {
            'id': 7,
            'fullName': 'Juan Dela Cruz',
            'email': 'juan@example.com',
            'isPro': true,
            'suspended': false,
            'lastActiveOn': '2026-11-06',
            'joinedOn': '2026-11-05',
          },
          {
            'id': 6,
            'fullName': 'Maria Santos',
            'email': 'maria@example.com',
            'isPro': false,
            'suspended': true,
            'lastActiveOn': null,
            'joinedOn': '2026-11-01',
          },
        ],
        'page': 2,
        'limit': 30,
        'total': 62,
      }),
    );

    final result = await repo.users(q: 'jua', filter: 'pro', page: 2);

    final url = sent.single.url;
    expect(sent.single.method, 'GET');
    expect(url.path, '/api/v1/admin/users');
    expect(url.queryParameters, {'q': 'jua', 'filter': 'pro', 'page': '2'});
    expect(result.page, 2);
    expect(result.total, 62);
    // 2 pages of 30 = 60 shown, 62 in all.
    expect(result.hasMore, isTrue);
    final juan = result.users.first;
    expect(juan.id, 7);
    expect(juan.fullName, 'Juan Dela Cruz');
    expect(juan.email, 'juan@example.com');
    expect(juan.isPro, isTrue);
    expect(juan.suspended, isFalse);
    expect(juan.lastActiveOn, '2026-11-06');
    expect(juan.joinedOn, '2026-11-05');
    expect(result.users.last.suspended, isTrue);
    expect(result.users.last.lastActiveOn, isNull);
  });

  test('users with the defaults sends filter all and page 1', () async {
    final sent = <http.Request>[];
    final repo = _repo(
      sent,
      (_) => _ok({'users': [], 'page': 1, 'limit': 30, 'total': 0}),
    );

    final result = await repo.users();

    expect(sent.single.url.queryParameters, {'filter': 'all', 'page': '1'});
    expect(result.users, isEmpty);
    expect(result.hasMore, isFalse);
  });

  test('user reads the detail from /admin/users/:id', () async {
    final sent = <http.Request>[];
    final repo = _repo(sent, (_) => _ok({'user': _detailJson()}));

    final user = await repo.user(7);

    expect(sent.single.method, 'GET');
    expect(sent.single.url.path, '/api/v1/admin/users/7');
    expect(user.id, 7);
    expect(user.fullName, 'Juan Dela Cruz');
    expect(user.email, 'juan@example.com');
    expect(user.joinedOn, '2026-11-05');
    expect(user.emailVerified, isTrue);
    expect(user.signInMethods, ['password', 'google']);
    expect(user.lastActiveOn, '2026-11-06');
    expect(user.isPro, isTrue);
    expect(user.proSource, 'paid');
    expect(user.proUntil, DateTime.utc(2026, 12, 5, 3));
    expect(user.suspendedAt, isNull);
    expect(user.suspended, isFalse);
  });

  test('an unknown trainee surfaces as USER_NOT_FOUND', () async {
    final repo = _repo(
      [],
      (_) => _error(404, 'USER_NOT_FOUND', 'No such trainee.'),
    );

    await expectLater(
      repo.user(99),
      throwsA(
        isA<ApiException>()
            .having((e) => e.code, 'code', 'USER_NOT_FOUND')
            .having((e) => e.message, 'message', 'No such trainee.'),
      ),
    );
  });

  test('suspend posts to /suspend and returns the new detail', () async {
    final sent = <http.Request>[];
    final repo = _repo(
      sent,
      (_) => _ok({'user': _detailJson(suspendedAt: '2026-11-07T02:00:00Z')}),
    );

    final user = await repo.suspend(7);

    expect(sent.single.method, 'POST');
    expect(sent.single.url.path, '/api/v1/admin/users/7/suspend');
    expect(user.suspended, isTrue);
    expect(user.suspendedAt, DateTime.utc(2026, 11, 7, 2));
  });

  test('reinstate posts to /reinstate and returns the new detail', () async {
    final sent = <http.Request>[];
    final repo = _repo(sent, (_) => _ok({'user': _detailJson()}));

    final user = await repo.reinstate(7);

    expect(sent.single.method, 'POST');
    expect(sent.single.url.path, '/api/v1/admin/users/7/reinstate');
    expect(user.suspended, isFalse);
  });

  test('a failed suspend surfaces the server error', () async {
    final repo = _repo(
      [],
      (_) => _error(404, 'USER_NOT_FOUND', 'No such trainee.'),
    );

    await expectLater(
      repo.suspend(99),
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'USER_NOT_FOUND'),
      ),
    );
  });

  test('a granted Pro and a free trainee read with no end date', () async {
    final granted = _detailJson()
      ..['pro'] = {'isPro': true, 'source': 'granted', 'until': null}
      ..['signInMethods'] = ['google']
      ..['emailVerified'] = false
      ..['lastActiveOn'] = null;
    final repo = _repo([], (_) => _ok({'user': granted}));

    final user = await repo.user(7);

    expect(user.proSource, 'granted');
    expect(user.proUntil, isNull);
    expect(user.signInMethods, ['google']);
    expect(user.emailVerified, isFalse);
    expect(user.lastActiveOn, isNull);
  });
}
