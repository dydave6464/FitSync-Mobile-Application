import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/features/sessions/data/session_repository.dart';
import 'package:fitsync/features/sessions/domain/shared_report.dart';
import 'package:fitsync/features/sessions/presentation/providers.dart';
import 'package:fitsync/features/sessions/presentation/widgets/share_report_sheet.dart';

class _FakeRepo implements SessionRepository {
  _FakeRepo({this.error});

  final Object? error;
  Map<String, bool>? asked;

  @override
  Future<SharedReport> shareReport({
    required String period,
    required Map<String, bool> include,
  }) async {
    if (error != null) throw error!;
    asked = include;
    return SharedReport(
      url: 'https://fitsync.test/api/v1/reports/abc',
      expiresAt: DateTime.utc(2026, 10, 19),
    );
  }

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} is not used here');
}

Future<_FakeRepo> _open(WidgetTester tester, {Object? error}) async {
  final repo = _FakeRepo(error: error);
  await tester.pumpWidget(ProviderScope(
    overrides: [sessionRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp(
      theme: fsLightTheme(),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showShareReportSheet(context, period: 'week'),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  testWidgets('the sheet lists the sections that can be shared', (tester) async {
    await _open(tester);

    expect(find.text('Training volume'), findsOneWidget);
    expect(find.text('Body weight'), findsOneWidget);
    expect(find.text('Muscle balance'), findsOneWidget);
    expect(find.text('Recent sessions'), findsOneWidget);
  });

  // Muscle balance is the Pro section, and the sheet says so rather than
  // letting a free user wonder why it came back empty.
  testWidgets('the Pro section is marked', (tester) async {
    await _open(tester);

    expect(find.text('Pro'), findsOneWidget);
  });

  testWidgets('a section switched off is sent as false', (tester) async {
    // _create() copies the report's link to the clipboard on success, and
    // this SDK's flutter_test has no built-in clipboard mock -- without a
    // handler here, that platform call never replies and the sheet hangs in
    // its busy state forever, timing pumpAndSettle out below.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => null,
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    final repo = await _open(tester);

    await tester.tap(find.byKey(const Key('share.toggle.bodyWeight')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('share.create')));
    await tester.pumpAndSettle();

    expect(repo.asked!['bodyWeight'], isFalse);
    expect(repo.asked!['volume'], isTrue);
  });

  testWidgets('creating a report puts its link on the clipboard', (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await _open(tester);
    await tester.tap(find.byKey(const Key('share.create')));
    await tester.pumpAndSettle();

    expect(copied, ['https://fitsync.test/api/v1/reports/abc']);
  });

  // A share that failed must not look like one that worked -- the user would
  // send a coach a link they never got.
  testWidgets('a failed share says so and copies nothing', (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') copied.add('x');
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await _open(tester, error: Exception('offline'));
    await tester.tap(find.byKey(const Key('share.create')));
    await tester.pumpAndSettle();

    expect(copied, isEmpty);
    // describeError's fallback for a non-ApiException.
    expect(find.textContaining('Something went wrong'), findsOneWidget);
  });
}
