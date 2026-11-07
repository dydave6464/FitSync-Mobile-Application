import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../onboarding/presentation/edit_scaffold.dart';
import '../domain/admin_models.dart';

/// Adds one of FitSync's own ads ([ad] null) or edits one.
class AdFormScreen extends ConsumerStatefulWidget {
  const AdFormScreen({super.key, this.ad});

  final AdminAd? ad;

  @override
  ConsumerState<AdFormScreen> createState() => _AdFormScreenState();
}

class _AdFormScreenState extends ConsumerState<AdFormScreen> {
  @override
  Widget build(BuildContext context) => EditScaffold(
    title: widget.ad == null ? 'New ad' : 'Edit ad',
    onSave: null,
    child: const SizedBox.shrink(),
  );
}
