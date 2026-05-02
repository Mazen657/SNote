import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';

import '../../core/theme/app_theme.dart';

/// Shown on the rare path where the native root gate (MainActivity.kt)
/// did not block the app — for example on a platform where the native
/// handler is not available — but the Dart-layer checks subsequently
/// detected root.
///
/// The screen is intentionally non-dismissible:
///   - [PopScope] blocks every back gesture and button.
///   - An auto-exit timer terminates the process after [_exitAfterSeconds].
///   - The "Exit Now" button terminates the process immediately.
///   - No navigation routes lead back to any sensitive UI.
class CompromisedDevicePage extends StatefulWidget {
  const CompromisedDevicePage({super.key});

  @override
  State<CompromisedDevicePage> createState() => _CompromisedDevicePageState();
}

class _CompromisedDevicePageState extends State<CompromisedDevicePage> {
  static const int _exitAfterSeconds = 10;

  late int _countdown;
  Timer?  _timer;

  @override
  void initState() {
    super.initState();
    _countdown = _exitAfterSeconds;
    _startCountdown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _countdown--);
      if (_countdown <= 0) {
        t.cancel();
        _exit();
      }
    });
  }

  void _exit() {
    // Terminate the Flutter process cleanly.
    // SystemNavigator.pop() requests the OS to remove this task; on Android
    // it calls finish() on the activity.
    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Block every back gesture — the user cannot leave this screen
      // except by tapping "Exit Now" or waiting for the countdown.
      canPop: false,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Shield icon.
                Container(
                  width:  88,
                  height: 88,
                  decoration: BoxDecoration(
                    color:  AppTheme.error.withOpacity(0.08),
                    shape:  BoxShape.circle,
                    border: Border.all(
                      color: AppTheme.error.withOpacity(0.45),
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.gpp_bad_outlined,
                    color: AppTheme.error,
                    size:  44,
                  ),
                ),

                const Gap(32),

                // Title.
                Text(
                  'Security Violation',
                  style: Theme.of(context).textTheme.displayMedium?.copyWith(
                        fontSize: 24,
                        color:    AppTheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                  textAlign: TextAlign.center,
                ),

                const Gap(20),

                // Body text.
                Text(
                  'This application cannot run on rooted devices '
                  'for security reasons.\n\n'
                  'Root access allows unauthorised tools to read memory, '
                  'intercept encryption keys, and extract your private notes '
                  'without your knowledge.\n\n'
                  'SNote will now exit.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        height: 1.65,
                        color:  AppTheme.textSecondary,
                      ),
                  textAlign: TextAlign.center,
                ),

                const Gap(36),

                // Auto-exit countdown indicator.
                _CountdownRing(
                  countdown:   _countdown,
                  totalSeconds: _exitAfterSeconds,
                ),

                const Gap(10),

                Text(
                  'Exiting in $_countdown second${_countdown == 1 ? '' : 's'}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                ),

                const Gap(32),

                // Immediate exit button.
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _exit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.error,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Exit Now',
                      style: TextStyle(
                        fontSize:   16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Countdown ring ────────────────────────────────────────────────────────────

class _CountdownRing extends StatelessWidget {
  final int countdown;
  final int totalSeconds;

  const _CountdownRing({
    required this.countdown,
    required this.totalSeconds,
  });

  @override
  Widget build(BuildContext context) {
    final progress = countdown / totalSeconds;
    return SizedBox(
      width:  64,
      height: 64,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value:           progress,
            strokeWidth:     4,
            backgroundColor: AppTheme.surfaceVariant,
            valueColor:      const AlwaysStoppedAnimation<Color>(AppTheme.error),
          ),
          Text(
            '$countdown',
            style: const TextStyle(
              color:      AppTheme.textPrimary,
              fontSize:   20,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}