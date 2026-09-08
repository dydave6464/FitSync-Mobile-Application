import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme.dart';
import '../../domain/active_session.dart';

/// One line of the set table: number, kg, reps, tick.
///
/// Write-through, not optimistic. The row disables while the write is in
/// flight and only ticks once [onComplete] returns, so a visible tick always
/// means a stored set. A failure shows a retry on this row alone and leaves
/// every other set untouched.
class SetRow extends StatefulWidget {
  const SetRow({
    super.key,
    required this.setNumber,
    required this.logged,
    required this.onComplete,
    required this.onUndo,
    this.prefillWeightKg,
  });

  final int setNumber;

  /// Non-null once the server holds this set.
  final LoggedSet? logged;

  /// Seeded from the last session's heaviest set, when there was one.
  final double? prefillWeightKg;

  final Future<void> Function(double? weightKg, int? reps) onComplete;
  final Future<void> Function() onUndo;

  @override
  State<SetRow> createState() => _SetRowState();
}

class _SetRowState extends State<SetRow> {
  late final TextEditingController _weight;
  late final TextEditingController _reps;
  bool _busy = false;
  bool _failed = false;

  /// Trailing zeros read as noise on a phone: 22.5, not 22.50; 20, not 20.0.
  static String _formatWeight(double value) {
    final text = value.toStringAsFixed(2);
    return text.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  @override
  void initState() {
    super.initState();
    final logged = widget.logged;
    _weight = TextEditingController(
      text: logged?.weightKg != null
          ? _formatWeight(logged!.weightKg!)
          : widget.prefillWeightKg != null
              ? _formatWeight(widget.prefillWeightKg!)
              : '',
    );
    _reps = TextEditingController(text: logged?.reps?.toString() ?? '');
  }

  @override
  void dispose() {
    _weight.dispose();
    _reps.dispose();
    super.dispose();
  }

  Future<void> _tick() async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      if (widget.logged != null) {
        await widget.onUndo();
      } else {
        // An empty field is "not recorded", never zero.
        await widget.onComplete(
          double.tryParse(_weight.text.trim()),
          int.tryParse(_reps.text.trim()),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final done = widget.logged != null;
    final editable = !done && !_busy;

    InputDecoration decoration(String hint) => InputDecoration(
          hintText: hint,
          isDense: true,
          filled: true,
          fillColor: done ? t.accentDim : t.surface2,
          contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(FsRadius.sm),
            borderSide: BorderSide.none,
          ),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text(
              '${widget.setNumber}',
              style: TextStyle(fontFamily: fsMonoFamily, fontSize: 12, color: t.text3),
            ),
          ),
          Expanded(
            child: TextField(
              key: Key('set.${widget.setNumber}.weight'),
              controller: _weight,
              enabled: editable,
              textAlign: TextAlign.center,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                // Three digits and two decimals: weight_kg is DECIMAL(6,2) and
                // the server rejects anything above 999.99 anyway.
                FilteringTextInputFormatter.allow(RegExp(r'^\d{0,3}\.?\d{0,2}')),
              ],
              decoration: decoration('kg'),
              style: TextStyle(fontFamily: fsMonoFamily, fontSize: 13.5, color: t.text),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              key: Key('set.${widget.setNumber}.reps'),
              controller: _reps,
              enabled: editable,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d{0,3}')),
              ],
              decoration: decoration('reps'),
              style: TextStyle(fontFamily: fsMonoFamily, fontSize: 13.5, color: t.text),
            ),
          ),
          SizedBox(
            width: _failed ? 74 : 44,
            child: _failed
                ? TextButton(
                    key: Key('set.${widget.setNumber}.tick'),
                    onPressed: _busy ? null : _tick,
                    child: const Text('Retry'),
                  )
                : IconButton(
                    key: Key('set.${widget.setNumber}.tick'),
                    onPressed: _busy ? null : _tick,
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            done ? Icons.check_circle : Icons.circle_outlined,
                            size: 20,
                            color: done ? t.accent : t.line2,
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}
