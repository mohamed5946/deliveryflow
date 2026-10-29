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
///   digits-only input. v27.35: each box is its OWN real TextField —
///   v27.34's single overlay field rendered as one rectangle and the
///   boxes disappeared, so it was rejected on the device.
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
  // v27.35: one REAL input per box. v27.34 covered the boxes row
  // with a single transparent field and the field rendered as one
  // big rectangle — the boxes disappeared and the user rightly
  // rejected it. Each box below is its own TextField, so tapping
  // any box focuses a genuine editable field and opens the numeric
  // keyboard; digits then fill the boxes sequentially in order.
  late final List<TextEditingController> _controllers =
      List.generate(_gate.digitCount, (_) => TextEditingController());
  late final List<FocusNode> _focusNodes =
      List.generate(_gate.digitCount, (_) => FocusNode());
  bool _updating = false;
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  OtpPhase _phase = OtpPhase.entering;
  int _attempt = 0;

  String get _digits =>
      _controllers.map((c) => c.text).join();

  bool get _allFilled =>
      _controllers.every((c) => c.text.isNotEmpty);

  int get _firstEmptyIndex =>
      _controllers.indexWhere((c) => c.text.isEmpty);

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < _focusNodes.length; i++) {
      final index = i;
      // Gold highlight follows the focused box.
      _focusNodes[i].addListener(() {
        if (mounted) setState(() {});
      });
      // Backspace on an EMPTY box deletes the previous digit and
      // moves focus back (the classic OTP-field behaviour). Without
      // this, backspace on an empty box does nothing at all.
      _focusNodes[i].onKeyEvent = (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.backspace &&
            _controllers[index].text.isEmpty &&
            index > 0) {
          _controllers[index - 1].clear();
          _focusBox(index - 1);
          setState(() {});
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      };
    }
    // Post-frame focus: autofocus alone fires before the route is
    // fully settled on some devices and the request is then lost
    // with no retry. Re-requesting after the first frame is the
    // retry that actually opens the keyboard.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _phase == OtpPhase.entering) {
        _focusBox(0);
      }
    });
  }

  /// Focus box [index] and force the keyboard open.
  ///
  /// Some OEM keyboards ignore a focus request on its own, so asking
  /// the text-input channel directly is the fallback that actually
  /// shows the IME. The try/catch only covers environments without
  /// an IME channel (widget tests).
  void _focusBox(int index) {
    if (index < 0 || index >= _focusNodes.length) return;
    _focusNodes[index].requestFocus();
    SystemChannels.textInput.invokeMethod('TextInput.show').catchError(
      (_) {},
    );
  }

  @override
  void dispose() {
    _spin.dispose();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _clearAll() {
    for (final c in _controllers) {
      c.clear();
    }
  }

  void _onBoxChanged(int index, String value) {
    if (_phase != OtpPhase.entering || _updating) return;
    // Each box holds exactly one digit: a paste or an IME composing
    // more than one char keeps only the last digit typed.
    final digit = value.isEmpty ? '' : value[value.length - 1];
    if (value != digit) {
      _updating = true;
      _controllers[index].text = digit;
      _updating = false;
    }
    setState(() {});
    if (digit.isEmpty) return; // Deletion: stay on this box.
    if (_allFilled) {
      _submit();
      return;
    }
    if (index + 1 < _controllers.length) _focusBox(index + 1);
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
          _clearAll();
          setState(() => _phase = OtpPhase.entering);
          _focusBox(0);
        });
      }
    });
  }

  Widget _digitBoxes() {
    final boxes = <Widget>[];
    for (var i = 0; i < _gate.digitCount; i++) {
      final index = i;
      final filled = _controllers[i].text.isNotEmpty;
      final focused = _focusNodes[i].hasFocus;
      final highlighted = filled || focused;
      boxes.add(Container(
        width: 52,
        height: 64,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.white.withValues(alpha: 0.08),
          border: Border.all(
            color: highlighted
                ? _gold.withValues(alpha: 0.9)
                : Colors.white.withValues(alpha: 0.25),
            width: highlighted ? 2 : 1,
          ),
        ),
        // Each box IS a real TextField (v27.35): tapping it focuses
        // a genuine editable field, which is the reliable path to
        // opening the keyboard. There is no single rectangular
        // field, no overlay strip, and no hidden-field trick.
        child: TextField(
          key: ValueKey('otpBox-$i'),
          controller: _controllers[i],
          focusNode: _focusNodes[i],
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
          showCursor: false,
          enableInteractiveSelection: false,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(1),
          ],
          decoration: const InputDecoration(
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
          onTap: () {
            // Sequential fill: tapping AHEAD of the next empty box
            // jumps back to that box, so digits always land one
            // after another. Tapping an earlier (filled) box keeps
            // focus there so it can be edited.
            final firstEmpty = _firstEmptyIndex;
            if (firstEmpty != -1 && index > firstEmpty) {
              _focusBox(firstEmpty);
            }
          },
          onChanged: (value) => _onBoxChanged(index, value),
        ),
      ));
    }
    return Row(
      key: const ValueKey('otpBoxesRow'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < boxes.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          boxes[i],
        ],
      ],
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
