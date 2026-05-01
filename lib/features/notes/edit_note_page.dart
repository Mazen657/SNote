import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import 'note_model.dart';
import 'notes_repository.dart';

class EditNotePage extends ConsumerStatefulWidget {
  final String? noteId;
  const EditNotePage({super.key, this.noteId});

  @override
  ConsumerState<EditNotePage> createState() => _EditNotePageState();
}

class _EditNotePageState extends ConsumerState<EditNotePage> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _contentFocus = FocusNode();

  NoteView? _original;
  List<String> _selectedTagIds = [];
  bool _isSaving = false;
  bool _isLoading = true;

  bool get _isEditing => widget.noteId != null;

  @override
  void initState() {
    super.initState();
    _loadNote();
  }

  Future<void> _loadNote() async {
    if (widget.noteId != null) {
      final repo = ref.read(notesRepositoryProvider);
      final note = await repo.getNoteById(widget.noteId!);
      if (note != null && mounted) {
        setState(() {
          _original = note;
          _titleController.text = note.title;
          _contentController.text = note.content;
          _selectedTagIds = List.from(note.tagIds);
        });
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();

    // Auto-delete empty notes rather than storing blank records.
    if (title.isEmpty && content.isEmpty) {
      Navigator.pop(context);
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

  bool _hasUnsavedChanges() {
    if (_original == null) {
      return _titleController.text.isNotEmpty ||
          _contentController.text.isNotEmpty;
    }
    return _titleController.text != _original!.title ||
        _contentController.text != _original!.content;
  }

  Future<bool?> _showSaveDialog() => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: const Text('Save changes?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Discard',
                    style: TextStyle(color: AppTheme.error))),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Save',
                    style: TextStyle(color: AppTheme.primary))),
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

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _contentFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final tags = ref.watch(tagsProvider);
    final selectedTags =
        tags.where((t) => _selectedTagIds.contains(t.id)).toList();

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
            if (_isEditing && _original != null)
              IconButton(
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
            IconButton(
              icon: const Icon(Icons.label_outline),
              onPressed: _showTagPicker,
            ),
            TextButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save',
                      style: TextStyle(color: AppTheme.primary)),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              if (_original != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Modified ${DateFormat('MMM d, y  HH:mm').format(_original!.modifiedAt)}',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(fontSize: 12),
                    ),
                  ),
                ),
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
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  controller: _titleController,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontSize: 22),
                  decoration: const InputDecoration(
                    hintText: 'Title',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding:
                        EdgeInsets.symmetric(vertical: 8),
                  ),
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) =>
                      FocusScope.of(context).requestFocus(_contentFocus),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20),
                  child: TextField(
                    controller: _contentController,
                    focusNode: _contentFocus,
                    maxLines: null,
                    expands: true,
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
            ],
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
                child: const Text('Done',
                    style: TextStyle(color: AppTheme.primary)),
              ),
            ],
          ),
          const Gap(12),
          if (widget.tags.isEmpty)
            const Text('No tags yet. Create tags in Settings.',
                style: TextStyle(color: AppTheme.textSecondary))
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
                  selectedColor:
                      Color(tag.colorValue).withOpacity(0.2),
                  checkmarkColor: Color(tag.colorValue),
                  side: BorderSide(
                      color: sel
                          ? Color(tag.colorValue)
                          : AppTheme.divider),
                );
              }).toList(),
            ),
          const Gap(8),
        ],
      ),
    );
  }
}