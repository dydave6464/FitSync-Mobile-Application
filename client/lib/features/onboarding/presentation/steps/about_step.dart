import 'package:flutter/material.dart';

import '../../../../core/theme.dart';
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

const _months = <String>[
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
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
  final hadBirthday = now.month > born.month ||
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
  const AboutStep({super.key, required this.value, required this.onChanged});

  final AboutAnswers value;
  final ValueChanged<AboutAnswers> onChanged;

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
    _weight = TextEditingController(text: _format(widget.value.weightKg))
      ..addListener(_onNumberChanged);
    _goalWeight = TextEditingController(text: _format(widget.value.goalWeightKg))
      ..addListener(_onNumberChanged);
  }

  @override
  void dispose() {
    _height.dispose();
    _weight.dispose();
    _goalWeight.dispose();
    super.dispose();
  }

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

  void _emit() => widget.onChanged(AboutAnswers(
        sex: _sex,
        dateOfBirth: _dateOfBirth,
        heightCm: _parse(_height.text),
        weightKg: _parse(_weight.text),
        goalWeightKg: _parse(_goalWeight.text),
        activityLevel: _activityLevel,
      ));

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initial = _dateOfBirth == null
        ? DateTime(now.year - 25)
        : DateTime.tryParse(_dateOfBirth!) ?? DateTime(now.year - 25);

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 100),
      lastDate: now,
    );
    if (picked == null) return;

    setState(() => _dateOfBirth =
        '${picked.year.toString().padLeft(4, '0')}-'
        '${picked.month.toString().padLeft(2, '0')}-'
        '${picked.day.toString().padLeft(2, '0')}');
    _emit();
  }

  Widget _statField(Key key, TextEditingController controller, String label,
          String unit, {bool accent = false}) =>
      FsStatField(
        fieldKey: key,
        label: label,
        unit: unit,
        controller: controller,
        accent: accent,
      );

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final theme = Theme.of(context);

    final age = _ageFrom(_dateOfBirth);
    final targets = estimateDailyTargets(
      sex: _sex,
      dateOfBirth: _dateOfBirth,
      heightCm: _parse(_height.text),
      weightKg: _parse(_weight.text),
      activityLevel: _activityLevel,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('A bit about you', style: theme.textTheme.headlineSmall),
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
        const SizedBox(height: 18),
        const FsEyebrow('Date of birth'),
        const SizedBox(height: 10),
        FsCard(
          key: const Key('dateOfBirth'),
          small: true,
          onTap: _pickDate,
          child: Row(
            children: [
              const FsIconTile(icon: Icons.calendar_today_outlined, size: 38),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _readableDate(_dateOfBirth) ?? 'Not set',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: _dateOfBirth == null ? t.text3 : t.text,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      'Used for age-based targets',
                      style: TextStyle(fontSize: 11, color: t.text3),
                    ),
                  ],
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
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _statField(
                  const Key('heightCm'), _height, 'Height', 'cm'),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _statField(
                  const Key('weightKg'), _weight, 'Weight', 'kg'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _statField(const Key('goalWeightKg'), _goalWeight, 'Goal weight', 'kg',
            accent: true),
        const SizedBox(height: 18),
        const FsEyebrow('Daily activity level'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 9,
          runSpacing: 9,
          children: [
            for (final option in _activityLevels)
              FsChip(
                key: Key('activity.${option.value}'),
                label: option.label,
                selected: _activityLevel == option.value,
                onTap: () {
                  setState(() => _activityLevel = option.value);
                  _emit();
                },
              ),
          ],
        ),
        // Absent until every term of the equation is answered — the same rule
        // `estimateSessionKcal` follows for an unknown body weight. A card
        // that filled its gaps with population averages would show a
        // confident target belonging to nobody.
        if (targets != null) ...[
          const SizedBox(height: 18),
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
                    style: TextStyle(fontSize: 11.5, color: t.text, height: 1.45),
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
