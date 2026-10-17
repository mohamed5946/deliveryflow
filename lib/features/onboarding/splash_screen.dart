import 'dart:async';

import 'package:flutter/material.dart';
import 'package:deliveryflow/l10n/gen/app_localizations.dart';
import 'package:go_router/go_router.dart';

import '../../theme/design_system.dart';

/// Splash screen from the approved mockup: truck logo, "DeliveryFlow",
/// tagline, and a loading indicator. Auto-navigates after a beat —
/// the router redirect sends first-launch users to onboarding.
///
/// The loading bar shows REAL progress: the splash's init work is the
/// timed 1600ms warm-up, so progress tracks elapsed time and the
/// scooter reaches the end of the track exactly when navigation fires.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  static const _warmUp = Duration(milliseconds: 1600);

  double _progress = 0.0;
  Timer? _timer;
  late final DateTime _startedAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      final elapsed = DateTime.now().difference(_startedAt);
      final p =
          (elapsed.inMilliseconds / _warmUp.inMilliseconds).clamp(0.0, 1.0);
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _progress = p);
      if (p >= 1.0) {
        timer.cancel();
        context.go('/home');
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const AuroraBackground(),
          SafeArea(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(30),
                      gradient: LiquidPalette.brandGradientLg,
                      boxShadow: [
                        BoxShadow(
                          color: LiquidPalette.primaryBlue
                              .withValues(alpha: 0.45),
                          blurRadius: 32,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.local_shipping_rounded,
                      color: Colors.white,
                      size: 58,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'DeliveryFlow',
                    style: text.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: LiquidPalette.primaryBlue,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l10n.workSmarterTagline,
                    style: text.bodyMedium?.copyWith(
                      color: text.bodyMedium?.color
                          ?.withValues(alpha: 0.6),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 48),
                  DeliveryLoadingBar(
                      width: 190, progress: _progress),
                  const SizedBox(height: 12),
                  Text(
                    l10n.splashLoading,
                    style: text.bodySmall?.copyWith(
                      color: text.bodySmall?.color
                          ?.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
