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
