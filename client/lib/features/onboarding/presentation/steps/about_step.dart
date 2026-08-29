import 'package:flutter/material.dart';

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
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          key: key,
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: label,
            suffixText: suffix,
            border: const OutlineInputBorder(),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('About you', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          'Used to size your starting loads and calorie targets.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        Text('Sex', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final option in _sexes)
              ChoiceChip(
                key: Key('sex.${option.value}'),
                label: Text(option.label),
                selected: _sex == option.value,
                onSelected: (_) {
                  setState(() => _sex = option.value);
                  _emit();
                },
              ),
          ],
        ),
        const SizedBox(height: 20),
        ListTile(
          key: const Key('dateOfBirth'),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.cake_outlined),
          title: const Text('Date of birth'),
          subtitle: Text(_dateOfBirth ?? 'Not set'),
          trailing: const Icon(Icons.edit_calendar_outlined),
          onTap: _pickDate,
        ),
        const SizedBox(height: 12),
        _measurement(const Key('heightCm'), _height, 'Height', 'cm'),
        _measurement(const Key('weightKg'), _weight, 'Weight', 'kg'),
        _measurement(const Key('goalWeightKg'), _goalWeight, 'Goal weight', 'kg'),
        const SizedBox(height: 8),
        Text('How active are you?', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final option in _activityLevels)
          Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              key: Key('activity.${option.value}'),
              selected: _activityLevel == option.value,
              title: Text(option.label),
              subtitle: Text(option.blurb),
              trailing: _activityLevel == option.value
                  ? const Icon(Icons.check_circle)
                  : null,
              onTap: () {
                setState(() => _activityLevel = option.value);
                _emit();
              },
            ),
          ),
      ],
    );
  }
}
