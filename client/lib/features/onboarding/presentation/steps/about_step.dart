import 'package:flutter/material.dart';

import '../../../../core/theme.dart';
import '../../../../core/widgets/fs_kit.dart';

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

/// `sex` ENUM values. `prefer_not_to_say` is absent from the mockup but present
/// in the schema, and a user who does not want to answer needs somewhere to go
/// that is not a wrong answer.
const _sexes = <({String value, String label})>[
  (value: 'male', label: 'Male'),
  (value: 'female', label: 'Female'),
  (value: 'prefer_not_to_say', label: 'Prefer not to say'),
];

/// `activity_level` ENUM values. `active` is likewise missing from the mockup;
/// leaving it out would push those users onto a neighbouring value and skew
/// their plan.
const _activityLevels = <({String value, String label, String blurb})>[
  (value: 'sedentary', label: 'Sedentary', blurb: 'Desk work, little walking'),
  (value: 'light', label: 'Lightly active', blurb: 'Light exercise 1-3 days a week'),
  (value: 'moderate', label: 'Moderately active', blurb: 'Exercise 3-5 days a week'),
  (value: 'active', label: 'Active', blurb: 'Exercise 6-7 days a week'),
  (value: 'very_active', label: 'Very active', blurb: 'Physical job or twice-daily training'),
];

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
    _height = TextEditingController(text: _format(widget.value.heightCm))
      ..addListener(_emit);
    _weight = TextEditingController(text: _format(widget.value.weightKg))
      ..addListener(_emit);
    _goalWeight = TextEditingController(text: _format(widget.value.goalWeightKg))
      ..addListener(_emit);
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

  Widget _measurement(Key key, TextEditingController controller, String label,
          String suffix) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: FsField(
          fieldKey: key,
          controller: controller,
          hint: label,
          suffix: suffix,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('About you', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          'Used to size your starting loads and calorie targets.',
          style: TextStyle(fontSize: 12.5, color: t.text2, height: 1.5),
        ),
        const SizedBox(height: 22),
        const FsEyebrow('Sex'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in _sexes)
              FsChip(
                key: Key('sex.${option.value}'),
                label: option.label,
                selected: _sex == option.value,
                onTap: () {
                  setState(() => _sex = option.value);
                  _emit();
                },
              ),
          ],
        ),
        const SizedBox(height: 22),
        const FsEyebrow('Date of birth'),
        const SizedBox(height: 10),
        FsCard(
          key: const Key('dateOfBirth'),
          small: true,
          onTap: _pickDate,
          child: Row(
            children: [
              const FsIconTile(icon: Icons.cake_outlined, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _dateOfBirth ?? 'Not set',
                  style: TextStyle(
                    fontSize: 14,
                    color: _dateOfBirth == null ? t.text3 : t.text,
                  ),
                ),
              ),
              Icon(Icons.edit_calendar_outlined, size: 17, color: t.text3),
            ],
          ),
        ),
        const SizedBox(height: 22),
        const FsEyebrow('Measurements'),
        const SizedBox(height: 10),
        _measurement(const Key('heightCm'), _height, 'Height', 'cm'),
        _measurement(const Key('weightKg'), _weight, 'Weight', 'kg'),
        _measurement(const Key('goalWeightKg'), _goalWeight, 'Goal weight', 'kg'),
        const SizedBox(height: 12),
        const FsEyebrow('How active are you?'),
        const SizedBox(height: 10),
        for (final option in _activityLevels) ...[
          FsCard(
            key: Key('activity.${option.value}'),
            small: true,
            accent: _activityLevel == option.value,
            onTap: () {
              setState(() => _activityLevel = option.value);
              _emit();
            },
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(option.label, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        option.blurb,
                        style: TextStyle(fontSize: 11, color: t.text3),
                      ),
                    ],
                  ),
                ),
                FsRadioDot(selected: _activityLevel == option.value),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}
