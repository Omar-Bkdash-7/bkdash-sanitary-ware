import 'dart:async';

import 'package:bkdash_sanitary_ware/core/constants/app_constants.dart';
import 'package:bkdash_sanitary_ware/core/widgets/bkdash_logo.dart';
import 'package:bkdash_sanitary_ware/features/security/presentation/pin_pad.dart';
import 'package:bkdash_sanitary_ware/features/security/presentation/security_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// Creates the PIN on the first run and unlocks the app afterwards.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String _pin = '';

  /// During setup: the PIN typed the first time, waiting for confirmation.
  String? _firstEntry;
  String? _message;
  bool _hasError = false;
  bool _busy = false;
  Timer? _countdown;

  bool get _isSetup =>
      context.read<SecurityController>().status == LockStatus.needsSetup;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncCountdown();
      final security = context.read<SecurityController>();
      if (security.status == LockStatus.locked && security.canUseBiometrics) {
        unawaited(_unlockWithBiometrics());
      }
    });
  }

  @override
  void dispose() {
    _countdown?.cancel();
    super.dispose();
  }

  void _onDigit(int digit) {
    if (_busy || _pin.length >= AppConstants.pinLength) return;
    setState(() {
      _pin += '$digit';
      _hasError = false;
    });
    if (_pin.length == AppConstants.pinLength) unawaited(_submit());
  }

  void _onBackspace() {
    if (_busy || _pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _submit() async {
    final security = context.read<SecurityController>();
    final entered = _pin;
    setState(() => _busy = true);

    if (_isSetup) {
      await _submitSetup(security, entered);
    } else {
      await _submitUnlock(security, entered);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _submitSetup(SecurityController security, String entered) async {
    final first = _firstEntry;
    if (first == null) {
      setState(() {
        _firstEntry = entered;
        _pin = '';
        _message = null;
      });
    } else if (first == entered) {
      await security.createPin(entered);
    } else {
      await HapticFeedback.heavyImpact();
      setState(() {
        _firstEntry = null;
        _pin = '';
        _hasError = true;
        _message = 'الرمزان غير متطابقين، ابدأ من جديد.';
      });
    }
  }

  Future<void> _submitUnlock(
    SecurityController security,
    String entered,
  ) async {
    final result = await security.unlockWithPin(entered);
    if (!mounted) return;
    switch (result) {
      case PinAccepted():
        break; // the gate replaces this screen
      case PinRejected(:final attemptsLeft):
        await HapticFeedback.heavyImpact();
        setState(() {
          _pin = '';
          _hasError = true;
          _message = 'رمز PIN غير صحيح. المحاولات المتبقية: $attemptsLeft';
        });
      case PinBlocked():
        await HapticFeedback.heavyImpact();
        setState(() {
          _pin = '';
          _hasError = true;
          _message = null;
        });
        _syncCountdown();
    }
  }

  Future<void> _unlockWithBiometrics() async {
    if (_busy) return;
    setState(() => _busy = true);
    await context.read<SecurityController>().unlockWithBiometrics();
    if (mounted) setState(() => _busy = false);
  }

  /// Re-draws the screen every second while PIN entry is blocked.
  void _syncCountdown() {
    final security = context.read<SecurityController>();
    if (security.blockRemaining == null) {
      _countdown?.cancel();
      _countdown = null;
      return;
    }
    _countdown ??= Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (context.read<SecurityController>().blockRemaining == null) {
        timer.cancel();
        _countdown = null;
        setState(() => _hasError = false);
      } else {
        setState(() {});
      }
    });
  }

  String _formatRemaining(Duration remaining) {
    final minutes = remaining.inMinutes.toString().padLeft(2, '0');
    final seconds = (remaining.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final security = context.watch<SecurityController>();
    final theme = Theme.of(context);
    final blocked = security.blockRemaining;
    final isSetup = security.status == LockStatus.needsSetup;

    final title = isSetup
        ? (_firstEntry == null ? 'إنشاء رمز PIN' : 'تأكيد رمز PIN')
        : 'أدخل رمز PIN';
    final subtitle = isSetup
        ? (_firstEntry == null
              ? 'اختر رمزاً من ${AppConstants.pinLength} أرقام لحماية بياناتك'
              : 'أعد إدخال الرمز نفسه')
        : 'أدخل الرمز لفتح التطبيق';
    final message = blocked != null
        ? 'تم إيقاف الإدخال مؤقتاً. حاول بعد ${_formatRemaining(blocked)}'
        : _message;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const BkdashLogo(size: 64),
                const SizedBox(height: 28),
                Text(title, style: theme.textTheme.titleLarge),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                PinDots(
                  filled: _pin.length,
                  hasError: _hasError || blocked != null,
                ),
                SizedBox(
                  height: 48,
                  child: Center(
                    child: message == null
                        ? null
                        : Text(
                            message,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                  ),
                ),
                PinPad(
                  enabled: !_busy && blocked == null,
                  onDigit: _onDigit,
                  onBackspace: _onBackspace,
                  onBiometric: !isSetup && security.canUseBiometrics
                      ? () => unawaited(_unlockWithBiometrics())
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
