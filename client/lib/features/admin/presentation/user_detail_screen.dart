import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/fs_kit.dart';
import '../../pro/domain/pro_status.dart' show formatProDate;
import '../domain/admin_format.dart';
import '../domain/admin_models.dart';
import 'providers.dart';
import 'widgets/admin_widgets.dart';

/// One trainee's account, opened from the Users list: account information
/// only (no body, food, workouts or health answers), and the one thing an
/// admin can do to it, suspend or reinstate.
class UserDetailScreen extends ConsumerStatefulWidget {
  const UserDetailScreen({super.key, required this.userId});

  final int userId;

  @override
  ConsumerState<UserDetailScreen> createState() => _UserDetailScreenState();
}

class _UserDetailScreenState extends ConsumerState<UserDetailScreen> {
  /// The account as the last suspend or reinstate answered it, which is
  /// newer than the one the page loaded with.
  AdminUserDetail? _changed;
  bool _busy = false;

  Future<void> _suspend(AdminUserDetail user) async {
    final firstName = user.fullName.trim().split(RegExp(r'\s+')).first;
    final confirmed = await confirmDestructive(
      context,
      keyPrefix: 'admin.suspend',
      title: 'Suspend $firstName?',
      message:
          "They're signed out on every phone and can't sign in until you "
          'reinstate them. Their data is kept.',
      action: 'Suspend',
      cancel: 'Keep',
    );
    if (!confirmed || !mounted) return;
    await _run(
      () => ref.read(adminRepositoryProvider).suspend(user.id),
      done: 'Account suspended.',
    );
  }

  Future<void> _reinstate(AdminUserDetail user) => _run(
    () => ref.read(adminRepositoryProvider).reinstate(user.id),
    done: 'Account reinstated.',
  );

  Future<void> _run(
    Future<AdminUserDetail> Function() call, {
    required String done,
  }) async {
    if (_busy) return;
    // Held from here: the list is refreshed even if this page is left
    // while the call runs, when `ref` can no longer be used.
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() => _busy = true);
    AdminUserDetail? changed;
    String message;
    try {
      changed = await call();
      message = done;
    } catch (error) {
      message = userMessage(error);
    }
    // The list's tags and filters are out of date either way: a failure
    // may mean the trainee is gone or was changed by another admin.
    container.invalidate(adminUsersProvider);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (changed != null) _changed = changed;
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final loaded = ref.watch(adminUserProvider(widget.userId));

    return Scaffold(
      appBar: AppBar(),
      body: loaded.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => FsRetry(
          fullScreen: true,
          message: userMessage(error),
          buttonKey: const Key('admin.user.retry'),
          onRetry: () => ref.invalidate(adminUserProvider(widget.userId)),
        ),
        data: (user) => _page(_changed ?? user),
      ),
    );
  }

  Widget _page(AdminUserDetail user) {
    final t = context.fs;
    final today = ref.watch(adminTodayProvider);
    final active = lastActiveLabel(user.lastActiveOn, today);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        Row(
          children: [
            InitialsAvatar(user.fullName),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      user.fullName,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  Text(
                    user.email,
                    style: TextStyle(fontSize: 13, color: t.text2),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (user.suspended) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: StatusTag('Suspended', color: t.red),
          ),
        ],
        const SizedBox(height: 16),
        FsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (i, line) in [
                joinedLabel(user.joinedOn),
                'Signs in with: ${_methods(user.signInMethods)}',
                'Email verified: ${user.emailVerified ? 'Yes' : 'No'}',
                active[0].toUpperCase() + active.substring(1),
                _proLine(user),
              ].indexed) ...[
                if (i > 0) const SizedBox(height: 10),
                Text(
                  line,
                  style: TextStyle(fontSize: 13.5, height: 1.4, color: t.text),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        if (user.suspended)
          FsButton(
            key: const Key('admin.user.reinstate'),
            label: 'Reinstate account',
            busy: _busy,
            onPressed: () => _reinstate(user),
          )
        else
          // The spec's red outline around the kit's red ghost button: the
          // border says "a button" as the secondary one's does, in red.
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(FsRadius.pill),
              border: Border.all(color: t.red),
            ),
            child: FsButton(
              key: const Key('admin.user.suspend'),
              label: 'Suspend account',
              kind: FsButtonKind.ghost,
              danger: true,
              busy: _busy,
              onPressed: () => _suspend(user),
            ),
          ),
      ],
    );
  }
}

/// "Email and password", "Google", or both, in that order.
String _methods(List<String> methods) => [
  if (methods.contains('password')) 'Email and password',
  if (methods.contains('google')) 'Google',
].join(', ');

/// "Pro until 5 Dec 2026", "Pro (granted)" or "Free".
String _proLine(AdminUserDetail user) {
  if (!user.isPro) return 'Free';
  if (user.proSource == 'granted') return 'Pro (granted)';
  final until = user.proUntil;
  return until == null ? 'Pro' : 'Pro until ${formatProDate(until)}';
}
