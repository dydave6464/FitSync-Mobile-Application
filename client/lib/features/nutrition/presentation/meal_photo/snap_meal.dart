import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/app_settings.dart';
import '../../../../core/theme.dart';
import '../../../../core/widgets/fs_kit.dart';
import '../../../pro/presentation/pro_screen.dart';
import '../../../profile/presentation/providers.dart' show profileProvider;
import '../../data/meal_photo_picker.dart';
import '../error_snack_bar.dart';
import 'capture_choice_sheet.dart';
import 'meal_photo_screen.dart';
import 'providers.dart';

/// Snap a meal from either door. A free account sees the Pro screen; a Pro
/// one picks camera or library, then the photo screen. True once a meal was
/// logged (Log food then closes as well). A null [mealType] opens the
/// confirm list with no meal picked.
Future<bool> startSnapMeal(
  BuildContext context,
  WidgetRef ref, {
  required String? mealType,
  String? date,
  required void Function(BuildContext context, String? mealType) onSearchInstead,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  bool pro;
  try {
    pro = (await ref.read(profileProvider.future)).isPremium;
  } catch (_) {
    // No profile to go by (offline, a timeout): let the server decide. A
    // free account's photo is refused with PRO_REQUIRED, which the photo
    // screen turns into the Pro screen; a Pro one is not sent to the
    // purchase page as if it had lost Pro.
    pro = true;
  }
  if (!context.mounted) return false;
  if (!pro) {
    await openProScreen(context);
    return false;
  }
  final captured = await _capture(context, ref, messenger);
  if (captured == null || !context.mounted) return false;
  final logged = await Navigator.of(context).push<bool>(MaterialPageRoute(
    builder: (_) => MealPhotoScreen(
      photo: captured.photo,
      source: captured.source,
      mealType: mealType,
      date: date,
      onSearchInstead: onSearchInstead,
    ),
  ));
  return logged == true;
}

/// Camera or library. A refused camera offers Settings or the library; a
/// photo that isn't a JPEG or PNG, or a picker failure, says so. Null when
/// the user backed out or nothing usable came back.
Future<({PickedPhoto photo, PhotoSource source})?> _capture(
  BuildContext context,
  WidgetRef ref,
  ScaffoldMessengerState messenger,
) async {
  var source = await showCaptureChoiceSheet(context);
  if (source == null || !context.mounted) return null;
  final picker = ref.read(mealPhotoPickerProvider);
  final openSettings = ref.read(appSettingsOpenerProvider);
  // At most twice: the camera, then -- if it was refused -- the library,
  // which never raises CameraAccessDenied.
  while (true) {
    try {
      final photo = await picker.pick(source!);
      return photo == null ? null : (photo: photo, source: source);
    } on CameraAccessDenied {
      if (!context.mounted) return null;
      final useLibrary = await showCameraDeniedDialog(context, openSettings: openSettings);
      if (!useLibrary || !context.mounted) return null;
      source = PhotoSource.library;
    } on UnsupportedPhoto {
      showErrorSnackBar(messenger, "Couldn't read this photo. Try another one.");
      return null;
    } catch (_) {
      showErrorSnackBar(messenger, "Couldn't get a photo. Try again.");
      return null;
    }
  }
}

/// The Nutrition tab's door, as the prototype draws it: a camera tile,
/// "Snap a meal" with the Pro tag, and what it does.
class SnapMealCard extends StatelessWidget {
  const SnapMealCard({super.key, required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    return FsCard(
      key: const Key('snap.card'),
      small: true,
      accent: true,
      onTap: onTap,
      child: Row(
        children: [
          ExcludeSemantics(
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: t.accent, borderRadius: BorderRadius.circular(FsRadius.sm)),
              child: Icon(Icons.photo_camera_outlined, size: 20, color: t.onAccent),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The tag drops under the title at large text rather than
                // squeezing it.
                Wrap(
                  spacing: 7,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('Snap a meal', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: t.text)),
                    const FsTag('Pro'),
                  ],
                ),
                const SizedBox(height: 2),
                Text('AI suggests the food — you confirm & log.', style: TextStyle(fontSize: 12, color: t.text2)),
              ],
            ),
          ),
          ExcludeSemantics(child: Icon(Icons.chevron_right, size: 18, color: t.accentText)),
        ],
      ),
    );
  }
}

/// Log food's door, beside Add manually: a pill the height of FsButton, in
/// the accent tint, with the Pro tag -- or, [compact], a 52 dp camera button
/// for a narrow phone or large text, where the bar must stay one button tall.
/// Heard as one button either way.
class SnapMealButton extends StatelessWidget {
  const SnapMealButton({super.key, required this.onTap, this.compact = false});

  final VoidCallback onTap;
  final bool compact;

  static const _label = 'Snap a meal';
  static const _labelStyle = TextStyle(fontSize: 15, fontWeight: FontWeight.w700);

  /// The width the labelled pill needs to show "Snap a meal" and its Pro tag
  /// whole, measured with the real text styles and the user's text size:
  /// padding 16, icon 18, gap 8, label, gap 8, tag, padding 16. The tag is
  /// [FsTag]: 10.5 w600 text in 8 px padding and a 1 px border each side.
  static double labelledWidth(BuildContext context) {
    final base = Theme.of(context).textTheme.bodyMedium;
    final label = measureTextWidth(context, _label, base?.merge(_labelStyle) ?? _labelStyle);
    const tagStyle = TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600);
    final tag = measureTextWidth(context, 'Pro', base?.merge(tagStyle) ?? tagStyle) + 8 * 2 + 1 * 2;
    return 16 + 18 + 8 + label + 8 + tag + 16;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fs;
    final icon = Icon(Icons.photo_camera_outlined, size: compact ? 22 : 18, color: t.accentText);
    final Widget button = ConstrainedBox(
      constraints: compact
          ? const BoxConstraints.tightFor(width: 52, height: 52)
          : const BoxConstraints(minHeight: 52),
      child: Material(
        color: t.accentDim,
        shape: StadiumBorder(side: BorderSide(color: t.accentLine)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: compact
              ? Center(child: icon)
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      icon,
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _labelStyle.copyWith(color: t.text),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const FsTag('Pro'),
                    ],
                  ),
                ),
        ),
      ),
    );
    return Semantics(
      button: true,
      label: 'Snap a meal, Pro',
      excludeSemantics: true,
      // excludeSemantics drops the InkWell's action, so the node carries it.
      onTap: onTap,
      // The camera button has no words of its own: a long press says them.
      child: compact ? Tooltip(message: 'Snap a meal (Pro)', child: button) : button,
    );
  }
}

/// How wide [text] is drawn on one line in [style] at the user's text size,
/// rounded up to a whole pixel so a measured fit is never short by a hair.
double measureTextWidth(BuildContext context, String text, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final width = painter.width.ceilToDouble();
  painter.dispose();
  return width;
}
