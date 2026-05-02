import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:gap/gap.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/secure_text_field.dart';
import '../settings/settings_page.dart';
import 'edit_note_page.dart';
import 'note_model.dart';
import 'notes_repository.dart';
import '../../widgets/note_card.dart';

class NotesPage extends ConsumerStatefulWidget {
  const NotesPage({super.key});

  @override
  ConsumerState<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends ConsumerState<NotesPage> {
  // ─── Search state ─────────────────────────────────────────────────────────
  final _searchController = TextEditingController();
  bool   _isSearching     = false;
  String? _selectedTagId;

  // ─── Selection state ──────────────────────────────────────────────────────
  /// When non-null the page is in multi-select mode.
  final Set<String> _selectedIds = {};
  bool get _isSelecting => _selectedIds.isNotEmpty;

  // ─── Lifecycle ────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ─── Selection helpers ────────────────────────────────────────────────────

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _selectAll(List<NoteView> notes) {
    setState(() {
      _selectedIds
        ..clear()
        ..addAll(notes.map((n) => n.id));
    });
  }

  void _clearSelection() {
    setState(() => _selectedIds.clear());
  }

  // ─── Delete selected ──────────────────────────────────────────────────────

  Future<void> _confirmDeleteSelected() async {
    if (_selectedIds.isEmpty) return;

    final count = _selectedIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete $count note${count == 1 ? '' : 's'}?'),
        content: Text(
          'This will permanently remove $count note${count == 1 ? '' : 's'}. '
          'This action cannot be undone and the data cannot be recovered.',
          style: const TextStyle(color: AppTheme.textSecondary),
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
            child: Text(
              'Delete $count',
              style: const TextStyle(
                color: AppTheme.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // Capture ids before clearing selection (setState is async-safe here).
    final toDelete = Set<String>.from(_selectedIds);
    _clearSelection();
    await ref.read(notesProvider.notifier).deleteNotes(toDelete);
  }

  // ─── Single note delete (swipe) ───────────────────────────────────────────

  Future<void> _confirmDeleteSingle(NoteView note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete note?'),
        content: Text(
          'Delete "${note.title}"? This cannot be undone.',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: AppTheme.error, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      ref.read(notesProvider.notifier).deleteNote(note.id);
    }
  }

  // ─── Navigation ───────────────────────────────────────────────────────────

  void _openNote(NoteView note) {
    if (_isSelecting) {
      _toggleSelection(note.id);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EditNotePage(noteId: note.id)),
    ).then((_) => ref.read(notesProvider.notifier).refresh());
  }

  void _newNote() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const EditNotePage()),
    ).then((_) => ref.read(notesProvider.notifier).refresh());
  }

  // ─── Search ───────────────────────────────────────────────────────────────

  void _onSearch(String query) {
    final notifier = ref.read(notesProvider.notifier);
    query.isEmpty ? notifier.clearFilters() : notifier.search(query);
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final notesAsync = ref.watch(notesProvider);
    final tags       = ref.watch(tagsProvider);

    return PopScope(
      canPop: !_isSelecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isSelecting) _clearSelection();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── App bar area ───────────────────────────────────────────────
              notesAsync.when(
                data:    (notes) => _buildHeader(notes, tags),
                loading: () => _buildHeader([], tags),
                error:   (_, __) => _buildHeader([], tags),
              ),

              // ── Search bar ─────────────────────────────────────────────────
              if (_isSearching && !_isSelecting)
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 4),
                  child: TextField(
                    controller:         _searchController,
                    autofocus:          true,
                    onChanged:          _onSearch,
                    contextMenuBuilder: pasteOnlyContextMenu,
                    decoration: const InputDecoration(
                      hintText:   'Search notes...',
                      prefixIcon: Icon(Icons.search,
                          color: AppTheme.textSecondary),
                    ),
                  ),
                ),

              const Gap(4),

              // ── Tag filter chips ───────────────────────────────────────────
              if (tags.isNotEmpty && !_isSelecting)
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      _TagChip(
                        label:    'All',
                        selected: _selectedTagId == null,
                        onTap: () {
                          setState(() => _selectedTagId = null);
                          ref.read(notesProvider.notifier).clearFilters();
                        },
                      ),
                      ...tags.map(
                        (tag) => _TagChip(
                          label:    tag.name,
                          color:    Color(tag.colorValue),
                          selected: _selectedTagId == tag.id,
                          onTap: () {
                            setState(() => _selectedTagId = tag.id);
                            ref.read(notesProvider.notifier).filterByTag(tag.id);
                          },
                        ),
                      ),
                    ],
                  ),
                ),

              if (tags.isNotEmpty && !_isSelecting) const Gap(12),
              if (tags.isEmpty || _isSelecting) const Gap(12),

              // ── Notes list ─────────────────────────────────────────────────
              Expanded(
                child: notesAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(
                    child: Text('Error: $e',
                        style: const TextStyle(
                            color: AppTheme.textSecondary)),
                  ),
                  data: (notes) => notes.isEmpty
                      ? _EmptyState(onNewNote: _newNote)
                      : AnimationLimiter(
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 4),
                            itemCount: notes.length,
                            itemBuilder: (context, index) {
                              final note     = notes[index];
                              final isSelected =
                                  _selectedIds.contains(note.id);
                              return AnimationConfiguration.staggeredList(
                                position: index,
                                duration:
                                    const Duration(milliseconds: 260),
                                child: SlideAnimation(
                                  verticalOffset: 18,
                                  child: FadeInAnimation(
                                    child: _SelectableNoteCard(
                                      note:       note,
                                      tags:       tags
                                          .where((t) =>
                                              note.tagIds.contains(t.id))
                                          .toList(),
                                      isSelected: isSelected,
                                      isSelecting: _isSelecting,
                                      onTap: () => _openNote(note),
                                      onLongPress: () =>
                                          _toggleSelection(note.id),
                                      onPin: () => ref
                                          .read(notesProvider.notifier)
                                          .togglePin(note.id),
                                      onDelete: () =>
                                          _confirmDeleteSingle(note),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
        floatingActionButton: _isSelecting
            ? null
            : FloatingActionButton.extended(
                onPressed: _newNote,
                icon:  const Icon(Icons.add),
                label: const Text('New Note'),
              ),
      ),
    );
  }

  // ─── Header builder ───────────────────────────────────────────────────────

  Widget _buildHeader(List<NoteView> notes, List<TagModel> tags) {
    if (_isSelecting) {
      return _SelectionHeader(
        selectedCount: _selectedIds.length,
        totalCount:    notes.length,
        onClose:       _clearSelection,
        onSelectAll:   () => _selectAll(notes),
        onDelete:      _confirmDeleteSelected,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SNote',
                    style: Theme.of(context).textTheme.titleLarge),
                Text(
                  '${notes.length} note${notes.length == 1 ? '' : 's'}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () =>
                setState(() => _isSearching = !_isSearching),
            icon: Icon(
              _isSearching ? Icons.search_off : Icons.search,
              color: AppTheme.textSecondary,
            ),
          ),
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsPage()),
            ),
            icon: const Icon(Icons.settings_outlined,
                color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ─── Selection mode header ────────────────────────────────────────────────────

class _SelectionHeader extends StatelessWidget {
  final int selectedCount;
  final int totalCount;
  final VoidCallback onClose;
  final VoidCallback onSelectAll;
  final VoidCallback onDelete;

  const _SelectionHeader({
    required this.selectedCount,
    required this.totalCount,
    required this.onClose,
    required this.onSelectAll,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final allSelected = selectedCount == totalCount && totalCount > 0;
    return Container(
      color: AppTheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        children: [
          // Close selection mode.
          IconButton(
            icon:  const Icon(Icons.close, color: AppTheme.textPrimary),
            onPressed: onClose,
            tooltip: 'Cancel selection',
          ),

          // Count label.
          Expanded(
            child: Text(
              '$selectedCount selected',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),

          // Select all / deselect all.
          TextButton(
            onPressed: allSelected ? onClose : onSelectAll,
            child: Text(
              allSelected ? 'Deselect all' : 'Select all',
              style: const TextStyle(color: AppTheme.primary),
            ),
          ),

          // Delete selected.
          IconButton(
            icon: const Icon(Icons.delete_outline),
            color: selectedCount > 0 ? AppTheme.error : AppTheme.textSecondary,
            tooltip: 'Delete selected',
            onPressed: selectedCount > 0 ? onDelete : null,
          ),
        ],
      ),
    );
  }
}

// ─── Selectable note card wrapper ─────────────────────────────────────────────

/// Wraps [NoteCard] and adds a long-press handler plus a visible selection
/// indicator (checkbox overlay) when the list is in selection mode.
class _SelectableNoteCard extends StatelessWidget {
  final NoteView       note;
  final List<TagModel> tags;
  final bool           isSelected;
  final bool           isSelecting;
  final VoidCallback   onTap;
  final VoidCallback   onLongPress;
  final VoidCallback   onPin;
  final VoidCallback   onDelete;

  const _SelectableNoteCard({
    required this.note,
    required this.tags,
    required this.isSelected,
    required this.isSelecting,
    required this.onTap,
    required this.onLongPress,
    required this.onPin,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: onLongPress,
      child: Stack(
        children: [
          // The existing NoteCard — swipe-to-delete still works when not
          // in selection mode.
          NoteCard(
            note:         note,
            tags:         tags,
            onTap:        onTap,
            onPin:        isSelecting ? () {} : onPin,
            onDelete:     isSelecting ? () {} : onDelete,
            // Disable swipe-to-delete while in multi-select mode so the
            // horizontal drag gesture does not fire alongside long-press.
            disableSwipe: isSelecting,
          ),

          // Selection overlay shown only in selection mode.
          if (isSelecting)
            Positioned(
              top:   16,
              right: 46, // clear of the pin icon
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width:  22,
                height: 22,
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppTheme.primary
                      : AppTheme.surfaceVariant,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? AppTheme.primary
                        : AppTheme.textSecondary,
                    width: 2,
                  ),
                ),
                child: isSelected
                    ? const Icon(Icons.check,
                        color: Colors.white, size: 14)
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Tag chip ─────────────────────────────────────────────────────────────────

class _TagChip extends StatelessWidget {
  final String     label;
  final bool       selected;
  final Color?     color;
  final VoidCallback onTap;

  const _TagChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final chipColor = color ?? AppTheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin:  const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? chipColor.withOpacity(0.2)
              : AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? chipColor : AppTheme.divider,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize:   13,
            color:      selected ? chipColor : AppTheme.textSecondary,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onNewNote;
  const _EmptyState({required this.onNewNote});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.edit_note,
              size:  72,
              color: AppTheme.textSecondary.withOpacity(0.35)),
          const Gap(16),
          Text(
            'No notes yet',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: AppTheme.textSecondary),
          ),
          const Gap(8),
          Text(
            'Tap the button below to create your first note.',
            style:     Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const Gap(24),
          TextButton.icon(
            onPressed: onNewNote,
            icon:  const Icon(Icons.add, color: AppTheme.primary),
            label: const Text('New Note',
                style: TextStyle(color: AppTheme.primary)),
          ),
        ],
      ),
    );
  }
}