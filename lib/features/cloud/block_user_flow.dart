// v27.35 blacklist — shared block / unblock confirmation flows.
//
// The swipe Block action on the Management driver list, the Block
// button on the driver detail screen, and the Unblock actions (in
// the Blacklist section and on a blocked driver's detail screen)
// all go through these helpers, so the wording and the guards are
// identical everywhere.
//
// Block is REVERSIBLE and deletes nothing: it only sets the blocked
// flag on the profile. The driver's orders, summaries, adjustments,
// rollups and login lookups are all kept, so unblocking restores him
// fully. Nothing is ever blocked on swipe alone — swipe only reveals
// the action; the confirmation dialog below is the only path to a
// block, and the bin-eats-label button is its confirmation.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/cloud/cloud_providers.dart';
import '../../core/cloud/cloud_types.dart';
import '../../theme/bin_eating_delete_button.dart';
import '../../theme/design_system.dart';

/// Shows the block confirmation dialog for [target] and, on
/// confirmation, blocks him. Returns true only when the block
/// succeeded (callers refresh the dashboard then). Shows a plain
/// snackbar for both outcomes; a failed block never leaves the
/// dialog hanging — the dialog is already closed when it runs.
Future<bool> confirmAndBlockUser({
  required BuildContext context,
  required WidgetRef ref,
  required CloudAccount target,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Block driver?'),
      content: const Text(
        'This driver will not be able to sign in. He will disappear '
        'from the team list, and his salaries will not be counted in '
        'any total.\n\n'
        'His data is kept — unblocking restores him fully. Nothing '
        'is deleted.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        BinEatingDeleteButton(
          key: const ValueKey('managementBlockUserConfirm'),
          label: 'Block',
          onConfirmed: () => Navigator.pop(ctx, true),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;
  final ok =
      await ref.read(cloudAccountProvider.notifier).blockUser(target.uid);
  if (!context.mounted) return ok;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        ok ? 'Driver blocked' : 'Could not block driver',
      ),
    ),
  );
  return ok;
}

/// Shows the unblock confirmation dialog for [target] and, on
/// confirmation, unblocks him. Returns true only when the unblock
/// succeeded (callers refresh the dashboard then).
Future<bool> confirmAndUnblockUser({
  required BuildContext context,
  required WidgetRef ref,
  required CloudAccount target,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Unblock driver?'),
      content: Text(
        '${target.displayName} will be able to sign in again with '
        'his email, with all his data intact, and will rejoin the '
        'team list.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const ValueKey('managementUnblockUserConfirm'),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Unblock'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;
  final ok =
      await ref.read(cloudAccountProvider.notifier).unblockUser(target.uid);
  if (!context.mounted) return ok;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        ok ? 'Driver unblocked' : 'Could not unblock driver',
      ),
    ),
  );
  return ok;
}

/// One place to bump the dashboard refresh signal after a
/// block/unblock, so the team list (and the Blacklist section)
/// refetch immediately.
void bumpManagementRefresh(WidgetRef ref) {
  ref.read(managementRefreshProvider.notifier).state++;
}

/// Small card for one blocked driver in the Blacklist section:
/// name + blocked date + an Unblock button (manager-only by
/// construction — the whole Management screen is manager-only).
class BlockedDriverCard extends ConsumerWidget {
  const BlockedDriverCard({
    super.key,
    required this.account,
    required this.blockedDateLabel,
  });

  final CloudAccount account;
  final String blockedDateLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GlassCard(
      key: ValueKey('managementBlocked-${account.uid}'),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  account.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (blockedDateLabel.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Blocked on $blockedDateLabel',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          GlassButton(
            key: ValueKey('managementUnblock-${account.uid}'),
            label: 'Unblock',
            icon: Icons.lock_open_rounded,
            primary: false,
            onPressed: () async {
              final ok = await confirmAndUnblockUser(
                context: context,
                ref: ref,
                target: account,
              );
              if (ok) bumpManagementRefresh(ref);
            },
          ),
        ],
      ),
    );
  }
}
