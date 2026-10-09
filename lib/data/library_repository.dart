import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../domain/library.dart';
import '../domain/content_page.dart';
import 'legacy_api.dart';
import 'notebook_database.dart';

/// Public server content has its own cache. It never updates editable notes,
/// their revision history, or the pending local outbox.
class LibraryRepository extends ChangeNotifier {
  LibraryRepository(this.database, this.api);
  final NotebookDatabase database;
  final LegacyApi api;
  final Map<String, Future<Object>> _refreshes = {};
  int _articleEpoch = 0;

  String _key(String resource) => '${api.endpoint}::$resource';

  String noteCategoryId(String id) => _key('category:$id');

  String? serverCategoryId(String localId) {
    final prefix = _key('category:');
    return localId.startsWith(prefix) ? localId.substring(prefix.length) : null;
  }

  Future<void> _storeCategoryReferences(
    Transaction txn,
    List<LibraryCategory> categories,
  ) async {
    for (final category in categories) {
      final id = noteCategoryId(category.id);
      await txn.insert('categories', {
        'id': id,
        'name': plainHtml(category.name),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await txn.update(
        'categories',
        {'name': plainHtml(category.name)},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  Future<List<Map<String, dynamic>>?> _cached(String resource) async {
    final rows = await database.db.query(
      'library_cache',
      where: 'cache_key = ?',
      whereArgs: [_key(resource)],
    );
    if (rows.isEmpty) return null;
    return (jsonDecode(rows.single['payload']! as String) as List)
        .cast<Map<String, dynamic>>();
  }

  Future<void> _store(
    String resource,
    List<Map<String, dynamic>> data, {
    List<LibraryCategory>? categories,
    int? articleEpoch,
  }) async {
    await database.db.transaction((txn) async {
      if (articleEpoch != null && articleEpoch != _articleEpoch) return;
      if (categories != null) await _storeCategoryReferences(txn, categories);
      await txn.insert('library_cache', {
        'cache_key': _key(resource),
        'payload': jsonEncode(data),
        'fetched_at': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  // Concurrent screens share one refresh; an older response cannot finish last
  // and overwrite a newer refresh of the same resource.
  Future<T> _refresh<T extends Object>(
    String key,
    Future<T> Function() operation,
  ) async {
    final pending = _refreshes[key];
    if (pending != null) return await pending as T;
    final result = operation();
    _refreshes[key] = result;
    try {
      return await result;
    } finally {
      _refreshes.remove(key);
    }
  }

  Future<List<LibraryCategory>?> cachedCategories() async {
    final rows = await _cached('categories');
    if (rows == null) return null;
    final categories = rows.map(LibraryCategory.fromJson).toList();
    await database.db.transaction(
      (txn) => _storeCategoryReferences(txn, categories),
    );
    return categories;
  }

  Future<List<LibraryArticle>?> cachedArticles(String id) async =>
      (await _cached('category:$id'))?.map(LibraryArticle.fromJson).toList();

  Future<List<ContentPage>?> cachedPages() async =>
      (await _cached('pages'))?.map(ContentPage.fromJson).toList();

  Future<List<ContentPage>> refreshPages() => _refresh('pages', () async {
    final pages = await api.pages();
    await _store('pages', pages.map((page) => page.toJson()).toList());
    return pages;
  });

  Future<List<LibraryCategory>> refreshCategories() =>
      _refresh('categories', () async {
        final data = await api.categories();
        await _store(
          'categories',
          data.map((c) => c.toJson()).toList(),
          categories: data,
        );
        return data;
      });

  Future<List<LibraryArticle>> refreshArticles(String id) =>
      _refresh('category:$id', () async {
        final epoch = _articleEpoch;
        final data = await api.articles(id);
        await _store(
          'category:$id',
          data.map((a) => a.toJson()).toList(),
          articleEpoch: epoch,
        );
        return epoch == _articleEpoch ? data : await cachedArticles(id) ?? data;
      });

  Future<int> recordArticleView(LibraryArticle article) async {
    final count = await api.incrementArticleView(article.id);
    final rows = await _cached('category:${article.categoryId}') ?? [];
    final updated = rows.map((row) {
      if (row['nid']?.toString() != article.id) return row;
      return <String, dynamic>{...row, 'view_count': count};
    }).toList();
    if (rows.isNotEmpty) {
      await _store('category:${article.categoryId}', updated);
      notifyListeners();
    }
    return count;
  }

  Future<void> commitPost({
    required String articleId,
    required Future<void> Function(Transaction) acknowledge,
    String? categoryId,
    List<LibraryArticle>? categoryArticles,
  }) async {
    _articleEpoch++;
    await database.db.transaction((txn) async {
      final rows = await txn.query('library_cache');
      for (final row in rows) {
        final key = row['cache_key']! as String;
        if (!key.startsWith(_key('category:'))) continue;
        final articles = (jsonDecode(row['payload']! as String) as List)
            .cast<Map<String, dynamic>>();
        articles.removeWhere(
          (article) => article['nid'].toString() == articleId,
        );
        await txn.update(
          'library_cache',
          {'payload': jsonEncode(articles)},
          where: 'cache_key = ?',
          whereArgs: [key],
        );
      }
      if (categoryId != null && categoryArticles != null) {
        await txn.insert('library_cache', {
          'cache_key': _key('category:$categoryId'),
          'payload': jsonEncode(
            categoryArticles.map((article) => article.toJson()).toList(),
          ),
          'fetched_at': DateTime.now().millisecondsSinceEpoch,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await acknowledge(txn);
    });
    notifyListeners();
  }
}
