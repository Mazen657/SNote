import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/encryption/encryption_service.dart';
import '../../core/security/security_service.dart';
import '../../core/storage/hive_storage.dart';
import 'note_model.dart';

/// All CRUD operations for notes and tags.
/// Notes are encrypted/decrypted transparently; only [NoteView] objects
/// (decrypted, in-memory) are exposed to the UI.
class NotesRepository {
  final EncryptionService _enc;

  NotesRepository(this._enc);

  // ─── Create ───────────────────────────────────────────────────────────────

  Future<NoteView> createNote({
    required String title,
    required String content,
    List<String> tagIds = const [],
  }) async {
    final salt = _enc.generateNoteSalt();
    final encTitle = await _enc.encryptTitle(
      title.isEmpty ? 'Untitled' : title,
      salt,
    );
    final encContent = await _enc.encryptContent(content, salt);

    final model = NoteModel(
      encryptedTitle: encTitle,
      encryptedContent: encContent,
      noteSalt: salt,
      tagIds: tagIds,
    );
    await HiveStorage.notesBox.put(model.id, model.toJson());
    return _toView(model, title.isEmpty ? 'Untitled' : title, content);
  }

  // ─── Read ─────────────────────────────────────────────────────────────────

  Future<List<NoteView>> getAllNotes() async {
    final views = <NoteView>[];
    for (final key in HiveStorage.notesBox.keys) {
      final raw = HiveStorage.notesBox.get(key);
      if (raw == null) continue;
      final model =
          NoteModel.fromJson(Map<String, dynamic>.from(raw as Map));
      if (model.isDeleted) continue;
      try {
        final title = await _enc.decryptTitle(
            model.encryptedTitle, model.noteSalt);
        final content = await _enc.decryptContent(
            model.encryptedContent, model.noteSalt);
        views.add(_toView(model, title, content));
      } catch (_) {
        // Skip notes that cannot be decrypted (wrong key / corruption).
      }
    }
    views.sort((a, b) {
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;
      return b.modifiedAt.compareTo(a.modifiedAt);
    });
    return views;
  }

  Future<NoteView?> getNoteById(String id) async {
    final raw = HiveStorage.notesBox.get(id);
    if (raw == null) return null;
    final model =
        NoteModel.fromJson(Map<String, dynamic>.from(raw as Map));
    try {
      final title =
          await _enc.decryptTitle(model.encryptedTitle, model.noteSalt);
      final content =
          await _enc.decryptContent(model.encryptedContent, model.noteSalt);
      return _toView(model, title, content);
    } catch (_) {
      return null;
    }
  }

  // ─── Update ───────────────────────────────────────────────────────────────

  /// Re-encrypts with a fresh salt on every save — rotating the per-note key.
  Future<NoteView?> updateNote({
    required String id,
    String? title,
    String? content,
    List<String>? tagIds,
    bool? isPinned,
  }) async {
    final raw = HiveStorage.notesBox.get(id);
    if (raw == null) return null;
    final existing =
        NoteModel.fromJson(Map<String, dynamic>.from(raw as Map));

    // Always generate a fresh salt so the encryption key rotates.
    final newSalt = _enc.generateNoteSalt();

    final resolvedTitle = title ??
        await _enc.decryptTitle(existing.encryptedTitle, existing.noteSalt);
    final resolvedContent = content ??
        await _enc.decryptContent(
            existing.encryptedContent, existing.noteSalt);

    final encTitle = await _enc.encryptTitle(resolvedTitle, newSalt);
    final encContent = await _enc.encryptContent(resolvedContent, newSalt);

    final updated = existing.copyWith(
      encryptedTitle: encTitle,
      encryptedContent: encContent,
      noteSalt: newSalt,
      tagIds: tagIds,
      isPinned: isPinned,
    );
    await HiveStorage.notesBox.put(id, updated.toJson());
    return _toView(updated, resolvedTitle, resolvedContent);
  }

  Future<void> togglePin(String id) async {
    final view = await getNoteById(id);
    if (view == null) return;
    await updateNote(id: id, isPinned: !view.isPinned);
  }

  // ─── Delete ───────────────────────────────────────────────────────────────

  Future<void> softDeleteNote(String id) async {
    final raw = HiveStorage.notesBox.get(id);
    if (raw == null) return;
    final model =
        NoteModel.fromJson(Map<String, dynamic>.from(raw as Map));
    await HiveStorage.notesBox.put(id, model.copyWith(isDeleted: true).toJson());
  }

  Future<void> permanentlyDeleteNote(String id) =>
      HiveStorage.notesBox.delete(id);

  // ─── Search ───────────────────────────────────────────────────────────────

  Future<List<NoteView>> search(String query) async {
    if (query.trim().isEmpty) return getAllNotes();
    final lower = query.toLowerCase();
    final all = await getAllNotes();
    return all
        .where((n) =>
            n.title.toLowerCase().contains(lower) ||
            n.content.toLowerCase().contains(lower))
        .toList();
  }

  Future<List<NoteView>> filterByTag(String tagId) async {
    final all = await getAllNotes();
    return all.where((n) => n.tagIds.contains(tagId)).toList();
  }

  // ─── Tags ─────────────────────────────────────────────────────────────────

  Future<TagModel> createTag(String name, {int? colorValue}) async {
    final tag = TagModel(name: name, colorValue: colorValue);
    await HiveStorage.tagsBox.put(tag.id, tag.toJson());
    return tag;
  }

  List<TagModel> getAllTags() {
    return HiveStorage.tagsBox.values
        .map((raw) =>
            TagModel.fromJson(Map<String, dynamic>.from(raw as Map)))
        .toList();
  }

  Future<void> deleteTag(String id) async {
    await HiveStorage.tagsBox.delete(id);
    for (final key in List.from(HiveStorage.notesBox.keys)) {
      final raw = HiveStorage.notesBox.get(key);
      if (raw == null) continue;
      final model =
          NoteModel.fromJson(Map<String, dynamic>.from(raw as Map));
      if (model.tagIds.contains(id)) {
        final updated = model.copyWith(
          tagIds: model.tagIds.where((t) => t != id).toList(),
        );
        await HiveStorage.notesBox.put(key, updated.toJson());
      }
    }
  }

  // ─── Backup & Restore ─────────────────────────────────────────────────────

  Future<File> exportBackup() async {
    final notesRaw = HiveStorage.notesBox.values.toList();
    final tagsRaw = HiveStorage.tagsBox.values.toList();
    final payload = jsonEncode({
      'version': 2,
      'exportedAt': DateTime.now().toIso8601String(),
      'notes': notesRaw,
      'tags': tagsRaw,
    });

    // Encrypt the entire JSON blob with a throw-away salt.
    final backupSalt = _enc.generateNoteSalt();
    final encPayload = await _enc.encryptContent(payload, backupSalt);

    final dir = await getApplicationDocumentsDirectory();
    final name =
        'snote_backup_${DateTime.now().millisecondsSinceEpoch}.notesbackup';
    final file = File('${dir.path}/$name');
    await file.writeAsString(
        jsonEncode({'salt': backupSalt, 'data': encPayload}));
    return file;
  }

  Future<int> importBackup(File file) async {
    final wrapper =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final salt = wrapper['salt'] as String;
    final encData = wrapper['data'] as String;
    final payload =
        jsonDecode(await _enc.decryptContent(encData, salt)) as Map<String, dynamic>;

    final notes = (payload['notes'] as List).cast<Map>();
    final tags = (payload['tags'] as List? ?? []).cast<Map>();

    for (final t in tags) {
      final tag = TagModel.fromJson(Map<String, dynamic>.from(t));
      await HiveStorage.tagsBox.put(tag.id, tag.toJson());
    }

    int count = 0;
    for (final n in notes) {
      final model = NoteModel.fromJson(Map<String, dynamic>.from(n));
      if (!model.isDeleted) {
        await HiveStorage.notesBox.put(model.id, model.toJson());
        count++;
      }
    }
    return count;
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  NoteView _toView(NoteModel model, String title, String content) => NoteView(
        id: model.id,
        title: title,
        content: content,
        createdAt: model.createdAt,
        modifiedAt: model.modifiedAt,
        tagIds: model.tagIds,
        isPinned: model.isPinned,
      );
}

// ─── Providers ────────────────────────────────────────────────────────────────

final notesRepositoryProvider = Provider<NotesRepository>((ref) {
  final security = ref.watch(securityServiceProvider);
  return NotesRepository(security.encryptionService);
});

final notesProvider =
    AsyncNotifierProvider<NotesNotifier, List<NoteView>>(NotesNotifier.new);

final tagsProvider =
    NotifierProvider<TagsNotifier, List<TagModel>>(TagsNotifier.new);

// ─── State Notifiers ──────────────────────────────────────────────────────────

class NotesNotifier extends AsyncNotifier<List<NoteView>> {
  String _tagFilter = '';
  String _searchQuery = '';

  @override
  Future<List<NoteView>> build() => _load();

  Future<List<NoteView>> _load() {
    final repo = ref.read(notesRepositoryProvider);
    if (_searchQuery.isNotEmpty) return repo.search(_searchQuery);
    if (_tagFilter.isNotEmpty) return repo.filterByTag(_tagFilter);
    return repo.getAllNotes();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_load);
  }

  void search(String query) {
    _searchQuery = query;
    _tagFilter = '';
    refresh();
  }

  void filterByTag(String tagId) {
    _tagFilter = tagId;
    _searchQuery = '';
    refresh();
  }

  void clearFilters() {
    _tagFilter = '';
    _searchQuery = '';
    refresh();
  }

  Future<void> createNote({
    required String title,
    required String content,
    List<String> tagIds = const [],
  }) async {
    await ref
        .read(notesRepositoryProvider)
        .createNote(title: title, content: content, tagIds: tagIds);
    await refresh();
  }

  Future<void> updateNote({
    required String id,
    String? title,
    String? content,
    List<String>? tagIds,
    bool? isPinned,
  }) async {
    await ref.read(notesRepositoryProvider).updateNote(
          id: id,
          title: title,
          content: content,
          tagIds: tagIds,
          isPinned: isPinned,
        );
    await refresh();
  }

  Future<void> deleteNote(String id) async {
    await ref.read(notesRepositoryProvider).softDeleteNote(id);
    await refresh();
  }

  Future<void> togglePin(String id) async {
    await ref.read(notesRepositoryProvider).togglePin(id);
    await refresh();
  }
}

class TagsNotifier extends Notifier<List<TagModel>> {
  @override
  List<TagModel> build() =>
      ref.read(notesRepositoryProvider).getAllTags();

  Future<void> createTag(String name, {int? colorValue}) async {
    await ref
        .read(notesRepositoryProvider)
        .createTag(name, colorValue: colorValue);
    state = ref.read(notesRepositoryProvider).getAllTags();
  }

  Future<void> deleteTag(String id) async {
    await ref.read(notesRepositoryProvider).deleteTag(id);
    state = ref.read(notesRepositoryProvider).getAllTags();
  }
}