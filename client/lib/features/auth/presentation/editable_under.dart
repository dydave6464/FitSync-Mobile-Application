import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

/// The first [EditableTextState] in the subtree under [key], or null when the
/// key is not mounted or holds nothing editable.
///
/// The auth screens use it to put the cursor in a particular field: the kit's
/// fields take no focus node, so the field's own editable state is found
/// under a key wrapped around it instead.
EditableTextState? editableUnder(GlobalKey key) {
  EditableTextState? found;
  void visit(Element element) {
    if (found != null) return;
    if (element is StatefulElement && element.state is EditableTextState) {
      found = element.state as EditableTextState;
      return;
    }
    element.visitChildren(visit);
  }

  (key.currentContext as Element?)?.visitChildren(visit);
  return found;
}

/// After a failed check, takes the cursor -- and a screen reader, which then
/// reads the field's name and the message now in its hint -- to the field
/// under [key]. Otherwise nothing is heard after the tap, and a failed check
/// sounds like a hang.
///
/// When that field already has focus (typed in last: a phone does not
/// unfocus a field on an outside tap) focus cannot move, so nothing would be
/// read; [message] is announced instead -- only then, so it is never said
/// twice. Does nothing when nothing editable is under [key].
void focusOrAnnounce(BuildContext context, GlobalKey key, String message) {
  final target = editableUnder(key);
  if (target == null) return;
  if (target.widget.focusNode.hasFocus) {
    SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      Directionality.of(context),
    );
    return;
  }
  target.requestKeyboard();
}
