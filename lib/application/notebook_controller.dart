import 'dart:collection';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../data/notebook_database.dart';
import '../domain/note.dart';
import '../domain/library.dart';
import '../data/legacy_api.dart';
import '../data/library_repository.dart';
import '../data/post_api.dart';
import '../data/post_service.dart';

class NotebookController extends ChangeNotifier {
  NotebookController(this.database, {LegacyApi? api, PostApi? postApi}) {
    library = LibraryRepository(database, api ?? LegacyApi());
    posts = PostService(library, postApi ?? PostApi(library.api.endpoint));
    posts.api.addListener(notifyListeners);
  }
  final NotebookDatabase database;
  late final LibraryRepository library;
  late final PostService posts;

  @override
  void dispose() {
    posts.api.removeListener(notifyListeners);
    posts.api.close();
    library.api.close();
    library.dispose();
    super.dispose();
  }

  List<Note> notes = [];
  List<NoteCategory> categories = [];
  List<NoteCategory> _storedCategories = [];
  String? lastNoteId;
  double textSize = 24;
  int pendingCount = 0;
  Future<void> _writes = Future.value();

  Future<void> load() async {
    notes = await database.listNotes();
    _storedCategories = await database.categories();
    try {
      await cachedCategories();
    } catch (_) {
      categories = [];
    }
    lastNoteId = await database.preference('last_note');
    textSize =
        (double.tryParse(await database.preference('font_size') ?? '') ?? 24)
            .clamp(20, 32)
            .toDouble();
    pendingCount = await database.pendingCount();
    notifyListeners();
  }

  /// Re-read personal notes when the notes tab becomes visible. This keeps
  /// the list correct after returning from an editor or another route that
  /// may have committed directly to the local database.
  Future<void> refreshNotes() async {
    await _writes;
    notes = await database.listNotes();
    pendingCount = await database.pendingCount();
    notifyListeners();
  }

  /// All user edits are queued in their input order, without an autosave timer.
  /// Failure is returned to the editor; the queue stays available for retry.
  Future<Note> save(Note draft, {String? editSession}) {
    final result = _writes.then(
      (_) => database.save(draft, editSession: editSession),
    );
    _writes = result.then((_) {}, onError: (Object error, StackTrace stack) {});
    return result.then((saved) async {
      // Avoid rereading every note body on every keystroke. The transaction
      // already returned the durable record, in the same order as input.
      notes = [
        ...notes.where((n) => n.id != saved.id),
        if (!saved.deleted) saved,
      ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      try {
        pendingCount = await database.pendingCount();
      } catch (_) {
        /* A status refresh failure must not report a committed edit as unsaved. */
      }
      notifyListeners();
      return saved;
    });
  }

  Future<void> flush() => _writes;

  Future<void> deletePost(LibraryArticle article) => posts.delete(article);

  Future<Note?> publish(Note draft) async {
    await flush();
    final remaining = await posts.publish(draft);
    notes = [
      for (final n in notes)
        if (n.id != draft.id) n,
      if (remaining != null && !remaining.deleted) remaining,
    ];
    try {
      pendingCount = await database.pendingCount();
    } catch (_) {}
    notifyListeners();
    return remaining;
  }

  Future<Note> draftForArticle(LibraryArticle article) async {
    await flush();
    final drafts = await database.listNotes();
    for (final draft in drafts) {
      if (draft.serverSource == library.api.endpoint.toString() &&
          draft.original?.id == article.id) {
        return draft;
      }
    }
    return Note.empty().copyWith(
      title: article.title,
      subtitle: article.subtitle,
      body: article.htmlBody,
      bodyIsHtml: true,
      categoryId: library.noteCategoryId(article.categoryId),
      serverBase: jsonEncode(article.toJson()),
      serverSource: library.api.endpoint.toString(),
    );
  }

  String categoryName(String? id) =>
      _storedCategories
          .where((c) => c.id == id)
          .map((c) => c.name)
          .firstOrNull ??
      'بدون دسته';

  Future<void> _setCategories(List<LibraryCategory> data) async {
    _storedCategories = await database.categories();
    categories = [
      for (final category in data)
        NoteCategory(
          library.noteCategoryId(category.id),
          plainHtml(category.name),
        ),
    ];
    notifyListeners();
  }

  Future<List<LibraryCategory>?> cachedCategories() async {
    final data = await library.cachedCategories();
    if (data != null) await _setCategories(data);
    return data;
  }

  Future<List<LibraryCategory>> refreshCategories() async {
    final data = await library.refreshCategories();
    await _setCategories(data);
    return data;
  }

  Note? get lastNote => notes.where((n) => n.id == lastNoteId).firstOrNull;

  Future<void> opened(Note note) async {
    await database.setPreference('last_note', note.id);
    lastNoteId = note.id;
    notifyListeners();
  }

  Future<void> setTextSize(double size) async {
    final next = size.clamp(20.0, 32.0).toDouble();
    await database.setPreference('font_size', next.toString());
    textSize = next;
    notifyListeners();
  }
}
