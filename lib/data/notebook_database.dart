import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import '../domain/note.dart';

/// SQLite is the source of truth. A content change, its prior version, and
/// its outbox entry commit in one transaction. No server is required to read.
class NotebookDatabase {
  NotebookDatabase(this.db);
  final Database db;

  static Future<NotebookDatabase> open({
    String? path,
    DatabaseFactory? factory,
  }) async {
    final sqlFactory =
        factory ?? (kIsWeb ? databaseFactoryFfiWeb : databaseFactory);
    final databasePath =
        path ??
        (kIsWeb
            ? 'hajqasem.db'
            : p.join(await sqlFactory.getDatabasesPath(), 'hajqasem.db'));
    final db = await sqlFactory.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 6,
        onConfigure: (db) async {
          final version = await db.getVersion();
          await db.execute(
            'PRAGMA foreign_keys = ${version > 0 && version < 3 ? 'OFF' : 'ON'}',
          );
          await db.execute('PRAGMA synchronous = FULL');
        },
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE categories (id TEXT PRIMARY KEY, name TEXT NOT NULL)',
          );
          await db.execute('''CREATE TABLE notes (
            id TEXT PRIMARY KEY, title TEXT NOT NULL, body TEXT NOT NULL,
            category_id TEXT REFERENCES categories(id), updated_at INTEGER NOT NULL,
            revision INTEGER NOT NULL, favorite INTEGER NOT NULL DEFAULT 0,
            deleted INTEGER NOT NULL DEFAULT 0, last_edit_session TEXT)''');
          await db.execute(
            '''CREATE TABLE versions (id INTEGER PRIMARY KEY AUTOINCREMENT,
            note_id TEXT NOT NULL REFERENCES notes(id), title TEXT NOT NULL,
            body TEXT NOT NULL, created_at INTEGER NOT NULL)''',
          );
          await db.execute(
            '''CREATE TABLE outbox (note_id TEXT PRIMARY KEY REFERENCES notes(id),
            revision INTEGER NOT NULL, payload TEXT NOT NULL)''',
          );
          await db.execute(
            'CREATE TABLE preferences (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE INDEX notes_updated ON notes(deleted, updated_at DESC)',
          );
          await _createLibraryCache(db);
          await _createPostSupport(db);
          await _createLocalPosts(db);
          await _createRichTextSupport(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) await _createLibraryCache(db);
          if (oldVersion < 3) {
            await db.execute(
              'CREATE TABLE categories_next (id TEXT PRIMARY KEY, name TEXT NOT NULL)',
            );
            await db.execute('''INSERT INTO categories_next SELECT id, name
              FROM categories WHERE id IN
              (SELECT category_id FROM notes WHERE category_id IS NOT NULL)''');
            await db.execute('DROP TABLE categories');
            await db.execute(
              'ALTER TABLE categories_next RENAME TO categories',
            );
            if ((await db.rawQuery('PRAGMA foreign_key_check')).isNotEmpty) {
              throw StateError('Category migration broke a reference');
            }
          }
          if (oldVersion < 4) await _createPostSupport(db);
          if (oldVersion < 5) await _createLocalPosts(db);
          if (oldVersion < 6) await _createRichTextSupport(db);
        },
        onOpen: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
      ),
    );
    return NotebookDatabase(db);
  }

  static Future<void> _createLibraryCache(Database db) => db.execute('''
    CREATE TABLE library_cache (cache_key TEXT PRIMARY KEY,
      payload TEXT NOT NULL, fetched_at INTEGER NOT NULL)''');

  static Future<void> _createRichTextSupport(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(notes)');
    if (!columns.any((column) => column['name'] == 'rich_text_delta')) {
      await db.execute('ALTER TABLE notes ADD COLUMN rich_text_delta TEXT');
    }
  }

  static Future<void> _createPostSupport(Database db) async {
    final columns = (await db.rawQuery(
      'PRAGMA table_info(notes)',
    )).map((row) => row['name']).toSet();
    for (final entry in {
      'subtitle': "TEXT NOT NULL DEFAULT ''",
      'body_is_html': 'INTEGER NOT NULL DEFAULT 0',
      'server_base': 'TEXT',
      'server_source': 'TEXT',
    }.entries) {
      if (!columns.contains(entry.key)) {
        await db.execute(
          'ALTER TABLE notes ADD COLUMN ${entry.key} ${entry.value}',
        );
      }
    }
    final versionColumns = (await db.rawQuery(
      'PRAGMA table_info(versions)',
    )).map((row) => row['name']).toSet();
    if (!versionColumns.contains('snapshot')) {
      await db.execute('ALTER TABLE versions ADD COLUMN snapshot TEXT');
    }
    await db.execute(
      'CREATE TABLE IF NOT EXISTS post_operations (operation_key TEXT PRIMARY KEY, payload TEXT NOT NULL)',
    );
  }

  static Future<void> _createLocalPosts(Database db) => db.execute('''
    CREATE TABLE IF NOT EXISTS local_posts (
      id TEXT PRIMARY KEY, category_id TEXT NOT NULL, title TEXT NOT NULL,
      subtitle TEXT NOT NULL DEFAULT '', html_body TEXT NOT NULL,
      updated_at INTEGER NOT NULL, deleted INTEGER NOT NULL DEFAULT 0)
  ''');

  Future<List<Note>> listNotes({bool deleted = false}) async => (await db.query(
    'notes',
    where: 'deleted = ?',
    whereArgs: [deleted ? 1 : 0],
    orderBy: 'updated_at DESC',
  )).map(Note.fromMap).toList();

  Future<Note?> note(String id) async {
    final rows = await db.query('notes', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Note.fromMap(rows.first);
  }

  Future<Note> save(Note draft, {String? editSession}) => db.transaction((
    txn,
  ) async {
    final rows = await txn.query(
      'notes',
      where: 'id = ?',
      whereArgs: [draft.id],
    );
    final previous = rows.isEmpty ? null : Note.fromMap(rows.first);
    if (previous != null &&
        previous.title == draft.title &&
        previous.body == draft.body &&
        previous.categoryId == draft.categoryId &&
        previous.favorite == draft.favorite &&
        previous.deleted == draft.deleted) {
      if (previous.subtitle == draft.subtitle &&
          previous.bodyIsHtml == draft.bodyIsHtml &&
          previous.serverBase == draft.serverBase &&
          previous.serverSource == draft.serverSource &&
          previous.richTextDelta == draft.richTextDelta) {
        return previous;
      }
    }
    final contentChanged =
        previous != null &&
        (previous.title != draft.title ||
            previous.body != draft.body ||
            previous.subtitle != draft.subtitle ||
            previous.bodyIsHtml != draft.bodyIsHtml ||
            previous.richTextDelta != draft.richTextDelta);
    // Keep a complete pre-edit snapshot once per editor visit rather than
    // replacing meaningful history with the last 20 individual keystrokes.
    if (previous != null &&
        contentChanged &&
        (editSession == null ||
            rows.first['last_edit_session'] != editSession)) {
      await txn.insert('versions', {
        'note_id': draft.id,
        'title': previous.title,
        'body': previous.body,
        'created_at': previous.updatedAt.millisecondsSinceEpoch,
        'snapshot': jsonEncode(previous.toMap()),
      });
      // Retain the newest 20 recovery snapshots per note.
      await txn.rawDelete(
        '''DELETE FROM versions WHERE note_id = ? AND id NOT IN
        (SELECT id FROM versions WHERE note_id = ? ORDER BY id DESC LIMIT 20)''',
        [draft.id, draft.id],
      );
    }
    final saved = draft.copyWith(
      revision: (previous?.revision ?? 0) + 1,
      updatedAt: DateTime.now(),
      serverBase: previous?.serverBase,
      serverSource: previous?.serverSource,
    );
    final values = {
      ...saved.toMap(),
      'last_edit_session': previous == null || contentChanged
          ? editSession
          : rows.first['last_edit_session'],
    };
    if (previous == null) {
      await txn.insert('notes', values);
    } else {
      await txn.update('notes', values, where: 'id = ?', whereArgs: [saved.id]);
    }
    await txn.insert('outbox', {
      'note_id': saved.id,
      'revision': saved.revision,
      'payload': jsonEncode(saved.toMap()),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return saved;
  });

  Future<List<NoteCategory>> categories() async =>
      (await db.query('categories', orderBy: 'rowid'))
          .map(
            (row) => NoteCategory(row['id']! as String, row['name']! as String),
          )
          .toList();

  Future<List<NoteVersion>> versions(String noteId) async =>
      (await db.query(
            'versions',
            where: 'note_id = ?',
            whereArgs: [noteId],
            orderBy: 'id DESC',
          ))
          .map(
            (r) => NoteVersion(
              id: r['id']! as int,
              noteId: r['note_id']! as String,
              title: r['title']! as String,
              body: r['body']! as String,
              createdAt: DateTime.fromMillisecondsSinceEpoch(
                r['created_at']! as int,
              ),
              snapshot: r['snapshot'] == null
                  ? null
                  : Note.fromMap(
                      jsonDecode(r['snapshot']! as String)
                          as Map<String, dynamic>,
                    ),
            ),
          )
          .toList();

  Future<String?> preference(String key) async {
    final rows = await db.query(
      'preferences',
      where: 'key = ?',
      whereArgs: [key],
    );
    return rows.isEmpty ? null : rows.first['value']! as String;
  }

  Future<void> setPreference(String key, String value) async {
    await db.insert('preferences', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> pendingCount() async =>
      Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM outbox')) ??
      0;
  Future<void> acknowledge(String noteId, int revision) async {
    // A late server acknowledgement must never discard a newer local edit.
    await db.delete(
      'outbox',
      where: 'note_id = ? AND revision = ?',
      whereArgs: [noteId, revision],
    );
  }

  Future<void> close() => db.close();
}
