import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/logging/app_log_service.dart';
import '../../core/providers.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../theme/design_system.dart';

/// v27.2: سجل التشخيص — viewer for the in-app diagnostics log.
///
/// Reads the [AppLogService] box directly (synchronous Hive reads, no
/// polling): entries newest-first, filterable by category, each with
/// its technical detail expandable + selectable so a failure can be
/// screenshotted or copied exactly. Copy-all / share / clear complete
/// the loop that ends blind debugging: reproduce → open log → send.
class DiagnosticsLogScreen extends ConsumerStatefulWidget {
  const DiagnosticsLogScreen({super.key});

  @override
  ConsumerState<DiagnosticsLogScreen> createState() =>
      _DiagnosticsLogScreenState();
}

class _DiagnosticsLogScreenState
    extends ConsumerState<DiagnosticsLogScreen> {
  AppLogCategory? _filter;
  List<AppLogEntry> _entries = const [];
  bool _hasAny = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final svc = ref.read(appLogServiceProvider);
    _hasAny = svc.length > 0;
    _entries = svc.entries(category: _filter);
  }

  void _reload() => setState(_load);

  String _categoryLabel(AppLocalizations l10n, AppLogCategory c) =>
      switch (c) {
        AppLogCategory.notifications => l10n.logCategoryNotifications,
        AppLogCategory.tracking => l10n.logCategoryTracking,
        AppLogCategory.orders => l10n.logCategoryOrders,
        AppLogCategory.share => l10n.logCategoryShare,
        AppLogCategory.system => l10n.logCategorySystem,
        AppLogCategory.settings => l10n.logCategorySettings,
      };

  String _levelLabel(AppLocalizations l10n, AppLogLevel level) =>
      switch (level) {
        AppLogLevel.info => l10n.logLevelInfo,
        AppLogLevel.warn => l10n.logLevelWarn,
        AppLogLevel.error => l10n.logLevelError,
      };

  Color _levelColor(BuildContext context, AppLogLevel level) =>
      switch (level) {
        AppLogLevel.info => LiquidPalette.primaryBlue,
        AppLogLevel.warn => Colors.orange,
        AppLogLevel.error => Theme.of(context).colorScheme.error,
      };

  Future<void> _copyAll() async {
    final svc = ref.read(appLogServiceProvider);
    await Clipboard.setData(ClipboardData(text: svc.exportText()));
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.diagnosticsLogCopied)),
    );
  }

  Future<void> _shareAll() async {
    final svc = ref.read(appLogServiceProvider);
    await SharePlus.instance.share(ShareParams(
      text: svc.exportText(),
      subject: 'DeliveryFlow diagnostics log',
    ));
  }

  Future<void> _clearAll() async {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.diagnosticsLogClearConfirmTitle),
        content: Text(l10n.diagnosticsLogClearConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: scheme.error),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(appLogServiceProvider).clear();
    if (!mounted) return;
    setState(() {
      _filter = null;
      _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final categories = AppLogCategory.values
        .where((c) =>
            ref.read(appLogServiceProvider).entries(category: c).isNotEmpty)
        .toList();

    return GlassScaffold(
      appBar: AppBar(
        title: Text(l10n.diagnosticsLogTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _reload,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: _hasAny ? _copyAll : null,
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: Text(l10n.diagnosticsLogCopy),
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    onPressed: _hasAny ? _shareAll : null,
                    icon: const Icon(Icons.share_rounded, size: 18),
                    label: Text(l10n.diagnosticsLogShare),
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    onPressed: _hasAny ? _clearAll : null,
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: Text(l10n.diagnosticsLogClear),
                    style: TextButton.styleFrom(
                      foregroundColor:
                          Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (categories.length > 1)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  ChoiceChip(
                    label: Text(l10n.diagnosticsLogAll),
                    selected: _filter == null,
                    onSelected: (_) => setState(() {
                      _filter = null;
                      _load();
                    }),
                  ),
                  for (final c in categories) ...[
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: Text(_categoryLabel(l10n, c)),
                      selected: _filter == c,
                      onSelected: (_) => setState(() {
                        _filter = c;
                        _load();
                      }),
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: _entries.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        l10n.diagnosticsLogEmpty,
                        textAlign: TextAlign.center,
                        style: text.bodyMedium?.copyWith(
                          color: text.bodyMedium?.color
                              ?.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: _entries.length,
                    itemBuilder: (context, i) => _LogEntryTile(
                      entry: _entries[i],
                      categoryLabel:
                          _categoryLabel(l10n, _entries[i].category),
                      levelLabel: _levelLabel(l10n, _entries[i].level),
                      levelColor: _levelColor(context, _entries[i].level),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// One log row: time + category + level badge + message, with the
/// technical detail expandable (and selectable) on tap.
class _LogEntryTile extends StatefulWidget {
  const _LogEntryTile({
    required this.entry,
    required this.categoryLabel,
    required this.levelLabel,
    required this.levelColor,
  });

  final AppLogEntry entry;
  final String categoryLabel;
  final String levelLabel;
  final Color levelColor;

  @override
  State<_LogEntryTile> createState() => _LogEntryTileState();
}

class _LogEntryTileState extends State<_LogEntryTile> {
  bool _expanded = false;

  String get _stamp {
    final t = widget.entry.timestamp;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final entry = widget.entry;
    final hasDetail = entry.detail != null && entry.detail!.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: hasDetail
              ? () => setState(() => _expanded = !_expanded)
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.circle, size: 9, color: widget.levelColor),
                  const SizedBox(width: 6),
                  Text(
                    widget.levelLabel,
                    style: text.labelSmall?.copyWith(
                      color: widget.levelColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest
                          .withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      widget.categoryLabel,
                      style: text.labelSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _stamp,
                    style: text.labelSmall?.copyWith(
                      color: text.labelSmall?.color
                          ?.withValues(alpha: 0.55),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (hasDetail)
                    Icon(
                      _expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 18,
                      color: text.labelSmall?.color
                          ?.withValues(alpha: 0.5),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(entry.message, style: text.bodyMedium),
              if (hasDetail && _expanded) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: SelectableText(
                    entry.detail!,
                    style: text.bodySmall?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
