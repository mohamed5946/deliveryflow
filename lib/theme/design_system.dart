import 'dart:ui';

import 'package:deliveryflow/l10n/gen/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import 'app_theme.dart';
import 'pressable.dart';

/// Central design tokens for the Liquid Glass aesthetic.
abstract class GlassTokens {
  static const double radiusL = 24;
  static const double radiusM = 18;
  static const double radiusS = 12;

  static const double blurSigma = 12;

  static const EdgeInsets cardPadding =
      EdgeInsets.symmetric(horizontal: 18, vertical: 16);
  static const EdgeInsets screenPadding = EdgeInsets.all(16);
}

/// Brand palette from the Liquid Glass design language.
/// Used for brand-gradient elements (primary buttons, selected nav pill,
/// chart bars, hero accents). Theme presets still drive backgrounds.
abstract class LiquidPalette {
  static const Color primaryBlue = Color(0xFF0EA5E9);
  static const Color primaryPurple = Color(0xFF8B5CF6);
  static const Color accentCyan = Color(0xFF06B6D4);
  static const Color accentViolet = Color(0xFFA855F7);

  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);

  /// The signature brand gradient: blue → purple.
  static const List<Color> brandGradient = [primaryBlue, primaryPurple];

  static LinearGradient get brandGradientLg => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: brandGradient,
      );
}

/// A translucent frosted-glass card.
///
/// Uses [BackdropFilter] blur over a semi-transparent gradient fill with a
/// thin translucent border — the signature Liquid Glass surface.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final VoidCallback? onTap;
  final double blurSigma;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = GlassTokens.cardPadding,
    this.borderRadius = GlassTokens.radiusM,
    this.onTap,
    this.blurSigma = GlassTokens.blurSigma,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [
                      Colors.white.withValues(alpha: 0.10),
                      Colors.white.withValues(alpha: 0.04),
                    ]
                  : [
                      Colors.white.withValues(alpha: 0.75),
                      Colors.white.withValues(alpha: 0.45),
                    ],
            ),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.14)
                  : scheme.primary.withValues(alpha: 0.14),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(borderRadius),
        onTap: onTap,
        child: card,
      ),
    );
  }
}

/// Animated glass button with a soft gradient fill.
class GlassButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final IconData? icon;

  const GlassButton({
    super.key,
    required this.label,
    this.onPressed,
    this.primary = true,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = primary
        ? LiquidPalette.brandGradient
        : (isDark
            ? [Colors.white.withValues(alpha: 0.16), Colors.white.withValues(alpha: 0.08)]
            : [Colors.white.withValues(alpha: 0.9), Colors.white.withValues(alpha: 0.6)]);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(GlassTokens.radiusM),
        gradient: LinearGradient(colors: colors),
        border: Border.all(
          color: Colors.white.withValues(alpha: isDark ? 0.25 : 0.6),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: (primary ? scheme.primary : Colors.black)
                .withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Pressable(
        // InkWell below handles the tap + ripple; Pressable adds the
        // tactile scale even when onPressed is null (disabled button).
        scaleOnly: true,
        child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(GlassTokens.radiusM),
          onTap: onPressed,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon,
                      size: 20,
                      color: primary ? Colors.white : scheme.onSurface),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: primary ? Colors.white : scheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}

/// Small labeled statistic tile used on the dashboard.
class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color accent;

  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accent.withValues(alpha: 0.28),
                  accent.withValues(alpha: 0.10),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: accent.withValues(alpha: 0.25),
                width: 1,
              ),
            ),
            child: Icon(icon, color: accent, size: 22),
          ),
          const SizedBox(height: 12),
          Text(value,
              style: text.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800, height: 1.0)),
          const SizedBox(height: 4),
          Text(label,
              style: text.bodySmall?.copyWith(
                  color:
                      text.bodySmall?.color?.withValues(alpha: 0.75),
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Elegant empty state with an action button.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    scheme.primary.withValues(alpha: 0.25),
                    scheme.secondary.withValues(alpha: 0.12),
                  ],
                ),
              ),
              child: Icon(icon, size: 44, color: scheme.primary),
            ),
            const SizedBox(height: 18),
            Text(title,
                style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(body,
                style: text.bodyMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            GlassButton(label: actionLabel, onPressed: onAction, icon: Icons.add),
          ],
        ),
      ),
    );
  }
}

/// Shimmer-free loading indicator inside a glass surface.
class GlassLoading extends StatelessWidget {
  const GlassLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(48),
        child: CircularProgressIndicator(),
      ),
    );
  }
}

/// Animated aurora background: soft drifting color blobs over a subtle
/// vertical gradient. This is what makes the frosted-glass surfaces read
/// as real glass — they refract the color behind them.
class AuroraBackground extends ConsumerWidget {
  const AuroraBackground({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final presetId =
        ref.watch(settingsProvider.select((s) => s.themePreset));
    final preset = AppThemePreset.of(presetId);
    final blobs = isDark ? preset.auroraDark : preset.auroraLight;
    final bg = isDark ? preset.bgDark : preset.bgLight;
    // Static (no animation) for maximum smoothness: the blobs are pre-blurred
    // once and cached by the RepaintBoundary. The glass cards above still
    // provide depth via their own backdrop blur.
    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [bg[0], bg[1]],
          ),
        ),
        child: Stack(
          children: [
            _blob(
              top: -70,
              left: -70,
              size: 330,
              color: blobs[0],
              opacity: isDark ? 0.38 : 0.55,
            ),
            _blob(
              top: 130,
              right: -90,
              size: 290,
              color: blobs[1],
              opacity: isDark ? 0.32 : 0.5,
            ),
            _blob(
              bottom: -70,
              left: 30,
              size: 310,
              color: blobs[2],
              opacity: isDark ? 0.28 : 0.45,
            ),
            _blob(
              bottom: 90,
              right: 50,
              size: 240,
              color: blobs[3],
              opacity: isDark ? 0.2 : 0.38,
            ),
          ],
        ),
      ),
    );
  }

  Widget _blob({
    double? top,
    double? bottom,
    double? left,
    double? right,
    required double size,
    required Color color,
    required double opacity,
  }) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 72, sigmaY: 72),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: opacity),
          ),
        ),
      ),
    );
  }
}

/// Scaffold with the aurora background behind a transparent body —
/// the standard shell for every screen in the Liquid Glass theme.
class GlassScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;

  const GlassScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.floatingActionButton,
    this.bottomNavigationBar,
  });

  @override
  Widget build(BuildContext context) {
    // Status-bar inset read above the Scaffold: with
    // extendBodyBehindAppBar the body (aurora) bleeds behind the
    // transparent app bar, so the body content is padded to start
    // below it — the title and back button stay exactly where they are,
    // only the black band behind them becomes the page background.
    final topInset = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: Colors.transparent,
      // Extend the aurora body behind the floating nav bar so no black
      // shows around its rounded corners.
      extendBody: true,
      extendBodyBehindAppBar: true,
      appBar: appBar,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
      body: Stack(
        children: [
          const AuroraBackground(),
          if (appBar != null)
            Padding(
              padding:
                  EdgeInsets.only(top: topInset + kToolbarHeight),
              child: body,
            )
          else
            body,
        ],
      ),
    );
  }
}

/// Tiny "يدوي / Manual" pill marking manually entered distances,
/// so reports visually distinguish GPS vs manual values.
class ManualBadge extends StatelessWidget {
  const ManualBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(6),
        border:
            Border.all(color: Colors.amber.withValues(alpha: 0.55)),
      ),
      child: Text(
        l10n.manualBadge,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: Colors.amber.shade800,
        ),
      ),
    );
  }
}

/// Floating frosted-glass bottom navigation bar.
class GlassNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<IconData> icons;
  final List<IconData> selectedIcons;
  final List<String> labels;

  const GlassNavBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.icons,
    required this.selectedIcons,
    required this.labels,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [
                        Colors.white.withValues(alpha: 0.14),
                        Colors.white.withValues(alpha: 0.06),
                      ]
                    : [
                        Colors.white.withValues(alpha: 0.8),
                        Colors.white.withValues(alpha: 0.55),
                      ],
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: isDark ? 0.18 : 0.7),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.12),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                for (var i = 0; i < labels.length; i++) _item(context, i),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _item(BuildContext context, int i) {
    final selected = i == selectedIndex;
    final scheme = Theme.of(context).colorScheme;
    return Pressable(
      onTap: () => onDestinationSelected(i),
      pressedScale: 0.9,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: EdgeInsets.symmetric(
            horizontal: selected ? 16 : 10, vertical: 8),
        decoration: selected
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LiquidPalette.brandGradientLg,
                boxShadow: [
                  BoxShadow(
                    color: LiquidPalette.primaryBlue
                        .withValues(alpha: 0.4),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              )
            : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected ? selectedIcons[i] : icons[i],
              size: 24,
              color: selected ? Colors.white : scheme.onSurface.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 2),
            Text(
              labels[i],
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? Colors.white : scheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
