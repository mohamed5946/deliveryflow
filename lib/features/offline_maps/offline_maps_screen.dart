import 'package:flutter/material.dart';
import 'package:deliveryflow/l10n/gen/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/offline_maps/offline_map_service.dart';
import '../../theme/design_system.dart';
import '../../theme/pressable.dart';

/// Offline map regions: list, download new, delete, clear all.
///
/// Entry point: profile ("حسابي") → "الخرائط دون اتصال".
class OfflineMapsScreen extends StatelessWidget {
  const OfflineMapsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final svc = OfflineMapService.instance;

    return GlassScaffold(
      appBar: AppBar(title: Text(l10n.offlineMaps)),
      body: SafeArea(
        child: Padding(
          padding: GlassTokens.screenPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Honest limitation, always visible.
              GlassCard(
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        color: scheme.primary, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        l10n.offlineMapsHint,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (!svc.fmtcReady)
                GlassCard(
                  child: Text(
                    l10n.offlineStorageErrorMsg,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: scheme.error),
                  ),
                ),
              if (!svc.fmtcReady) const SizedBox(height: 12),
              Expanded(
                child: ValueListenableBuilder<List<OfflineRegion>>(
                  valueListenable: svc.regions,
                  builder: (context, regions, _) {
                    if (regions.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            l10n.noOfflineRegions,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ),
                      );
                    }
                    return ListView.separated(
                      itemCount: regions.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 10),
                      itemBuilder: (context, i) =>
                          _regionCard(context, l10n, regions[i]),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              _primaryButton(
                context,
                icon: Icons.download_rounded,
                label: l10n.downloadNewRegion,
                enabled: svc.fmtcReady,
                onTap: () => context.push('/offline-maps/pick'),
              ),
              const SizedBox(height: 8),
              ValueListenableBuilder<List<OfflineRegion>>(
                valueListenable: svc.regions,
                builder: (context, regions, _) {
                  if (regions.isEmpty) return const SizedBox.shrink();
                  return _dangerButton(
                    context,
                    icon: Icons.delete_sweep_outlined,
                    label: l10n.clearAllRegions,
                    onTap: () => _confirmClearAll(context, l10n),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _regionCard(
      BuildContext context, AppLocalizations l10n, OfflineRegion region) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final date = DateFormat('d MMM yyyy', l10n.localeName)
        .format(DateTime.fromMillisecondsSinceEpoch(region.createdAtMs));
    final mb = (region.sizeKiB / 1024).toStringAsFixed(1);
    return GlassCard(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(GlassTokens.radiusS),
            ),
            child: Icon(Icons.map_rounded, color: scheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(region.label,
                    style: text.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(
                  '$date • ${region.tileCount} • $mb م.ب • زوم ${region.minZoom}–${region.maxZoom}',
                  style: text.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Pressable(
            onTap: () => _confirmDelete(context, l10n, region),
            borderRadius: BorderRadius.circular(GlassTokens.radiusS),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(Icons.delete_outline_rounded,
                  color: scheme.error, size: 22),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, AppLocalizations l10n, OfflineRegion region) async {
    final ok = await showGlassDialog<bool>(
      context: context,
      title: Text(l10n.deleteRegion),
      content: Text(l10n.deleteRegionConfirm),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error),
          child: Text(l10n.deleteRegion),
        ),
      ],
    );
    if (ok == true && context.mounted) {
      try {
        await OfflineMapService.instance.deleteRegion(region);
      } catch (_) {
        if (context.mounted) {
          await showGlassDialog<void>(
            context: context,
            title: Text(l10n.offlineStorageError),
            content: Text(l10n.offlineStorageErrorMsg),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          );
        }
      }
    }
  }

  Future<void> _confirmClearAll(
      BuildContext context, AppLocalizations l10n) async {
    final ok = await showGlassDialog<bool>(
      context: context,
      title: Text(l10n.clearAllRegions),
      content: Text(l10n.clearAllRegionsConfirm),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error),
          child: Text(l10n.clearAllRegions),
        ),
      ],
    );
    if (ok == true && context.mounted) {
      await OfflineMapService.instance.clearAll();
    }
  }

  Widget _primaryButton(BuildContext context,
      {required IconData icon,
      required String label,
      required bool enabled,
      required VoidCallback onTap}) {
    final scheme = Theme.of(context).colorScheme;
    return Pressable(
      onTap: enabled ? onTap : () {},
      borderRadius: BorderRadius.circular(GlassTokens.radiusM),
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [scheme.primary, scheme.primary.withValues(alpha: 0.75)],
            ),
            borderRadius: BorderRadius.circular(GlassTokens.radiusM),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white),
              const SizedBox(width: 8),
              Text(label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dangerButton(BuildContext context,
      {required IconData icon,
      required String label,
      required VoidCallback onTap}) {
    final scheme = Theme.of(context).colorScheme;
    return Pressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(GlassTokens.radiusM),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: scheme.error.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(GlassTokens.radiusM),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: scheme.error),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    color: scheme.error, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
