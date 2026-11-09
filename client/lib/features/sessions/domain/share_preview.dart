import '../../../core/dates.dart';
import '../../../core/units.dart';
import '../../profile/domain/body_weight.dart';
import 'session_history.dart';
import 'training_analytics.dart';

/// How many days each period covers, as `SUMMARY_WINDOWS` in
/// `server/src/db/sessions.js` has them.
const _periodDays = {'week': 7, 'month': 30, 'year': 365};

/// The window a report of [period] covers: N days ending [today], today
/// included -- the rule `POST /reports` freezes. [today] is the Manila day
/// (`volumeToday()`), as the server counts it. Years appear only when the
/// window crosses one: "Oct 11 – Nov 9", "Nov 10, 2025 – Nov 9, 2026".
String shareWindowLabel(String period, DateTime today) {
  final days = _periodDays[period] ?? 7;
  final end = DateTime.utc(today.year, today.month, today.day);
  final start = DateTime.utc(today.year, today.month, today.day - (days - 1));
  return start.year == end.year
      ? '${shortDate(start)} – ${shortDate(end)}'
      : '${shortDate(start)}, ${start.year} – ${shortDate(end)}, ${end.year}';
}

/// One number in the share sheet's preview, as the coach's page opens with it.
class SharePreviewTile {
  const SharePreviewTile({required this.value, required this.label, this.note});

  final String value;
  final String label;
  final String? note;
}

/// The tiles the report page will open with -- the same rules as `tiles` in
/// `server/src/lib/report-page.js` -- from what the Progress tab already
/// holds, so the sheet never waits on the network. A null input is still
/// loading (or failed): its values read as a dash.
///
/// Kilograms whatever the user's unit, because the page is in kilograms and
/// this is a preview of the page.
List<SharePreviewTile> sharePreviewTiles({
  required String period,
  required TrainingSummary? summary,
  required TrainingAnalytics? analytics,
  required BodyWeightSeries? bodyWeight,
  required bool includeVolume,
  required bool includeBodyWeight,
}) {
  const dash = '–';
  final pct = includeVolume ? analytics?.change.changePct : null;
  final target = analytics?.adherence.target;

  final tiles = [
    SharePreviewTile(
      value: summary == null
          ? dash
          : '${formatWeightCompact(summary.totalVolumeKg, WeightUnit.kg)} kg',
      label: 'Volume',
      note: pct == null
          ? null
          : '${pct >= 0 ? '+' : ''}$pct% vs previous $period',
    ),
    SharePreviewTile(
      value: summary == null ? dash : '${summary.sessionCount}',
      label: 'Sessions',
      note: target == null ? null : 'of $target planned',
    ),
    SharePreviewTile(
      value: summary == null ? dash : '${summary.setCount}',
      label: 'Sets',
    ),
  ];

  final change = includeBodyWeight ? _weightChange(bodyWeight) : null;
  if (change != null) {
    tiles.add(
      SharePreviewTile(
        value: change.delta,
        label: 'Body weight',
        note: change.fromTo,
      ),
    );
  }
  return tiles;
}

/// Null when the tile has nothing honest to say: fewer than two entries, or a
/// widened series reaching outside the window.
({String delta, String fromTo})? _weightChange(BodyWeightSeries? series) {
  if (series == null || series.widened || series.points.length < 2) return null;
  final points = [...series.points]
    ..sort((a, b) => a.loggedOn.compareTo(b.loggedOn));
  final first = points.first.weightKg;
  final last = points.last.weightKg;
  final delta = ((last - first) * 10).round() / 10;
  final text = delta == 0
      ? '0 kg'
      : '${delta > 0 ? '+' : '−'}${_plain(delta.abs())} kg';
  return (delta: text, fromTo: '${_plain(first)} → ${_plain(last)}');
}

/// 75.0 as "75", 76.4 as "76.4" -- how JavaScript prints the same numbers
/// on the page.
String _plain(double value) =>
    value == value.roundToDouble() ? value.toStringAsFixed(0) : '$value';
