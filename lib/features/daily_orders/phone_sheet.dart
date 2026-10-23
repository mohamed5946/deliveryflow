import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:deliveryflow/l10n/gen/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/design_system.dart';
import '../../theme/top_snack_bar.dart';

/// Customer phone bottom sheet (mockup style): shows the full number,
/// with "اتصال" (call) and "نسخ الرقم" (copy) actions.
Future<void> showCustomerPhoneSheet(
    BuildContext context, String phone) {
  final l10n = AppLocalizations.of(context);
  final text = Theme.of(context).textTheme;
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: GlassCard(
          borderRadius: GlassTokens.radiusL,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color: text.bodySmall?.color
                          ?.withValues(alpha: 0.25) ??
                      Colors.grey.withValues(alpha: 0.4),
                ),
              ),
              const SizedBox(height: 14),
              const Icon(Icons.phone_rounded,
                  size: 40, color: LiquidPalette.primaryBlue),
              const SizedBox(height: 8),
              SelectableText(
                phone,
                textDirection: TextDirection.ltr,
                style: text.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: GlassButton(
                      label: l10n.call,
                      icon: Icons.call_rounded,
                      onPressed: () {
                        Navigator.pop(ctx);
                        launchUrl(
                            Uri(scheme: 'tel', path: phone));
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GlassButton(
                      label: l10n.copyNumber,
                      primary: false,
                      icon: Icons.copy_rounded,
                      onPressed: () {
                        Clipboard.setData(
                            ClipboardData(text: phone));
                        Navigator.pop(ctx);
                        showTopSnackBar(context, l10n.copied);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
