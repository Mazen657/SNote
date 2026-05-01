import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/secure_text_field.dart';
import 'note_model.dart';
import 'notes_repository.dart';

class EditNotePage extends ConsumerStatefulWidget {
  /// Null means "create new note".
  final String? noteId;
  const EditNotePage({super.key, this.noteId});

  @override
  ConsumerState<EditNotePage> createState() => _EditNotePageState();
}

class _EditNotePageState extends ConsumerState<EditNotePage> {
  final _titleController  = TextEditingController();
  final _contentController = TextEditingController();
  final _contentFocus     = FocusNode();

  NoteView? _original;
  List<String> _selectedTagIds = [];
  bool _isSaving = false;
  bool _isLoading = true;

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

  // ─── Data loading ─────────────────────────────────────────────────────────

  Future<void> _loadNote() async {
    if (widget.noteId != null) {
      final repo = ref.read(notesRepositoryProvider);
      final note = await repo.getNoteById(widget.noteId!);
      if (note != null && mounted) {
        setState(() {
          _original = note;
          _titleController.text  = note.title;
          _contentController.text = note.content;
          _selectedTagIds = List.from(note.tagIds);
        });
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  // ─── Save ─────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    final title   = _titleController.text.trim();
    final content = _contentController.text.trim();

    // Empty notes are never stored — discard silently.
    if (title.isEmpty && content.isEmpty) {
      if (mounted) Navigator.pop(context);
      return;
    }

    setState(() => _isSaving = true);
    final notifier = ref.read(notesProvider.notifier);

    if (_isEditing) {
      await notifier.updateNote(
        id: widget.noteId!,
        title: title.isEmpty ? 'Untitled' : title,
        content: content,
        tagIds: _selectedTagIds,
      );
    } else {
      await notifier.createNote(
        title: title.isEmpty ? 'Untitled' : title,
        content: content,
        tagIds: _selectedTagIds,
      );
    }

    if (mounted) Navigator.pop(context);
  }

  // ─── Clear note ───────────────────────────────────────────────────────────

  /// Shows a confirmation dialog then wipes both title and content fields.
  Future<void> _confirmClearNote() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Clear note?'),
        content: const Text(
          'All title and content text will be permanently removed. '
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
    );

    if (confirmed == true && mounted) {
      _titleController.clear();
      _contentController.clear();
      // Move focus to title so the user can immediately retype.
      FocusScope.of(context).requestFocus(_contentFocus);
    }
  }

  // ─── Back / unsaved changes ───────────────────────────────────────────────

  bool _hasUnsavedChanges() {
    if (_original == null) {
      return _titleController.text.isNotEmpty ||
          _contentController.text.isNotEmpty;
    }
    return _titleController.text  != _original!.title ||
        _contentController.text != _original!.content;
  }

  Future<bool?> _showSaveDialog() => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.surface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Save changes?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text(
                'Discard',
                style: TextStyle(color: AppTheme.error),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(
                'Save',
                style: TextStyle(color: AppTheme.primary),
              ),
            ),
          ],
        ),
      );

  Future<void> _handleBack() async {
    if (_hasUnsavedChanges()) {
      final save = await _showSaveDialog();
      if (save == true) await _save();
      if (save != null && mounted) Navigator.pop(context);
    } else {
      Navigator.pop(context);
    }
  }

  // ─── Tag picker ───────────────────────────────────────────────────────────

  void _showTagPicker() {
    final tags = ref.read(tagsProvider);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _TagPickerSheet(
        tags: tags,
        selectedTagIds: List.from(_selectedTagIds),
        onDone: (ids) => setState(() => _selectedTagIds = ids),
      ),
    );
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
            // ── Pin toggle (edit mode only) ──────────────────────────────
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
                onPressed: () async {
                  await ref
                      .read(notesProvider.notifier)
                      .togglePin(widget.noteId!);
                  final updated = await ref
                      .read(notesRepositoryProvider)
                      .getNoteById(widget.noteId!);
                  if (updated != null && mounted) {
                    setState(() => _original = updated);
                  }
                },
              ),

            // ── Clear note ───────────────────────────────────────────────
            IconButton(
              tooltip: 'Clear note',
              icon: const Icon(Icons.delete_sweep_outlined),
              color: AppTheme.textSecondary,
              onPressed: _confirmClearNote,
            ),

            // ── Tags ─────────────────────────────────────────────────────
            IconButton(
              tooltip: 'Tags',
              icon: const Icon(Icons.label_outline),
              onPressed: _showTagPicker,
            ),

            // ── Save ─────────────────────────────────────────────────────
            TextButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      'Save',
                      style: TextStyle(color: AppTheme.primary),
                    ),
            ),
          ],
        ),

        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Modified date ────────────────────────────────────────────
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

              // ── Active tags row ──────────────────────────────────────────
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
                                  color: Color(t.colorValue).withOpacity(0.4)),
                              padding: EdgeInsets.zero,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ))
                        .toList(),
                  ),
                ),

              // ── Title field ──────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  controller: _titleController,
                  // Paste-only context menu on all note fields.
                  contextMenuBuilder: pasteOnlyContextMenu,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontSize: 22),
                  decoration: const InputDecoration(
                    hintText: 'Title',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 8),
                  ),
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) =>
                      FocusScope.of(context).requestFocus(_contentFocus),
                ),
              ),

              const Divider(height: 1),

              // ── Content field ────────────────────────────────────────────
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: TextField(
                    controller: _contentController,
                    focusNode: _contentFocus,
                    maxLines: null,
                    expands: true,
                    // Paste-only context menu on all note fields.
                    contextMenuBuilder: pasteOnlyContextMenu,
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(height: 1.6),
                    decoration: const InputDecoration(
                      hintText: 'Start writing...',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.only(top: 12),
                    ),
                    textAlignVertical: TextAlignVertical.top,
                  ),
                ),
              ),

              // ── Clear Note button ────────────────────────────────────────
              _ClearNoteButton(onPressed: _confirmClearNote),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Clear Note button widget ─────────────────────────────────────────────────

/// Displayed at the bottom of the editor as a clearly labelled,
/// visually distinct danger action.
class _ClearNoteButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _ClearNoteButton({required this.onPressed});

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
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: const RoundedRectangleBorder(),
          foregroundColor: AppTheme.error,
        ),
        icon: const Icon(Icons.delete_sweep_outlined, size: 18),
        label: const Text(
          'Clear Note',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
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
              spacing: 8,
              runSpacing: 8,
              children: widget.tags.map((tag) {
                final sel = _selected.contains(tag.id);
                return FilterChip(
                  label: Text(tag.name),
                  selected: sel,
                  onSelected: (val) => setState(() {
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