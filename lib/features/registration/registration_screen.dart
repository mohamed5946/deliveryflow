import 'package:deliveryflow/l10n/gen/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../theme/design_system.dart';

/// First-launch registration gate: a BLOCKING code screen shown before
/// anything else (home/shell) until the correct registration code is
/// entered. No skip button; the Android back button is disabled here
/// (PopScope canPop: false). Existing installs see it exactly once
/// after updating, then `registered` persists and it never shows again.
class RegistrationScreen extends ConsumerStatefulWidget {
  const RegistrationScreen({super.key});

  @override
  ConsumerState<RegistrationScreen> createState() =>
      _RegistrationScreenState();
}

class _RegistrationScreenState extends ConsumerState<RegistrationScreen> {
  /// Registration code. Exact match after trimming whitespace;
  /// case-sensitive.
  static const _validCode = 'MEMO2004\$';

  final _controller = TextEditingController();
  bool _showError = false;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    final entered = _controller.text.trim();
    if (entered != _validCode) {
      setState(() => _showError = true);
      return;
    }
    setState(() {
      _saving = true;
      _showError = false;
    });
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
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // v23: guarantee contrast — white text when the effective background
    // is dark, near-black when it is light.
    final onBg = isDark ? Colors.white : const Color(0xFF111418);

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            const AuroraBackground(),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: GlassTokens.screenPadding,
                  child: GlassCard(
                    borderRadius: GlassTokens.radiusL,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            gradient: LiquidPalette.brandGradientLg,
                            boxShadow: [
                              BoxShadow(
                                color: LiquidPalette.primaryBlue
                                    .withValues(alpha: 0.4),
                                blurRadius: 24,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.vpn_key_rounded,
                            color: Colors.white,
                            size: 38,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          l10n.registerTitle,
                          textAlign: TextAlign.center,
                          style: text.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: onBg,
                          ),
                        ),
                        const SizedBox(height: 20),
                        GlassCard(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 4),
                          child: TextField(
                            controller: _controller,
                            obscureText: true,
                            enableSuggestions: false,
                            autocorrect: false,
                            keyboardType: TextInputType.visiblePassword,
                            textInputAction: TextInputAction.done,
                            textAlign: TextAlign.center,
                            onChanged: (_) {
                              if (_showError) {
                                setState(() => _showError = false);
                              }
                            },
                            onSubmitted: (_) => _submit(),
                            style: text.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              letterSpacing: 2,
                              color: onBg,
                            ),
                            decoration: InputDecoration(
                              hintText: l10n.registerHint,
                              hintStyle: text.bodyMedium?.copyWith(
                                color: scheme.onSurface
                                    .withValues(alpha: 0.45),
                                letterSpacing: 0,
                              ),
                              border: InputBorder.none,
                              prefixIcon: Icon(
                                Icons.lock_outline_rounded,
                                color: scheme.primary,
                              ),
                            ),
                          ),
                        ),
                        if (_showError) ...[
                          const SizedBox(height: 10),
                          Text(
                            l10n.registerError,
                            textAlign: TextAlign.center,
                            style: text.bodyMedium?.copyWith(
                              color: scheme.error,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        GlassButton(
                          label: l10n.confirm,
                          icon: Icons.check_rounded,
                          onPressed: _saving ? null : _submit,
                        ),
                      ],
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
