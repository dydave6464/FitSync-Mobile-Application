import 'dart:convert';
import 'dart:ui' show CheckedState, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SemanticsData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fitsync/core/api_client.dart';
import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/token_store.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';
import 'package:fitsync/features/exercises/presentation/providers.dart'
    show apiClientProvider;
import 'package:fitsync/features/profile/domain/profile.dart';
import 'package:fitsync/features/profile/presentation/providers.dart'
    show injuryOptionsProvider;
import 'package:fitsync/features/sessions/domain/session_outcome.dart';
import 'package:fitsync/features/sessions/presentation/widgets/outcome_sheet.dart';
import 'package:fitsync/features/sessions/presentation/widgets/sheet_header.dart';

const _pending = PendingOutcome(
  sessionId: 7,
  sessionDate: '2026-09-21',
  planName: 'Upper Body · Push',
);

const _regions = [
  InjuryOption(
    injuryId: 1,
    name: 'Shoulder',
    isLateral: true,
    regionGroup: 'upper_body',
  ),
  InjuryOption(
    injuryId: 13,
    name: 'Knee',
    isLateral: true,
    regionGroup: 'lower_body',
  ),
];

/// Opens the sheet over a Scaffold and returns every body POSTed to the
/// outcome route. [status] and [errorCode] shape the server's answer.
/// [onResult] is handed whatever [showOutcomeSheet] resolves with, once the
/// sheet closes.
Future<List<Map<String, dynamic>>> _open(
  WidgetTester tester, {
  int status = 201,
  String errorCode = 'INTERNAL',
  ValueChanged<bool?>? onResult,
  // How many times injuryOptionsProvider throws before it starts returning
  // _regions -- 0 means it never fails.
  int regionsFailures = 0,
}) async {
  final posts = <Map<String, dynamic>>[];
  var regionsCalls = 0;
  final client = MockClient((request) async {
    if (request.method == 'POST' &&
        request.url.path == '/api/v1/sessions/7/outcome') {
      posts.add(jsonDecode(request.body) as Map<String, dynamic>);
      if (status == 201) {
        return http.Response('{"data":{"outcome":{}}}', 201);
      }
      return http.Response(
        jsonEncode({
          'error': {'code': errorCode, 'message': 'x'},
        }),
        status,
      );
    }
    return http.Response('{"data":{}}', 200);
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(
          ApiClient(
            baseUrl: 'http://test.local',
            tokens: TokenStore(backing: InMemorySecureStore()),
            client: client,
          ),
        ),
        injuryOptionsProvider.overrideWith((ref) async {
          if (regionsCalls++ < regionsFailures) {
            throw Exception("Couldn't load body regions.");
          }
          return _regions;
        }),
      ],
      child: MaterialApp(
        theme: fsLightTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                final result = await showOutcomeSheet(context, _pending);
                onResult?.call(result);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return posts;
}

Finder _pain(String level) => find.byKey(Key('outcome.pain.$level'));
Finder _region(int id) => find.byKey(Key('outcome.region.$id'));
final _submit = find.byKey(const Key('outcome.submit'));
const _question = 'How did your last workout leave you?';

bool _submitEnabled(WidgetTester tester) =>
    tester.widget<FsButton>(_submit).onPressed != null;

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('has the shared sheet header, and its Close shuts the sheet', (
    tester,
  ) async {
    await _open(tester);
    final header = find.byType(SheetHeader);
    expect(header, findsOneWidget);
    expect(
      find.descendant(
        of: header,
        matching: find.text('How did your last workout leave you?'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text(_question), findsNothing);
  });

  testWidgets('names the session it is asking about', (tester) async {
    await _open(tester);
    expect(find.text(_question), findsOneWidget);
    expect(find.textContaining('Upper Body · Push'), findsOneWidget);
  });

  test('a hand-picked session is named the way History names it', () {
    // History calls a session with no plan by the muscles it worked; the
    // pain question must not call the same workout "Your own workout".
    final pending = PendingOutcome.fromJson({
      'sessionId': 9,
      'sessionDate': '2026-09-21',
      'planName': null,
      'muscleGroups': ['pectorals', 'lats'],
    });
    expect(pending.title, 'Chest & Back workout');
    // A server that does not send them yet still gets a name.
    expect(
      PendingOutcome.fromJson({'sessionId': 9, 'sessionDate': '2026-09-21'})
          .title,
      'Your own workout',
    );
  });

  testWidgets('says the day in words, as History does', (tester) async {
    await _open(tester);
    expect(find.textContaining('2026-09-21'), findsNothing);
    // September 21, 2026 was a Monday.
    expect(find.textContaining('Mon, Sep 21'), findsOneWidget);
  });

  testWidgets('opens with nothing selected and nothing to submit', (
    tester,
  ) async {
    // A pre-selected "None" would manufacture negatives from anyone who
    // taps through -- the defect the label exists to avoid.
    await _open(tester);
    for (final level in painLevels) {
      expect(
        tester.widget<FsChip>(_pain(level)).selected,
        isFalse,
        reason: level,
      );
    }
    expect(_submitEnabled(tester), isFalse);
  });

  testWidgets('asks where only once there is pain', (tester) async {
    await _open(tester);
    expect(_region(13), findsNothing);

    await _tap(tester, _pain('none'));
    expect(_region(13), findsNothing);
    expect(_submitEnabled(tester), isTrue);

    await _tap(tester, _pain('mild'));
    expect(_region(13), findsOneWidget);
    expect(
      _submitEnabled(tester),
      isFalse,
      reason: 'pain without a region is not a complete answer',
    );

    await _tap(tester, _region(13));
    expect(_submitEnabled(tester), isTrue);
  });

  testWidgets('pain and region are each one choice for a screen reader', (
    tester,
  ) async {
    // Ruling M4: one answer per question, so TalkBack hears "radio button,
    // checked" as it does on the check-in sheet's same question.
    final handle = tester.ensureSemantics();
    await _open(tester);
    await _tap(tester, _pain('mild'));

    SemanticsData data(Finder f) => tester.getSemantics(f).getSemanticsData();
    final mild = data(_pain('mild'));
    expect(mild.flagsCollection.isInMutuallyExclusiveGroup, isTrue);
    expect(mild.flagsCollection.isChecked, CheckedState.isTrue);
    expect(mild.flagsCollection.isSelected, Tristate.none);
    expect(data(_pain('none')).flagsCollection.isChecked, CheckedState.isFalse);

    final knee = data(_region(13));
    expect(knee.flagsCollection.isInMutuallyExclusiveGroup, isTrue);
    expect(knee.flagsCollection.isChecked, CheckedState.isFalse);
    await _tap(tester, _region(13));
    expect(data(_region(13)).flagsCollection.isChecked, CheckedState.isTrue);
    handle.dispose();
  });

  // One row of chips is only as tall as a chip, so without room around the
  // row a chip answers its drawn ~32 dp pill and no more.
  testWidgets('the chips take a tap just above or below their pill', (
    tester,
  ) async {
    await _open(tester);

    await tester.ensureVisible(_pain('mild'));
    await tester.tapAt(
      tester.getRect(_pain('mild')).topCenter.translate(0, -7),
    );
    await tester.pumpAndSettle();
    expect(_region(13), findsOneWidget, reason: 'mild should be picked');

    await tester.ensureVisible(_region(13));
    await tester.tapAt(
      tester.getRect(_region(13)).bottomCenter.translate(0, 7),
    );
    await tester.pumpAndSettle();
    expect(_submitEnabled(tester), isTrue, reason: 'the region was picked');
  });

  testWidgets('going back to no pain clears the region', (tester) async {
    await _open(tester);
    await _tap(tester, _pain('moderate'));
    await _tap(tester, _region(1));
    await _tap(tester, _pain('none'));
    await _tap(tester, _pain('moderate'));

    expect(tester.widget<FsChip>(_region(1)).selected, isFalse);
    expect(_submitEnabled(tester), isFalse);
  });

  testWidgets('no pain posts without a region and closes', (tester) async {
    bool? result;
    final posts = await _open(tester, onResult: (r) => result = r);
    await _tap(tester, _pain('none'));
    await _tap(tester, _submit);

    expect(posts, [
      {'painLevel': 'none'},
    ]);
    expect(find.text(_question), findsNothing);
    expect(result, isFalse, reason: 'a successful save was not lost');
  });

  testWidgets('pain posts its region', (tester) async {
    final posts = await _open(tester);
    await _tap(tester, _pain('severe'));
    await _tap(tester, _region(13));
    await _tap(tester, _submit);

    expect(posts, [
      {'painLevel': 'severe', 'injuryId': 13},
    ]);
  });

  testWidgets('dismissing posts nothing', (tester) async {
    bool? result;
    final posts = await _open(tester, onResult: (r) => result = r);
    await _tap(tester, _pain('mild'));
    await _tap(tester, find.byKey(const Key('outcome.skip')));

    expect(posts, isEmpty);
    expect(find.text(_question), findsNothing);
    expect(result, isFalse, reason: 'nothing was submitted, so nothing failed');
  });

  testWidgets('an answer already stored counts as saved', (tester) async {
    bool? result;
    await _open(
      tester,
      status: 409,
      errorCode: 'OUTCOME_EXISTS',
      onResult: (r) => result = r,
    );
    await _tap(tester, _pain('none'));
    await _tap(tester, _submit);

    expect(find.text(_question), findsNothing);
    expect(
      result,
      isFalse,
      reason: 'a 409 means an earlier tap already saved it',
    );
  });

  testWidgets('a failed save closes the sheet and says so', (tester) async {
    bool? result;
    await _open(tester, status: 500, onResult: (r) => result = r);
    await _tap(tester, _pain('none'));
    await _tap(tester, _submit);

    expect(
      find.text(_question),
      findsNothing,
      reason: 'a failure must not stand between the user and training',
    );
    expect(result, isTrue, reason: 'the caller must be told the save failed');
  });

  testWidgets('a failed body-region load can be retried', (tester) async {
    await _open(tester, regionsFailures: 1);
    await _tap(tester, _pain('moderate'));

    expect(find.text("Couldn't load body regions."), findsOneWidget);
    expect(_region(13), findsNothing);
    // The kit's retry, in plain words, with "Try again" as the button.
    expect(find.byType(FsRetry), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('outcome.regions.retry')),
        matching: find.text('Try again'),
      ),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsNothing);

    await _tap(tester, find.byKey(const Key('outcome.regions.retry')));

    expect(_region(13), findsOneWidget);
  });
}
