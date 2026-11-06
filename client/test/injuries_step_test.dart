import 'dart:ui' show CheckedState;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/api_exception.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';
import 'package:fitsync/features/onboarding/presentation/steps/injuries_step.dart';
import 'package:fitsync/features/profile/domain/profile.dart';
import 'package:fitsync/features/profile/presentation/providers.dart';

/// Region groups as the seed actually writes them: slugs, not display text.
/// The server returns them ordered by `region_group, name`, which is
/// alphabetical — back_core, lower_body, upper_body — so the display order the
/// design asks for has to be imposed by the step.
const _options = [
  InjuryOption(
    injuryId: 1,
    name: 'Shoulder',
    isLateral: true,
    regionGroup: 'upper_body',
  ),
  InjuryOption(
    injuryId: 2,
    name: 'Elbow',
    isLateral: true,
    regionGroup: 'upper_body',
  ),
  InjuryOption(
    injuryId: 7,
    name: 'Lower back',
    isLateral: false,
    regionGroup: 'back_core',
  ),
  InjuryOption(
    injuryId: 13,
    name: 'Knee',
    isLateral: true,
    regionGroup: 'lower_body',
  ),
];

/// The step is a controlled widget: it reports a new value and renders
/// whatever it is given back. This stands in for the owner that closes that
/// loop, so a selection actually appears on screen.
class _Host extends StatefulWidget {
  const _Host({required this.initial, required this.sink});

  final List<SelectedInjury> initial;
  final List<List<SelectedInjury>> sink;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late List<SelectedInjury> _value = widget.initial;

  @override
  Widget build(BuildContext context) => InjuriesStep(
    value: _value,
    onChanged: (next) {
      widget.sink.add(next);
      setState(() => _value = next);
    },
  );
}

/// Returns the list of every value the step emitted, newest last.
Future<List<List<SelectedInjury>>> _pump(
  WidgetTester tester, {
  List<SelectedInjury> value = const [],
  List<InjuryOption> options = _options,
}) async {
  final sink = <List<SelectedInjury>>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [injuryOptionsProvider.overrideWith((ref) async => options)],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: _Host(initial: value, sink: sink),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return sink;
}

Future<void> _tapKey(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

/// The semantics a single-choice chip reports (P-1a): one of a group where
/// picking one unpicks the rest, checked or not checked.
SemanticsData _chipData(WidgetTester tester, Key key) => tester
    .getSemantics(
      find.descendant(of: find.byKey(key), matching: find.byType(Text)),
    )
    .getSemanticsData();

void main() {
  testWidgets('groups the regions and orders the groups for reading', (
    tester,
  ) async {
    await _pump(tester);

    // Group headings render through the eyebrow style, which uppercases.
    final upper = tester.getTopLeft(find.text('UPPER BODY')).dy;
    final back = tester.getTopLeft(find.text('BACK AND CORE')).dy;
    final lower = tester.getTopLeft(find.text('LOWER BODY')).dy;

    expect(upper, lessThan(back));
    expect(back, lessThan(lower));
  });

  testWidgets('a lateral region offers a side once selected', (tester) async {
    await _pump(tester);

    expect(
      find.byKey(const Key('side.1.left')),
      findsNothing,
      reason: 'the side control belongs to a selected region only',
    );

    await _tapKey(tester, const Key('injury.1'));

    expect(find.byKey(const Key('side.1.left')), findsOneWidget);
    expect(find.byKey(const Key('side.1.right')), findsOneWidget);
    expect(find.byKey(const Key('side.1.both')), findsOneWidget);
  });

  testWidgets('a non-lateral region never offers a side', (tester) async {
    await _pump(tester);

    await _tapKey(tester, const Key('injury.7'));

    // The server rejects a side on a non-lateral injury with a 400, so a UI
    // that offers one produces an error the user cannot act on.
    expect(find.byKey(const Key('side.7.left')), findsNothing);
    expect(find.byKey(const Key('side.7.right')), findsNothing);
    expect(find.byKey(const Key('side.7.both')), findsNothing);
  });

  testWidgets('a non-lateral selection emits a null side', (tester) async {
    final emitted = await _pump(tester);

    await _tapKey(tester, const Key('injury.7'));

    expect(emitted.last.single.injuryId, 7);
    expect(emitted.last.single.side, isNull);
  });

  testWidgets('choosing a side emits it', (tester) async {
    final emitted = await _pump(
      tester,
      value: const [SelectedInjury(injuryId: 1)],
    );

    await _tapKey(tester, const Key('side.1.both'));

    expect(emitted.last.single.injuryId, 1);
    expect(emitted.last.single.side, 'both');
  });

  testWidgets('deselecting a region drops it and its side', (tester) async {
    final emitted = await _pump(
      tester,
      value: const [
        SelectedInjury(injuryId: 1, side: 'left'),
        SelectedInjury(injuryId: 13, side: 'right'),
      ],
    );

    await _tapKey(tester, const Key('injury.1'));

    expect(emitted.last, hasLength(1));
    expect(emitted.last.single.injuryId, 13);
    expect(find.byKey(const Key('side.1.left')), findsNothing);
  });

  testWidgets('no injuries at all is a valid answer, not null', (tester) async {
    final emitted = await _pump(
      tester,
      value: const [SelectedInjury(injuryId: 1)],
    );

    await _tapKey(tester, const Key('injury.1'));

    // Having no injuries is the common case and must be expressible.
    expect(emitted.last, isNotNull);
    expect(emitted.last, isEmpty);
  });

  testWidgets(
    'renders a region group it has never seen rather than dropping it',
    (tester) async {
      await _pump(
        tester,
        options: const [
          InjuryOption(
            injuryId: 99,
            name: 'Jaw',
            isLateral: false,
            regionGroup: 'other',
          ),
        ],
      );

      expect(find.byKey(const Key('injury.99')), findsOneWidget);
    },
  );

  testWidgets('says what actually happens to the answers', (tester) async {
    await _pump(tester);

    expect(find.textContaining('not a medical diagnosis'), findsOneWidget);
    // Injury-aware exercise filtering is Module 2. Promising it here would be
    // a claim the build cannot honour.
    expect(find.textContaining('safer variations'), findsNothing);
    expect(find.textContaining('avoid risky'), findsNothing);
  });

  testWidgets('a region tells a screen reader whether it is picked', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);

    final shoulder = find.byKey(const Key('injury.1'));
    expect(
      tester.getSemantics(shoulder),
      isSemantics(
        label: 'Shoulder',
        isButton: true,
        hasTapAction: true,
        hasSelectedState: true,
        isSelected: false,
      ),
    );

    await _tapKey(tester, const Key('injury.1'));
    expect(
      tester.getSemantics(shoulder),
      isSemantics(
        label: 'Shoulder',
        isButton: true,
        hasSelectedState: true,
        isSelected: true,
      ),
    );
    handle.dispose();
  });

  // The tappable row was only as tall as its name, about 20dp, inside the
  // card's padding. The row now reaches the card's edges.
  testWidgets('a region takes a 48dp tap across its card', (tester) async {
    final emitted = await _pump(tester);

    final row = tester.getRect(find.byKey(const Key('injury.7')));
    expect(row.height, greaterThanOrEqualTo(48));

    // The card's own corner, outside the name, still picks the region.
    await tester.tapAt(row.topLeft + const Offset(2, 2));
    await tester.pumpAndSettle();
    expect(emitted.last.single.injuryId, 7);
  });

  testWidgets('fits a 320dp phone at 2x text with a side picked', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          injuryOptionsProvider.overrideWith((ref) async => _options),
        ],
        child: MaterialApp(
          home: MediaQuery.withClampedTextScaling(
            minScaleFactor: 2,
            maxScaleFactor: 2,
            child: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _Host(
                  initial: const [SelectedInjury(injuryId: 1, side: 'left')],
                  sink: [],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('side.1.both')), findsOneWidget);
  });

  // The side chips are 32 dp and the last line of their card: 8 dp of the
  // card's padding below them is theirs to take.
  testWidgets('a side chip takes a tap just below its pill', (tester) async {
    final sink = await _pump(tester);
    await _tapKey(tester, const Key('injury.1'));

    final chip = find.byKey(const Key('side.1.left'));
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getRect(chip).bottomCenter.translate(0, 7));
    await tester.pumpAndSettle();

    expect(sink.last.single.side, 'left');
  });

  group('the side chips', () {
    testWidgets('take a tap just above their pill', (tester) async {
      final sink = await _pump(tester);
      await _tapKey(tester, const Key('injury.1'));

      final chip = find.byKey(const Key('side.1.right'));
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.tapAt(tester.getRect(chip).topCenter.translate(0, -7));
      await tester.pumpAndSettle();

      expect(sink.last.single.side, 'right');
    });

    testWidgets('sit 8 dp apart', (tester) async {
      await _pump(tester);
      await _tapKey(tester, const Key('injury.1'));

      final left = tester.getRect(find.byKey(const Key('side.1.left')));
      final right = tester.getRect(find.byKey(const Key('side.1.right')));
      final both = tester.getRect(find.byKey(const Key('side.1.both')));
      expect(right.left - left.right, greaterThanOrEqualTo(8));
      expect(both.left - right.right, greaterThanOrEqualTo(8));
    });
    // No androidTapTargetGuideline check here: it passed with the chips'
    // band at 37 dp. The tap-just-above and tap-just-below tests are the
    // ones that fail when the band shrinks.
  });

  testWidgets('a failed lookup says why and offers Try again', (tester) async {
    // The lookup stays down until the user asks again: a garbled reply is
    // retried twice on its own first (apiRetryPolicy), so failing only the
    // first call would never reach the error state.
    var calls = 0;
    var down = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          injuryOptionsProvider.overrideWith((ref) async {
            calls++;
            if (down) {
              throw const ApiException('INVALID_RESPONSE', 'HTTP 502 <html>');
            }
            return _options;
          }),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: _Host(initial: const [], sink: []),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FsRetry), findsOneWidget);
    expect(
      find.text(userMessage(const ApiException('INVALID_RESPONSE', ''))),
      findsOneWidget,
    );
    expect(calls, 3, reason: 'the first try and two automatic retries');
    down = false;
    await _tapKey(tester, const Key('injuries.retry'));

    expect(calls, 4);
    expect(find.byType(FsRetry), findsNothing);
  });

  // P-1a: an injury has one side, so its side chips are a radio group.
  testWidgets('the side chips are one single choice', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      value: const [SelectedInjury(injuryId: 1, side: 'left')],
    );

    for (final side in ['left', 'right', 'both']) {
      final data = _chipData(tester, Key('side.1.$side'));
      expect(data.flagsCollection.isInMutuallyExclusiveGroup, isTrue);
      expect(
        data.flagsCollection.isChecked,
        side == 'left' ? CheckedState.isTrue : CheckedState.isFalse,
      );
    }
    handle.dispose();
  });
}
