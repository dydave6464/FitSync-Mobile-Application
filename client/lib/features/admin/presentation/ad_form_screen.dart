import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../core/dates.dart' show monthShort;
import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';
import '../../nutrition/data/meal_photo_picker.dart'
    show PickedPhoto, UnsupportedPhoto;
import '../../nutrition/presentation/widgets/text_limits.dart';
import '../../onboarding/presentation/edit_scaffold.dart';
import '../data/ad_image_picker.dart';
import '../domain/admin_format.dart';
import '../domain/admin_models.dart';
import 'providers.dart';

/// The server's limits for an ad (server/src/routes/admin-ads.js).
const _maxTitle = 80;
const _maxAdvertiser = 120;
const _maxLink = 500;
const _maxAmountPhp = 1000000.0;

/// The server's image limit (server/src/lib/image-check.js).
const _maxImageBytes = 1500000;

const _linkError = 'Use a link that starts with https://';
const _amountError = 'Enter an amount from ₱0 to ₱1,000,000.';
const _runError = "The end date can't be before the start date.";

/// Pesos to the centavo: digits, then at most two after a point.
final _amountShape = RegExp(r'^\d{0,7}(\.\d{0,2})?$');

/// "1200", "1200.5": a stored amount as it is typed.
String _typedPhp(double php) =>
    php == php.roundToDouble() ? php.toInt().toString() : php.toString();

DateTime _date(String ymd) {
  final parts = ymd.split('-').map(int.parse).toList();
  return DateTime(parts[0], parts[1], parts[2]);
}

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// "1 Nov 2026".
String _dayText(String ymd) {
  final d = _date(ymd);
  return '${d.day} ${monthShort[d.month - 1]} ${d.year}';
}

/// An https address with a host, within the server's length, as the server
/// checks it; blank is no link.
bool _linkOk(String text) {
  if (text.isEmpty) return true;
  final uri = Uri.tryParse(text);
  return uri != null &&
      uri.scheme == 'https' &&
      uri.host.isNotEmpty &&
      text.length <= _maxLink;
}

/// Adds one of FitSync's own ads ([ad] null) or edits one: title, image,
/// optional link, advertiser, what they paid and the run. Editing also
/// pauses the ad, or resumes it. There is no delete: the amount is a
/// revenue record.
class AdFormScreen extends ConsumerStatefulWidget {
  const AdFormScreen({super.key, this.ad});

  final AdminAd? ad;

  @override
  ConsumerState<AdFormScreen> createState() => _AdFormScreenState();
}

class _AdFormScreenState extends ConsumerState<AdFormScreen> {
  late final _title = TextEditingController(text: widget.ad?.title ?? '');
  late final _link = TextEditingController(text: widget.ad?.linkUrl ?? '');
  late final _advertiser = TextEditingController(
    text: widget.ad?.advertiser ?? '',
  );
  late final _amount = TextEditingController(
    text: switch (widget.ad) {
      final ad? => _typedPhp(ad.amountPhp),
      null => '',
    },
  );
  late String? _startsOn = widget.ad?.startsOn;
  late String? _endsOn = widget.ad?.endsOn;

  /// An image picked here; null keeps the ad's own (on an edit).
  PickedPhoto? _image;
  String? _imageError;

  /// What the form opened with, to tell an edit from an untouched form.
  late final String _opened;

  /// What the server said about one field on the last Save, by the
  /// server's field name; cleared as that field changes.
  final _fieldErrors = <String, String>{};
  String? _error;
  bool _saving = false;

  /// Running or not: the ad's own flag, then whatever the last Pause or
  /// Resume answered.
  late bool _active = widget.ad?.active ?? true;
  bool _toggling = false;

  bool get _editing => widget.ad != null;

  @override
  void initState() {
    super.initState();
    _opened = _snapshot();
  }

  @override
  void dispose() {
    _title.dispose();
    _link.dispose();
    _advertiser.dispose();
    _amount.dispose();
    super.dispose();
  }

  String _snapshot() => [
    _title.text.trim(),
    _link.text.trim(),
    _advertiser.text.trim(),
    _amount.text.trim(),
    _startsOn,
    _endsOn,
    // Any picked image is a change, even the same picture again.
    _image == null ? '' : identityHashCode(_image),
  ].join('\u0000');

  /// Blank is null; anything unreadable is NaN, which fails the range.
  double? get _php {
    final text = _amount.text.trim();
    return text.isEmpty ? null : (double.tryParse(text) ?? double.nan);
  }

  void _changed(String serverField) => setState(() {
    _fieldErrors.remove(serverField);
    _error = null;
  });

  /// Why Save is off for a missing answer, in the form's order.
  String? _missing() {
    if (_title.text.trim().isEmpty) return 'Add a title';
    if (!_editing && _image == null) return 'Choose an image';
    if (_advertiser.text.trim().isEmpty) return 'Add the advertiser';
    if (_amount.text.trim().isEmpty) return 'Add the amount paid';
    if (_startsOn == null) return 'Choose a start date';
    if (_endsOn == null) return 'Choose an end date';
    return null;
  }

  /// The link's error once it can no longer become https: "http" may still
  /// be on its way there, "http://" is not.
  String? get _linkFieldError {
    final text = _link.text.trim();
    if (_linkOk(text) || 'https://'.startsWith(text)) return null;
    return _linkError;
  }

  String? get _amountFieldError {
    final php = _php;
    if (php == null || (php >= 0 && php <= _maxAmountPhp)) return null;
    return _amountError;
  }

  String? get _runFieldError {
    final start = _startsOn;
    final end = _endsOn;
    if (start == null || end == null || end.compareTo(start) >= 0) {
      return null;
    }
    return _runError;
  }

  AdInput _input() {
    final link = _link.text.trim();
    return AdInput(
      title: clipUtf16(_title.text, _maxTitle),
      advertiser: clipUtf16(_advertiser.text, _maxAdvertiser),
      amountPhp: _php!,
      startsOn: _startsOn!,
      endsOn: _endsOn!,
      linkUrl: link.isEmpty ? null : link,
      image: _image?.bytes,
      mimeType: _image?.mimeType,
    );
  }

  Future<void> _pickImage() async {
    final picker = ref.read(adImagePickerProvider);
    String? problem;
    PickedPhoto? picked;
    try {
      picked = await picker.pick();
      if (picked != null && picked.bytes.length > _maxImageBytes) {
        picked = null;
        problem = 'The image must be at most 1.5 MB.';
      }
    } on UnsupportedPhoto {
      problem = 'The image must be a JPEG or PNG.';
    } catch (_) {
      problem = "Couldn't open your photos. Try again.";
    }
    if (!mounted) return;
    // Backing out of the gallery changes nothing.
    if (picked == null && problem == null) return;
    setState(() {
      _error = null;
      _imageError = problem;
      if (picked != null) _image = picked;
    });
  }

  Future<void> _pickDay({required bool start}) async {
    final today = _date(ref.read(adminTodayProvider));
    // The end opens on the start, where most runs end a few weeks on.
    final shown = start ? _startsOn : (_endsOn ?? _startsOn);
    final initial = shown == null ? today : _date(shown);
    var first = DateTime(2020);
    if (initial.isBefore(first)) first = initial;
    var last = DateTime(today.year + 5, 12, 31);
    if (initial.isAfter(last)) last = initial;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: start ? 'Start date' : 'End date',
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (start) {
        _startsOn = _ymd(picked);
      } else {
        _endsOn = _ymd(picked);
      }
      // A refusal of either day was about the run as a whole.
      _fieldErrors
        ..remove('startsOn')
        ..remove('endsOn');
      _error = null;
    });
  }

  Future<void> _save() async {
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final route = ModalRoute.of(context);
    final repo = ref.read(adminRepositoryProvider);
    setState(() {
      _saving = true;
      _error = null;
      _imageError = null;
      _fieldErrors.clear();
    });
    try {
      final ad = widget.ad;
      if (ad == null) {
        await repo.createAd(_input());
      } else {
        await repo.updateAd(ad.id, _input());
      }
    } catch (error) {
      // No answer is not "not saved": the ad may be in even so. The list
      // shows it before the admin presses Save again and makes a second.
      if (error is ApiException && error.code == 'NETWORK_ERROR') {
        container.invalidate(adminAdsProvider);
      }
      if (!mounted) return;
      setState(() {
        _saving = false;
        _placeError(error);
      });
      return;
    }
    container.invalidate(adminAdsProvider);
    // The amount is ad revenue: Overview's month and every Revenue month
    // already opened show it, so they are fetched again too.
    container.invalidate(adminOverviewProvider);
    container.invalidate(adminRevenueProvider);
    // As the food form: only while this form is still the page on top, and
    // still "saving" as it pops, so the discard guard lets it go.
    if (route != null && route.isCurrent) navigator.pop();
    messenger.showSnackBar(const SnackBar(content: Text('Ad saved.')));
  }

  static const _fieldsShown = {
    'title',
    'advertiser',
    'amountPhp',
    'startsOn',
    'endsOn',
    'linkUrl',
  };

  /// A refusal about one field goes under it, the image's under Image;
  /// anything else above Save.
  void _placeError(Object error) {
    final message = userMessage(error);
    if (error is ApiException) {
      if (error.code == 'INVALID_IMAGE') {
        _imageError = message;
        return;
      }
      for (final detail in error.details) {
        final field = detail['field'];
        if (field == 'image' || field == 'mimeType') {
          _imageError = message;
          return;
        }
        if (field is String && _fieldsShown.contains(field)) {
          _fieldErrors[field] = message;
          return;
        }
      }
    }
    _error = message;
  }

  /// Pause or Resume: at once, no confirm (nothing is lost, and the other
  /// button undoes it).
  Future<void> _setActive(AdminAd ad, {required bool active}) async {
    if (_toggling) return;
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() => _toggling = true);
    AdminAd? changed;
    String message;
    try {
      changed = await ref
          .read(adminRepositoryProvider)
          .setAdActive(ad.id, active: active);
      message = active ? 'Ad resumed.' : 'Ad paused.';
    } catch (error) {
      message = userMessage(error);
    }
    container.invalidate(adminAdsProvider);
    if (!mounted) return;
    setState(() {
      _toggling = false;
      if (changed != null) _active = changed.active;
    });
    // Replacing, not queueing behind, the last Pause or Resume's message:
    // queued, "Ad resumed." would wait out "Ad paused.".
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final ad = widget.ad;
    final missing = _missing();
    final linkError = _linkFieldError;
    final linkDone = _linkOk(_link.text.trim());
    final amountError = _amountFieldError;
    final runError = _runFieldError;
    final valid =
        missing == null && linkDone && amountError == null && runError == null;

    Widget? errorLine(String? message) => message == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: 4),
            child: FsErrorLine(message),
          );

    Widget textBox(
      String name,
      String serverField, {
      required TextEditingController controller,
      required String label,
      required String hint,
      required List<TextInputFormatter> formatters,
      TextInputType? keyboardType,
      TextCapitalization capitalization = TextCapitalization.none,
      String? clientError,
    }) {
      final error = _fieldErrors[serverField] ?? clientError;
      return KeyedSubtree(
        key: Key('admin.ad.$name.box'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FsField(
              controller: controller,
              fieldKey: Key('admin.ad.$name'),
              label: label,
              hint: hint,
              keyboardType: keyboardType,
              textCapitalization: capitalization,
              inputFormatters: formatters,
              errorText: error,
              onChanged: (_) => _changed(serverField),
            ),
            ?errorLine(error),
          ],
        ),
      );
    }

    Widget dateBox(String name, String label, String? day, String? error) =>
        KeyedSubtree(
          key: Key('admin.ad.$name.box'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DateBox(
                boxKey: Key('admin.ad.$name'),
                label: label,
                day: day,
                error: error,
                onTap: _saving
                    ? null
                    : () => _pickDay(start: name == 'startsOn'),
              ),
              ?errorLine(error),
            ],
          ),
        );

    return EditScaffold(
      title: _editing ? 'Edit ad' : 'New ad',
      dirty: _snapshot() != _opened,
      busy: _saving,
      error: _error,
      hint:
          missing ??
          (!linkDone && linkError == null
              ? 'Finish the link, or leave it empty'
              : null),
      // Not while Pause or Resume runs: one change to the ad at a time.
      onSave: valid && !_toggling ? _save : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          textBox(
            'title',
            'title',
            controller: _title,
            label: 'Title',
            hint: 'e.g. Protein bars, 20% off',
            capitalization: TextCapitalization.sentences,
            formatters: const [Utf16LengthLimit(_maxTitle)],
          ),
          const SizedBox(height: 16),
          _imageSection(t, ad, errorLine(_imageError)),
          const SizedBox(height: 16),
          textBox(
            'link',
            'linkUrl',
            controller: _link,
            label: 'Link · optional',
            hint: 'https://',
            keyboardType: TextInputType.url,
            formatters: const [Utf16LengthLimit(_maxLink)],
            clientError: linkError,
          ),
          const SizedBox(height: 16),
          textBox(
            'advertiser',
            'advertiser',
            controller: _advertiser,
            label: 'Advertiser',
            hint: 'e.g. GymShark PH',
            capitalization: TextCapitalization.words,
            formatters: const [Utf16LengthLimit(_maxAdvertiser)],
          ),
          const SizedBox(height: 16),
          textBox(
            'amount',
            'amountPhp',
            controller: _amount,
            label: 'Amount paid (₱)',
            hint: 'e.g. 1200',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            formatters: [
              TextInputFormatter.withFunction(
                (old, next) => _amountShape.hasMatch(next.text) ? next : old,
              ),
            ],
            clientError: amountError,
          ),
          const SizedBox(height: 16),
          dateBox(
            'startsOn',
            'Start date',
            _startsOn,
            _fieldErrors['startsOn'],
          ),
          const SizedBox(height: 16),
          dateBox(
            'endsOn',
            'End date',
            _endsOn,
            _fieldErrors['endsOn'] ?? runError,
          ),
          if (ad != null) ...[
            const SizedBox(height: 24),
            if (_active)
              FsButton(
                key: const Key('admin.ad.pause'),
                label: 'Pause ad',
                kind: FsButtonKind.secondary,
                busy: _toggling,
                onPressed: _saving ? null : () => _setActive(ad, active: false),
              )
            else
              FsButton(
                key: const Key('admin.ad.resume'),
                label: 'Resume ad',
                kind: FsButtonKind.secondary,
                busy: _toggling,
                onPressed: _saving ? null : () => _setActive(ad, active: true),
              ),
          ],
        ],
      ),
    );
  }

  /// The image: a square preview of the one picked here or, on an edit, the
  /// ad's own; the button to pick one; and what the server takes.
  Widget _imageSection(FsTokens t, AdminAd? ad, Widget? error) {
    final placeholder = Center(
      child: Icon(Icons.image_outlined, size: 24, color: t.text3),
    );
    Widget? image;
    if (_image case final picked?) {
      image = Image.memory(
        picked.bytes,
        fit: BoxFit.cover,
        semanticLabel: "The ad's image",
        errorBuilder: (_, _, _) => placeholder,
      );
    } else if (ad != null) {
      final baseUrl = ref.watch(adminRepositoryProvider).baseUrl;
      image = Image.network(
        mediaUrl(baseUrl, ad.imageUrl),
        fit: BoxFit.cover,
        semanticLabel: "The ad's image",
        errorBuilder: (_, _, _) => placeholder,
      );
    }

    return KeyedSubtree(
      key: const Key('admin.ad.image.box'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(header: true, child: const FsEyebrow('Image')),
          const SizedBox(height: 6),
          if (image != null) ...[
            // Square and cropped, as the trainee's card draws it beside
            // the title; a little larger here so it can be checked.
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: ClipRRect(
                key: const Key('admin.ad.image.preview'),
                borderRadius: BorderRadius.circular(FsRadius.sm),
                child: SizedBox.square(
                  dimension: 96,
                  child: ColoredBox(color: t.surface2, child: image),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FsButton(
              key: const Key('admin.ad.image.pick'),
              label: image == null ? 'Choose image' : 'Change image',
              kind: FsButtonKind.secondary,
              small: true,
              icon: const Icon(Icons.photo_library_outlined),
              onPressed: _saving ? null : _pickImage,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'JPEG or PNG, up to 1.5 MB. Shown small and square.',
            style: TextStyle(fontSize: 12, height: 1.4, color: t.text3),
          ),
          ?error,
        ],
      ),
    );
  }
}

/// A day, chosen in the date picker: its name as an eyebrow, then a box the
/// size of a field with the day in it ("1 Nov 2026") or "Choose a date".
class _DateBox extends StatelessWidget {
  const _DateBox({
    required this.boxKey,
    required this.label,
    required this.day,
    required this.error,
    required this.onTap,
  });

  final Key boxKey;
  final String label;
  final String? day;
  final String? error;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final shown = day;
    final radius = BorderRadius.circular(FsRadius.md);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(child: FsEyebrow(label)),
        const SizedBox(height: 6),
        Semantics(
          button: true,
          label: label,
          value: shown == null ? 'Not chosen' : _dayText(shown),
          hint: error,
          // excludeSemantics drops the InkWell's own tap, so the tap (and
          // whether it is off while saving) is given here instead.
          enabled: onTap != null,
          onTap: onTap,
          excludeSemantics: true,
          child: Material(
            color: t.surface,
            shape: RoundedRectangleBorder(
              borderRadius: radius,
              side: BorderSide(color: error == null ? t.line : t.red),
            ),
            child: InkWell(
              key: boxKey,
              onTap: onTap,
              borderRadius: radius,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 52),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_today_outlined,
                        size: 18,
                        color: t.text3,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          shown == null ? 'Choose a date' : _dayText(shown),
                          style: TextStyle(
                            fontSize: 14,
                            color: shown == null ? t.text3 : t.text,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
