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
  final _searchController = TextEditingController();
  bool _isSearching = false;
  String? _selectedTagId;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearch(String query) {
    final notifier = ref.read(notesProvider.notifier);
    if (query.isEmpty) {
      notifier.clearFilters();
    } else {
      notifier.search(query);
    }
  }

  void _openNote(NoteView note) {
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

  @override
  Widget build(BuildContext context) {
    final notesAsync = ref.watch(notesProvider);
    final tags       = ref.watch(tagsProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  Expanded(
                    child: notesAsync.when(
                      data: (notes) => Column(
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
                      loading: () => Text('SNote',
                          style: Theme.of(context).textTheme.titleLarge),
                      error: (_, __) => Text('SNote',
                          style: Theme.of(context).textTheme.titleLarge),
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
            ),

            // ── Search bar ──────────────────────────────────────────────────
            if (_isSearching)
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 4),
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  onChanged: _onSearch,
                  // Paste-only context menu on the search field too.
                  contextMenuBuilder: pasteOnlyContextMenu,
                  decoration: const InputDecoration(
                    hintText: 'Search notes...',
                    prefixIcon:
                        Icon(Icons.search, color: AppTheme.textSecondary),
                  ),
                ),
              ),

            const Gap(4),

            // ── Tag filter chips ─────────────────────────────────────────────
            if (tags.isNotEmpty)
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    _TagChip(
                      label: 'All',
                      selected: _selectedTagId == null,
                      onTap: () {
                        setState(() => _selectedTagId = null);
                        ref.read(notesProvider.notifier).clearFilters();
                      },
                    ),
                    ...tags.map(
                      (tag) => _TagChip(
                        label: tag.name,
                        color: Color(tag.colorValue),
                        selected: _selectedTagId == tag.id,
                        onTap: () {
                          setState(() => _selectedTagId = tag.id);
                          ref
                              .read(notesProvider.notifier)
                              .filterByTag(tag.id);
                        },
                      ),
                    ),
                  ],
                ),
              ),

            const Gap(12),

            // ── Notes list ───────────────────────────────────────────────────
            Expanded(
              child: notesAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Text('Error: $e',
                      style: const TextStyle(color: AppTheme.textSecondary)),
                ),
                data: (notes) => notes.isEmpty
                    ? _EmptyState(onNewNote: _newNote)
                    : AnimationLimiter(
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          itemCount: notes.length,
                          itemBuilder: (context, index) {
                            final note = notes[index];
                            return AnimationConfiguration.staggeredList(
                              position: index,
                              duration: const Duration(milliseconds: 280),
                              child: SlideAnimation(
                                verticalOffset: 20,
                                child: FadeInAnimation(
                                  child: NoteCard(
                                    note: note,
                                    tags: tags
                                        .where((t) =>
                                            note.tagIds.contains(t.id))
                                        .toList(),
                                    onTap: () => _openNote(note),
                                    onPin: () => ref
                                        .read(notesProvider.notifier)
                                        .togglePin(note.id),
                                    onDelete: () => _confirmDelete(note),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newNote,
        icon: const Icon(Icons.add),
        label: const Text('New Note'),
      ),
    );
  }

  void _confirmDelete(NoteView note) {
    showDialog(
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
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(notesProvider.notifier).deleteNote(note.id);
            },
            child: const Text('Delete',
                style: TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
  }
}

// ─── Tag chip ─────────────────────────────────────────────────────────────────

class _TagChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color? color;
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
        margin: const EdgeInsets.only(right: 8),
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
            fontSize: 13,
            color: selected ? chipColor : AppTheme.textSecondary,
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
              size: 72,
              color: AppTheme.textSecondary.withOpacity(0.35)),
          const Gap(16),
          Text('No notes yet',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: AppTheme.textSecondary)),
          const Gap(8),
          Text(
            'Tap the button below to create your first note.',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const Gap(24),
          TextButton.icon(
            onPressed: onNewNote,
            icon: const Icon(Icons.add, color: AppTheme.primary),
            label: const Text('New Note',
                style: TextStyle(color: AppTheme.primary)),
          ),
        ],
      ),
    );
  }
}