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

/// Brand palette — exact colors from the approved Arabic mockup.
/// Primary Blue #0A84FF (buttons, active states), Sky Blue #5AC8FA
/// (accents, chart highlights), Glass Tint #E5F1FF (light surfaces),
/// Dark #1C1C1E (dark surfaces).
abstract class LiquidPalette {
  static const Color primaryBlue = Color(0xFF0A84FF);
  static const Color skyBlue = Color(0xFF5AC8FA);
  static const Color glassTint = Color(0xFFE5F1FF);
  static const Color darkSurface = Color(0xFF1C1C1E);

  // Exact palette from the approved design brief.
  static const Color backgroundLight = Color(0xFFF5F9FF);
  static const Color textPrimary = Color(0xFF172B4D);
  static const Color textOnDark = Color(0xFFF5F9FF);
  static const Color textSecondary = Color(0xFF7890AD);

  // Legacy accents (kept for compatibility with older screens).
  static const Color primaryPurple = Color(0xFF8B5CF6);
  static const Color accentCyan = Color(0xFF06B6D4);
  static const Color accentViolet = Color(0xFFA855F7);

  static const Color success = Color(0xFF34C759);
  static const Color warning = Color(0xFFFFB020);
  static const Color error = Color(0xFFFF453A);
  static const Color info = Color(0xFF3B82F6);

  /// The signature brand gradient: primary blue → sky blue.
  static const List<Color> brandGradient = [primaryBlue, skyBlue];

  static LinearGradient get brandGradientLg => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: brandGradient,
      );

  /// Soft tinted surface for cards in light mode (mockup glass tint).
  static Color cardTint(bool isDark) =>
      isDark ? darkSurface : glassTint;
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
        child: DeliveryLoadingBar(),
      ),
    );
  }
}

/// Custom loading indicator replacing every CircularProgressIndicator
/// app-wide: a horizontal WHITE track; a delivery-scooter icon rides
/// from LEFT to RIGHT (always LTR, even in the RTL layout) while the
/// portion of the line BEHIND the scooter fills with brand blue
/// (#0A84FF) — white ahead, blue trail behind, reading as real
/// progress. GPU-cheap: a single short repeating animation driving one
/// tiny subtree, no blurs, no per-frame rebuild storms elsewhere.
class DeliveryLoadingBar extends StatefulWidget {
  final double width;
  final double trackHeight;

  const DeliveryLoadingBar({
    super.key,
    this.width = 200,
    this.trackHeight = 6,
  });

  @override
  State<DeliveryLoadingBar> createState() =>
      _DeliveryLoadingBarState();
}

class _DeliveryLoadingBarState extends State<DeliveryLoadingBar>
    with SingleTickerProviderStateMixin {
  static const double _scooterSize = 30;
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Forced left-to-right: Mohamed explicitly wants the scooter to ride
    // from the left edge to the right edge.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        width: widget.width,
        height: 44,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value;
            final rideWidth = widget.width - _scooterSize;
            final scooterX = t * rideWidth;
            // Blue trail covers everything behind the scooter's center.
            final trailWidth = scooterX + _scooterSize / 2;
            return Stack(
              alignment: Alignment.centerLeft,
              children: [
                // White track.
                Container(
                  width: widget.width,
                  height: widget.trackHeight,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(
                        widget.trackHeight / 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
                // Brand-blue trail behind the scooter.
                Container(
                  width: trailWidth,
                  height: widget.trackHeight,
                  decoration: BoxDecoration(
                    color: LiquidPalette.primaryBlue,
                    borderRadius: BorderRadius.circular(
                        widget.trackHeight / 2),
                  ),
                ),
                // The scooter.
                Positioned(
                  left: scooterX,
                  top: (44 - _scooterSize) / 2,
                  child: Container(
                    width: _scooterSize,
                    height: _scooterSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LiquidPalette.brandGradientLg,
                      boxShadow: [
                        BoxShadow(
                          color: LiquidPalette.primaryBlue
                              .withValues(alpha: 0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.delivery_dining_rounded,
                      color: Colors.white,
                      size: 17,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
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
    // Dark mode: keep blobs VERY subtle so the background reads as true
    // near-black #1C1C1E (per the mockup) instead of navy blue — just a
    // hint of brand glow.
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
              opacity: isDark ? 0.14 : 0.55,
            ),
            _blob(
              top: 130,
              right: -90,
              size: 290,
              color: blobs[1],
              opacity: isDark ? 0.10 : 0.5,
            ),
            _blob(
              bottom: -70,
              left: 30,
              size: 310,
              color: blobs[2],
              opacity: isDark ? 0.08 : 0.45,
            ),
            _blob(
              bottom: 90,
              right: 50,
              size: 240,
              color: blobs[3],
              opacity: isDark ? 0.06 : 0.38,
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

/// Circular progress ring (mockup's "تقدم الأسبوع" / "ملخص اليوم").
///
/// Static one-shot render — no continuous animation, GPU-cheap.
class ProgressRing extends StatelessWidget {
  final double progress; // 0..1
  final double size;
  final String centerTop;
  final String centerBottom;
  final double strokeWidth;

  const ProgressRing({
    super.key,
    required this.progress,
    required this.centerTop,
    required this.centerBottom,
    this.size = 120,
    this.strokeWidth = 12,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = Theme.of(context).textTheme;
    final p = progress.clamp(0.0, 1.0);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _RingPainter(
              progress: p,
              strokeWidth: strokeWidth,
              trackColor: isDark
                  ? Colors.white.withValues(alpha: 0.12)
                  : LiquidPalette.primaryBlue.withValues(alpha: 0.15),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                centerTop,
                style: text.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: LiquidPalette.primaryBlue,
                  height: 1.0,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                centerBottom,
                style: text.bodySmall?.copyWith(
                  color: text.bodySmall?.color?.withValues(alpha: 0.65),
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final double strokeWidth;
  final Color trackColor;

  _RingPainter({
    required this.progress,
    required this.strokeWidth,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - strokeWidth) / 2;
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, trackPaint);
    if (progress <= 0) return;
    final arcPaint = Paint()
      ..shader = const LinearGradient(
        colors: LiquidPalette.brandGradient,
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -3.141592653589793 / 2,
      2 * 3.141592653589793 * progress,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.strokeWidth != strokeWidth ||
      old.trackColor != trackColor;
}

/// 7-day week strip (mockup's "الجدول الأسبوعي" mini strip).
/// Sunday-first, like the rest of the app.
class WeekDayStrip extends StatelessWidget {
  final DateTime weekStart; // Sunday of the week
  final DateTime? highlightedDay; // defaults to today if in week
  final ValueChanged<DateTime>? onSelect;

  const WeekDayStrip({
    super.key,
    required this.weekStart,
    this.highlightedDay,
    this.onSelect,
  });

  static const _dayNames = [
    'الأحد',
    'الاثنين',
    'الثلاثاء',
    'الأربعاء',
    'الخميس',
    'الجمعة',
    'السبت',
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = Theme.of(context).textTheme;
    final today = DateTime.now();
    final todayKey = DateTime(today.year, today.month, today.day);
    return Row(
      children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Builder(
              builder: (context) {
                final day = weekStart.add(Duration(days: i));
                final dayKey = DateTime(day.year, day.month, day.day);
                final isToday = dayKey == todayKey;
                final isHighlighted = highlightedDay != null
                    ? dayKey ==
                        DateTime(highlightedDay!.year,
                            highlightedDay!.month, highlightedDay!.day)
                    : isToday;
                final cell = Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  padding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: isHighlighted
                        ? LiquidPalette.brandGradientLg
                        : null,
                    color: isHighlighted
                        ? null
                        : (isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : Colors.white.withValues(alpha: 0.65)),
                    border: Border.all(
                      color: isHighlighted
                          ? Colors.transparent
                          : (isDark
                              ? Colors.white.withValues(alpha: 0.10)
                              : LiquidPalette.primaryBlue
                                  .withValues(alpha: 0.12)),
                    ),
                    boxShadow: isHighlighted
                        ? [
                            BoxShadow(
                              color: LiquidPalette.primaryBlue
                                  .withValues(alpha: 0.35),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : null,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _dayNames[i],
                        style: text.bodySmall?.copyWith(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isHighlighted
                              ? Colors.white
                              : text.bodySmall?.color
                                  ?.withValues(alpha: 0.65),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${day.day}',
                        style: text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: isHighlighted
                              ? Colors.white
                              : (isDark
                                  ? Colors.white
                                  : LiquidPalette.primaryBlue),
                        ),
                      ),
                    ],
                  ),
                );
                if (onSelect == null) return cell;
                return Pressable(
                  onTap: () => onSelect!(dayKey),
                  child: cell,
                );
              },
            ),
          ),
      ],
    );
  }
}

/// Section header with optional action (mockup style).
class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: text.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          if (actionLabel != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                actionLabel!,
                style: const TextStyle(
                  color: LiquidPalette.primaryBlue,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Frosted-glass dialog — the Liquid Glass replacement for [AlertDialog].
///
/// Shows [title], [content] and [actions] inside a blurred glass surface
/// with the signature thin border and soft shadow. Backdrop is dimmed.
class GlassDialog extends StatelessWidget {
  final Widget? title;
  final Widget content;
  final List<Widget> actions;

  const GlassDialog({
    super.key,
    this.title,
    required this.content,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(GlassTokens.radiusL),
        child: BackdropFilter(
          filter: ImageFilter.blur(
              sigmaX: GlassTokens.blurSigma + 4,
              sigmaY: GlassTokens.blurSigma + 4),
          child: Container(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 14),
            decoration: BoxDecoration(
              borderRadius:
                  BorderRadius.circular(GlassTokens.radiusL),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [
                        LiquidPalette.darkSurface
                            .withValues(alpha: 0.92),
                        LiquidPalette.darkSurface
                            .withValues(alpha: 0.82),
                      ]
                    : [
                        Colors.white.withValues(alpha: 0.92),
                        Colors.white.withValues(alpha: 0.78),
                      ],
              ),
              border: Border.all(
                color: Colors.white
                    .withValues(alpha: isDark ? 0.16 : 0.7),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black
                      .withValues(alpha: isDark ? 0.5 : 0.18),
                  blurRadius: 40,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (title != null) ...[
                  DefaultTextStyle(
                    style: text.titleLarge!.copyWith(
                        fontWeight: FontWeight.w800),
                    child: title!,
                  ),
                  const SizedBox(height: 12),
                ],
                content,
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      for (var i = 0; i < actions.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        actions[i],
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows a [GlassDialog] with the standard dimmed barrier.
Future<T?> showGlassDialog<T>({
  required BuildContext context,
  Widget? title,
  required Widget content,
  List<Widget> actions = const [],
  bool barrierDismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (ctx) => GlassDialog(
      title: title,
      content: content,
      actions: actions,
    ),
  );
}
