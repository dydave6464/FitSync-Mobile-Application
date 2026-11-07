import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fitsync/core/api_client.dart';
import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/token_store.dart';
import 'package:fitsync/features/ads/data/ad_source.dart';

HouseAdSource _source(
  List<http.Request> sent,
  http.Response Function(http.Request) respond,
) => HouseAdSource(
  ApiClient(
    baseUrl: 'http://10.0.2.2:3000',
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

http.Response _serverError() => http.Response(
  jsonEncode({
    'error': {'code': 'SERVER_ERROR', 'message': 'nope'},
  }),
  500,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  test('current reads the one ad from /ads/current', () async {
    final sent = <http.Request>[];
    final source = _source(
      sent,
      (_) => _ok({
        'ad': {
          'id': 5,
          'title': 'Protein bars, 20% off',
          'imageUrl': '/storage/ads/5.jpg',
          'linkUrl': 'https://shop.example.ph/',
        },
      }),
    );

    final ad = await source.current();

    expect(sent.single.method, 'GET');
    expect(sent.single.url.path, '/api/v1/ads/current');
    expect(ad, isNotNull);
    expect(ad!.id, 5);
    expect(ad.title, 'Protein bars, 20% off');
    // Joined to the server's address here, so the slot shows it as it is
    // (an ad from another source would carry a full address of its own).
    expect(ad.imageUrl, 'http://10.0.2.2:3000/storage/ads/5.jpg');
    expect(ad.linkUrl, 'https://shop.example.ph/');
  });

  test('current is null when nothing runs, or for a Pro member', () async {
    final source = _source([], (_) => _ok({'ad': null}));

    expect(await source.current(), isNull);
  });

  test('an ad without a link reads with a null link', () async {
    final source = _source(
      [],
      (_) => _ok({
        'ad': {
          'id': 6,
          'title': 'Weekly deals',
          'imageUrl': '/storage/ads/6.png',
          'linkUrl': null,
        },
      }),
    );

    expect((await source.current())!.linkUrl, isNull);
  });

  test('viewed and tapped post to /ads/:id/view and /tap', () async {
    final sent = <http.Request>[];
    final source = _source(sent, (_) => http.Response('', 204));

    await source.viewed(5);
    await source.tapped(5);

    expect(sent.map((r) => (r.method, r.url.path)), [
      ('POST', '/api/v1/ads/5/view'),
      ('POST', '/api/v1/ads/5/tap'),
    ]);
  });

  test('a failed view or tap report is swallowed', () async {
    final source = _source([], (_) => _serverError());

    await expectLater(source.viewed(5), completes);
    await expectLater(source.tapped(5), completes);
  });

  test('a failed current surfaces the error for the slot to hide', () async {
    final source = _source([], (_) => _serverError());

    await expectLater(source.current(), throwsA(isA<ApiException>()));
  });
}
