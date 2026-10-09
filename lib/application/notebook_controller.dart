import 'dart:collection';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../data/notebook_database.dart';
import '../domain/note.dart';
import '../domain/library.dart';
import '../data/legacy_api.dart';
import '../data/library_repository.dart';
import '../data/post_api.dart';
import '../data/post_service.dart';
import '../data/token_vault.dart';
import '../domain/jalali_date.dart';

class NotebookController extends ChangeNotifier {
  NotebookController(
    this.database, {
    LegacyApi? api,
    PostApi? postApi,
    TokenVault? tokenVault,
    JalaliDateService? dateService,
  }) : tokenVault = tokenVault ?? MemoryTokenVault(),
       dateService = dateService ?? const ShamsiDateService() {
    library = LibraryRepository(database, api ?? LegacyApi());
    posts = PostService(library, postApi ?? PostApi(library.api.endpoint));
    posts.api.addListener(notifyListeners);
  }
  final NotebookDatabase database;
  final TokenVault tokenVault;
  final JalaliDateService dateService;
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
    textSize = _snapReadingTextSize(
      double.tryParse(await database.preference('font_size') ?? '') ?? 24,
    );
    pendingCount = await database.pendingCount();
    accountToken = await tokenVault.read();
    if (accountToken != null) unawaited(refreshAccount());
    notifyListeners();
  }

  String? accountToken;
  Map<String, dynamic>? accountUser;
  bool get isSignedIn => accountToken != null;

  Future<Map<String, dynamic>> startAccountOtp(String mobile) =>
      library.api.startAccountOtp(mobile);

  Future<Map<String, dynamic>> verifyAccountOtp(
    String challengeId,
    String otp, {
    String? name,
  }) async {
    final result = await library.api.verifyAccountOtp(
      challengeId,
      otp,
      name: name,
    );
    final token = result['access_token'];
    if (token is String && RegExp(r'^[a-f0-9]{64}$').hasMatch(token)) {
      await tokenVault.write(token);
      accountToken = token;
      accountUser = result['user'] is Map<String, dynamic>
          ? result['user'] as Map<String, dynamic>
          : null;
      notifyListeners();
    }
    return result;
  }

  Future<void> refreshAccount() async {
    final token = accountToken;
    if (token == null) return;
    try {
      accountUser = await library.api.accountUser(token);
      notifyListeners();
    } catch (_) {
      // Keep the secure token on transient network failures; the API will
      // reject an expired token when the user next performs an account action.
    }
  }

  Future<void> logoutAccount() async {
    final token = accountToken;
    if (token != null) {
      try {
        await library.api.logoutAccount(token);
      } catch (_) {
        // Clear the device session even when offline.
      }
    }
    await tokenVault.delete();
    accountToken = null;
    accountUser = null;
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
    final next = _snapReadingTextSize(size);
    await database.setPreference('font_size', next.toString());
    textSize = next;
    notifyListeners();
  }

  Future<void> adjustTextSize(int direction) async {
    if (direction == 0) return;
    const sizes = [20.0, 24.0, 28.0];
    final currentIndex = sizes.indexOf(_snapReadingTextSize(textSize));
    final nextIndex = (currentIndex + direction.sign).clamp(
      0,
      sizes.length - 1,
    );
    await setTextSize(sizes[nextIndex]);
  }

  double _snapReadingTextSize(double size) {
    const sizes = [20.0, 24.0, 28.0];
    return sizes.reduce(
      (best, candidate) =>
          (candidate - size).abs() < (best - size).abs() ? candidate : best,
    );
  }
}
