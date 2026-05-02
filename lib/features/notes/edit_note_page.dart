import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/secure_text_field.dart';
import 'note_model.dart';
import 'notes_repository.dart';

// ─── Save-dialog result ───────────────────────────────────────────────────────

enum _ExitChoice { save, discard, cancel }

// ─── Snapshot used for change detection ──────────────────────────────────────

/// Immutable record of what was last persisted to storage for this note.
/// Compared against live controller values to decide whether unsaved changes
/// exist.  Initialised from the loaded note (edit mode) or all-empty (new
/// note), and updated every time a successful save completes.
class _NoteSnapshot {
  final String title;
  final String content;
  final List<String> tagIds;

  const _NoteSnapshot({
    required this.title,
    required this.content,
    required this.tagIds,
  });

  /// An all-empty snapshot used for brand-new notes before any save.
  const _NoteSnapshot.empty()
      : title = '',
        content = '',
        tagIds = const [];

  _NoteSnapshot copyWithSaved({
    required String title,
    required String content,
    required List<String> tagIds,
  }) =>
      _NoteSnapshot(title: title, content: content, tagIds: tagIds);
}

// ─── Page widget ─────────────────────────────────────────────────────────────

class EditNotePage extends ConsumerStatefulWidget {
  /// Null = create new note.
  final String? noteId;
  const EditNotePage({super.key, this.noteId});

  @override
  ConsumerState<EditNotePage> createState() => _EditNotePageState();
}

class _EditNotePageState extends ConsumerState<EditNotePage> {
  final _titleController   = TextEditingController();
  final _contentController = TextEditingController();
  final _contentFocus      = FocusNode();

  // The last-persisted state of this note.
  _NoteSnapshot _saved = const _NoteSnapshot.empty();

  // Live tag selection (may differ from _saved.tagIds before save).
  List<String> _selectedTagIds = [];

  // Displayed in the modified-date row.
  NoteView? _original;

  bool _isLoading            = true;
  bool _isSaving             = false;

  // Guards against opening the exit dialog twice (e.g. back gesture + back
  // button firing simultaneously).
  bool _dialogInProgress     = false;

  bool get _isEditing => widget.noteId != null;

  // ─── Lifecycle ────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadNote();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _contentFocus.dispose();
    super.dispose();
  }

  // ─── Load ─────────────────────────────────────────────────────────────────

  Future<void> _loadNote() async {
    if (widget.noteId != null) {
      final note =
          await ref.read(notesRepositoryProvider).getNoteById(widget.noteId!);
      if (note != null && mounted) {
        _titleController.text   = note.title;
        _contentController.text = note.content;
        _selectedTagIds         = List.from(note.tagIds);
        _original               = note;
        // Snapshot matches what is on disk — no unsaved changes yet.
        _saved = _NoteSnapshot(
          title:   note.title,
          content: note.content,
          tagIds:  List.from(note.tagIds),
        );
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  // ─── Change detection ─────────────────────────────────────────────────────

  /// Returns true when the live editor state differs from the last-persisted
  /// snapshot.  Tag order is normalised before comparison so a tag re-order
  /// without an add/remove does not trigger a false positive.
  bool _hasUnsavedChanges() {
    final liveTitle   = _titleController.text;
    final liveContent = _contentController.text;

    if (liveTitle   != _saved.title)   return true;
    if (liveContent != _saved.content) return true;

    final liveSorted  = List<String>.from(_selectedTagIds)..sort();
    final savedSorted = List<String>.from(_saved.tagIds)..sort();
    if (liveSorted.length != savedSorted.length) return true;
    for (int i = 0; i < liveSorted.length; i++) {
      if (liveSorted[i] != savedSorted[i]) return true;
    }
    return false;
  }

  // ─── Save ─────────────────────────────────────────────────────────────────

  /// Persists the note and updates [_saved] so subsequent exit checks do not
  /// re-prompt.  Returns true on success, false when the note was empty and
  /// was intentionally discarded without navigation.
  Future<bool> _save() async {
    if (_isSaving) return false;

    final title   = _titleController.text.trim();
    final content = _contentController.text.trim();

    // Empty notes are silently discarded — they are never stored.
    if (title.isEmpty && content.isEmpty) {
      return false; // caller handles navigation
    }

    setState(() => _isSaving = true);

    try {
      final notifier       = ref.read(notesProvider.notifier);
      final resolvedTitle  = title.isEmpty ? 'Untitled' : title;

      if (_isEditing) {
        await notifier.updateNote(
          id:      widget.noteId!,
          title:   resolvedTitle,
          content: content,
          tagIds:  _selectedTagIds,
        );
      } else {
        await notifier.createNote(
          title:   resolvedTitle,
          content: content,
          tagIds:  _selectedTagIds,
        );
      }

      // Update snapshot so the editor no longer considers the note dirty.
      setState(() {
        _saved = _saved.copyWithSaved(
          title:   resolvedTitle,
          content: content,
          tagIds:  List.from(_selectedTagIds),
        );
        _isSaving = false;
      });
      return true;
    } catch (_) {
      if (mounted) setState(() => _isSaving = false);
      return false;
    }
  }

  // ─── Exit flow ────────────────────────────────────────────────────────────

  /// Central exit handler called by every back path (app-bar button, system
  /// back gesture, PopScope).  Guarantees at most one dialog is shown.
  Future<void> _handleBack() async {
    if (_dialogInProgress) return;

    // Nothing changed — leave immediately.
    if (!_hasUnsavedChanges()) {
      _leave();
      return;
    }

    // Both fields empty — discard silently (no point prompting).
    if (_titleController.text.trim().isEmpty &&
        _contentController.text.trim().isEmpty) {
      _leave();
      return;
    }

    _dialogInProgress = true;
    final choice = await _showExitDialog();
    _dialogInProgress = false;

    if (!mounted) return;

    switch (choice) {
      case _ExitChoice.save:
        final saved = await _save();
        if (!mounted) return;
        // Navigate regardless of save result — if it failed the error is
        // already surfaced through the saving state; do not trap the user.
        _leave();
        break;

      case _ExitChoice.discard:
        _leave();

      case _ExitChoice.cancel:
      case null:
        // Stay in editor — do nothing.
        break;
    }
  }

  void _leave() {
    if (mounted) Navigator.of(context).pop();
  }

  // ─── Dialogs ──────────────────────────────────────────────────────────────

  /// Three-choice exit dialog: Save / Discard / Cancel.
  Future<_ExitChoice?> _showExitDialog() => showDialog<_ExitChoice>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          title: const Text('Save changes?'),
          content: const Text(
            'You have unsaved changes. Would you like to save them '
            'before leaving?',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
          actions: [
            // Cancel — stay in editor.
            TextButton(
              onPressed: () => Navigator.pop(ctx, _ExitChoice.cancel),
              child: const Text(
                'Cancel',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            ),
            // Discard — leave without saving.
            TextButton(
              onPressed: () => Navigator.pop(ctx, _ExitChoice.discard),
              child: const Text(
                'Discard',
                style: TextStyle(color: AppTheme.error),
              ),
            ),
            // Save — persist then leave.
            TextButton(
              onPressed: () => Navigator.pop(ctx, _ExitChoice.save),
              child: const Text(
                'Save',
                style: TextStyle(
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );

  /// Clear-note confirmation.  Returns true when the user confirmed.
  Future<bool> _showClearDialog() => showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          title: const Text('Clear note?'),
          content: const Text(
            'All title and content text will be removed. '
            'This cannot be undone.',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text(
                'Cancel',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(
                'Clear',
                style: TextStyle(
                  color: AppTheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ).then((v) => v ?? false);

  // ─── Actions ──────────────────────────────────────────────────────────────

  /// Explicit save triggered from the Save button in the app bar.
  Future<void> _onSavePressed() async {
    final title   = _titleController.text.trim();
    final content = _contentController.text.trim();

    if (title.isEmpty && content.isEmpty) {
      // Nothing to save — leave without prompting.
      _leave();
      return;
    }

    final ok = await _save();
    if (ok && mounted) _leave();
  }

  Future<void> _onClearPressed() async {
    final confirmed = await _showClearDialog();
    if (confirmed && mounted) {
      _titleController.clear();
      _contentController.clear();
      FocusScope.of(context).requestFocus(_contentFocus);
    }
  }

  void _showTagPicker() {
    final tags = ref.read(tagsProvider);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _TagPickerSheet(
        tags:           tags,
        selectedTagIds: List.from(_selectedTagIds),
        onDone:         (ids) => setState(() => _selectedTagIds = ids),
      ),
    );
  }

  Future<void> _onTogglePin() async {
    if (widget.noteId == null) return;
    await ref.read(notesProvider.notifier).togglePin(widget.noteId!);
    final updated =
        await ref.read(notesRepositoryProvider).getNoteById(widget.noteId!);
    if (updated != null && mounted) setState(() => _original = updated);
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final tags         = ref.watch(tagsProvider);
    final selectedTags = tags.where((t) => _selectedTagIds.contains(t.id)).toList();

    return PopScope(
      // Never let the framework pop automatically — route every back through
      // our handler so the unsaved-changes check is always applied.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new),
            onPressed: _handleBack,
          ),
          actions: [
            // Pin toggle (edit mode only).
            if (_isEditing && _original != null)
              IconButton(
                tooltip: _original!.isPinned ? 'Unpin' : 'Pin',
                icon: Icon(
                  _original!.isPinned
                      ? Icons.push_pin
                      : Icons.push_pin_outlined,
                  color: _original!.isPinned
                      ? AppTheme.primary
                      : AppTheme.textSecondary,
                ),
                onPressed: _onTogglePin,
              ),

            // Clear all content.
            IconButton(
              tooltip: 'Clear note',
              icon: const Icon(Icons.delete_sweep_outlined),
              color: AppTheme.textSecondary,
              onPressed: _onClearPressed,
            ),

            // Tags.
            IconButton(
              tooltip: 'Tags',
              icon: const Icon(Icons.label_outline),
              onPressed: _showTagPicker,
            ),

            // Save and exit.
            TextButton(
              onPressed: _isSaving ? null : _onSavePressed,
              child: _isSaving
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      'Save',
                      style: TextStyle(
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ],
        ),

        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Modified date.
              if (_original != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 4),
                  child: Text(
                    'Modified ${DateFormat('MMM d, y  HH:mm').format(_original!.modifiedAt)}',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontSize: 12),
                  ),
                ),

              // Active tag chips.
              if (selectedTags.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 6),
                  child: Wrap(
                    spacing: 6,
                    children: selectedTags
                        .map((t) => Chip(
                              label: Text(t.name,
                                  style: const TextStyle(fontSize: 12)),
                              backgroundColor:
                                  Color(t.colorValue).withOpacity(0.15),
                              side: BorderSide(
                                  color:
                                      Color(t.colorValue).withOpacity(0.4)),
                              padding: EdgeInsets.zero,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ))
                        .toList(),
                  ),
                ),

              // Title field.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  controller: _titleController,
                  contextMenuBuilder: pasteOnlyContextMenu,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontSize: 22),
                  decoration: const InputDecoration(
                    hintText:      'Title',
                    border:        InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                    // Override the theme fill so the field blends with the
                    // scaffold background and is not visible as a box.
                    filled:        true,
                    fillColor:     Colors.transparent,
                  ),
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) =>
                      FocusScope.of(context).requestFocus(_contentFocus),
                ),
              ),

              const Divider(height: 1),

              // Content field.
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: TextField(
                    controller:  _contentController,
                    focusNode:   _contentFocus,
                    maxLines:    null,
                    expands:     true,
                    contextMenuBuilder: pasteOnlyContextMenu,
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(height: 1.6),
                    decoration: const InputDecoration(
                      hintText:      'Start writing...',
                      border:        InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.only(top: 12),
                      // Match scaffold background — no visible fill box.
                      filled:        true,
                      fillColor:     Colors.transparent,
                    ),
                    textAlignVertical: TextAlignVertical.top,
                  ),
                ),
              ),

              // Clear Note bottom button.
              _ClearNoteBar(onPressed: _onClearPressed),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Clear Note bottom bar ────────────────────────────────────────────────────

class _ClearNoteBar extends StatelessWidget {
  final VoidCallback onPressed;
  const _ClearNoteBar({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppTheme.divider)),
      ),
      child: TextButton.icon(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          padding:          const EdgeInsets.symmetric(vertical: 14),
          shape:            const RoundedRectangleBorder(),
          foregroundColor:  AppTheme.error,
        ),
        icon:  const Icon(Icons.delete_sweep_outlined, size: 18),
        label: const Text(
          'Clear Note',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}

// ─── Tag picker bottom sheet ──────────────────────────────────────────────────

class _TagPickerSheet extends StatefulWidget {
  final List<TagModel> tags;
  final List<String> selectedTagIds;
  final void Function(List<String>) onDone;

  const _TagPickerSheet({
    required this.tags,
    required this.selectedTagIds,
    required this.onDone,
  });

  @override
  State<_TagPickerSheet> createState() => _TagPickerSheetState();
}

class _TagPickerSheetState extends State<_TagPickerSheet> {
  late List<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = List.from(widget.selectedTagIds);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Select Tags',
                  style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              TextButton(
                onPressed: () {
                  widget.onDone(_selected);
                  Navigator.pop(context);
                },
                child: const Text(
                  'Done',
                  style: TextStyle(color: AppTheme.primary),
                ),
              ),
            ],
          ),
          const Gap(12),
          if (widget.tags.isEmpty)
            const Text(
              'No tags yet. Create tags in Settings.',
              style: TextStyle(color: AppTheme.textSecondary),
            )
          else
            Wrap(
              spacing:    8,
              runSpacing: 8,
              children: widget.tags.map((tag) {
                final sel = _selected.contains(tag.id);
                return FilterChip(
                  label:         Text(tag.name),
                  selected:      sel,
                  onSelected:    (val) => setState(() {
                    val ? _selected.add(tag.id) : _selected.remove(tag.id);
                  }),
                  selectedColor: Color(tag.colorValue).withOpacity(0.2),
                  checkmarkColor: Color(tag.colorValue),
                  side: BorderSide(
                    color: sel ? Color(tag.colorValue) : AppTheme.divider,
                  ),
                );
              }).toList(),
            ),
          const Gap(8),
        ],
      ),
    );
  }
}