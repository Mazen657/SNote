import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../core/theme/app_theme.dart';

/// Shown when root or jailbreak is detected.
/// There is no bypass — the user cannot proceed.
class CompromisedDevicePage extends StatelessWidget {
  const CompromisedDevicePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppTheme.error.withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: AppTheme.error.withOpacity(0.4), width: 1.5),
                ),
                child: const Icon(Icons.gpp_bad_outlined,
                    color: AppTheme.error, size: 40),
              ),
              const Gap(32),
              Text(
                'Security Alert',
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      fontSize: 26,
                      color: AppTheme.error,
                    ),
                textAlign: TextAlign.center,
              ),
              const Gap(16),
              Text(
                'This device is not secure.\n\n'
                'SNote has detected that your device may be rooted or '
                'jailbroken. Running on a compromised device puts your '
                'encrypted notes at risk of exposure.\n\n'
                'SNote cannot run on this device.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      height: 1.6,
                      color: AppTheme.textSecondary,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}