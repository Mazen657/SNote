import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import '../../core/security/security_service.dart';
import '../../core/theme/app_theme.dart';
import '../notes/notes_page.dart';
import '../../widgets/secure_text_field.dart';

class SetupPasswordPage extends ConsumerStatefulWidget {
  const SetupPasswordPage({super.key});

  @override
  ConsumerState<SetupPasswordPage> createState() => _SetupPasswordPageState();
}

class _SetupPasswordPageState extends ConsumerState<SetupPasswordPage> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _confirmFocus = FocusNode();

  String? _error;
  bool _isLoading = false;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  Future<void> _setup() async {
    final p1 = _passwordController.text;
    final p2 = _confirmController.text;

    if (p1.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }
    if (p1 != p2) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final security = ref.read(securityServiceProvider);
    await security.setPassword(p1);

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const NotesPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Gap(48),
              _AppIcon(icon: Icons.shield_outlined),
              const Gap(32),
              Text(
                'Set up your password',
                style: Theme.of(context)
                    .textTheme
                    .displayMedium
                    ?.copyWith(fontSize: 26),
              ),
              const Gap(10),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppTheme.accent.withOpacity(0.25)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_outlined,
                        color: AppTheme.accent, size: 18),
                    const Gap(10),
                    Expanded(
                      child: Text(
                        'Important: If you forget your password your notes '
                        'cannot be recovered. There is no reset option.',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: AppTheme.accent),
                      ),
                    ),
                  ],
                ),
              ),
              const Gap(32),
              SecureTextField(
                controller: _passwordController,
                hintText: 'Create password (min. 6 characters)',
                prefixIcon: const Icon(Icons.lock_outline,
                    color: AppTheme.textSecondary),
                textInputAction: TextInputAction.next,
                onSubmitted: (_) =>
                    FocusScope.of(context).requestFocus(_confirmFocus),
              ),
              const Gap(14),
              SecureTextField(
                controller: _confirmController,
                focusNode: _confirmFocus,
                hintText: 'Confirm password',
                prefixIcon: const Icon(Icons.lock_outline,
                    color: AppTheme.textSecondary),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _setup(),
                errorText: _error,
              ),
              const Gap(28),
              ElevatedButton(
                onPressed: _isLoading ? null : _setup,
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Create Password and Continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppIcon extends StatelessWidget {
  final IconData icon;
  const _AppIcon({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: AppTheme.primary.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: AppTheme.primary.withOpacity(0.3), width: 1),
      ),
      child: Icon(icon, color: AppTheme.primary, size: 32),
    );
  }
}