import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import '../../core/security/security_service.dart';
import '../../core/theme/app_theme.dart';
import '../notes/notes_page.dart';
import 'setup_password_page.dart';
import '../../widgets/secure_text_field.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage>
    with WidgetsBindingObserver {
  final _passwordController = TextEditingController();
  final _focusNode = FocusNode();

  bool _isLoading = false;
  String? _errorMessage;
  bool _biometricAvailable = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkSetup();
  }

  Future<void> _checkSetup() async {
    final security = ref.read(securityServiceProvider);
    final hasPassword = await security.hasPassword;

    if (!mounted) return;
    if (!hasPassword) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const SetupPasswordPage()),
      );
      return;
    }

    final bioAvail = await security.isBiometricAvailable;
    final bioEnabled = await security.isBiometricEnabled;
    if (!mounted) return;
    setState(() => _biometricAvailable = bioAvail && bioEnabled);
    if (_biometricAvailable) _tryBiometrics();
  }

  Future<void> _tryBiometrics() async {
    final result =
        await ref.read(securityServiceProvider).authenticateWithBiometrics();
    if (result == AuthResult.success && mounted) _goHome();
  }

  Future<void> _submitPassword() async {
    final password = _passwordController.text;
    if (password.isEmpty) {
      setState(() => _errorMessage = 'Please enter your password.');
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final security = ref.read(securityServiceProvider);
    final result = await security.verifyPassword(password);
    if (!mounted) return;
    setState(() => _isLoading = false);

    switch (result) {
      case AuthResult.success:
        // Cache master key for biometric unlock if enabled.
        if (await security.isBiometricEnabled) {
          await security.cacheMasterKeyForBiometrics();
        }
        _goHome();
      case AuthResult.wrongPassword:
        final remaining = await security.getRemainingAttempts();
        setState(() {
          _errorMessage =
              'Wrong password. $remaining attempt${remaining == 1 ? '' : 's'} remaining.';
          _passwordController.clear();
        });
        _focusNode.requestFocus();
      case AuthResult.lockedOut:
        setState(() => _errorMessage =
            'Too many failed attempts. The app is locked.');
      default:
        setState(() => _errorMessage = 'Authentication failed.');
    }
  }

  void _goHome() {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const NotesPage(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 350),
      ),
    );
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _focusNode.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Gap(48),
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: AppTheme.primary.withOpacity(0.3), width: 1),
                ),
                child: const Icon(Icons.lock_outline,
                    color: AppTheme.primary, size: 32),
              ),
              const Gap(32),
              Text('Welcome back',
                  style: Theme.of(context)
                      .textTheme
                      .displayMedium
                      ?.copyWith(fontSize: 28)),
              const Gap(8),
              Text(
                'Enter your password to access your notes.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const Gap(40),
              SecureTextField(
                controller: _passwordController,
                focusNode: _focusNode,
                hintText: 'Password',
                autofocus: true,
                prefixIcon: const Icon(Icons.key_outlined,
                    color: AppTheme.textSecondary),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submitPassword(),
                errorText: _errorMessage,
              ),
              const Gap(20),
              ElevatedButton(
                onPressed: _isLoading ? null : _submitPassword,
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Unlock'),
              ),
              if (_biometricAvailable) ...[
                const Gap(16),
                Center(
                  child: TextButton.icon(
                    onPressed: _tryBiometrics,
                    icon: const Icon(Icons.fingerprint,
                        color: AppTheme.primary, size: 22),
                    label: const Text('Use Biometrics',
                        style: TextStyle(color: AppTheme.primary)),
                  ),
                ),
              ],
              const Spacer(),
              Center(
                child: Text(
                  'SNote  |  Fully offline and encrypted',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}