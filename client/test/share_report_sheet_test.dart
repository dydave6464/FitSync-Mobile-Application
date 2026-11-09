import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';
import 'package:fitsync/features/sessions/data/session_repository.dart';
import 'package:fitsync/features/sessions/domain/shared_report.dart';
import 'package:fitsync/features/profile/domain/profile.dart';
import 'package:fitsync/features/profile/presentation/providers.dart';
import 'package:fitsync/features/sessions/presentation/providers.dart';
import 'package:fitsync/features/pro/presentation/pro_screen.dart';
import 'package:fitsync/features/pro/presentation/providers.dart';
import 'package:fitsync/features/sessions/presentation/widgets/share_report_sheet.dart';
import 'package:fitsync/features/profile/domain/body_weight.dart';
import 'package:fitsync/features/sessions/domain/session_history.dart';
import 'package:fitsync/features/sessions/domain/share_preview.dart';
import 'package:fitsync/features/sessions/domain/training_analytics.dart';
import 'package:fitsync/features/sessions/domain/volume_labels.dart';
import 'package:fitsync/features/sessions/presentation/share_actions.dart';

import 'helpers/fake_pro_repository.dart';
import 'helpers/sheet_insets.dart';

class _FakeRepo implements SessionRepository {
  _FakeRepo({this.error});

  final Object? error;
  Map<String, bool>? asked;
  int calls = 0;

  @override
  Future<SharedReport> shareReport({
    required String period,
    required Map<String, bool> include,
  }) async {
    calls++;
    if (error != null) throw error!;
    asked = include;
    return SharedReport(
      url: 'https://fitsync.test/api/v1/reports/abc',
      // A local DateTime, and midday rather than midnight: the sheet reads
      // the expiry in local time, so a UTC value here would name a different
      // calendar day depending on where the test ran.
      expiresAt: DateTime(2026, 10, 19, 12),
    );
  }

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} is not used here');
}

/// The sheet reads isPremium to decide whether the Pro section can be
/// switched on at all, so every test here has to say which kind of account
/// is looking at it.
class _StubProfileNotifier extends ProfileNotifier {
  _StubProfileNotifier({required this.premium});

  final bool premium;

  @override
  Future<Profile> build() async => Profile(
    userId: 7,
    email: 'juan@example.com',
    fullName: 'Juan Dela Cruz',
    onboardingCompleted: true,
    isPremium: premium,
    notificationsEnabled: true,
    equipment: const [],
    injuries: const [],
  );
}

/// Answers Clipboard.setData so a create can finish.
///
/// Without it the await in _create never returns, _busy stays true, and
/// FsButton's spinner animates forever -- which surfaces as pumpAndSettle
/// timing out rather than as anything to do with the clipboard.
void _stubClipboard(WidgetTester tester) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async => null,
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
}

/// Scrolls [finder] into view, then taps it. The sheet is taller than the
/// default 800x600 test surface now that it opens with the preview card, so
/// its buttons start below the fold, as they would on a short phone.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
}

class _FakeShare {
  final shared = <String>[];
  final opened = <Uri>[];
  bool menuOpens = true;

  ShareActions get actions => ShareActions(
    share: (text) async {
      shared.add(text);
      return menuOpens;
    },
    open: (url) async {
      opened.add(url);
      return true;
    },
  );
}

Future<(_FakeRepo, _FakeShare)> _open(
  WidgetTester tester, {
  Object? error,
  bool premium = true,
  bool menuOpens = true,
}) async {
  final repo = _FakeRepo(error: error);
  final share = _FakeShare()..menuOpens = menuOpens;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionRepositoryProvider.overrideWithValue(repo),
        proRepositoryProvider.overrideWithValue(FakeProRepository()),
        profileProvider.overrideWith(
          () => _StubProfileNotifier(premium: premium),
        ),
        shareActionsProvider.overrideWithValue(share.actions),
        trainingSummaryProvider.overrideWith(
          (ref) async => const TrainingSummary(
            sessionCount: 13,
            setCount: 75,
            totalVolumeKg: 31243.5,
          ),
        ),
        trainingAnalyticsProvider('week').overrideWith(
          (ref) async => const TrainingAnalytics(
            period: 'week',
            volume: [],
            change: VolumeChange(
              totalKg: 31243.5,
              previousKg: 25800,
              changePct: 21,
            ),
            adherence: Adherence(done: 13, target: 13, weeks: 1),
            muscles: [],
          ),
        ),
        bodyWeightProvider('week').overrideWith(
          (ref) async => const BodyWeightSeries(
            widened: false,
            points: [
              BodyWeightPoint(loggedOn: '2026-10-16', weightKg: 76.4),
              BodyWeightPoint(loggedOn: '2026-11-06', weightKg: 75.2),
            ],
            reference: null,
            unit: 'kg',
          ),
        ),
      ],
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
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return (repo, share);
}

void main() {
  // P-21: the × and the title sit at the one sheet inset every sheet uses.
  testWidgets('the header sits at the shared sheet inset', (tester) async {
    await _open(tester);
    expectSheetHeaderAtSideInset(tester, title: 'Share with coach');
  });

  testWidgets('has the shared sheet header, and its Close shuts the sheet', (
    tester,
  ) async {
    await _open(tester);
    final header = find.byType(FsSheetHeader);
    expect(header, findsOneWidget);
    expect(
      find.descendant(of: header, matching: find.text('Share with coach')),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('share.copy')), findsNothing);
  });

  testWidgets('names the period it shares in plain words', (tester) async {
    await _open(tester);

    expect(find.textContaining("this week's progress"), findsOneWidget);
    expect(find.textContaining('window'), findsNothing);
  });

  testWidgets('the sheet lists the sections that can be shared', (
    tester,
  ) async {
    await _open(tester);

    // Looked for inside each switch row: 'Body weight' is also the label of
    // a tile in the preview card above them.
    for (final (key, label) in const [
      ('volume', 'Training volume'),
      ('bodyWeight', 'Body weight'),
      ('muscles', 'Muscle balance'),
      ('sessions', 'Recent sessions'),
    ]) {
      expect(
        find.descendant(
          of: find.byKey(Key('share.toggle.$key')),
          matching: find.text(label),
        ),
        findsOneWidget,
        reason: label,
      );
    }
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
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    final (repo, _) = await _open(tester);

    await _tap(tester, find.byKey(const Key('share.toggle.bodyWeight')));
    await tester.pump();
    await _tap(tester, find.byKey(const Key('share.copy')));
    await tester.pumpAndSettle();

    expect(repo.asked!['bodyWeight'], isFalse);
    expect(repo.asked!['volume'], isTrue);
  });

  testWidgets('Copy link puts the link on the clipboard', (tester) async {
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
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await _open(tester);
    await _tap(tester, find.byKey(const Key('share.copy')));
    await tester.pumpAndSettle();

    expect(copied, ['https://fitsync.test/api/v1/reports/abc']);
    expect(find.text('Link copied.'), findsOneWidget);
  });

  // Built from the DateTime's fields rather than a formatting package, so it
  // is worth pinning the shape directly.
  test('the expiry is formatted as a plain date', () {
    expect(formatShareExpiry(DateTime(2026, 1, 5, 9)), 'January 5, 2026');
    expect(formatShareExpiry(DateTime(2026, 12, 31, 9)), 'December 31, 2026');
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
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await _open(tester, error: Exception('offline'));
    await _tap(tester, find.byKey(const Key('share.copy')));
    await tester.pumpAndSettle();

    expect(copied, isEmpty);
    // describeError's fallback for a non-ApiException.
    expect(find.textContaining('Something went wrong'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.textContaining('Something went wrong'),
        matching: find.byType(FsErrorLine),
      ),
      findsOneWidget,
    );
    final retry = tester.widget<FsButton>(find.byKey(const Key('share.share')));
    expect(retry.onPressed, isNotNull);
    expect(find.byKey(const Key('share.ready')), findsNothing);
  });

  testWidgets('the sheet paints its own surface', (tester) async {
    await _open(tester);

    // The rows are SwitchListTiles, which paint themselves on the nearest
    // Material ancestor: the surface has to be that Material's own colour,
    // not a box behind it. A transparent one leaves the toggles sitting on
    // the scrim with the screen showing through.
    final title = find.text('Share with coach');
    final t = tester.element(title).fs;
    final behind = tester.widget<Material>(
      find.ancestor(of: title, matching: find.byType(Material)).first,
    );

    expect(behind.color, t.surface);
  });

  testWidgets('the preview names the window and the page’s numbers', (
    tester,
  ) async {
    await _open(tester);

    final preview = find.byKey(const Key('share.preview'));
    expect(preview, findsOneWidget);
    expect(
      find.descendant(
        of: preview,
        // FsEyebrow draws its text in capitals, as the prototype's
        // eyebrows are.
        matching: find.text(
          'Week · ${shareWindowLabel('week', volumeToday())}'.toUpperCase(),
        ),
      ),
      findsOneWidget,
    );
    for (final text in [
      '31.2k kg',
      '+21% vs previous week',
      '13',
      'of 13 planned',
      '75',
      '−1.2 kg',
      '76.4 → 75.2',
    ]) {
      expect(
        find.descendant(of: preview, matching: find.text(text)),
        findsOneWidget,
        reason: text,
      );
    }
  });

  testWidgets('says the summary is always included', (tester) async {
    await _open(tester);
    expect(find.text('Summary is always included.'), findsOneWidget);
  });

  testWidgets('Share report makes one link and opens the share menu', (
    tester,
  ) async {
    final (repo, share) = await _open(tester);

    await _tap(tester, find.byKey(const Key('share.share')));
    await tester.pumpAndSettle();

    expect(repo.calls, 1);
    expect(share.shared, [
      'My FitSync training report, ${shareWindowLabel('week', volumeToday())}: '
          'https://fitsync.test/api/v1/reports/abc',
    ]);
    // The sheet stays open on Link ready.
    expect(find.text('Share with coach'), findsOneWidget);
    expect(find.byKey(const Key('share.ready')), findsOneWidget);
  });

  testWidgets('Link ready names the real expiry date', (tester) async {
    await _open(tester);
    await _tap(tester, find.byKey(const Key('share.share')));
    await tester.pumpAndSettle();

    expect(find.text('Works until October 19, 2026'), findsOneWidget);
    expect(find.textContaining('30 days'), findsNothing);
  });

  testWidgets('every action after the first reuses the same link', (
    tester,
  ) async {
    _stubClipboard(tester);
    final (repo, share) = await _open(tester);

    await _tap(tester, find.byKey(const Key('share.share')));
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const Key('share.copy')));
    await tester.pumpAndSettle();
    await _tap(tester, find.byKey(const Key('share.share')));
    await tester.pumpAndSettle();

    expect(repo.calls, 1);
    expect(share.shared.length, 2);
  });

  testWidgets('the switches lock once the link exists', (tester) async {
    await _open(tester);
    await _tap(tester, find.byKey(const Key('share.share')));
    await tester.pumpAndSettle();

    final toggle = tester.widget<SwitchListTile>(
      find.byKey(const Key('share.toggle.volume')),
    );
    expect(toggle.onChanged, isNull);
  });

  testWidgets('a share menu that cannot open copies the link instead', (
    tester,
  ) async {
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
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await _open(tester, menuOpens: false);
    await _tap(tester, find.byKey(const Key('share.share')));
    await tester.pumpAndSettle();

    expect(copied, ['https://fitsync.test/api/v1/reports/abc']);
    expect(
      find.text(
        "Couldn't open the share menu, so the link was copied instead.",
      ),
      findsOneWidget,
    );
  });

  testWidgets('See what your coach sees opens the page', (tester) async {
    final (_, share) = await _open(tester);
    await _tap(tester, find.byKey(const Key('share.share')));
    await tester.pumpAndSettle();

    await _tap(tester, find.byKey(const Key('share.open')));
    await tester.pumpAndSettle();

    expect(share.opened, [
      Uri.parse('https://fitsync.test/api/v1/reports/abc'),
    ]);
  });

  group('the Pro section on a free account', () {
    testWidgets('is locked rather than switched on', (tester) async {
      await _open(tester, premium: false);

      // The badge stays -- it is what says the feature exists, the same
      // reason VolumeByMuscleCard keeps its own in every state.
      expect(find.text('Pro'), findsOneWidget);
      expect(find.byKey(const Key('share.locked.muscles')), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);

      // No switch to turn on: a togglable row that the server will not honour
      // is worse than no row.
      expect(find.byKey(const Key('share.toggle.muscles')), findsNothing);
    });

    testWidgets('is a way through to Pro', (tester) async {
      await _open(tester, premium: false);

      await _tap(tester, find.byKey(const Key('share.locked.muscles')));
      await tester.pumpAndSettle();

      // The sheet is the moment a user is thinking about what their coach
      // will see, which makes it the best moment to learn Pro adds something.
      expect(find.byType(ProScreen), findsOneWidget);
    });

    testWidgets('is not sent with the report', (tester) async {
      _stubClipboard(tester);
      final (repo, _) = await _open(tester, premium: false);

      await _tap(tester, find.byKey(const Key('share.copy')));
      await tester.pumpAndSettle();

      // buildReportSnapshot answers null for muscles without Pro however it
      // is asked, so sending true would promise the coach a section the
      // report cannot contain.
      expect(repo.asked!['muscles'], isFalse);
      expect(repo.asked!['volume'], isTrue);
    });
  });

  testWidgets('a Pro account still gets the switch', (tester) async {
    await _open(tester);

    expect(find.byKey(const Key('share.toggle.muscles')), findsOneWidget);
    expect(find.byKey(const Key('share.locked.muscles')), findsNothing);
    // Selling Pro to someone who already has it is the worse mistake of the
    // two, as the progress card's own comment puts it.
    expect(find.byIcon(Icons.lock_outline), findsNothing);
  });

  // 'Muscle balance' plus the Pro tag needs about 270 dp at 2.0x, and the
  // label was not allowed to wrap, so the coach-report options overflowed
  // at the largest text sizes (SE-12).
  group('fits a small phone at 2.0x text', () {
    for (final size in const [Size(360, 640), Size(320, 568)]) {
      for (final premium in [true, false]) {
        testWidgets(
          '${size.width.toInt()} dp, ${premium ? 'Pro' : 'free'} account',
          (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1.0;
            tester.platformDispatcher.textScaleFactorTestValue = 2.0;
            addTearDown(tester.view.reset);
            addTearDown(
              tester.platformDispatcher.clearTextScaleFactorTestValue,
            );

            await _open(tester, premium: premium);

            expect(tester.takeException(), isNull);
            expect(find.text('Muscle balance'), findsOneWidget);
            await tester.ensureVisible(find.byKey(const Key('share.share')));
            await _tap(tester, find.byKey(const Key('share.share')));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await tester.ensureVisible(find.byKey(const Key('share.open')));
            expect(find.byKey(const Key('share.open')), findsOneWidget);
          },
        );
      }
    }
  });
}
