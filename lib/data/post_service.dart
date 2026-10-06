import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../domain/library.dart';
import '../domain/note.dart';
import 'library_repository.dart';
import 'post_api.dart';

class PostService {
  PostService(this.library, this.api);
  final LibraryRepository library;
  final PostApi api;
  bool _busy = false;
  String key(String kind, String id) => '${library.api.endpoint}::$kind:$id';

  Future<Map<String, dynamic>?> _pending(String key) async {
    final rows = await library.database.db.query(
      'post_operations',
      where: 'operation_key = ?',
      whereArgs: [key],
    );
    return rows.isEmpty
        ? null
        : jsonDecode(rows.single['payload']! as String) as Map<String, dynamic>;
  }

  Future<bool> pendingDraft(String id) async =>
      await _pending(key('draft', id)) != null;
  Future<bool> pendingDelete(String id) async =>
      await _pending(key('delete', id)) != null;

  Future<T> _exclusive<T>(Future<T> Function() operation) async {
    if (_busy) throw const PostFailure('درخواست قبلی هنوز در حال انجام است.');
    _busy = true;
    try {
      return await operation();
    } finally {
      _busy = false;
    }
  }

  bool _same(LibraryArticle a, LibraryArticle b) =>
      jsonEncode(a.toJson()) == jsonEncode(b.toJson());
  bool _content(LibraryArticle a, LibraryArticle b) =>
      a.categoryId == b.categoryId &&
      a.title == b.title &&
      a.subtitle == b.subtitle &&
      a.htmlBody == b.htmlBody;

  Future<void> _journal(
    String operationKey,
    Map<String, dynamic> operation,
  ) async {
    await library.database.db.insert('post_operations', {
      'operation_key': operationKey,
      'payload': jsonEncode(operation),
    }, conflictAlgorithm: ConflictAlgorithm.abort);
  }

  Future<void> _checkOtherOperation(String articleId) async {
    final rows = await library.database.db.query('post_operations');
    for (final row in rows) {
      if (!(row['operation_key']! as String).startsWith(
        '${library.api.endpoint}::',
      )) {
        continue;
      }
      final data =
          jsonDecode(row['payload']! as String) as Map<String, dynamic>;
      if (data['articleId'] == articleId) {
        throw const PostFailure(
          'نتیجهٔ درخواست قبلی این مطلب را ابتدا بررسی کنید.',
        );
      }
    }
  }

  Future<Note?> publish(Note draft) => _exclusive(() async {
    final operationKey = key('draft', draft.id);
    var operation = await _pending(operationKey);
    if (operation == null) {
      if (draft.serverSource != null &&
          draft.serverSource != library.api.endpoint.toString()) {
        throw const PostFailure('این پیش‌نویس متعلق به سرور دیگری است.');
      }
      final category = draft.categoryId == null
          ? null
          : library.serverCategoryId(draft.categoryId!);
      if (category == null ||
          [
            draft.title,
            draft.subtitle,
            draft.body,
          ].any((s) => s.trim().isEmpty)) {
        throw const PostFailure('عنوان، عنوان فرعی، دسته و متن را کامل کنید.');
      }
      if (!(await library.api.categories()).any((c) => c.id == category)) {
        throw const PostFailure('دستهٔ انتخاب‌شده دیگر روی سرور موجود نیست.');
      }
      final original = draft.original;
      if (original != null) await _checkOtherOperation(original.id);
      final path = original == null ? 'add-menu.php' : 'edit-menu.php';
      final button = original == null ? 'btnAdd' : 'btnEdit';
      await api.requireForm(path, button, original?.id);
      if (original != null) {
        final fresh = await library.api.findArticle(original.id);
        if (fresh == null || !_same(original, fresh)) {
          throw const PostFailure(
            'مطلب روی سرور تغییر کرده یا حذف شده است. پیش‌نویس محفوظ است؛ نسخهٔ تازه را بررسی کنید.',
          );
        }
      }
      final baseline = original == null
          ? await library.api.articles(category)
          : <LibraryArticle>[];
      final target = LibraryArticle(
        id: original?.id ?? '',
        categoryId: category,
        title: draft.title,
        subtitle: draft.subtitle,
        htmlBody: draft.htmlBody,
      );
      operation = {
        'articleId': original?.id,
        'draft': draft.toMap(),
        'target': {...target.toJson(), 'nid': original?.id ?? 'pending'},
        'baseline': baseline.map((a) => a.id).toList(),
      };
      await _journal(operationKey, operation);
      try {
        await api.submit(path, {
          'news_heading': target.title,
          'news_date': target.subtitle,
          'news_description': target.htmlBody,
          'cid': category,
          button: '1',
        }, original?.id);
      } on PostRejected {
        await library.database.db.delete(
          'post_operations',
          where: 'operation_key = ?',
          whereArgs: [operationKey],
        );
        rethrow;
      } catch (_) {
        /* A timed-out POST may already have committed. Read only. */
      }
    }
    return _verifyPublish(operationKey, operation);
  });

  Future<Note?> _verifyPublish(
    String operationKey,
    Map<String, dynamic> operation,
  ) async {
    final submitted = Note.fromMap(
      Map<String, Object?>.from(operation['draft'] as Map),
    );
    final target = LibraryArticle.fromJson(
      Map<String, dynamic>.from(operation['target'] as Map),
    );
    late List<LibraryArticle> articles;
    late LibraryArticle confirmed;
    try {
      articles = await library.api.articles(target.categoryId);
      final id = operation['articleId'] as String?;
      final baseline = (operation['baseline'] as List).cast<String>();
      final matches = articles
          .where(
            (a) =>
                _content(a, target) &&
                (id == null ? !baseline.contains(a.id) : a.id == id),
          )
          .toList();
      if (matches.length != 1) throw const PostUnconfirmed();
      confirmed = matches.single;
    } catch (_) {
      throw const PostUnconfirmed();
    }

    Note? remaining;
    await library.commitPost(
      articleId: confirmed.id,
      categoryId: confirmed.categoryId,
      categoryArticles: articles,
      acknowledge: (txn) async {
        final rows = await txn.query(
          'notes',
          where: 'id = ?',
          whereArgs: [submitted.id],
        );
        if (rows.isNotEmpty) {
          final latest = Note.fromMap(rows.single);
          if (latest.revision == submitted.revision) {
            await txn.delete(
              'outbox',
              where: 'note_id = ?',
              whereArgs: [submitted.id],
            );
            await txn.delete(
              'versions',
              where: 'note_id = ?',
              whereArgs: [submitted.id],
            );
            await txn.delete(
              'notes',
              where: 'id = ?',
              whereArgs: [submitted.id],
            );
          } else {
            remaining = latest.copyWith(
              serverBase: jsonEncode(confirmed.toJson()),
              serverSource: library.api.endpoint.toString(),
            );
            await txn.update(
              'notes',
              remaining!.toMap(),
              where: 'id = ?',
              whereArgs: [submitted.id],
            );
            await txn.update(
              'outbox',
              {'payload': jsonEncode(remaining!.toMap())},
              where: 'note_id = ?',
              whereArgs: [submitted.id],
            );
          }
        }
        await txn.delete(
          'post_operations',
          where: 'operation_key = ?',
          whereArgs: [operationKey],
        );
      },
    );
    return remaining;
  }

  Future<void> delete(LibraryArticle article) => _exclusive(() async {
    final operationKey = key('delete', article.id);
    if (await _pending(operationKey) == null) {
      await _checkOtherOperation(article.id);
      await api.requireForm('delete-menu.php', 'btnDelete', article.id);
      final fresh = await library.api.findArticle(article.id);
      if (fresh != null && !_same(fresh, article)) {
        throw const PostFailure(
          'مطلب روی سرور تغییر کرده است؛ پیش از حذف نسخهٔ تازه را بررسی کنید.',
        );
      }
      await _journal(operationKey, {'articleId': article.id});
      if (fresh != null) {
        try {
          await api.submit('delete-menu.php', {'btnDelete': '1'}, article.id);
        } on PostRejected {
          await library.database.db.delete(
            'post_operations',
            where: 'operation_key = ?',
            whereArgs: [operationKey],
          );
          rethrow;
        } catch (_) {
          /* Verify without repeating the delete. */
        }
      }
    }
    try {
      if (await library.api.findArticle(article.id) != null) {
        throw const PostUnconfirmed();
      }
    } catch (_) {
      throw const PostUnconfirmed();
    }
    await library.commitPost(
      articleId: article.id,
      acknowledge: (txn) async {
        await txn.delete(
          'post_operations',
          where: 'operation_key = ?',
          whereArgs: [operationKey],
        );
      },
    );
  });
}
