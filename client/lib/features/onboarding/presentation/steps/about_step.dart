import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsService;

import '../../../../core/theme.dart';
import '../../../../core/units.dart';
import '../../../../core/widgets/fs_kit.dart';
import '../../domain/daily_targets.dart';

/// The answers step 2 collects.
///
/// A value object rather than six separate callbacks, so the step can report
/// one complete answer set and its owner can decide what to do with it.
class AboutAnswers {
  const AboutAnswers({
    this.sex,
    this.dateOfBirth,
    this.heightCm,
    this.weightKg,
    this.goalWeightKg,
    this.activityLevel,
  });

  final String? sex;

  /// `YYYY-MM-DD`, the wire format. See `Profile.dateOfBirth` for why this is
  /// not a `DateTime`.
  final String? dateOfBirth;

  final double? heightCm;
  final double? weightKg;
  final double? goalWeightKg;
  final String? activityLevel;
}

/// Heights and body weights a person can plausibly have. Outside them a
/// typed number is far more likely a slip -- 17 for 170 -- than a fact, and
/// it would drive the plan and the calorie target. Soft limits: the step
/// asks once, and a second Continue keeps the number. The server refuses
/// heights outside 50-275 cm and weights outside 20-500 kg, so these must
/// stay inside those, or the second Continue would be refused.
const heightRangeCm = (min: 100.0, max: 250.0);
const weightRangeKg = (min: 25.0, max: 300.0);

/// The answers on this step that look like typos, by API field name, each
/// with what to say under its card. Weights are worded in [unit], the one the
/// user typed in.
Map<String, String> aboutRangeProblems(AboutAnswers value, WeightUnit unit) {
  String number(double n) =>
      n == n.roundToDouble() ? n.toStringAsFixed(0) : n.toString();

  String? query(
    double? measured,
    String name,
    ({double min, double max}) range, {
    WeightUnit? weightUnit,
  }) {
    if (measured == null || (measured >= range.min && measured <= range.max)) {
      return null;
    }
    final shown = weightUnit == null
        ? '${number(measured)} cm'
        : formatWeightWithUnit(measured, weightUnit);
    final min = weightUnit == null
        ? number(range.min)
        : convertFromKg(range.min, weightUnit).round().toString();
    final max = weightUnit == null
        ? number(range.max)
        : convertFromKg(range.max, weightUnit).round().toString();
    final suffix = weightUnit?.api ?? 'cm';
    return 'Check this: $shown? $name is usually $min–$max $suffix.';
  }

  return {
    'heightCm': ?query(value.heightCm, 'Height', heightRangeCm),
    'weightKg': ?query(
      value.weightKg,
      'Weight',
      weightRangeKg,
      weightUnit: unit,
    ),
    'goalWeightKg': ?query(
      value.goalWeightKg,
      'Goal weight',
      weightRangeKg,
      weightUnit: unit,
    ),
  };
}

/// The two `sex` values the design offers.
///
/// The schema also has `prefer_not_to_say`, and profiles answered under the
/// older three-chip control still carry it. It is not offered here, but a
/// stored one is left alone: [FsSegmented] lights no segment for a value it
/// does not know, and nothing rewrites it until the user picks.
const _sexes = <({String value, String label})>[
  (value: 'male', label: 'Male'),
  (value: 'female', label: 'Female'),
];

/// `activity_level` ENUM values. The mockup draws four chips and no "Active";
/// leaving it out would push those users onto a neighbouring multiplier and
/// skew both their plan and the estimate below.
const _activityLevels = <({String value, String label})>[
  (value: 'sedentary', label: 'Sedentary'),
  (value: 'light', label: 'Light'),
  (value: 'moderate', label: 'Moderate'),
  (value: 'active', label: 'Active'),
  (value: 'very_active', label: 'Very active'),
];

/// What each activity level means, in a usual week rather than a
/// multiplier: the five steps run from 1.2 to 1.9 times the resting burn
/// (daily_targets.dart), the biggest swing in the estimate below, so the
/// choice should not be a guess. The same pattern as the Level step's hint.
String _activityHint(String? level) => switch (level) {
  'sedentary' => 'Mostly sitting, with little or no exercise.',
  'light' => 'On your feet some of the day, or 1 to 3 workouts a week.',
  'moderate' => '3 to 5 workouts a week, or a job that keeps you moving.',
  'active' => '6 or 7 workouts a week, or a physical job.',
  'very_active' => 'Hard training most days, or a very physical job.',
  _ => 'Pick the one closest to a usual week, work included.',
};

/// The youngest age the date picker offers. The calorie estimate uses an
/// adult equation (Mifflin-St Jeor), and a birthday this year or last is a
/// slip, not a user.
const _minimumAge = 13;

const _months = <String>[
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// `1998-03-14` as `14 March 1998` — the wire format is not something to read.
String? _readableDate(String? iso) {
  final date = iso == null ? null : DateTime.tryParse(iso);
  if (date == null) return null;
  return '${date.day} ${_months[date.month - 1]} ${date.year}';
}

/// Whole years since [iso], or null when it is unset or unreadable.
int? _ageFrom(String? iso) {
  final born = iso == null ? null : DateTime.tryParse(iso);
  if (born == null) return null;

  final now = DateTime.now();
  final hadBirthday =
      now.month > born.month ||
      (now.month == born.month && now.day >= born.day);
  return now.year - born.year - (hadBirthday ? 0 : 1);
}

/// 2300 as `2,300`. One separator is enough: nobody's daily target reaches
/// seven figures.
String _grouped(int value) {
  final digits = value.toString();
  if (digits.length <= 3) return digits;
  return '${digits.substring(0, digits.length - 3)},'
      '${digits.substring(digits.length - 3)}';
}

/// Step 2: the body and lifestyle facts the plan generator needs.
///
/// Like [GoalStep], it reads no providers and saves nothing.
class AboutStep extends StatefulWidget {
  /// The step's heading, also said when onboarding moves to it.
  static const title = 'A bit about you';

  const AboutStep({
    super.key,
    required this.value,
    required this.onChanged,
    this.unit = WeightUnit.kg,
    this.onUnitChanged,
    required this.goals,
    this.fieldErrors = const {},
    this.mainGoal,
  });

  /// The main goal from step 1, which moves the estimate below the way the
  /// food log's own target moves (-500 kcal to lose weight, +250 to build
  /// muscle), so the two screens show one number. Null is maintenance.
  final String? mainGoal;

  final AboutAnswers value;

  /// What to say under an answer that needs checking, by API field name
  /// (`heightCm`, `weightKg`, ...): a typo [aboutRangeProblems] caught, or a
  /// value the server turned down. Shown right under that answer's card, so
  /// the user does not have to guess which of six to fix.
  final Map<String, String> fieldErrors;
  final ValueChanged<AboutAnswers> onChanged;

  /// The goals step 1 collected, or the saved ones in Settings. Goal weight
  /// only draws the target line on the weight chart, so it is asked outright
  /// only when losing weight is one of them; for anyone else it is one
  /// optional tap away. Required, so no screen showing this step can forget
  /// to pass them.
  final List<String> goals;

  /// The unit the two weight cards display and read. [AboutAnswers] stays in
  /// kilograms whatever this is -- the estimate below the cards and the plan
  /// generator both define their inputs that way.
  final WeightUnit unit;

  /// Null renders the weight card's toggle inert rather than absent.
  final ValueChanged<WeightUnit>? onUnitChanged;

  @override
  State<AboutStep> createState() => _AboutStepState();
}

class _AboutStepState extends State<AboutStep> {
  late final TextEditingController _height;
  late final TextEditingController _weight;
  late final TextEditingController _goalWeight;

  String? _sex;
  String? _dateOfBirth;
  String? _activityLevel;

  /// Once shown, goal weight stays shown: a number already given is never
  /// tucked away behind the button again.
  late bool _showGoalWeight =
      widget.goals.contains('lose_weight') || widget.value.goalWeightKg != null;

  /// Moves the cursor into goal weight when the user asks for it. A field
  /// shown outright never grabs the keyboard.
  final _goalWeightFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _sex = widget.value.sex;
    _dateOfBirth = widget.value.dateOfBirth;
    _activityLevel = widget.value.activityLevel;
    // `_onNumberChanged` rather than `_emit`: the estimate card is computed
    // from these controllers, so a typed digit has to rebuild this step as
    // well as report upwards.
    _height = TextEditingController(text: _format(widget.value.heightCm))
      ..addListener(_onNumberChanged);
    _weight = TextEditingController(text: _formatKg(widget.value.weightKg))
      ..addListener(_onNumberChanged);
    _goalWeight = TextEditingController(
      text: _formatKg(widget.value.goalWeightKg),
    )..addListener(_onNumberChanged);
  }

  /// Carries whatever is already typed across a unit change, so a number does
  /// not silently start meaning something else. See SetRow's own
  /// didUpdateWidget -- same hazard, same resolution.
  ///
  /// The listeners are off while the fields are rewritten: this runs inside
  /// the owner's rebuild, where reporting upwards would have the owner ask
  /// for a rebuild mid-build. The rounded figure now shown is reported once
  /// the frame is done, and the build that follows this redraws the step.
  @override
  void didUpdateWidget(AboutStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.unit == widget.unit) return;
    var rewritten = false;
    for (final controller in [_weight, _goalWeight]) {
      final kg = parseWeight(controller.text, oldWidget.unit);
      if (kg == null) continue;
      final converted = formatWeight(kg, widget.unit);
      controller
        ..removeListener(_onNumberChanged)
        ..value = TextEditingValue(
          text: converted,
          selection: TextSelection.collapsed(offset: converted.length),
        )
        ..addListener(_onNumberChanged);
      rewritten = true;
    }
    if (rewritten) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _emit();
      });
    }
  }

  @override
  void dispose() {
    _height.dispose();
    _weight.dispose();
    _goalWeight.dispose();
    _goalWeightFocus.dispose();
    super.dispose();
  }

  /// A stored kilogram figure as the chosen unit shows it.
  String _formatKg(double? kg) =>
      kg == null ? '' : formatWeight(kg, widget.unit);

  /// What is typed in the weight cards, back in kilograms.
  double? _parseKg(String text) => parseWeight(text, widget.unit);

  static String _format(double? value) {
    if (value == null) return '';
    // Drop a trailing ".0" so a whole number does not read as a measurement
    // taken to one decimal place.
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toString();
  }

  /// Anything that is not a number becomes null rather than an exception, so a
  /// half-typed "1" or a stray letter cannot crash the step.
  static double? _parse(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    return double.tryParse(trimmed);
  }

  void _onNumberChanged() {
    if (mounted) setState(() {});
    _emit();
  }

  void _emit() => widget.onChanged(
    AboutAnswers(
      sex: _sex,
      dateOfBirth: _dateOfBirth,
      heightCm: _parse(_height.text),
      weightKg: _parseKg(_weight.text),
      goalWeightKg: _parseKg(_goalWeight.text),
      activityLevel: _activityLevel,
    ),
  );

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final last = DateTime(now.year - _minimumAge, now.month, now.day);
    var initial = _dateOfBirth == null
        ? DateTime(now.year - 25)
        : DateTime.tryParse(_dateOfBirth!) ?? DateTime(now.year - 25);
    // A date saved before the limit existed must still open the picker,
    // which refuses an initial date past its last one.
    if (initial.isAfter(last)) initial = last;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 100),
      lastDate: last,
      // A birth year is decades back: start on the years rather than make
      // the user page back month by month.
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked == null) return;

    setState(
      () => _dateOfBirth =
          '${picked.year.toString().padLeft(4, '0')}-'
          '${picked.month.toString().padLeft(2, '0')}-'
          '${picked.day.toString().padLeft(2, '0')}',
    );
    _emit();
  }

  /// The space between the Height and Weight cards when they share a row.
  static const _pairGap = 10.0;

  /// How wide the Weight card must be before its number, unit and kg/lb
  /// toggle fit on one line. The toggle and unit grow with the text size and
  /// the card's padding does not; measured, the card needs about 161dp at 2x
  /// text and 135dp at 1.5x, and this keeps a few dp in hand. Below it the
  /// cards stack, so the row cannot overflow on a narrow phone at large text.
  static double _weightCardMinWidth(TextScaler scaler) =>
      64 + 52 * scaler.scale(12) / 12;

  /// A number card for [field], its API name, which also keys its editable.
  Widget _statField(
    String field,
    TextEditingController controller,
    String label,
    String unit, {
    bool accent = false,
    Widget? unitControl,
    FocusNode? focusNode,
  }) => FsStatField(
    fieldKey: Key(field),
    label: label,
    unit: unit,
    controller: controller,
    accent: accent,
    unitControl: unitControl,
    focusNode: focusNode,
    // The card is marked as well as the message under it, so the answer
    // that needs checking stands out among six.
    error: widget.fieldErrors.containsKey(field),
  );

  /// [AboutStep.fieldErrors]'s message for [field], under the answer it is
  /// about; nothing when that answer is fine.
  List<Widget> _errorFor(String field) {
    final message = widget.fieldErrors[field];
    if (message == null) return const [];
    return [
      const SizedBox(height: 8),
      FsErrorLine(message, key: Key('error.$field')),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final theme = Theme.of(context);

    final age = _ageFrom(_dateOfBirth);
    final targets = estimateDailyTargets(
      sex: _sex,
      dateOfBirth: _dateOfBirth,
      heightCm: _parse(_height.text),
      weightKg: _parseKg(_weight.text),
      activityLevel: _activityLevel,
      mainGoal: widget.mainGoal,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // A heading, so a screen reader can jump to it and hears it as the
        // title of the step.
        Semantics(
          header: true,
          child: Text(AboutStep.title, style: theme.textTheme.headlineSmall),
        ),
        const SizedBox(height: 8),
        Text(
          'Powers your calorie targets, recovery and progress tracking.',
          style: TextStyle(fontSize: 12.5, color: t.text2, height: 1.5),
        ),
        const SizedBox(height: 22),
        const FsEyebrow('Sex'),
        const SizedBox(height: 10),
        FsSegmented(
          options: _sexes,
          selected: _sex,
          onSelected: (value) {
            setState(() => _sex = value);
            _emit();
          },
        ),
        ..._errorFor('sex'),
        const SizedBox(height: 18),
        // Said by the card below, as its name, rather than as a node of
        // its own that touch exploration finds apart from the button.
        const ExcludeSemantics(child: FsEyebrow('Date of birth')),
        const SizedBox(height: 10),
        FsCard(
          key: const Key('dateOfBirth'),
          small: true,
          onTap: _pickDate,
          // Named for what it sets: on its own the date (or 'Not set') says
          // nothing about what the button is for.
          child: Semantics(
            label: 'Date of birth',
            value: switch (_readableDate(_dateOfBirth)) {
              null => 'Not set',
              final date when age != null => '$date, $age years old',
              final date => date,
            },
            hint: 'Opens a date picker',
            excludeSemantics: true,
            child: Row(
              children: [
                const FsIconTile(icon: Icons.calendar_today_outlined, size: 38),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _readableDate(_dateOfBirth) ?? 'Not set',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: _dateOfBirth == null ? t.text3 : t.text,
                    ),
                  ),
                ),
                if (age != null) ...[
                  FsTag('$age yrs'),
                  const SizedBox(width: 8),
                ],
                Icon(Icons.chevron_right, size: 16, color: t.text3),
              ],
            ),
          ),
        ),
        ..._errorFor('dateOfBirth'),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final height = _statField('heightCm', _height, 'Height', 'cm');
            final weight = _statField(
              'weightKg',
              _weight,
              'Weight',
              widget.unit.api,
              // Only this card carries the toggle. Goal weight follows it,
              // and two identical switches side by side would be noise
              // rather than a second choice.
              unitControl: FsUnitToggle(
                value: widget.unit,
                onChanged: widget.onUnitChanged,
              ),
            );

            // Stacked, each message goes under its own card; side by side,
            // both go under the pair.
            if ((constraints.maxWidth - _pairGap) / 2 <
                _weightCardMinWidth(MediaQuery.textScalerOf(context))) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  height,
                  ..._errorFor('heightCm'),
                  const SizedBox(height: 10),
                  weight,
                  ..._errorFor('weightKg'),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: height),
                    const SizedBox(width: _pairGap),
                    Expanded(child: weight),
                  ],
                ),
                ..._errorFor('heightCm'),
                ..._errorFor('weightKg'),
              ],
            );
          },
        ),
        const SizedBox(height: 10),
        if (_showGoalWeight) ...[
          _statField(
            'goalWeightKg',
            _goalWeight,
            'Goal weight',
            widget.unit.api,
            // The design's accent belongs to a goal the number serves.
            accent: widget.goals.contains('lose_weight'),
            focusNode: _goalWeightFocus,
          ),
          ..._errorFor('goalWeightKg'),
          const SizedBox(height: 6),
          Text(
            'Optional. Shows as your target line on the weight chart.',
            style: TextStyle(fontSize: 12, color: t.text2, height: 1.4),
          ),
        ] else
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const Key('goalWeight.add'),
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: () {
                setState(() => _showGoalWeight = true);
                // The field exists from the next frame. Focus it then, which
                // also takes the cursor from the weight just typed: a tap
                // outside a field does not unfocus it on a phone.
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _goalWeightFocus.requestFocus();
                });
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add a goal weight (optional)'),
            ),
          ),
        const SizedBox(height: 18),
        const FsEyebrow('Daily activity level'),
        const SizedBox(height: 2),
        // A Wrap is only as tall as its rows, so the room around it is this
        // padding's: 8 of the 10 above and 8 below, since the chips are the
        // step's last line until the card appears. The top and bottom rows get
        // their full 8 dp on the outer side: 48 dp on one row, 44 where the
        // chips wrap and the inner side shares the gap between rows.
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: FsTapRoom(
            child: Wrap(
              spacing: 9,
              runSpacing: 9,
              children: [
                for (final option in _activityLevels)
                  FsChip(
                    key: Key('activity.${option.value}'),
                    label: option.label,
                    selected: _activityLevel == option.value,
                    exclusive: true,
                    onTap: () {
                      final changed = _activityLevel != option.value;
                      setState(() => _activityLevel = option.value);
                      _emit();
                      // Focus stays on the chip, so the explanation that just
                      // changed below it is read out.
                      if (changed) {
                        SemanticsService.sendAnnouncement(
                          View.of(context),
                          _activityHint(option.value),
                          Directionality.of(context),
                        );
                      }
                    },
                  ),
              ],
            ),
          ),
        ),
        Text(
          _activityHint(_activityLevel),
          key: const Key('activity.hint'),
          style: TextStyle(fontSize: 12.5, color: t.text2, height: 1.4),
        ),
        ..._errorFor('activityLevel'),
        // Absent until every term of the equation is answered — the same rule
        // `estimateSessionKcal` follows for an unknown body weight. A card
        // that filled its gaps with population averages would show a
        // confident target belonging to nobody.
        if (targets != null) ...[
          // 18 with the chips' padding above.
          const SizedBox(height: 10),
          FsCard(
            key: const Key('dailyTargets'),
            small: true,
            accent: true,
            child: Row(
              children: [
                Icon(Icons.auto_awesome, size: 18, color: t.accent),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    'Estimated daily target \u2248 ${_grouped(targets.kcal)} kcal'
                    ' \u00b7 ${targets.proteinG}g protein',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: t.text,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
