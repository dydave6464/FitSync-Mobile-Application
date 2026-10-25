import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api_exception.dart';
import '../../../../core/manila_day.dart';
import '../../../../core/theme.dart';
import '../../../../core/widgets/fs_kit.dart';
import '../../../exercises/presentation/exercise_list_screen.dart' show describeError;
import '../../../pro/presentation/pro_screen.dart';
import '../../data/meal_photo_picker.dart';
import '../../domain/meal_photo.dart';
import '../../domain/nutrition.dart';
import '../error_snack_bar.dart';
import '../log_food_screen.dart' show pickFood;
import '../providers.dart';
import '../widgets/fatsecret_attribution.dart';
import 'photo_cards.dart';
import 'providers.dart';

/// What went wrong with a photo; each has its own next step.
enum PhotoProblem { noFood, unavailable, limit, unreadable }

PhotoProblem problemOf(Object error) => switch (error) {
  ApiException(code: 'PHOTO_LIMIT_REACHED') => PhotoProblem.limit,
  ApiException(code: 'INVALID_IMAGE' || 'PAYLOAD_TOO_LARGE') => PhotoProblem.unreadable,
  UnsupportedPhoto() => PhotoProblem.unreadable,
  _ => PhotoProblem.unavailable,
};

const photoProblemText = {
  PhotoProblem.noFood: "Couldn't spot any food in this photo.",
  PhotoProblem.unavailable: "Couldn't look at your photo right now.",
  PhotoProblem.limit: "You've used today's meal photos. Try again tomorrow.",
  PhotoProblem.unreadable: "Couldn't read this photo. Try another one.",
};

String logButtonLabel(int n) => switch (n) {
  0 => 'Log items',
  1 => 'Log 1 item',
  _ => 'Log $n items',
};

/// Snap a meal once the photo is taken: analysing, then the confirm list --
/// or what went wrong, with a way on. Pops true once the meal is logged.
class MealPhotoScreen extends ConsumerStatefulWidget {
  const MealPhotoScreen({
    super.key,
    required this.photo,
    required this.source,
    required this.mealType,
    this.date,
    required this.onSearchInstead,
  });

  final PickedPhoto photo;

  /// Where the photo came from, so Retake goes back there.
  final PhotoSource source;

  /// The meal it opens on: Log food's meal, or the time of day's.
  final String mealType;

  /// The day it logs to; null is today in Manila.
  final String? date;

  /// "Search instead", with this screen's context and the meal chosen here.
  final void Function(BuildContext context, String mealType) onSearchInstead;

  @override
  ConsumerState<MealPhotoScreen> createState() => _MealPhotoScreenState();
}

enum _Phase { analysing, failed, confirm }

class _MealPhotoScreenState extends ConsumerState<MealPhotoScreen> {
  late PickedPhoto _photo = widget.photo;
  late String _meal = widget.mealType;
  _Phase _phase = _Phase.analysing;
  PhotoProblem? _problem;
  PhotoRecognition? _recognition;
  List<DraftCard> _cards = [];
  bool _logging = false;

  /// Which request is current: a Retake or Try again makes an earlier
  /// answer stale.
  int _attempt = 0;

  ScaffoldMessengerState? _messenger;
  int _undoToken = 0;
  bool _undoShowing = false;

  @override
  void initState() {
    super.initState();
    _recognize();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messenger = ScaffoldMessenger.of(context);
  }

  @override
  void dispose() {
    // A "Removed … · Undo" left up would act on a screen that is gone.
    if (_undoShowing) _messenger?.hideCurrentSnackBar();
    super.dispose();
  }

  Future<void> _recognize() async {
    final attempt = ++_attempt;
    try {
      final r = await ref.read(mealPhotoRepositoryProvider).recognize(_photo.bytes, _photo.mimeType);
      if (!mounted || attempt != _attempt) return;
      setState(() {
        _recognition = r;
        if (r.isEmpty) {
          _phase = _Phase.failed;
          _problem = PhotoProblem.noFood;
        } else {
          _cards = [for (final s in r.items) DraftCard.suggested(s), for (final u in r.unlisted) DraftCard.unlisted(u)];
          _phase = _Phase.confirm;
        }
      });
    } catch (e) {
      if (!mounted || attempt != _attempt) return;
      if (e is ApiException && e.code == 'PRO_REQUIRED') {
        final navigator = Navigator.of(context);
        navigator.pop(false);
        navigator.push(MaterialPageRoute<void>(builder: (_) => const ProScreen()));
        return;
      }
      setState(() {
        _phase = _Phase.failed;
        _problem = problemOf(e);
      });
    }
  }

  void _tryAgain() {
    setState(() {
      _phase = _Phase.analysing;
      _problem = null;
    });
    _recognize();
  }

  Future<void> _retake() async {
    final PickedPhoto? next;
    try {
      next = await ref.read(mealPhotoPickerProvider).pick(widget.source);
    } on UnsupportedPhoto {
      if (mounted) setState(() => _problem = PhotoProblem.unreadable);
      return;
    } catch (_) {
      if (mounted) showErrorSnackBar(ScaffoldMessenger.of(context), "Couldn't get a photo. Try again.");
      return;
    }
    if (next == null || !mounted) return;
    setState(() {
      _photo = next!;
      _phase = _Phase.analysing;
      _problem = null;
    });
    _recognize();
  }

  void _remove(int index) {
    final card = _cards[index];
    setState(() => _cards.removeAt(index));
    final messenger = ScaffoldMessenger.of(context);
    // Replace, not queue: with a screen reader these stay up until dismissed.
    messenger.hideCurrentSnackBar();
    final token = ++_undoToken;
    _undoShowing = true;
    messenger
        .showSnackBar(SnackBar(
          duration: const Duration(seconds: 4),
          persist: MediaQuery.accessibleNavigationOf(context),
          content: Text('Removed ${card.label}'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              // The snack bar sits outside the frozen list: mid-log, keep what was sent.
              if (!mounted || _logging) return;
              setState(() => _cards.insert(math.min(index, _cards.length), card));
            },
          ),
        ))
        .closed
        .then((_) {
          if (_undoToken == token) _undoShowing = false;
        });
  }

  /// A card's Search: Log food's search, started from the card's name.
  Future<void> _searchFor(DraftCard card) async {
    final picked = await pickFood(context, mealType: _meal, query: searchNameOf(card.label));
    if (picked == null || !mounted) return;
    setState(() => card.replaceWith(picked));
  }

  Future<void> _add() async {
    final picked = await pickFood(context, mealType: _meal);
    if (picked == null || !mounted) return;
    setState(() => _cards.add(DraftCard.added(picked)));
  }

  Future<void> _log() async {
    final items = logItemsOf(_cards);
    if (items.isEmpty || _logging) return;
    setState(() => _logging = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    // Kept across the await: the screen may be gone when the answer comes.
    final container = ProviderScope.containerOf(context, listen: false);
    final date = widget.date ?? manilaDayOf(ref.read(nutritionClockProvider)());
    final meal = _meal;
    final int n;
    try {
      n = await ref.read(mealPhotoRepositoryProvider).log(
        recognitionId: _recognition!.recognitionId, date: date, mealType: meal, items: items,
      );
    } catch (e) {
      if (e is ApiException && e.code == 'ALREADY_LOGGED') {
        // An earlier Log reached the server but its answer was lost (a
        // timeout, a dropped connection): the meal is logged, as sent then.
        _logged(container, messenger, navigator, items.length, meal);
        return;
      }
      // The log is all or nothing, but the server may have saved it before
      // the answer was lost: Nutrition reloads its day to show the truth.
      container.invalidate(nutritionDayProvider);
      if (!mounted) return;
      setState(() => _logging = false);
      // The list stays as it was, so Log can be tried again.
      showErrorSnackBar(messenger, describeError(e));
      return;
    }
    _logged(container, messenger, navigator, n, meal);
  }

  /// The meal is logged: Nutrition and Recent reload, the screen closes,
  /// and a snack bar says how many items went to which meal.
  void _logged(ProviderContainer container, ScaffoldMessengerState messenger, NavigatorState navigator, int n, String meal) {
    container.invalidate(nutritionDayProvider);
    container.invalidate(recentFoodsProvider);
    _undoShowing = false;
    if (mounted) navigator.pop(true);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text('Logged $n ${n == 1 ? 'item' : 'items'} to ${mealLabel(meal).toLowerCase()}')));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final toLog = logItemsOf(_cards).length;
    return PopScope(
      // Leaving mid-log would hide whether the meal was saved.
      canPop: !_logging,
      child: Scaffold(
        backgroundColor: t.bg,
        bottomNavigationBar: _phase != _Phase.confirm
            ? null
            : SafeArea(
                minimum: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: FsButton(
                  key: const Key('snap.log'),
                  label: logButtonLabel(toLog),
                  busy: _logging,
                  onPressed: toLog == 0 ? null : _log,
                ),
              ),
        body: ListView(
          padding: EdgeInsets.zero,
          children: [
            _PhotoHeader(photo: _photo, onBack: () => Navigator.of(context).maybePop()),
            // Mid-log the list is frozen: what is sent is what the user sees,
            // and no search can open over the screen that is about to close.
            AbsorbPointer(
              absorbing: _logging,
              child: switch (_phase) {
                _Phase.analysing => _analysing(context),
                _Phase.failed => _failed(context),
                _Phase.confirm => _confirm(context),
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _analysing(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
    child: Column(
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Semantics(
          key: const Key('snap.analysing'),
          liveRegion: true,
          child: Text('Looking at your meal…', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
        ),
        const SizedBox(height: 8),
        TextButton(
          key: const Key('snap.cancel'),
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );

  Widget _failed(BuildContext context) {
    final problem = _problem!;
    final again = switch (problem) {
      PhotoProblem.noFood || PhotoProblem.unreadable => FsButton(
        key: const Key('snap.retake'),
        label: widget.source == PhotoSource.camera ? 'Retake' : 'Choose another photo',
        onPressed: _retake,
      ),
      PhotoProblem.unavailable => FsButton(key: const Key('snap.retry'), label: 'Try again', onPressed: _tryAgain),
      PhotoProblem.limit => null,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            key: const Key('snap.error'),
            liveRegion: true,
            child: Text(photoProblemText[problem]!, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
          ),
          const SizedBox(height: 20),
          if (again != null) ...[again, const SizedBox(height: 10)],
          FsButton(
            key: const Key('snap.searchInstead'),
            label: 'Search instead',
            kind: again == null ? FsButtonKind.primary : FsButtonKind.secondary,
            onPressed: () => widget.onSearchInstead(context, _meal),
          ),
        ],
      ),
    );
  }

  Widget _confirm(BuildContext context) {
    final t = context.fs;
    final note = TextStyle(color: t.text2, fontSize: 12, height: 1.5);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ExcludeSemantics(child: Icon(Icons.auto_awesome, size: 16, color: t.accentText)),
              const SizedBox(width: 8),
              const Expanded(child: FsEyebrow('AI suggests · check before logging', maxLines: 3)),
            ],
          ),
          const SizedBox(height: 16),
          Text('Meal', style: TextStyle(color: t.text2, fontSize: 12)),
          const SizedBox(height: 6),
          FsTapRoom(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in mealTypes)
                  FsChip(key: Key('snap.meal.$m'), label: mealLabel(m), selected: _meal == m, onTap: () => setState(() => _meal = m)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_cards.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('Nothing left to log. Add an item to log this meal.', style: TextStyle(color: t.text2)),
            ),
          for (final (i, card) in _cards.indexed) ...[
            // Keyed by the card, not its place: after ✕ or Undo the other
            // cards move rather than take on a neighbour's food, so no live
            // portion line changes its text and gets read out again.
            KeyedSubtree(
              key: ObjectKey(card),
              child: card.isUnlisted
                  ? PhotoUnlistedCard(index: i, card: card, onSearch: () => _searchFor(card), onRemove: () => _remove(i))
                  : PhotoItemCard(
                      index: i,
                      card: card,
                      onSwap: (f) => setState(() => card.replaceWith(f)),
                      onSearch: () => _searchFor(card),
                      onServings: (s) => setState(() => card.setServings(s)),
                      onRemove: () => _remove(i),
                    ),
            ),
            const SizedBox(height: 10),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('snap.add'),
              onPressed: _add,
              icon: const Icon(Icons.add),
              label: const Text('Add an item'),
            ),
          ),
          const SizedBox(height: 8),
          PhotoTotalCard(totals: draftTotals(_cards)),
          const SizedBox(height: 12),
          Text('Estimates only — review each item and portion before logging.', textAlign: TextAlign.center, style: note),
          const SizedBox(height: 4),
          Text("Your photo is only used to recognise the food and isn't saved.", textAlign: TextAlign.center, style: note),
          if (_cards.any((c) => c.food?.showsFatsecret ?? false)) const FatsecretAttribution(),
        ],
      ),
    );
  }
}

/// The photo across the top, with ‹ back and the Pro tag over it.
class _PhotoHeader extends StatelessWidget {
  const _PhotoHeader({required this.photo, required this.onBack});

  final PickedPhoto photo;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final top = MediaQuery.paddingOf(context).top;
    final height = 200 + top;
    return Stack(
      children: [
        Semantics(
          image: true,
          label: 'Your meal photo',
          child: Image.memory(
            photo.bytes,
            key: const Key('snap.photo'),
            height: height,
            width: double.infinity,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            excludeFromSemantics: true,
            // A photo that won't decode still leaves the screen usable.
            errorBuilder: (_, _, _) => Container(height: height, color: t.surface2),
          ),
        ),
        Positioned(
          top: top + 8,
          left: 12,
          child: Material(
            color: t.bg.withValues(alpha: 0.75),
            shape: const CircleBorder(),
            child: IconButton(
              key: const Key('snap.back'),
              tooltip: 'Back',
              color: t.text,
              icon: const Icon(Icons.chevron_left),
              onPressed: onBack,
            ),
          ),
        ),
        Positioned(top: top + 18, right: 16, child: const FsTag('Pro')),
      ],
    );
  }
}
