import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fitsync/core/api_client.dart';
import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/token_store.dart';
import 'package:fitsync/features/admin/data/admin_repository.dart';
import 'package:fitsync/features/admin/domain/admin_models.dart';

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

  group('content', () {
    Map<String, dynamic> exerciseJson({
      int id = 41,
      String status = 'pending',
      String? pendingReason = 'cardio',
      String? thumbnailUrl = '/storage/exercises/41/thumb.jpg',
    }) => {
      'id': id,
      'name': 'jumping jack',
      'muscleGroup': 'cardiovascular system',
      'equipment': 'body weight',
      'thumbnailUrl': thumbnailUrl,
      'animationUrl': '/storage/exercises/41/demo.gif',
      'status': status,
      'pendingReason': pendingReason,
    };

    Map<String, dynamic> foodJson({bool hidden = false}) => {
      'id': 12,
      'name': 'Chicken adobo',
      'category': 'filipino',
      'foodType': 'home',
      'servingDesc': '1 cup (240 g)',
      'kcal': 320,
      'proteinG': 28.5,
      'carbsG': 4,
      'fatG': 21.25,
      'fiberG': null,
      'sugarG': 1.5,
      'sodiumMg': 870.5,
      'hidden': hidden,
    };

    test('exercises sends status, search and page as strings', () async {
      final sent = <http.Request>[];
      final repo = _repo(
        sent,
        (_) => _ok({
          'exercises': [
            exerciseJson(),
            exerciseJson(
              id: 42,
              status: 'live',
              pendingReason: null,
              thumbnailUrl: null,
            ),
          ],
          'counts': {'pending': 121, 'live': 1203},
          'page': 2,
          'limit': 30,
          'total': 61,
        }),
      );

      final result = await repo.exercises(status: 'live', q: 'jack', page: 2);

      expect(sent.single.method, 'GET');
      expect(sent.single.url.path, '/api/v1/admin/exercises');
      expect(sent.single.url.queryParameters, {
        'status': 'live',
        'q': 'jack',
        'page': '2',
      });
      expect(result.pendingCount, 121);
      expect(result.liveCount, 1203);
      expect(result.page, 2);
      expect(result.total, 61);
      expect(result.hasMore, isTrue);
      final first = result.exercises.first;
      expect(first.id, 41);
      expect(first.name, 'jumping jack');
      expect(first.muscleGroup, 'cardiovascular system');
      expect(first.equipment, 'body weight');
      expect(first.thumbnailUrl, '/storage/exercises/41/thumb.jpg');
      expect(first.animationUrl, '/storage/exercises/41/demo.gif');
      expect(first.live, isFalse);
      expect(first.pendingReason, 'cardio');
      expect(result.exercises.last.live, isTrue);
      expect(result.exercises.last.pendingReason, isNull);
      expect(result.exercises.last.thumbnailUrl, isNull);
    });

    test('exercises with the defaults asks for pending, page 1', () async {
      final sent = <http.Request>[];
      final repo = _repo(
        sent,
        (_) => _ok({
          'exercises': [],
          'counts': {'pending': 0, 'live': 3},
          'page': 1,
          'limit': 30,
          'total': 0,
        }),
      );

      final result = await repo.exercises();

      expect(sent.single.url.queryParameters, {
        'status': 'pending',
        'page': '1',
      });
      expect(result.hasMore, isFalse);
    });

    test('publish and unpublish post and read the exercise back', () async {
      final sent = <http.Request>[];
      final repo = _repo(sent, (request) {
        final live = request.url.path.endsWith('/publish');
        return _ok({
          'exercise': exerciseJson(
            status: live ? 'live' : 'pending',
            pendingReason: live ? null : 'rare_equipment',
          ),
        });
      });

      final published = await repo.publish(41);
      final unpublished = await repo.unpublish(41);

      expect(sent.map((r) => (r.method, r.url.path)), [
        ('POST', '/api/v1/admin/exercises/41/publish'),
        ('POST', '/api/v1/admin/exercises/41/unpublish'),
      ]);
      expect(published.live, isTrue);
      expect(unpublished.live, isFalse);
      expect(unpublished.pendingReason, 'rare_equipment');
    });

    test('a refused unpublish surfaces EXERCISE_IN_USE', () async {
      final repo = _repo(
        [],
        (_) => _error(
          409,
          'EXERCISE_IN_USE',
          "Trainees have this exercise in their plans or workouts, so it "
              "can't be unpublished.",
        ),
      );

      await expectLater(
        repo.unpublish(41),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'EXERCISE_IN_USE'),
        ),
      );
    });

    test('foods sends show, search and page and reads each food', () async {
      final sent = <http.Request>[];
      final repo = _repo(
        sent,
        (_) => _ok({
          'foods': [foodJson(), foodJson(hidden: true)],
          'counts': {'shown': 412, 'hidden': 3},
          'page': 1,
          'limit': 30,
          'total': 2,
        }),
      );

      final result = await repo.foods(show: 'hidden', q: 'adobo');

      expect(sent.single.method, 'GET');
      expect(sent.single.url.path, '/api/v1/admin/foods');
      expect(sent.single.url.queryParameters, {
        'show': 'hidden',
        'q': 'adobo',
        'page': '1',
      });
      expect(result.shownCount, 412);
      expect(result.hiddenCount, 3);
      expect(result.total, 2);
      expect(result.hasMore, isFalse);
      final food = result.foods.first;
      expect(food.id, 12);
      expect(food.name, 'Chicken adobo');
      expect(food.category, 'filipino');
      expect(food.foodType, 'home');
      expect(food.servingDesc, '1 cup (240 g)');
      expect(food.kcal, 320);
      expect(food.proteinG, 28.5);
      expect(food.carbsG, 4.0);
      expect(food.fatG, 21.25);
      expect(food.fiberG, isNull);
      expect(food.sugarG, 1.5);
      expect(food.sodiumMg, 870.5);
      expect(food.hidden, isFalse);
      expect(result.foods.last.hidden, isTrue);
    });

    test('foods with the defaults asks for shown, page 1', () async {
      final sent = <http.Request>[];
      final repo = _repo(
        sent,
        (_) => _ok({
          'foods': [],
          'counts': {'shown': 0, 'hidden': 0},
          'page': 1,
          'limit': 30,
          'total': 0,
        }),
      );

      await repo.foods();

      expect(sent.single.url.queryParameters, {'show': 'shown', 'page': '1'});
    });

    const input = FoodInput(
      name: 'Chicken adobo',
      category: 'filipino',
      foodType: 'home',
      servingDesc: '1 cup (240 g)',
      proteinG: 28.5,
      carbsG: 4,
      fatG: 21.25,
      sugarG: 1.5,
    );

    test('createFood posts every field, empty ones as null', () async {
      final sent = <http.Request>[];
      final repo = _repo(sent, (_) => _ok({'food': foodJson()}));

      final food = await repo.createFood(input);

      expect(sent.single.method, 'POST');
      expect(sent.single.url.path, '/api/v1/admin/foods');
      expect(jsonDecode(sent.single.body), {
        'name': 'Chicken adobo',
        'category': 'filipino',
        'foodType': 'home',
        'servingDesc': '1 cup (240 g)',
        'kcal': null,
        'proteinG': 28.5,
        'carbsG': 4,
        'fatG': 21.25,
        'fiberG': null,
        'sugarG': 1.5,
        'sodiumMg': null,
      });
      expect(food.id, 12);
    });

    test('updateFood patches the food with the label calories', () async {
      final sent = <http.Request>[];
      final repo = _repo(sent, (_) => _ok({'food': foodJson()}));

      await repo.updateFood(
        12,
        const FoodInput(
          name: 'Chicken adobo',
          category: 'international',
          foodType: 'fast_food',
          servingDesc: '1 pc',
          kcal: 300,
          proteinG: 20,
          carbsG: 10,
          fatG: 15,
          fiberG: 0.5,
          sodiumMg: 900,
        ),
      );

      expect(sent.single.method, 'PATCH');
      expect(sent.single.url.path, '/api/v1/admin/foods/12');
      final body = jsonDecode(sent.single.body) as Map<String, dynamic>;
      expect(body['category'], 'international');
      expect(body['foodType'], 'fast_food');
      expect(body['kcal'], 300);
      expect(body['fiberG'], 0.5);
      expect(body.containsKey('sugarG'), isTrue);
      expect(body['sugarG'], isNull);
      expect(body['sodiumMg'], 900);
    });

    test('a taken name keeps the server code and message', () async {
      final repo = _repo(
        [],
        (_) => _error(
          409,
          'FOOD_NAME_TAKEN',
          'A food with that name already exists.',
        ),
      );

      await expectLater(
        repo.createFood(input),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'FOOD_NAME_TAKEN')
              .having(
                (e) => e.message,
                'message',
                'A food with that name already exists.',
              ),
        ),
      );
    });

    test('hideFood and showFood post and read the food back', () async {
      final sent = <http.Request>[];
      final repo = _repo(
        sent,
        (request) =>
            _ok({'food': foodJson(hidden: request.url.path.endsWith('/hide'))}),
      );

      final hidden = await repo.hideFood(12);
      final shown = await repo.showFood(12);

      expect(sent.map((r) => (r.method, r.url.path)), [
        ('POST', '/api/v1/admin/foods/12/hide'),
        ('POST', '/api/v1/admin/foods/12/show'),
      ]);
      expect(hidden.hidden, isTrue);
      expect(shown.hidden, isFalse);
    });

    test("baseUrl is the client's, for joining media paths", () {
      final repo = AdminRepository(
        ApiClient(
          baseUrl: 'http://10.0.2.2:3000',
          tokens: TokenStore(backing: InMemorySecureStore()),
          client: MockClient((_) async => http.Response('{}', 200)),
        ),
      );

      expect(repo.baseUrl, 'http://10.0.2.2:3000');
    });
  });

  group('ads', () {
    Map<String, dynamic> adJson({
      bool active = true,
      String status = 'running',
      String? linkUrl = 'https://shop.example.ph/',
    }) => {
      'id': 5,
      'title': 'Protein bars, 20% off',
      'imageUrl': '/storage/ads/5.jpg',
      'linkUrl': linkUrl,
      'advertiser': 'GymShark PH',
      'amountPhp': 1200.5,
      'startsOn': '2026-11-01',
      'endsOn': '2026-11-30',
      'active': active,
      'status': status,
      'views': 1204,
      'taps': 37,
    };

    // A JPEG's first bytes, so the base64 is easy to check.
    final jpeg = Uint8List.fromList(const [0xFF, 0xD8, 0xFF, 0xE0]);

    AdInput input({Uint8List? image, String? linkUrl}) => AdInput(
      title: 'Protein bars, 20% off',
      advertiser: 'GymShark PH',
      amountPhp: 1200.5,
      startsOn: '2026-11-01',
      endsOn: '2026-11-30',
      linkUrl: linkUrl,
      image: image,
      mimeType: image == null ? null : 'image/jpeg',
    );

    test('ads reads every ad from /admin/ads', () async {
      final sent = <http.Request>[];
      final repo = _repo(
        sent,
        (_) => _ok({
          'ads': [
            adJson(),
            adJson(active: false, status: 'paused', linkUrl: null),
          ],
        }),
      );

      final ads = await repo.ads();

      expect(sent.single.method, 'GET');
      expect(sent.single.url.path, '/api/v1/admin/ads');
      expect(ads, hasLength(2));
      final ad = ads.first;
      expect(ad.id, 5);
      expect(ad.title, 'Protein bars, 20% off');
      expect(ad.imageUrl, '/storage/ads/5.jpg');
      expect(ad.linkUrl, 'https://shop.example.ph/');
      expect(ad.advertiser, 'GymShark PH');
      expect(ad.amountPhp, 1200.5);
      expect(ad.startsOn, '2026-11-01');
      expect(ad.endsOn, '2026-11-30');
      expect(ad.active, isTrue);
      expect(ad.status, 'running');
      expect(ad.views, 1204);
      expect(ad.taps, 37);
      expect(ads.last.linkUrl, isNull);
      expect(ads.last.status, 'paused');
    });

    test('createAd posts every field and the image as plain base64', () async {
      final sent = <http.Request>[];
      final repo = _repo(sent, (_) => _ok({'ad': adJson()}));

      final ad = await repo.createAd(
        input(image: jpeg, linkUrl: 'https://shop.example.ph/'),
      );

      expect(sent.single.method, 'POST');
      expect(sent.single.url.path, '/api/v1/admin/ads');
      expect(jsonDecode(sent.single.body), {
        'title': 'Protein bars, 20% off',
        'advertiser': 'GymShark PH',
        'amountPhp': 1200.5,
        'startsOn': '2026-11-01',
        'endsOn': '2026-11-30',
        'linkUrl': 'https://shop.example.ph/',
        'image': '/9j/4A==',
        'mimeType': 'image/jpeg',
      });
      expect(ad.id, 5);
    });

    test('updateAd without a new image leaves the image out', () async {
      final sent = <http.Request>[];
      final repo = _repo(sent, (_) => _ok({'ad': adJson(linkUrl: null)}));

      await repo.updateAd(5, input());

      expect(sent.single.method, 'PATCH');
      expect(sent.single.url.path, '/api/v1/admin/ads/5');
      final body = jsonDecode(sent.single.body) as Map<String, dynamic>;
      expect(body.containsKey('image'), isFalse);
      expect(body.containsKey('mimeType'), isFalse);
      // Sent as null, so an edit can take the link away.
      expect(body.containsKey('linkUrl'), isTrue);
      expect(body['linkUrl'], isNull);
      expect(body['title'], 'Protein bars, 20% off');
    });

    test('setAdActive patches only the active flag', () async {
      final sent = <http.Request>[];
      final repo = _repo(
        sent,
        (_) => _ok({'ad': adJson(active: false, status: 'paused')}),
      );

      final ad = await repo.setAdActive(5, active: false);

      expect(sent.single.method, 'PATCH');
      expect(sent.single.url.path, '/api/v1/admin/ads/5');
      expect(jsonDecode(sent.single.body), {'active': false});
      expect(ad.active, isFalse);
      expect(ad.status, 'paused');
    });

    test('a refused image keeps INVALID_IMAGE and its message', () async {
      final repo = _repo(
        [],
        (_) =>
            _error(400, 'INVALID_IMAGE', 'The image must be at most 1.5 MB.'),
      );

      await expectLater(
        repo.createAd(input(image: jpeg)),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'INVALID_IMAGE')
              .having(
                (e) => e.message,
                'message',
                'The image must be at most 1.5 MB.',
              ),
        ),
      );
    });
  });

  group('revenue', () {
    Map<String, dynamic> revenueJson() => {
      'month': '2026-11',
      'totalPhp': 3486.0,
      'previousTotalPhp': 2739.0,
      'pro': {'totalPhp': 2286.0, 'monthly': 2, 'annual': 1},
      'ads': {'totalPhp': 1200, 'count': 1},
      'lastSixMonths': [
        {'month': '2026-06', 'proPhp': 0.0, 'adsPhp': 0.0},
        {'month': '2026-11', 'proPhp': 2286.0, 'adsPhp': 1200.0},
      ],
      'proPayments': [
        {
          'paymentId': 4,
          'name': 'Juan Dela Cruz',
          'plan': 'monthly',
          'method': 'gcash',
          'amountPhp': 249.0,
          'paidOn': '2026-11-05',
        },
        {
          'paymentId': 5,
          'name': null,
          'plan': 'annual',
          'method': null,
          'amountPhp': 1788,
          'paidOn': '2026-11-06',
        },
      ],
      'adPayments': [
        {
          'adId': 1,
          'advertiser': 'Kusina Co.',
          'title': 'Fresh lunch boxes',
          'amountPhp': 1200.0,
          'startsOn': '2026-11-01',
          'endsOn': '2026-11-30',
        },
      ],
      'firstMonth': '2026-10',
    };

    test('revenue without a month asks for the current one', () async {
      final sent = <http.Request>[];
      final repo = _repo(sent, (_) => _ok(revenueJson()));

      await repo.revenue();

      expect(sent.single.method, 'GET');
      expect(sent.single.url.path, '/api/v1/admin/revenue');
      expect(sent.single.url.queryParameters, isEmpty);
    });

    test('revenue sends the month and reads every field', () async {
      final sent = <http.Request>[];
      final repo = _repo(sent, (_) => _ok(revenueJson()));

      final r = await repo.revenue(month: '2026-11');

      expect(sent.single.url.queryParameters, {'month': '2026-11'});
      expect(r.month, '2026-11');
      expect(r.totalPhp, 3486.0);
      expect(r.previousTotalPhp, 2739.0);
      expect(r.proTotalPhp, 2286.0);
      expect(r.proMonthly, 2);
      expect(r.proAnnual, 1);
      expect(r.adsTotalPhp, 1200.0);
      expect(r.adsCount, 1);
      expect(r.lastSixMonths.map((b) => b.month), ['2026-06', '2026-11']);
      expect(r.lastSixMonths.last.proPhp, 2286.0);
      expect(r.lastSixMonths.last.adsPhp, 1200.0);
      expect(r.firstMonth, '2026-10');

      final juan = r.proPayments.first;
      expect(juan.paymentId, 4);
      expect(juan.name, 'Juan Dela Cruz');
      expect(juan.plan, 'monthly');
      expect(juan.method, 'gcash');
      expect(juan.amountPhp, 249.0);
      expect(juan.paidOn, '2026-11-05');
      final deleted = r.proPayments.last;
      expect(deleted.name, isNull);
      expect(deleted.method, isNull);
      expect(deleted.amountPhp, 1788.0);

      final ad = r.adPayments.single;
      expect(ad.adId, 1);
      expect(ad.advertiser, 'Kusina Co.');
      expect(ad.title, 'Fresh lunch boxes');
      expect(ad.amountPhp, 1200.0);
      expect(ad.startsOn, '2026-11-01');
      expect(ad.endsOn, '2026-11-30');
    });

    test('a month with nothing before it has no firstMonth', () async {
      final repo = _repo(
        [],
        (_) => _ok({...revenueJson(), 'firstMonth': null}),
      );

      final r = await repo.revenue();

      expect(r.firstMonth, isNull);
    });
  });
}
