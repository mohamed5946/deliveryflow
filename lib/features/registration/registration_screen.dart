import 'package:deliveryflow/l10n/gen/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../theme/design_system.dart';
import 'glass_otp.dart';

/// First-launch registration gate: a BLOCKING code screen shown before
/// anything else (home/shell) until the correct registration code is
/// entered. No skip button; the Android back button is disabled here
/// (PopScope canPop: false). Existing installs see it exactly once
/// after updating, then `registered` persists and it never shows again.
///
/// v27.23: glassy OTP entry (video style) — numeric digit boxes, a
/// spinning-circle transition, green success only after a match, red
/// error + full restart on a wrong code. The gate is a courtesy lock
/// against casual users, not a security boundary.
class RegistrationScreen extends ConsumerStatefulWidget {
  const RegistrationScreen({super.key});

  @override
  ConsumerState<RegistrationScreen> createState() =>
      _RegistrationScreenState();
}

class _RegistrationScreenState extends ConsumerState<RegistrationScreen> {
  /// Registration code. Exact match after trimming whitespace.
  static const _validCode = '518424';

  bool _saving = false;

  Future<void> _onVerified() async {
    if (_saving) return;
    setState(() => _saving = true);
    await ref.read(settingsProvider.notifier).update((s) {
      s.registered = true;
      return s;
    });
    if (!mounted) return;
    context.go('/splash');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF0B1220),
        body: Stack(
          children: [
            // Dark glass backdrop: deep navy gradient + soft gold/blue
            // glows (plain gradients, no blur — zero scroll cost).
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF0B1220), Color(0xFF101C33)],
                ),
              ),
            ),
            Positioned(
              top: -60,
              right: -40,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFFD4A017).withValues(alpha: 0.25),
                      const Color(0xFFD4A017).withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -80,
              left: -50,
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Colors.blue.withValues(alpha: 0.22),
                      Colors.blue.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: GlassTokens.screenPadding,
                  child: GlassCard(
                    borderRadius: GlassTokens.radiusL,
                    child: GlassOtpEntry(
                      expectedCode: _validCode,
                      title: l10n.registerTitle,
                      hint: l10n.registerHint,
                      verifyLabel: l10n.confirm,
                      errorLabel: l10n.registerError,
                      successLabel: l10n.otpVerified,
                      onVerified: _onVerified,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
