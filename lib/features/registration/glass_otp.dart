import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/design_system.dart';

/// Phases of the glassy OTP code entry (v27.23, video style).
///
/// entering → verifying (digits spin in a circle, ≤1s) → success
/// (green check, gate opens) OR error (red X, input cleared, back to
/// entering). Success is shown ONLY after the entered code actually
/// matches [OtpGate.expected] — the spin is a transition, never a
/// faked verification.
enum OtpPhase { entering, verifying, success, error }

/// Pure, unit-testable core of the OTP gate.
///
/// Production code passes the real gate value; tests pass their own
/// dummy values. Nothing here ever logs or prints a code.
class OtpGate {
  const OtpGate(this.expected);

  final String expected;

  int get digitCount => expected.length;

  static String digitsOnly(String input) =>
      input.replaceAll(RegExp(r'[^0-9]'), '');

  bool matches(String entered) => entered.trim() == expected;
}

/// Dark glass OTP entry shared by the registration gate and the
/// Developer Mode gate (v27.23).
///
/// - Digit boxes with a gold accent (video style), numeric keypad,
///   digits-only input.
/// - On submit: digits fly into a spinning circle for ~900ms, then
///   green success (and [onVerified]) when the code matches, or a red
///   error followed by a full restart (input cleared) when it does not.
/// - [onCancel], when given, renders a cancel action (the Developer
///   Mode dialog has one; the blocking registration gate does not).
class GlassOtpEntry extends StatefulWidget {
  const GlassOtpEntry({
    super.key,
    required this.expectedCode,
    required this.title,
    required this.hint,
    required this.verifyLabel,
    required this.errorLabel,
    required this.successLabel,
    required this.onVerified,
    this.onWrongAttempt,
    this.onCancel,
    this.cancelLabel,
  });

  final String expectedCode;
  final String title;
  final String hint;
  final String verifyLabel;
  final String errorLabel;
  final String successLabel;
  final VoidCallback onVerified;
  final VoidCallback? onWrongAttempt;
  final VoidCallback? onCancel;
  final String? cancelLabel;

  @override
  State<GlassOtpEntry> createState() => _GlassOtpEntryState();
}

class _GlassOtpEntryState extends State<GlassOtpEntry>
    with SingleTickerProviderStateMixin {
  static const _gold = Color(0xFFD4A017);

  late final OtpGate _gate = OtpGate(widget.expectedCode);
  final _controller = TextEditingController();
  final _focus = FocusNode();
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  OtpPhase _phase = OtpPhase.entering;
  int _attempt = 0;

  String get _digits => _controller.text;

  @override
  void initState() {
    super.initState();
    // Post-frame focus: autofocus alone fires before the route is
    // fully settled on some devices and the request is then lost
    // with no retry. Re-requesting after the first frame is the
    // retry that actually opens the keyboard.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _phase == OtpPhase.entering) {
        _requestKeyboardFocus();
      }
    });
  }

  /// Focus the input and force the keyboard open.
  ///
  /// Some OEM keyboards ignore a focus request for a transparent
  /// field, so asking the text-input channel directly is the
  /// fallback that actually shows the IME. The try/catch only
  /// covers environments without an IME channel (widget tests).
  void _requestKeyboardFocus() {
    _focus.requestFocus();
    SystemChannels.textInput.invokeMethod('TextInput.show').catchError(
      (_) {},
    );
  }

  @override
  void dispose() {
    _spin.dispose();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    if (_phase != OtpPhase.entering) return;
    if (_digits.length != _gate.digitCount) return;
    final attempt = ++_attempt;
    final correct = _gate.matches(_digits);
    setState(() => _phase = OtpPhase.verifying);
    _spin.repeat();
    // Transition only: the result below follows the comparison above.
    Future.delayed(const Duration(milliseconds: 900), () {
      if (!mounted || attempt != _attempt) return;
      _spin.stop();
      if (correct) {
        setState(() => _phase = OtpPhase.success);
        Future.delayed(const Duration(milliseconds: 700), () {
          if (!mounted || attempt != _attempt) return;
          widget.onVerified();
        });
      } else {
        widget.onWrongAttempt?.call();
        setState(() => _phase = OtpPhase.error);
        Future.delayed(const Duration(milliseconds: 1000), () {
          if (!mounted || attempt != _attempt) return;
          _controller.clear();
          setState(() => _phase = OtpPhase.entering);
        });
      }
    });
  }

  Widget _digitBoxes() {
    final boxes = <Widget>[];
    for (var i = 0; i < _gate.digitCount; i++) {
      final filled = i < _digits.length;
      boxes.add(Container(
        width: 52,
        height: 64,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.white.withValues(alpha: 0.08),
          border: Border.all(
            color: filled
                ? _gold.withValues(alpha: 0.9)
                : Colors.white.withValues(alpha: 0.25),
            width: filled ? 2 : 1,
          ),
        ),
        child: Text(
          filled ? _digits[i] : '',
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ));
    }
    // v27.34: the boxes row IS the input. The old design hid a 1px,
    // opacity-0 TextField below the boxes and relied on a programmatic
    // focus request from the boxes' tap handler — on some devices
    // (field report: Infinix/XOS) the IME never opened for that
    // invisible field, so the boxes behaved as decoration only.
    // Now a real, normally-sized TextField covers the whole boxes
    // row: taps land on a genuine editable field (the reliable path
    // to opening the keyboard), while transparent text + hidden
    // cursor keep the boxes as the visible UI. Tapping the row also
    // re-requests focus with the forced keyboard-show fallback.
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _requestKeyboardFocus,
      child: SizedBox(
        height: 64,
        child: Stack(
          alignment: Alignment.center,
          children: [
            IgnorePointer(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < boxes.length; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    boxes[i],
                  ],
                ],
              ),
            ),
            Positioned.fill(
              child: TextField(
                controller: _controller,
                focusNode: _focus,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(_gate.digitCount),
                ],
                showCursor: false,
                enableInteractiveSelection: false,
                style: const TextStyle(color: Colors.transparent),
                decoration:
                    const InputDecoration(border: InputBorder.none),
                onChanged: (_) {
                  setState(() {});
                  if (_digits.length == _gate.digitCount) _submit();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The video's signature moment: entered digits arranged in a
  /// spinning circle while verification "runs".
  Widget _spinningCircle() {
    const radius = 46.0;
    return SizedBox(
      width: 132,
      height: 132,
      child: RotationTransition(
        turns: _spin,
        child: Stack(
          alignment: Alignment.center,
          children: [
            for (var i = 0; i < _digits.length; i++)
              Positioned(
                left: 66 +
                    radius * math.cos(2 * math.pi * i / _digits.length) -
                    13,
                top: 66 +
                    radius * math.sin(2 * math.pi * i / _digits.length) -
                    16,
                child: Text(
                  _digits[i],
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: _gold,
                  ),
                ),
              ),
            const Icon(Icons.lock_outline_rounded,
                color: Colors.white70, size: 28),
          ],
        ),
      ),
    );
  }

  Widget _resultIcon() {
    final ok = _phase == OtpPhase.success;
    return AnimatedScale(
      scale: 1.0,
      duration: const Duration(milliseconds: 250),
      child: Container(
        width: 84,
        height: 84,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: (ok ? Colors.green : Colors.red).withValues(alpha: 0.15),
          border: Border.all(
            color: ok ? Colors.green : Colors.red,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: (ok ? Colors.green : Colors.red)
                  .withValues(alpha: 0.45),
              blurRadius: 24,
            ),
          ],
        ),
        child: Icon(
          ok ? Icons.check_rounded : Icons.close_rounded,
          color: ok ? Colors.green : Colors.red,
          size: 44,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.vpn_key_rounded, color: _gold, size: 40),
        const SizedBox(height: 16),
        Text(
          widget.title,
          textAlign: TextAlign.center,
          style: text.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          widget.hint,
          textAlign: TextAlign.center,
          style: text.bodyMedium?.copyWith(color: Colors.white70),
        ),
        const SizedBox(height: 24),
        if (_phase == OtpPhase.verifying)
          Center(child: _spinningCircle())
        else if (_phase == OtpPhase.success ||
            _phase == OtpPhase.error) ...[
          Center(child: _resultIcon()),
          const SizedBox(height: 14),
          Text(
            _phase == OtpPhase.success
                ? widget.successLabel
                : widget.errorLabel,
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(
              color: _phase == OtpPhase.success ? Colors.green : Colors.red,
              fontWeight: FontWeight.w700,
            ),
          ),
        ] else ...[
          _digitBoxes(),
          const SizedBox(height: 20),
          GlassButton(
            label: widget.verifyLabel,
            icon: Icons.check_rounded,
            onPressed:
                _digits.length == _gate.digitCount ? _submit : null,
          ),
        ],
        if (widget.onCancel != null && _phase == OtpPhase.entering) ...[
          const SizedBox(height: 8),
          TextButton(
            onPressed: widget.onCancel,
            child: Text(widget.cancelLabel ?? ''),
          ),
        ],
      ],
    );
  }
}
