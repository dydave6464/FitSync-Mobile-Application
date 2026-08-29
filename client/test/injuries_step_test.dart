import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/onboarding/presentation/steps/injuries_step.dart';
import 'package:fitsync/features/profile/domain/profile.dart';
import 'package:fitsync/features/profile/presentation/providers.dart';

/// Region groups as the seed actually writes them: slugs, not display text.
/// The server returns them ordered by `region_group, name`, which is
/// alphabetical — back_core, lower_body, upper_body — so the display order the
/// design asks for has to be imposed by the step.
const _options = [
  InjuryOption(
      injuryId: 1, name: 'Shoulder', isLateral: true, regionGroup: 'upper_body'),
  InjuryOption(
      injuryId: 2, name: 'Elbow', isLateral: true, regionGroup: 'upper_body'),
  InjuryOption(
      injuryId: 7,
      name: 'Lower back',
      isLateral: false,
      regionGroup: 'back_core'),
  InjuryOption(
      injuryId: 13, name: 'Knee', isLateral: true, regionGroup: 'lower_body'),
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
  await tester.pumpWidget(ProviderScope(
    overrides: [
      injuryOptionsProvider.overrideWith((ref) async => options),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: _Host(initial: value, sink: sink),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return sink;
}

Future<void> _tapKey(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('groups the regions and orders the groups for reading',
      (tester) async {
    await _pump(tester);

    final upper = tester.getTopLeft(find.text('Upper body')).dy;
    final back = tester.getTopLeft(find.text('Back and core')).dy;
    final lower = tester.getTopLeft(find.text('Lower body')).dy;

    expect(upper, lessThan(back));
    expect(back, lessThan(lower));
  });

  testWidgets('a lateral region offers a side once selected', (tester) async {
    await _pump(tester);

    expect(find.byKey(const Key('side.1.left')), findsNothing,
        reason: 'the side control belongs to a selected region only');

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
    final emitted = await _pump(tester, value: const [SelectedInjury(injuryId: 1)]);

    await _tapKey(tester, const Key('side.1.both'));

    expect(emitted.last.single.injuryId, 1);
    expect(emitted.last.single.side, 'both');
  });

  testWidgets('deselecting a region drops it and its side', (tester) async {
    final emitted = await _pump(tester, value: const [
      SelectedInjury(injuryId: 1, side: 'left'),
      SelectedInjury(injuryId: 13, side: 'right'),
    ]);

    await _tapKey(tester, const Key('injury.1'));

    expect(emitted.last, hasLength(1));
    expect(emitted.last.single.injuryId, 13);
    expect(find.byKey(const Key('side.1.left')), findsNothing);
  });

  testWidgets('no injuries at all is a valid answer, not null', (tester) async {
    final emitted = await _pump(tester, value: const [SelectedInjury(injuryId: 1)]);

    await _tapKey(tester, const Key('injury.1'));

    // Having no injuries is the common case and must be expressible.
    expect(emitted.last, isNotNull);
    expect(emitted.last, isEmpty);
  });

  testWidgets('renders a region group it has never seen rather than dropping it',
      (tester) async {
    await _pump(tester, options: const [
      InjuryOption(
          injuryId: 99, name: 'Jaw', isLateral: false, regionGroup: 'other'),
    ]);

    expect(find.byKey(const Key('injury.99')), findsOneWidget);
  });

  testWidgets('says what actually happens to the answers', (tester) async {
    await _pump(tester);

    expect(find.textContaining('not a medical diagnosis'), findsOneWidget);
    // Injury-aware exercise filtering is Module 2. Promising it here would be
    // a claim the build cannot honour.
    expect(find.textContaining('safer variations'), findsNothing);
    expect(find.textContaining('avoid risky'), findsNothing);
  });
}
