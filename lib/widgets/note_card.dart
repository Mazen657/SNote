import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';

import '../core/theme/app_theme.dart';
import '../features/notes/note_model.dart';

class NoteCard extends StatelessWidget {
  final NoteView note;
  final List<TagModel> tags;
  final VoidCallback onTap;
  final VoidCallback onPin;
  final VoidCallback onDelete;

  const NoteCard({
    super.key,
    required this.note,
    required this.tags,
    required this.onTap,
    required this.onPin,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Dismissible(
        key: ValueKey(note.id),
        direction: DismissDirection.endToStart,
        background: _DeleteBackground(),
        confirmDismiss: (_) async {
          onDelete();
          return false;
        },
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: note.isPinned
                    ? AppTheme.primary.withOpacity(0.4)
                    : AppTheme.divider,
                width: note.isPinned ? 1.5 : 1,
              ),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (note.isPinned) ...[
                      const Icon(Icons.push_pin,
                          size: 14, color: AppTheme.primary),
                      const Gap(6),
                    ],
                    Expanded(
                      child: Text(
                        note.title,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Gap(8),
                    GestureDetector(
                      onTap: onPin,
                      child: Icon(
                        note.isPinned
                            ? Icons.push_pin
                            : Icons.push_pin_outlined,
                        size: 18,
                        color: note.isPinned
                            ? AppTheme.primary
                            : AppTheme.textSecondary.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
                if (note.preview.isNotEmpty) ...[
                  const Gap(6),
                  Text(
                    note.preview,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(height: 1.4, fontSize: 13),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const Gap(10),
                Row(
                  children: [
                    if (tags.isNotEmpty)
                      Expanded(
                        child: Wrap(
                          spacing: 4,
                          children: tags
                              .take(3)
                              .map((t) => Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Color(t.colorValue)
                                          .withOpacity(0.15),
                                      borderRadius:
                                          BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      t.name,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Color(t.colorValue),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ))
                              .toList(),
                        ),
                      )
                    else
                      const Spacer(),
                    Text(
                      _formatDate(note.modifiedAt),
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return DateFormat('HH:mm').format(dt);
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return DateFormat('EEEE').format(dt);
    return DateFormat('MMM d').format(dt);
  }
}

class _DeleteBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.error.withOpacity(0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.error.withOpacity(0.3)),
      ),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 20),
      child: const Icon(Icons.delete_outline, color: AppTheme.error),
    );
  }
}