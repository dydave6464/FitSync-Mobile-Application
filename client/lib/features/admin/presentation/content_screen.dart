import 'package:flutter/material.dart';

import '../../../core/widgets/fs_kit.dart';
import 'animations_tab.dart';
import 'food_form_screen.dart';
import 'meals_tab.dart';

/// The admin's Content tab: Animations · Meals · Ads, as the prototype
/// draws it. The app bar's + adds a food on Meals and an ad on Ads; there is
/// nothing to add on Animations (exercises are not uploaded here).
class ContentScreen extends StatefulWidget {
  const ContentScreen({super.key});

  @override
  State<ContentScreen> createState() => _ContentScreenState();
}

class _ContentScreenState extends State<ContentScreen> {
  static const _segments = [
    (value: 'animations', label: 'Animations'),
    (value: 'meals', label: 'Meals'),
    (value: 'ads', label: 'Ads'),
  ];

  String _segment = 'animations';

  /// Segments opened at least once: each is built on its first visit and
  /// then kept, with its search, chip and scroll, as the tabs are.
  final _visited = <String>{};

  Widget _body(String segment) => switch (segment) {
    'animations' => const AnimationsTab(),
    'meals' => const MealsTab(),
    _ => const Center(child: Text('Ads')),
  };

  void _addFood() => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const FoodFormScreen()));

  @override
  Widget build(BuildContext context) {
    _visited.add(_segment);
    final addTooltip = switch (_segment) {
      'meals' => 'Add food',
      'ads' => 'Add ad',
      _ => null,
    };

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        'Content',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ),
                  if (addTooltip != null)
                    IconButton(
                      key: const Key('admin.content.add'),
                      icon: const Icon(Icons.add),
                      tooltip: addTooltip,
                      // The ad form comes with the Ads segment itself.
                      onPressed: _segment == 'meals' ? _addFood : null,
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FsSegmented(
              options: _segments,
              selected: _segment,
              onSelected: (value) => setState(() => _segment = value),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: IndexedStack(
              index: _segments.indexWhere((s) => s.value == _segment),
              children: [
                for (final segment in _segments)
                  _visited.contains(segment.value)
                      ? _body(segment.value)
                      : const SizedBox.shrink(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
