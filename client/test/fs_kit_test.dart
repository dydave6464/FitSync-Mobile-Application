import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/core/theme.dart';
import 'package:fitsync/core/units.dart';
import 'package:fitsync/core/widgets/fs_kit.dart';

import 'helpers/a11y.dart';

Widget _host(Widget child) => MaterialApp(
  theme: fsLightTheme(),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('a selected chip shows a check when asked', (tester) async {
    await tester.pumpWidget(
      _host(
        FsChip(label: 'Bench', selected: true, showCheck: true, onTap: () {}),
      ),
    );
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('an unselected chip shows no check', (tester) async {
    await tester.pumpWidget(
      _host(
        FsChip(label: 'Bench', selected: false, showCheck: true, onTap: () {}),
      ),
    );
    expect(find.byIcon(Icons.check), findsNothing);
  });

  testWidgets('a chip without showCheck never shows one', (tester) async {
    await tester.pumpWidget(
      _host(FsChip(label: 'Home gym', selected: true, onTap: () {})),
    );
    expect(
      find.byIcon(Icons.check),
      findsNothing,
      reason: 'the location chips keep the plain treatment',
    );
  });

  testWidgets('ticking a chip does not change its width', (tester) async {
    // The check slot is reserved whenever showCheck is set, so selecting a
    // chip repaints it without resizing it. Building the icon on selection
    // alone widened the chip by 18px mid-layout, which reflowed the
    // enclosing Wrap and pushed neighbouring chips onto another line.
    Future<double> widthWhen(bool selected) async {
      await tester.pumpWidget(
        _host(
          FsChip(
            label: 'Pull-up bar',
            selected: selected,
            showCheck: true,
            onTap: _noop,
          ),
        ),
      );
      return tester.getSize(find.byType(FsChip)).width;
    }

    expect(await widthWhen(true), await widthWhen(false));
  });

  testWidgets('a chip without showCheck reserves no check slot', (
    tester,
  ) async {
    // The reserved slot must not leak onto the location chips, which would
    // gain 18px of dead space for a check they never render.
    await tester.pumpWidget(
      _host(const FsChip(label: 'Home gym', selected: false, onTap: _noop)),
    );
    final plain = tester.getSize(find.byType(FsChip)).width;

    await tester.pumpWidget(
      _host(
        const FsChip(
          label: 'Home gym',
          selected: false,
          showCheck: true,
          onTap: _noop,
        ),
      ),
    );
    final reserved = tester.getSize(find.byType(FsChip)).width;

    expect(plain, lessThan(reserved));
  });

  testWidgets('FsTag renders its text', (tester) async {
    await tester.pumpWidget(_host(const FsTag('4 selected')));
    expect(find.text('4 selected'), findsOneWidget);
  });

  testWidgets(
    'a chip with a long label wraps instead of overflowing on a narrow '
    'surface at a large text scale',
    (tester) async {
      // Reproduces the FsChip regression directly: the label sits inside a
      // Row (added for the optional check icon), and RenderFlex gives
      // non-flex children unbounded main-axis constraints, so the Text can no
      // longer soft-wrap to the Wrap's bounded width. 320dp mirrors a small
      // phone; 2.0x mirrors Android 14's maximum text scale.
      await tester.pumpWidget(
        _host(
          MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 800),
              textScaler: TextScaler.linear(2.0),
            ),
            child: const SizedBox(
              width: 320,
              child: Wrap(
                children: [
                  FsChip(
                    label: 'Adjustable resistance bands and ankle weights',
                    selected: true,
                    showCheck: true,
                    onTap: _noop,
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'the same long-label chip still hugs its content at normal text scale',
    (tester) async {
      // Guards the fix in the other direction: Flexible must not make the
      // chip stretch to fill the Wrap's width when nothing forces wrapping.
      await tester.pumpWidget(
        _host(
          const SizedBox(
            width: 320,
            child: Wrap(
              children: [FsChip(label: 'Bench', selected: false, onTap: _noop)],
            ),
          ),
        ),
      );

      final chipWidth = tester.getSize(find.byType(FsChip)).width;
      expect(
        chipWidth,
        lessThan(100),
        reason: 'a short label must not stretch to the Wrap width',
      );
    },
  );

  testWidgets('FsNav reports the tapped index and marks the current one', (
    tester,
  ) async {
    final taps = <int>[];
    await tester.pumpWidget(
      _host(
        FsNav(
          currentIndex: 0,
          onSelect: taps.add,
          items: const [
            FsNavItem(icon: Icons.home_outlined, label: 'Home'),
            FsNavItem(icon: Icons.fitness_center_outlined, label: 'Train'),
          ],
        ),
      ),
    );

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Train'), findsOneWidget);

    await tester.tap(find.text('Train'));
    await tester.pump();
    await tester.tap(find.text('Home'));
    await tester.pump();
    expect(taps, [
      1,
      0,
    ], reason: 'the bar reports each tap with its correct index');
  });

  testWidgets('the current tab reads in the text green', (tester) async {
    // A 10 px label in the brand green was 2.87:1 on the light bar.
    await tester.pumpWidget(
      _host(
        FsNav(
          currentIndex: 0,
          onSelect: (_) {},
          items: const [
            FsNavItem(icon: Icons.home_outlined, label: 'Home'),
            FsNavItem(icon: Icons.fitness_center_outlined, label: 'Train'),
          ],
        ),
      ),
    );

    final t = FsTokens.light;
    expect(tester.widget<Text>(find.text('Home')).style?.color, t.accentText);
    expect(
      tester.widget<Icon>(find.byIcon(Icons.home_outlined)).color,
      t.accentText,
    );
    expect(tester.widget<Text>(find.text('Train')).style?.color, t.text3);
  });

  testWidgets('FsNav does not overflow on narrow screens at 2.0x text scale', (
    tester,
  ) async {
    // Nav bar items have unguarded text that could wrap and overflow the
    // fixed 58px height at accessibility text scales. Constrain with
    // maxLines: 1 and overflow: TextOverflow.ellipsis.
    // 320dp mirrors a small phone; 2.0x mirrors Android 14's maximum text scale.
    await tester.pumpWidget(
      _host(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 800),
            textScaler: TextScaler.linear(2.0),
          ),
          child: FsNav(
            currentIndex: 0,
            onSelect: (_) {},
            items: const [
              FsNavItem(icon: Icons.home_outlined, label: 'Home'),
              FsNavItem(
                icon: Icons.fitness_center_outlined,
                label: 'Adjustable resistance training',
              ),
              FsNavItem(icon: Icons.settings_outlined, label: 'Settings'),
              FsNavItem(icon: Icons.person_outlined, label: 'Profile'),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'FsButton does not overflow on narrow screens at 2.0x text scale',
    (tester) async {
      // The label sits inside a Row alongside the optional icon, and RenderFlex
      // gives non-flex children unbounded main-axis constraints, so the label
      // could not soft-wrap or shrink to the button's bounded width — the same
      // failure mode already fixed for FsChip and FsNav. 290dp mirrors the
      // width left inside a card on a 320dp phone after its padding; 2.0x
      // mirrors Android 14's maximum text scale.
      await tester.pumpWidget(
        _host(
          MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 800),
              textScaler: TextScaler.linear(2.0),
            ),
            child: SizedBox(
              width: 290,
              child: FsButton(
                label: 'Start workout',
                small: true,
                icon: const Icon(Icons.play_arrow),
                onPressed: _noop,
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('FsButton keeps room around its label at its natural width', (
    tester,
  ) async {
    // Every use so far has been full width, where Center hid the fact that
    // there is no horizontal padding at all. Given intrinsic width -- beside
    // a block of text in a Row -- it shrink-wraps to the bare label and the
    // pill radius cuts into the word.
    await tester.pumpWidget(
      MaterialApp(
        theme: fsLightTheme(),
        home: Scaffold(
          body: Row(
            children: [
              const Expanded(child: Text('some explanatory copy')),
              FsButton(label: 'Add', small: true, onPressed: () {}),
            ],
          ),
        ),
      ),
    );

    final button = tester.getSize(find.byType(FsButton));
    final label = tester.getSize(find.text('Add'));
    expect(
      button.width - label.width,
      greaterThanOrEqualTo(24),
      reason: 'the label must not run to the edge of the pill',
    );
  });

  group('FsButton.wrapLabel', () {
    Future<void> pumpNarrow(
      WidgetTester tester, {
      required String label,
      required bool wrap,
    }) => tester.pumpWidget(
      _host(
        SizedBox(
          width: 160,
          child: FsButton(label: label, wrapLabel: wrap, onPressed: () {}),
        ),
      ),
    );

    testWidgets('a label too long for one line wraps, and the button grows', (
      tester,
    ) async {
      await pumpNarrow(tester, label: 'Discard it & start new', wrap: true);

      expect(tester.takeException(), isNull);
      expect(
        tester
            .renderObject<RenderParagraph>(find.text('Discard it & start new'))
            .didExceedMaxLines,
        isFalse,
        reason: 'read whole, not cut to an ellipsis',
      );
      expect(tester.getSize(find.byType(FsButton)).height, greaterThan(52));
    });

    testWidgets('a label that fits keeps the usual 52 dp', (tester) async {
      await pumpNarrow(tester, label: 'Cancel', wrap: true);

      expect(tester.getSize(find.byType(FsButton)).height, 52);
    });

    testWidgets('without it a long label stays on one 52 dp line', (
      tester,
    ) async {
      await pumpNarrow(tester, label: 'Discard it & start new', wrap: false);

      expect(tester.getSize(find.byType(FsButton)).height, 52);
    });
  });

  testWidgets('FsField is single line unless told otherwise', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: fsLightTheme(),
        home: Scaffold(
          body: FsField(controller: controller, hint: 'Name'),
        ),
      ),
    );

    expect(tester.widget<TextField>(find.byType(TextField)).maxLines, 1);
  });

  testWidgets('FsField renders a trailing widget inside the box', (
    tester,
  ) async {
    // suffixText holds a unit ('kg', 'cm') and nothing else -- it cannot be
    // tapped. A field with a clear or reveal affordance needs a real widget
    // inside the same border, not a second control alongside it.
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var taps = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: fsLightTheme(),
        home: Scaffold(
          body: FsField(
            controller: controller,
            hint: 'Search',
            trailing: IconButton(
              key: const Key('field.trailing'),
              icon: const Icon(Icons.close),
              onPressed: () => taps += 1,
            ),
          ),
        ),
      ),
    );

    final trailing = find.byKey(const Key('field.trailing'));
    expect(trailing, findsOneWidget);
    expect(
      find.ancestor(of: trailing, matching: find.byType(TextField)),
      findsOneWidget,
      reason: 'the affordance belongs inside the field, not beside it',
    );

    await tester.tap(trailing);
    expect(taps, 1);
  });

  testWidgets('FsField grows to the line count it is given', (tester) async {
    // A sentence typed into a one-line field scrolls sideways, which hides
    // the beginning of what the user wrote.
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: fsLightTheme(),
        home: Scaffold(
          body: FsField(controller: controller, hint: 'Describe', maxLines: 3),
        ),
      ),
    );

    expect(tester.widget<TextField>(find.byType(TextField)).maxLines, 3);
  });

  testWidgets('a segmented control marks only the chosen segment', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const FsSegmented(
          options: [
            (value: 'male', label: 'Male'),
            (value: 'female', label: 'Female'),
          ],
          selected: 'female',
          onSelected: _noopString,
        ),
      ),
    );

    // The fill is the whole affordance — there is no tick and no radio — so
    // reading it back off the painted decoration is the only honest check
    // that the right half is on.
    final t = fsLightTheme().extension<FsTokens>()!;
    Color fillOf(String label) {
      final box = tester.widget<DecoratedBox>(
        find
            .ancestor(of: find.text(label), matching: find.byType(DecoratedBox))
            .first,
      );
      return (box.decoration as BoxDecoration).color!;
    }

    expect(fillOf('Female'), t.accent);
    expect(fillOf('Male'), isNot(t.accent));
  });

  testWidgets('tapping a segment reports its value, not its label', (
    tester,
  ) async {
    final picked = <String>[];
    await tester.pumpWidget(
      _host(
        FsSegmented(
          options: const [
            (value: 'beginner', label: 'Beginner'),
            (value: 'intermediate', label: 'Intermediate'),
          ],
          selected: 'beginner',
          onSelected: picked.add,
        ),
      ),
    );

    await tester.tap(find.text('Intermediate'));

    expect(picked, [
      'intermediate',
    ], reason: 'the label is display text; the enum value is what is stored');
  });

  testWidgets('a segmented control with nothing selected still renders', (
    tester,
  ) async {
    // Profiles saved before an option was withdrawn — sex 'prefer_not_to_say'
    // — arrive here matching no segment at all, and must not blank the
    // control or throw.
    await tester.pumpWidget(
      _host(
        const FsSegmented(
          options: [
            (value: 'male', label: 'Male'),
            (value: 'female', label: 'Female'),
          ],
          selected: 'prefer_not_to_say',
          onSelected: _noopString,
        ),
      ),
    );

    expect(find.text('Male'), findsOneWidget);
    expect(find.text('Female'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a stat field refuses a fourth digit', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(
        FsStatField(
          fieldKey: const Key('heightCm'),
          label: 'Height',
          unit: 'cm',
          controller: controller,
        ),
      ),
    );
    final field = find.byKey(const Key('heightCm'));

    await tester.enterText(field, '175');
    expect(controller.text, '175');

    // No height, weight or goal weight is four digits. Refusing the keystroke
    // is quieter than accepting 1750 and failing validation later.
    await tester.enterText(field, '1750');
    expect(controller.text, '175');
  });

  testWidgets('a stat field still takes one decimal place', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(
        FsStatField(
          fieldKey: const Key('weightKg'),
          label: 'Weight',
          unit: 'kg',
          controller: controller,
        ),
      ),
    );
    final field = find.byKey(const Key('weightKg'));

    // Half a kilogram is a real measurement; the digit cap is about absurd
    // values, not about precision.
    await tester.enterText(field, '72.5');
    expect(controller.text, '72.5');

    await tester.enterText(field, '72.55');
    expect(controller.text, '72.5', reason: 'one decimal place is enough');
  });

  testWidgets('a stat field types into the big number', (tester) async {
    final controller = TextEditingController(text: '175');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _host(
        FsStatField(
          fieldKey: const Key('heightCm'),
          label: 'Height',
          unit: 'cm',
          controller: controller,
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('heightCm')), '182');

    expect(
      controller.text,
      '182',
      reason: 'the number in the card is the input, not a rendering of one',
    );
    expect(find.text('cm'), findsOneWidget);
    expect(
      find.text('HEIGHT'),
      findsOneWidget,
      reason: 'the design labels these in the eyebrow treatment',
    );
  });

  testWidgets('FsField passes input formatters and autofill hints through', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FsField(
            fieldKey: const Key('f'),
            controller: controller,
            hint: 'h',
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            autofillHints: const [AutofillHints.oneTimeCode],
          ),
        ),
      ),
    );

    final field = tester.widget<TextField>(find.byKey(const Key('f')));
    expect(field.inputFormatters, hasLength(1));
    expect(field.autofillHints, [AutofillHints.oneTimeCode]);

    await tester.enterText(find.byKey(const Key('f')), 'a1b2');
    expect(controller.text, '12');
  });

  // Screen readers can only say "selected", "disabled" or "button" when the
  // kit puts those flags on the node; the visuals alone say nothing to them.
  group('semantics', () {
    testWidgets('a chip is a button that says whether it is selected', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(FsChip(label: 'Bench', selected: true, onTap: _noop)),
      );
      expect(
        tester.getSemantics(find.byType(FsChip)),
        matchesSemantics(
          label: 'Bench',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasSelectedState: true,
          isSelected: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );

      await tester.pumpWidget(
        _host(FsChip(label: 'Bench', selected: false, onTap: _noop)),
      );
      expect(
        tester.getSemantics(find.byType(FsChip)),
        isSemantics(label: 'Bench', isButton: true, isSelected: false),
      );
      handle.dispose();
    });

    testWidgets('a chip without onTap is announced as disabled', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(const FsChip(label: 'Bench', selected: false, onTap: null)),
      );
      expect(
        tester.getSemantics(find.byType(FsChip)),
        matchesSemantics(
          label: 'Bench',
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
          hasSelectedState: true,
          isSelected: false,
        ),
      );
      handle.dispose();
    });

    testWidgets('each segment is a button with its selected state', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 300,
            child: FsSegmented(
              options: const [
                (value: 'male', label: 'Male'),
                (value: 'female', label: 'Female'),
              ],
              selected: 'female',
              onSelected: _noopString,
            ),
          ),
        ),
      );
      expect(
        tester.getSemantics(find.byKey(const Key('segment.female'))),
        isSemantics(
          label: 'Female',
          hint: '2 of 2',
          isButton: true,
          isEnabled: true,
          hasEnabledState: true,
          isSelected: true,
          hasSelectedState: true,
          isInMutuallyExclusiveGroup: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(find.byKey(const Key('segment.male'))),
        isSemantics(
          label: 'Male',
          hint: '1 of 2',
          isButton: true,
          isSelected: false,
          hasSelectedState: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('a tappable card is a button; a plain one is not', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(const FsCard(onTap: _noop, child: Text('Lose fat'))),
      );
      expect(
        tester.getSemantics(find.byType(FsCard)),
        isSemantics(
          label: 'Lose fat',
          isButton: true,
          hasTapAction: true,
          hasSelectedState: false,
        ),
      );

      await tester.pumpWidget(_host(const FsCard(child: Text('Summary'))));
      expect(
        tester.getSemantics(find.text('Summary')),
        isSemantics(label: 'Summary', isButton: false),
      );
      handle.dispose();
    });

    testWidgets('a card given a selected state exposes it', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          const FsCard(
            onTap: _noop,
            accent: true,
            selected: true,
            child: Text('Lose fat'),
          ),
        ),
      );
      expect(
        tester.getSemantics(find.byType(FsCard)),
        isSemantics(
          label: 'Lose fat',
          isButton: true,
          hasSelectedState: true,
          isSelected: true,
        ),
      );
      handle.dispose();
    });

    testWidgets(
      'a button is announced as one, and disabled without onPressed',
      (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          _host(const FsButton(label: 'Continue', onPressed: _noop)),
        );
        expect(
          tester.getSemantics(find.byType(FsButton)),
          isSemantics(
            label: 'Continue',
            isButton: true,
            hasEnabledState: true,
            isEnabled: true,
            hasTapAction: true,
          ),
        );

        await tester.pumpWidget(
          _host(const FsButton(label: 'Continue', onPressed: null)),
        );
        expect(
          tester.getSemantics(find.byType(FsButton)),
          isSemantics(
            label: 'Continue',
            isButton: true,
            hasEnabledState: true,
            isEnabled: false,
          ),
        );
        handle.dispose();
      },
    );

    testWidgets('a busy button keeps its label and says it is loading', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(const FsButton(label: 'Save', onPressed: _noop, busy: true)),
      );
      expect(
        tester.getSemantics(find.byType(FsButton)),
        isSemantics(
          label: 'Save, loading',
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
        ),
      );
      handle.dispose();
    });
  });

  // A thumb needs 48 dp; the chips and the kg/lb switch are drawn smaller
  // than that, and every row of them is laid out around the drawn size. So
  // the target grows and the drawing does not.
  group('tap targets', () {
    /// [child] with room all round, as a chip in a column of content has,
    /// so a tap just off it lands inside the column.
    Widget roomy(Widget child) => _host(
      SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 40),
            child,
            const SizedBox(height: 40),
          ],
        ),
      ),
    );

    testWidgets('a chip answers a tap just off its pill', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        roomy(FsChip(label: 'Bench', selected: false, onTap: () => taps++)),
      );

      final pill = tester.getRect(find.byType(FsChip));
      final slack = (48 - pill.height) / 2;
      await tester.tapAt(pill.topCenter - Offset(0, slack - 1));
      await tester.tapAt(pill.bottomCenter + Offset(0, slack - 1));
      expect(taps, 2);

      // Past the 48 dp band is past the chip.
      await tester.tapAt(pill.topCenter - Offset(0, slack + 2));
      expect(taps, 2);
    });

    testWidgets('a short chip is a full 48 dp wide to a thumb', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        roomy(
          FsChip(
            label: 'No',
            selected: false,
            small: true,
            onTap: () => taps++,
          ),
        ),
      );

      final pill = tester.getRect(find.byType(FsChip));
      expect(pill.width, lessThan(48), reason: 'the case being guarded');
      await tester.tapAt(
        pill.centerLeft - Offset((48 - pill.width) / 2 - 1, 0),
      );
      expect(taps, 1);
    });

    testWidgets('a chip is drawn and laid out at the same size as before', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const FsChip(label: 'Bench', selected: false, onTap: _noop)),
      );

      // About 30 dp: the band is not layout, or every Wrap of chips would
      // spread apart.
      expect(tester.getSize(find.byType(FsChip)).height, lessThan(40));
    });

    testWidgets('a screen reader frames the chip at 48 dp too', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          const FsChip(label: 'No', selected: false, small: true, onTap: _noop),
        ),
      );

      final rect = tester.getSemantics(find.byType(FsChip)).rect;
      expect(rect.height, greaterThanOrEqualTo(48));
      expect(rect.width, greaterThanOrEqualTo(48));
      handle.dispose();
    });

    testWidgets('kg and lb each answer a tap off their letters', (
      tester,
    ) async {
      final picked = <WeightUnit>[];
      await tester.pumpWidget(
        roomy(FsUnitToggle(value: WeightUnit.kg, onChanged: picked.add)),
      );

      final lb = tester.getRect(find.byKey(const Key('unit.lb')));
      expect(lb.height, lessThan(48), reason: 'the case being guarded');
      await tester.tapAt(lb.topCenter - Offset(0, (48 - lb.height) / 2 - 1));
      // Out past the end of the word, away from kg.
      await tester.tapAt(lb.centerRight + const Offset(10, 0));
      expect(picked, [WeightUnit.lb, WeightUnit.lb]);
    });

    testWidgets("a tap on kg's own letters never reaches lb", (tester) async {
      final picked = <WeightUnit>[];
      await tester.pumpWidget(
        roomy(FsUnitToggle(value: WeightUnit.lb, onChanged: picked.add)),
      );

      // Each unit's band grows away from the other, so the two never
      // overlap: the right-hand edge of KG is still KG.
      final kg = tester.getRect(find.byKey(const Key('unit.kg')));
      await tester.tapAt(kg.centerRight - const Offset(1, 0));
      await tester.tapAt(kg.centerLeft - const Offset(10, 0));
      expect(picked, [WeightUnit.kg, WeightUnit.kg]);
    });

    // A one-row Wrap, or a Row, is exactly as tall as its chips, and a chip
    // can only answer a tap that reaches it through that box. FsTapRoom is
    // what lets a row take the taps just outside it.
    testWidgets('a chip in a one-row Wrap answers 7 dp off its pill', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        roomy(
          FsTapRoom(
            child: Wrap(
              children: [
                FsChip(label: 'Bench', selected: false, onTap: () => taps++),
              ],
            ),
          ),
        ),
      );

      final pill = tester.getRect(find.byType(FsChip));
      await tester.tapAt(pill.topCenter - const Offset(0, 7));
      await tester.tapAt(pill.bottomCenter + const Offset(0, 7));
      expect(taps, 2);

      // Its reach is a band, not the rest of the column.
      await tester.tapAt(pill.topCenter - const Offset(0, 14));
      expect(taps, 2);
    });

    // A parent asks its last child first, so in a Wrap the lower chip's
    // band would win anywhere the two bands overlap, including the bottom
    // of the chip drawn above it. A shared gap splits at its middle instead.
    testWidgets('two rows of small chips each keep their own pill', (
      tester,
    ) async {
      final picked = <String>[];
      // The test font sets a chip taller than the app's own does; half-size
      // text brings it to the app's 26 dp, where the bands overlap.
      await tester.pumpWidget(
        roomy(
          MediaQuery.withClampedTextScaling(
            maxScaleFactor: 0.5,
            child: SizedBox(
              width: 90,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final name in ['Lose fat', 'Build muscle'])
                    FsChip(
                      label: name,
                      selected: false,
                      small: true,
                      onTap: () => picked.add(name),
                    ),
                ],
              ),
            ),
          ),
        ),
      );

      final upper = tester.getRect(find.widgetWithText(FsChip, 'Lose fat'));
      final lower = tester.getRect(find.widgetWithText(FsChip, 'Build muscle'));
      expect(lower.top, greaterThan(upper.bottom), reason: 'two rows');
      expect(
        (48 - lower.height) / 2,
        greaterThan(lower.top - upper.bottom),
        reason: 'the case being guarded: the lower band reaches the upper pill',
      );

      await tester.tapAt(upper.bottomCenter - const Offset(0, 2));
      await tester.tapAt(upper.bottomCenter + const Offset(0, 2));
      await tester.tapAt(Offset(upper.center.dx, lower.top - 2));
      expect(picked, ['Lose fat', 'Lose fat', 'Build muscle']);
    });

    testWidgets('kg and lb in a row answer 7 dp above and below it', (
      tester,
    ) async {
      final picked = <WeightUnit>[];
      await tester.pumpWidget(
        roomy(
          FsTapRoom(
            child: Row(
              children: [
                const Expanded(child: Text('Weight unit')),
                FsUnitToggle(value: WeightUnit.kg, onChanged: picked.add),
              ],
            ),
          ),
        ),
      );

      final row = tester.getRect(find.byType(Row).first);
      final lb = tester.getRect(find.byKey(const Key('unit.lb')));
      await tester.tapAt(Offset(lb.center.dx, row.top - 7));
      await tester.tapAt(Offset(lb.center.dx, row.bottom + 7));
      expect(picked, [WeightUnit.lb, WeightUnit.lb]);
    });

    // In a stat card the switch sits 4 dp after the number, and a Row asks
    // its last child first: a band grown evenly would take the field's
    // right-hand end, so a tap meant for the number flipped the unit.
    testWidgets(
      "the unit switch in a stat card leaves the number's taps alone",
      (tester) async {
        final picked = <WeightUnit>[];
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          _host(
            SizedBox(
              width: 140,
              child: FsStatField(
                fieldKey: const Key('weightKg'),
                label: 'Weight',
                unit: 'lb',
                controller: controller,
                unitControl: FsUnitToggle(
                  value: WeightUnit.lb,
                  onChanged: picked.add,
                ),
              ),
            ),
          ),
        );

        final field = tester.getRect(find.byKey(const Key('weightKg')));
        await tester.tapAt(field.centerRight - const Offset(5, 0));
        await tester.pump();
        expect(picked, isEmpty, reason: 'the tap was the number');
        expect(
          tester
              .widget<EditableText>(find.byType(EditableText))
              .focusNode
              .hasFocus,
          isTrue,
        );

        // The switch still takes a tap a little above the row, over the
        // label.
        final row = tester.getRect(find.byType(Row).first);
        final kg = tester.getRect(find.byKey(const Key('unit.kg')));
        await tester.tapAt(Offset(kg.center.dx, row.top - 6));
        expect(picked, [WeightUnit.kg]);
      },
    );

    // lb is the row's last child, so the half of its band past the letters
    // lies outside the Row; the room for it is the card's own padding.
    testWidgets('lb in a stat card takes a tap in the padding past it', (
      tester,
    ) async {
      final picked = <WeightUnit>[];
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 140,
            child: FsStatField(
              fieldKey: const Key('weightKg'),
              label: 'Weight',
              unit: 'kg',
              controller: controller,
              unitControl: FsUnitToggle(
                value: WeightUnit.kg,
                onChanged: picked.add,
              ),
            ),
          ),
        ),
      );

      final lb = tester.getRect(find.byKey(const Key('unit.lb')));
      await tester.tapAt(lb.centerRight + const Offset(8, 0));
      expect(picked, [WeightUnit.lb]);

      // The card's edge is still the end of it.
      await tester.tapAt(lb.centerRight + const Offset(20, 0));
      expect(picked, [WeightUnit.lb]);
    });

    // The switch is drawn about 19 dp tall in a row the number sets. The
    // label above takes no taps and the card leaves a little padding below,
    // and both are the switch's to use: 48 dp from top to bottom.
    testWidgets('the unit switch in a stat card answers across 48 dp', (
      tester,
    ) async {
      final picked = <WeightUnit>[];
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 140,
            child: FsStatField(
              fieldKey: const Key('weightKg'),
              label: 'Weight',
              unit: 'lb',
              controller: controller,
              unitControl: FsUnitToggle(
                value: WeightUnit.lb,
                onChanged: picked.add,
              ),
            ),
          ),
        ),
      );

      // Not centred on the pill, which sits on the number's baseline low in
      // the row: what matters is how tall a strip of taps finds it.
      final kg = tester.getRect(find.byKey(const Key('unit.kg')));
      final answered = <double>[];
      for (var dy = -40.0; dy <= 40; dy += 0.5) {
        final before = picked.length;
        await tester.tapAt(Offset(kg.center.dx, kg.center.dy + dy));
        if (picked.length > before) answered.add(dy);
      }
      expect(answered.last - answered.first, greaterThanOrEqualTo(48));
      // One strip, no holes in it.
      expect(answered.length, (answered.last - answered.first) / 0.5 + 1);
    });

    // A tap inside the room's own box that nothing took was tested again at
    // the same point, so a see-through listener on the way was added to the
    // hit path twice and the pointer router refused the second.
    testWidgets('FsTapRoom tests a point inside its own box only once', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        roomy(
          FsTapRoom(
            child: Row(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () => taps++,
                  child: const SizedBox(width: 60, height: 32),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.byType(GestureDetector).last);
      expect(tester.takeException(), isNull);
      expect(taps, 1);
    });

    testWidgets('FsTapRoom reaches past its far end only as far as told', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        roomy(
          // The room past the row is this padding's, as in a card.
          Padding(
            padding: const EdgeInsets.only(right: 24),
            child: FsTapRoom(
              reach: 0,
              endReach: 16,
              child: Row(
                children: [
                  const Expanded(child: SizedBox(height: 20)),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => taps++,
                    child: const SizedBox(width: 20, height: 20),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      final row = tester.getRect(find.byType(Row));
      await tester.tapAt(row.centerRight + const Offset(15, 0));
      expect(taps, 1);
      await tester.tapAt(row.centerRight + const Offset(18, 0));
      expect(taps, 1);
    });

    // The neighbour that wins a point must also reach it: an upper chip
    // nearer by box, but whose band ends short, left the tap with nobody.
    testWidgets('a tap in a gap no upper band reaches goes to the chip below', (
      tester,
    ) async {
      final picked = <String>[];
      await tester.pumpWidget(
        roomy(
          SizedBox(
            width: 260,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final name in ['Squat', 'Bench', 'Romanian deadlift'])
                  FsChip(
                    label: name,
                    selected: false,
                    onTap: () => picked.add(name),
                  ),
              ],
            ),
          ),
        ),
      );

      final left = tester.getRect(find.widgetWithText(FsChip, 'Squat'));
      final right = tester.getRect(find.widgetWithText(FsChip, 'Bench'));
      final lower = tester.getRect(
        find.widgetWithText(FsChip, 'Romanian deadlift'),
      );
      expect(right.top, left.top, reason: 'Squat and Bench share a row');
      expect(lower.top, greaterThan(left.bottom), reason: 'two rows');
      expect(lower.height, lessThan(40), reason: 'one line, with a band');
      expect(left.width, greaterThan(48), reason: 'no band past its ends');
      final gapX = (left.right + right.left) / 2;
      expect(lower.left, lessThan(gapX), reason: 'the lower chip spans it');

      // In the gap between the upper chips, just below them.
      await tester.tapAt(Offset(gapX, left.bottom + 1));
      expect(picked, ['Romanian deadlift']);
    });

    testWidgets('a screen reader hears which unit is in force', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(FsUnitToggle(value: WeightUnit.kg, onChanged: (_) {})),
      );

      final kg = tester.getSemantics(find.byKey(const Key('unit.kg')));
      expect(kg, isSemantics(label: 'KG', isSelected: true));
      expect(kg.rect.height, greaterThanOrEqualTo(48));
      expect(
        tester.getSemantics(find.byKey(const Key('unit.lb'))),
        isSemantics(label: 'LB', isSelected: false, isButton: true),
      );
      handle.dispose();
    });
  });

  group('48 dp targets and spoken names', () {
    // The pill a small button draws, as opposed to the 48 dp box it lays out.
    Rect smallPill(WidgetTester tester, [Finder? button]) => tester.getRect(
      find.descendant(
        of: button ?? find.byType(FsButton),
        matching: find.byType(InkWell),
      ),
    );

    testWidgets('a small FsButton answers taps across 48 dp', (tester) async {
      final h = tester.ensureSemantics();
      var taps = 0;
      // A width short of the screen's, or the guideline skips the node as
      // touching the view's edge: a button in a Center fills the width. No
      // room is given around it: the 48 dp is the button's own.
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 200,
            child: FsButton(
              label: 'Retry',
              small: true,
              onPressed: () => taps++,
            ),
          ),
        ),
      );
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      final pill = smallPill(tester);
      expect(pill.height, 42, reason: 'the pill is drawn as before');
      expect(tester.getSize(find.byType(FsButton)).height, 48);
      // Just above and just below the 42 dp pill.
      await tester.tapAt(Offset(pill.center.dx, pill.top - 2));
      await tester.tapAt(Offset(pill.center.dx, pill.bottom + 2));
      expect(taps, 2);
      h.dispose();
    });

    testWidgets('a small FsButton that ends a card answers the full 48 dp', (
      tester,
    ) async {
      // Home's "Start workout" and the shell's Retry: the button is the last
      // child of a Column inside the card's padding, so the Column's bottom
      // edge is flush with the button. Room outside the Column never reaches
      // the button, so the 48 dp has to be inside it.
      final h = tester.ensureSemantics();
      var taps = 0;
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 240,
            child: FsCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Push day'),
                  const SizedBox(height: 14),
                  FsButton(
                    label: 'Start workout',
                    small: true,
                    onPressed: () => taps++,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      final pill = smallPill(tester);
      await tester.tapAt(Offset(pill.center.dx, pill.bottom + 2));
      expect(taps, 1, reason: 'just below the pill, at the Column\'s end');
      await tester.tapAt(Offset(pill.center.dx, pill.top - 2));
      expect(taps, 2, reason: 'just above the pill');
      // What a screen reader frames is what a thumb can hit.
      final node = tester.getSemantics(find.text('Start workout'));
      expect(node.rect.height, 48);
      expect(node.label, 'Start workout');
      h.dispose();
    });

    testWidgets('small FsButtons in a Wrap answer above and below the pill', (
      tester,
    ) async {
      // Home's "Turn on" / "Not now" and "Continue": each button fills its
      // own run of the Wrap, so a run's edge is flush with the pill.
      var turnOn = 0, notNow = 0;
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 240,
            child: FsCard(
              child: Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  FsButton(
                    key: const Key('on'),
                    label: 'Turn on',
                    small: true,
                    onPressed: () => turnOn++,
                  ),
                  FsButton(
                    key: const Key('off'),
                    label: 'Not now',
                    small: true,
                    kind: FsButtonKind.secondary,
                    onPressed: () => notNow++,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      final on = smallPill(tester, find.byKey(const Key('on')));
      final off = smallPill(tester, find.byKey(const Key('off')));
      await tester.tapAt(Offset(on.center.dx, on.top - 2));
      await tester.tapAt(Offset(on.center.dx, on.bottom + 2));
      await tester.tapAt(Offset(off.center.dx, off.top - 2));
      await tester.tapAt(Offset(off.center.dx, off.bottom + 2));
      expect((turnOn, notNow), (2, 2));
    });

    testWidgets('a small FsButton in a Row as tall as itself still gets 48', (
      tester,
    ) async {
      // Recovery's "Check in": the Row is as tall as the button.
      var taps = 0;
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 300,
            child: Row(
              children: [
                const Expanded(child: Text('How do you feel?')),
                FsButton(
                  label: 'Check in',
                  small: true,
                  onPressed: () => taps++,
                ),
              ],
            ),
          ),
        ),
      );
      final pill = smallPill(tester);
      await tester.tapAt(Offset(pill.center.dx, pill.top - 2));
      await tester.tapAt(Offset(pill.center.dx, pill.bottom + 2));
      expect(taps, 2);
    });

    testWidgets('the bottom-bar fab has a name and a tooltip', (tester) async {
      final h = tester.ensureSemantics();
      // Four tabs, as the shell has: the fab sits before the third, so a
      // shorter bar never draws it.
      await tester.pumpWidget(
        host(
          FsNav(
            currentIndex: 0,
            onSelect: (_) {},
            onFabTap: () {},
            items: const [
              FsNavItem(
                icon: Icons.home_outlined,
                activeIcon: Icons.home,
                label: 'Home',
              ),
              FsNavItem(
                icon: Icons.fitness_center_outlined,
                activeIcon: Icons.fitness_center,
                label: 'Train',
              ),
              FsNavItem(
                icon: Icons.restaurant_outlined,
                activeIcon: Icons.restaurant,
                label: 'Nutrition',
              ),
              FsNavItem(
                icon: Icons.person_outline,
                activeIcon: Icons.person,
                label: 'Profile',
              ),
            ],
          ),
        ),
      );
      expect(find.byKey(const Key('nav.fab')), findsOneWidget);
      expect(find.bySemanticsLabel('Start a workout'), findsOneWidget);
      expect(find.byTooltip('Start a workout'), findsOneWidget);
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      h.dispose();
    });

    testWidgets(
      'the current tab is selected in semantics and shows its filled icon',
      (tester) async {
        final h = tester.ensureSemantics();
        await tester.pumpWidget(
          host(
            FsNav(
              currentIndex: 1,
              onSelect: (_) {},
              items: const [
                FsNavItem(
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home,
                  label: 'Home',
                ),
                FsNavItem(
                  icon: Icons.person_outline,
                  activeIcon: Icons.person,
                  label: 'Profile',
                ),
              ],
            ),
          ),
        );
        expect(
          tester.getSemantics(find.text('Profile')),
          matchesSemantics(
            isButton: true,
            isSelected: true,
            hasSelectedState: true,
            isInMutuallyExclusiveGroup: true,
            hasTapAction: true,
            hasFocusAction: true,
            isFocusable: true,
            isEnabled: true,
            hasEnabledState: true,
            label: 'Profile',
            hint: 'Tab 2 of 2',
          ),
        );
        expect(
          tester.getSemantics(find.text('Home')),
          isSemantics(isSelected: false, hint: 'Tab 1 of 2'),
        );
        expect(find.byIcon(Icons.person), findsOneWidget);
        expect(find.byIcon(Icons.home_outlined), findsOneWidget);
        h.dispose();
      },
    );

    testWidgets('FsSegmented segments answer at least 48 dp and are equal', (
      tester,
    ) async {
      final h = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 340,
            child: FsSegmented(
              options: const [
                (value: 'a', label: '15 min'),
                (value: 'b', label: '1 hour before the session'),
              ],
              selected: 'a',
              onSelected: (_) {},
            ),
          ),
          textScale: 1.6,
        ),
      );
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      expect(tester.takeException(), isNull);
      final a = tester.getSize(find.byKey(const Key('segment.a')));
      final b = tester.getSize(find.byKey(const Key('segment.b')));
      expect(a.height, b.height, reason: 'segments share one height');
      // What a screen reader frames, and a thumb can hit, is 48 dp even
      // where the pill is drawn shorter.
      for (final value in ['a', 'b']) {
        final node = tester.getSemantics(find.byKey(Key('segment.$value')));
        expect(node.rect.height, greaterThanOrEqualTo(48));
      }
      h.dispose();
    });

    // `.seg > div { padding: 8px 0 }` in the prototype's styles.css: one line
    // of 12.5 text with 8 above and below it, in a track 4 bigger all round.
    testWidgets('FsSegmented draws its track and pill at the prototype size', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 300,
            child: FsSegmented(
              options: const [
                (value: 'male', label: 'Male'),
                (value: 'female', label: 'Female'),
              ],
              selected: 'female',
              onSelected: (_) {},
            ),
          ),
        ),
      );
      final line = tester.getSize(find.text('Female')).height;
      final pill = tester.getSize(
        find
            .ancestor(
              of: find.text('Female'),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      final track = tester.getSize(
        find
            .descendant(
              of: find.byType(FsSegmented),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(pill.height, line + 16, reason: 'the selected pill, as drawn');
      expect(pill.height, lessThan(48));
      expect(track.height, pill.height + 8);
      // The room for a thumb is laid out around the track, not drawn.
      expect(tester.getSize(find.byType(FsSegmented)).height, 48);
    });

    testWidgets('FsSegmented that ends a Column answers taps across 48 dp', (
      tester,
    ) async {
      // The sex and experience pickers: the control is the last child of a
      // Column, flush with its bottom edge. Room outside the Column never
      // reaches it, so the 48 dp has to be inside the control's own box.
      final h = tester.ensureSemantics();
      final picked = <String>[];
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 300,
            child: Column(
              key: const Key('column'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Sex'),
                FsSegmented(
                  options: const [
                    (value: 'male', label: 'Male'),
                    (value: 'female', label: 'Female'),
                  ],
                  selected: 'male',
                  onSelected: picked.add,
                ),
              ],
            ),
          ),
        ),
      );
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      final column = tester.getRect(find.byKey(const Key('column')));
      final pill = tester.getRect(find.byKey(const Key('segment.female')));
      final track = tester.getRect(
        find
            .descendant(
              of: find.byType(FsSegmented),
              matching: find.byType(Material),
            )
            .first,
      );
      final x = pill.center.dx;
      await tester.tapAt(Offset(x, column.bottom - 0.5));
      expect(picked, ['female'], reason: 'the Column\'s last dp');
      await tester.tapAt(Offset(x, pill.bottom + 2));
      expect(picked, hasLength(2), reason: 'the track, just under the pill');
      await tester.tapAt(Offset(x, track.top - 1));
      expect(picked, hasLength(3), reason: 'just above the drawn track');
      expect(picked.toSet(), {'female'});
      final node = tester.getSemantics(find.byKey(const Key('segment.female')));
      expect(node.rect.height, 48);
      expect(node.label, 'Female');
      h.dispose();
    });

    testWidgets('an action chip reports no selected state', (tester) async {
      final h = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          FsChip(label: 'Add', selected: false, toggle: false, onTap: () {}),
        ),
      );
      final data = tester.getSemantics(find.text('Add')).getSemanticsData();
      expect(data.flagsCollection.isSelected, Tristate.none);
      expect(data.flagsCollection.isButton, isTrue);
      h.dispose();
    });

    testWidgets('a toggle chip still reports its selected state', (
      tester,
    ) async {
      final h = tester.ensureSemantics();
      await tester.pumpWidget(
        host(FsChip(label: 'Bench', selected: false, onTap: () {})),
      );
      final data = tester.getSemantics(find.text('Bench')).getSemanticsData();
      expect(data.flagsCollection.isSelected, Tristate.isFalse);
      h.dispose();
    });
  });

  // A placeholder vanishes once the user types, and a label beside the field
  // is a separate node: the field itself has to carry its name.
  group('field labels', () {
    testWidgets('FsStatField is announced by its label and unit', (
      tester,
    ) async {
      final h = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          FsStatField(
            label: 'Height',
            unit: 'cm',
            controller: TextEditingController(),
          ),
        ),
      );
      // The name and unit sit on the editable node itself, not on whatever
      // node happens to lie above the TextField.
      final node = tester.getSemantics(find.byType(TextField));
      expect(node, isSemantics(isTextField: true, hint: 'cm'));
      expect(node.label, startsWith('Height'));
      // Said once: the visible eyebrow (drawn as 'HEIGHT') and the unit text
      // are not separate stops repeating what the field already says.
      expect(
        find.bySemanticsLabel(RegExp('^height', caseSensitive: false)),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('HEIGHT'), findsNothing);
      expect(find.bySemanticsLabel('cm'), findsNothing);
      h.dispose();
    });

    testWidgets('FsField with a label names its field and shows the label', (
      tester,
    ) async {
      final h = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          FsField(
            label: 'Habit name',
            hint: 'e.g. Stretch',
            controller: TextEditingController(text: 'Walk'),
          ),
        ),
      );
      // Drawn in the eyebrow treatment, which sets its text in capitals.
      expect(find.text('HABIT NAME'), findsOneWidget);
      expect(
        tester.getSemantics(find.byType(TextField)),
        isSemantics(isTextField: true, label: 'Habit name', value: 'Walk'),
      );
      // The visible eyebrow is not a second stop saying the name again.
      expect(find.bySemanticsLabel('HABIT NAME'), findsNothing);
      h.dispose();
    });

    testWidgets('FsLabeledField names its field and says its messages', (
      tester,
    ) async {
      final h = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          FsLabeledField(
            label: 'Password',
            helper: 'At least 8 characters',
            error: 'Too short',
            field: FsField(controller: TextEditingController(), hint: ''),
          ),
        ),
      );
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('At least 8 characters'), findsOneWidget);
      expect(find.text('Too short'), findsOneWidget);
      final data = tester
          .getSemantics(find.byType(TextField))
          .getSemanticsData();
      expect(data.label, contains('Password'));
      expect(data.hint, contains('Too short. At least 8 characters'));
      // Said once, on the field: not again as separate lines of text.
      expect(find.bySemanticsLabel('Too short'), findsNothing);
      expect(find.bySemanticsLabel('At least 8 characters'), findsNothing);
      h.dispose();
    });
  });

  group('readable controls', () {
    for (final dark in [false, true]) {
      testWidgets('an unselected radio ring takes the control outline '
          '(${dark ? 'dark' : 'light'})', (tester) async {
        await tester.pumpWidget(
          host(const FsRadioDot(selected: false), dark: dark),
        );
        final box = tester.widget<Container>(
          find.descendant(
            of: find.byType(FsRadioDot),
            matching: find.byType(Container),
          ),
        );
        final border = (box.decoration! as BoxDecoration).border! as Border;
        final t = dark ? FsTokens.dark : FsTokens.light;
        expect(border.top.color, t.control);
      });
    }

    testWidgets('FsRing reads as one labelled node', (tester) async {
      final h = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          const FsRing(
            semanticLabel: '1,160 of 2,050 kcal eaten',
            child: Text('1,160'),
          ),
        ),
      );
      expect(
        find.bySemanticsLabel('1,160 of 2,050 kcal eaten'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('1,160'), findsNothing);
      h.dispose();
    });
  });

  group('FsErrorLine', () {
    testWidgets('FsErrorLine is a live region', (tester) async {
      final h = tester.ensureSemantics();
      await tester.pumpWidget(host(const FsErrorLine('Wrong code')));
      expect(
        tester
            .getSemantics(find.text('Wrong code'))
            .getSemanticsData()
            .flagsCollection
            .isLiveRegion,
        isTrue,
      );
      h.dispose();
    });

    for (final dark in [false, true]) {
      testWidgets('reads in red with a red icon (${dark ? 'dark' : 'light'})', (
        tester,
      ) async {
        await tester.pumpWidget(
          host(const FsErrorLine('Wrong code'), dark: dark),
        );
        final t = dark ? FsTokens.dark : FsTokens.light;
        expect(
          tester.widget<Text>(find.text('Wrong code')).style?.color,
          t.red,
        );
        expect(
          tester.widget<Icon>(find.byIcon(Icons.error_outline)).color,
          t.red,
        );
        expect(contrast(t.red, t.bg), greaterThanOrEqualTo(4.5));
      });
    }

    testWidgets('keeps a caller key, so a screen can find it', (tester) async {
      await tester.pumpWidget(
        host(const FsErrorLine('Wrong code', key: Key('error'))),
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('error')),
          matching: find.text('Wrong code'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('wraps at large text on a small screen', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        host(
          const FsErrorLine(
            "Couldn't reach FitSync. Check your connection and try again.",
          ),
          textScale: 2.0,
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('FsRetry', () {
    testWidgets('FsRetry calls back and meets tap-target size', (tester) async {
      final h = tester.ensureSemantics();
      var n = 0;
      await tester.pumpWidget(
        host(FsRetry(message: "Couldn't load.", onRetry: () => n++)),
      );
      await tester.tap(find.text('Try again'));
      expect(n, 1);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      h.dispose();
    });

    testWidgets('shows the message over a small secondary Try again', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          FsRetry(
            message: "Couldn't load.",
            onRetry: () {},
            buttonKey: const Key('retry'),
          ),
        ),
      );
      final button = tester.widget<FsButton>(find.byKey(const Key('retry')));
      expect(button.label, 'Try again');
      expect(button.small, isTrue);
      expect(button.kind, FsButtonKind.secondary);
      expect(
        tester.getRect(find.text("Couldn't load.")).bottom,
        lessThanOrEqualTo(tester.getRect(find.byKey(const Key('retry'))).top),
      );
    });

    testWidgets('puts a secondary action below Try again', (tester) async {
      await tester.pumpWidget(
        host(
          FsRetry(
            message: "Couldn't load.",
            onRetry: () {},
            buttonKey: const Key('retry'),
            secondary: const Text('Sign out'),
          ),
        ),
      );
      expect(
        tester.getRect(find.text('Sign out')).top,
        greaterThanOrEqualTo(
          tester.getRect(find.byKey(const Key('retry'))).bottom,
        ),
      );
    });

    testWidgets('full screen sits inside the safe area, centred', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: fsLightTheme(),
          home: Scaffold(
            body: FsRetry(
              message: "Couldn't load.",
              onRetry: () {},
              fullScreen: true,
            ),
          ),
        ),
      );
      expect(
        find.ancestor(
          of: find.text("Couldn't load."),
          matching: find.byType(SafeArea),
        ),
        findsOneWidget,
      );
      final message = tester.getRect(find.text("Couldn't load."));
      expect(message.center.dx, closeTo(180, 1));
      expect(message.top, greaterThan(200));
    });

    testWidgets('full screen scrolls rather than overflows at large text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
          child: MaterialApp(
            theme: fsLightTheme(),
            home: Scaffold(
              body: FsRetry(
                message:
                    "Couldn't reach FitSync. Check your connection and try "
                        'again. ' *
                    4,
                onRetry: () {},
                fullScreen: true,
                secondary: const Text('Sign out'),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('confirmDiscard', () {
    /// Opens the dialog from a button and records its answer in [answers].
    Future<void> pumpAsker(
      WidgetTester tester,
      List<bool> answers, {
      String? message,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: fsLightTheme(),
          home: Builder(
            builder: (c) => TextButton(
              onPressed: () async =>
                  answers.add(await confirmDiscard(c, message: message)),
              child: const Text('ask'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('ask'));
      await tester.pumpAndSettle();
    }

    testWidgets('Keep editing answers false and Discard true', (tester) async {
      final answers = <bool>[];
      await pumpAsker(tester, answers);
      expect(find.text('Discard your changes?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.text('Discard your changes?'), findsNothing);

      await tester.tap(find.text('ask'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(answers, [false, true]);
    });

    testWidgets('a dismissed dialog keeps the edits', (tester) async {
      final answers = <bool>[];
      await pumpAsker(tester, answers);
      await tester.tapAt(const Offset(5, 5)); // the barrier
      await tester.pumpAndSettle();
      expect(answers, [false]);
    });

    testWidgets('Discard is drawn in red', (tester) async {
      await pumpAsker(tester, []);
      const t = FsTokens.light;
      final style = tester
          .widget<TextButton>(
            find.ancestor(
              of: find.text('Discard'),
              matching: find.byType(TextButton),
            ),
          )
          .style!;
      expect(style.foregroundColor!.resolve({}), t.red);
    });

    testWidgets('can say why discarding matters here', (tester) async {
      await pumpAsker(tester, [], message: 'The photo still counts today.');
      expect(find.text('The photo still counts today.'), findsOneWidget);
    });
  });

  group('FsDiscardGuard', () {
    Future<void> pumpGuard(WidgetTester tester, {required bool dirty}) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: fsLightTheme(),
          home: Builder(
            builder: (c) => TextButton(
              onPressed: () => Navigator.of(c).push(
                MaterialPageRoute<void>(
                  builder: (_) => FsDiscardGuard(
                    dirty: dirty,
                    message: 'Nothing here is saved yet.',
                    child: const Scaffold(body: Text('form')),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('a clean screen pops straight away', (tester) async {
      await pumpGuard(tester, dirty: false);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Discard your changes?'), findsNothing);
      expect(find.text('form'), findsNothing);
    });

    testWidgets('a dirty screen asks, in its own words, then obeys', (
      tester,
    ) async {
      await pumpGuard(tester, dirty: true);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Discard your changes?'), findsOneWidget);
      expect(find.text('Nothing here is saved yet.'), findsOneWidget);

      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.text('form'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.text('form'), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });
  });
}

void _noop() {}

void _noopString(String _) {}
