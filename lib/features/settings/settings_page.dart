import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/security/security_service.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/secure_text_field.dart';
import '../auth/login_page.dart';
import '../notes/notes_repository.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _bioAvailable    = false;
  bool _bioEnabled      = false;
  int  _autoLockMinutes = 5;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final s = ref.read(securityServiceProvider);
    final bioAvail = await s.isBiometricAvailable;
    final bioEn    = await s.isBiometricEnabled;
    final lock     = await s.getAutoLockMinutes();
    if (mounted) {
      setState(() {
        _bioAvailable    = bioAvail;
        _bioEnabled      = bioEn;
        _autoLockMinutes = lock;
      });
    }
  }

  // ─── Change password ──────────────────────────────────────────────────────

  void _changePassword() {
    final oldCtrl  = TextEditingController();
    final newCtrl  = TextEditingController();
    final confCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Change Password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SecureTextField(
                controller: oldCtrl, hintText: 'Current password'),
            const Gap(10),
            SecureTextField(
                controller: newCtrl,
                hintText: 'New password (min. 6 chars)'),
            const Gap(10),
            SecureTextField(
                controller: confCtrl, hintText: 'Confirm new password'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              if (newCtrl.text.length < 6) {
                _snack('Password must be at least 6 characters.', error: true);
                return;
              }
              if (newCtrl.text != confCtrl.text) {
                _snack('Passwords do not match.', error: true);
                return;
              }
              final s      = ref.read(securityServiceProvider);
              final result = await s.verifyPassword(oldCtrl.text);
              if (result != AuthResult.success) {
                if (mounted) {
                  _snack('Current password is incorrect.', error: true);
                }
                return;
              }
              await s.setPassword(newCtrl.text);
              if (mounted) {
                Navigator.pop(ctx);
                _snack('Password changed successfully.');
              }
            },
            child: const Text('Change',
                style: TextStyle(color: AppTheme.primary)),
          ),
        ],
      ),
    );
  }

  // ─── Auto-lock ────────────────────────────────────────────────────────────

  void _showAutoLockPicker() {
    const options = [0, 1, 2, 5, 10, 30];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Auto-lock after'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: options.map((min) {
            final label = min == 0
                ? 'Disabled'
                : '$min minute${min == 1 ? '' : 's'}';
            return RadioListTile<int>(
              value: min,
              groupValue: _autoLockMinutes,
              title: Text(label),
              onChanged: (val) async {
                if (val == null) return;
                await ref
                    .read(securityServiceProvider)
                    .setAutoLockMinutes(val);
                setState(() => _autoLockMinutes = val);
                if (mounted) Navigator.pop(ctx);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  // ─── Backup ───────────────────────────────────────────────────────────────

  Future<void> _export() async {
    try {
      final file = await ref.read(notesRepositoryProvider).exportBackup();
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'SNote Backup',
      );
    } catch (e) {
      _snack('Export failed: $e', error: true);
    }
  }

  Future<void> _import() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['notesbackup'],
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path == null) return;
    try {
      final count = await ref
          .read(notesRepositoryProvider)
          .importBackup(File(path));
      ref.read(notesProvider.notifier).refresh();
      _snack('Imported $count note${count == 1 ? '' : 's'}.');
    } catch (e) {
      _snack('Import failed. Wrong password or corrupt file.', error: true);
    }
  }

  // ─── Lock ─────────────────────────────────────────────────────────────────

  void _lock() {
    ref.read(securityServiceProvider).lock();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final lockLabel = _autoLockMinutes == 0
        ? 'Disabled'
        : '$_autoLockMinutes minute${_autoLockMinutes == 1 ? '' : 's'}';

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section('Security'),
          _tile(
            icon: Icons.lock_reset_outlined,
            title: 'Change Password',
            onTap: _changePassword,
          ),
          if (_bioAvailable)
            _switchTile(
              icon: Icons.fingerprint,
              title: 'Biometric Unlock',
              subtitle: 'Fingerprint or Face ID',
              value: _bioEnabled,
              onChanged: (val) async {
                await ref
                    .read(securityServiceProvider)
                    .setBiometricEnabled(val);
                if (val) {
                  await ref
                      .read(securityServiceProvider)
                      .cacheMasterKeyForBiometrics();
                }
                setState(() => _bioEnabled = val);
              },
            ),
          _tile(
            icon: Icons.timer_outlined,
            title: 'Auto-lock',
            subtitle: lockLabel,
            onTap: _showAutoLockPicker,
          ),
          const Gap(16),
          _section('Organisation'),
          _tile(
            icon: Icons.label_outline,
            title: 'Manage Tags',
            onTap: _showTagManager,
          ),
          const Gap(16),
          _section('Backup and Restore'),
          _tile(
            icon: Icons.upload_outlined,
            title: 'Export Backup',
            subtitle: 'Encrypted .notesbackup file',
            onTap: _export,
          ),
          _tile(
            icon: Icons.download_outlined,
            title: 'Import Backup',
            subtitle: 'Restore from .notesbackup file',
            onTap: _import,
          ),
          const Gap(16),
          _section('App'),
          _tile(
            icon: Icons.lock_outline,
            title: 'Lock App',
            onTap: _lock,
          ),
          const Gap(16),
          _section('Developer'),
          _tile(
            icon: Icons.person_outline,
            title: 'Mazen Abdallah',
            subtitle: 'Developer',
            onTap: () {},
          ),
          _tile(
            icon: Icons.link,
            title: 'LinkedIn',
            subtitle: 'linkedin.com/in/mazen-abdallah-mohamed',
            onTap: () => _launchUrl(
                'https://www.linkedin.com/in/mazen-abdallah-mohamed/'),
          ),
          _tile(
            icon: Icons.code,
            title: 'GitHub',
            subtitle: 'github.com/Mazen657',
            onTap: () => _launchUrl('https://github.com/Mazen657'),
          ),
          const Gap(32),
          Center(
            child: Text(
              'SNote v1.0.0\nAll data stored locally. No internet required.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontSize: 12),
            ),
          ),
          const Gap(16),
        ],
      ),
    );
  }

  // ─── Tag manager ──────────────────────────────────────────────────────────

  void _showTagManager() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const _TagManagerSheet(),
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
        child: Text(
          title.toUpperCase(),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: AppTheme.primary,
              ),
        ),
      );

  Widget _tile({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) =>
      Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: Icon(icon, color: AppTheme.textSecondary),
          title: Text(title),
          subtitle: subtitle != null
              ? Text(subtitle,
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 12))
              : null,
          trailing: const Icon(Icons.chevron_right,
              color: AppTheme.textSecondary, size: 18),
          onTap: onTap,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
        ),
      );

  Widget _switchTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) =>
      Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: SwitchListTile(
          secondary: Icon(icon, color: AppTheme.textSecondary),
          title: Text(title),
          subtitle: subtitle != null
              ? Text(subtitle,
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 12))
              : null,
          value: value,
          onChanged: onChanged,
          activeColor: AppTheme.primary,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
        ),
      );

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppTheme.error : AppTheme.success,
    ));
  }
}

// ─── Tag manager bottom sheet ─────────────────────────────────────────────────

class _TagManagerSheet extends ConsumerStatefulWidget {
  const _TagManagerSheet();

  @override
  ConsumerState<_TagManagerSheet> createState() => _TagManagerSheetState();
}

class _TagManagerSheetState extends ConsumerState<_TagManagerSheet> {
  final _nameCtrl = TextEditingController();
  int _selectedColor = 0xFF6C63FF;

  static const List<int> _colors = [
    0xFF6C63FF, 0xFFFF6584, 0xFF43BF72, 0xFFFFB547,
    0xFF00BCD4, 0xFFE91E63, 0xFF9C27B0, 0xFF607D8B,
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tags = ref.watch(tagsProvider);
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Manage Tags',
                style: Theme.of(context).textTheme.titleMedium),
            const Gap(16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameCtrl,
                    // Paste-only on tag name field too.
                    contextMenuBuilder: pasteOnlyContextMenu,
                    decoration:
                        const InputDecoration(hintText: 'Tag name'),
                  ),
                ),
                const Gap(8),
                ElevatedButton(
                  onPressed: () async {
                    final name = _nameCtrl.text.trim();
                    if (name.isEmpty) return;
                    await ref
                        .read(tagsProvider.notifier)
                        .createTag(name, colorValue: _selectedColor);
                    _nameCtrl.clear();
                  },
                  style: ElevatedButton.styleFrom(
                      minimumSize: const Size(70, 48)),
                  child: const Text('Add'),
                ),
              ],
            ),
            const Gap(10),
            Wrap(
              spacing: 8,
              children: _colors
                  .map((c) => GestureDetector(
                        onTap: () => setState(() => _selectedColor = c),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Color(c),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _selectedColor == c
                                  ? Colors.white
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                        ),
                      ))
                  .toList(),
            ),
            const Gap(16),
            ...tags.map(
              (tag) => ListTile(
                dense: true,
                leading: CircleAvatar(
                    radius: 8,
                    backgroundColor: Color(tag.colorValue)),
                title: Text(tag.name),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline,
                      color: AppTheme.error, size: 20),
                  onPressed: () =>
                      ref.read(tagsProvider.notifier).deleteTag(tag.id),
                ),
              ),
            ),
            const Gap(8),
          ],
        ),
      ),
    );
  }
}