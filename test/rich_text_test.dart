import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:html/parser.dart' as html;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:hajqasem_app/application/notebook_controller.dart';
import 'package:hajqasem_app/data/legacy_api.dart';
import 'package:hajqasem_app/data/notebook_database.dart';
import 'package:hajqasem_app/domain/library.dart';
import 'package:hajqasem_app/domain/note.dart';
import 'package:hajqasem_app/domain/rich_text.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hajqasem_app/ui/theme.dart';
import 'package:hajqasem_app/ui/editor_screen.dart';
import 'package:hajqasem_app/ui/library_reader_screen.dart';

void main() {
  sqfliteFfiInit();

  test('reader keeps safe inline images and uploaded videos playable', () {
    final output = html.parseFragment(readableHtml(
      '<p>پیش از رسانه</p><figure><img src="upload/news-media/pic.png"></figure>'
      '<figure class="media"><video controls playsinline><source src="/upload/news-media/clip.mp4" type="video/mp4"></video></figure>'
      '<video src="javascript:alert(1)"></video>',
      Uri.parse('https://divanhajghasem.ir/api.php'),
    ));
    expect(output.querySelector('img')!.attributes['src'],
        'https://divanhajghasem.ir/upload/news-media/pic.png');
    expect(output.querySelector('video')!.attributes.containsKey('controls'), isTrue);
    expect(output.querySelector('video source')!.attributes['src'],
        'https://divanhajghasem.ir/upload/news-media/clip.mp4');
    expect(output.querySelectorAll('video'), hasLength(1));
  });

  test('whitespace-only rich text does not become a publishable HTML body', () {
    final document = documentForNote(Note.empty().copyWith(body: '  \n '));
    expect(documentHtml(document), isEmpty);
  });

  test(
    'HTML conversion preserves Persian text, emphasis, links and images',
    () {
      final note = Note.empty().copyWith(
        bodyIsHtml: true,
        body:
            '<p dir="rtl"><strong>سلام</strong> دنیا '
            '<a href="https://example.test">پیوند</a></p>'
            '<ul><li>اول</li><li>دوم</li></ul>'
            '<p><img src="upload/sample.png"></p><script>discard</script>',
      );
      final document = documentForNote(
        note,
        baseUrl: Uri.parse('http://example.test/api.php'),
      );
      final output = html.parseFragment(documentHtml(document));
      expect(output.querySelector('strong')!.text, 'سلام');
      expect(
        output.querySelector('a')!.attributes['href'],
        'https://example.test',
      );
      expect(output.querySelectorAll('li'), hasLength(2));
      expect(
        output.querySelector('img')!.attributes['src'],
        'http://example.test/upload/sample.png',
      );
      expect(document.toPlainText(), isNot(contains('discard')));
      expect(
        document.toDelta().toJson().any(
          (op) => (op['attributes'] as Map?)?['direction'] == 'rtl',
        ),
        isTrue,
      );
    },
  );

  test(
    'article timestamps survive the cache format without invented dates',
    () {
      final article = LibraryArticle.fromJson({
        'nid': '7',
        'cat_id': '61',
        'news_heading': 'عنوان',
        'news_date': 'به قلم نویسنده',
        'news_description': '<p>متن</p>',
        'created_at': '2026-10-01T10:00:00Z',
        'updated_at': '2026-10-06T11:00:00Z',
      });
      final restored = LibraryArticle.fromJson(article.toJson());
      expect(restored.createdAt, DateTime.utc(2026, 10, 1, 10));
      expect(restored.updatedAt, DateTime.utc(2026, 10, 6, 11));
      expect(restored.subtitle, 'به قلم نویسنده');
      final legacy = {...article.toJson()}
        ..remove('created_at')
        ..remove('updated_at');
      expect(LibraryArticle.fromJson(legacy).createdAt, isNull);
      expect(LibraryArticle.fromJson(legacy).updatedAt, isNull);
    },
  );

  testWidgets(
    'rich editor autosaves formatting and restores Delta after restart',
    (tester) async {
      final folder = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('divan-rich-'),
      ))!;
      final path = '${folder.path}/notes.db';
      final database = (await tester.runAsync(
        () => NotebookDatabase.open(path: path, factory: databaseFactoryFfi),
      ))!;
      final controller = NotebookController(
        database,
        api: LegacyApi(
          client: MockClient((_) async => http.Response('[]', 200)),
        ),
      );
      await tester.runAsync(controller.load);
      await tester.runAsync(controller.refreshCategories);
      final note = Note.empty();
      await tester.pumpWidget(
        MaterialApp(
          theme: notebookTheme(),
          locale: const Locale('fa'),
          supportedLocales: const [Locale('fa')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: EditorScreen(controller: controller, initial: note),
        ),
      );
      await tester.runAsync(() => database.preference('barrier'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('note-body')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      final editor = tester.widget<quill.QuillEditor>(
        find.byType(quill.QuillEditor),
      );
      await tester.runAsync(() async {
        editor.controller.replaceText(0, 0, 'متن آفلاین', null);
        editor.controller.formatText(0, 3, quill.Attribute.bold);
        await Future<void>.delayed(Duration.zero);
      });
      for (var i = 0; i < 20; i++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      await tester.runAsync(controller.flush);
      await tester.pump();
      final saved = (await tester.runAsync(() => database.note(note.id)))!;
      expect(saved.bodyIsHtml, isTrue);
      expect(
        html.parseFragment(saved.body).querySelector('strong')!.text,
        'متن',
      );
      expect(saved.richTextDelta, isNotNull);
      expect(saved.copyWith(title: 'عنوان').richTextDelta, saved.richTextDelta);
      expect(saved.copyWith(body: 'متن جایگزین').richTextDelta, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      await tester.runAsync(database.close);
      final reopened = (await tester.runAsync(
        () => NotebookDatabase.open(path: path, factory: databaseFactoryFfi),
      ))!;
      final recovered = (await tester.runAsync(() => reopened.note(note.id)))!;
      expect(
        documentForNote(recovered).toDelta().toJson(),
        jsonDecode(saved.richTextDelta!),
      );
      expect(await tester.runAsync(reopened.pendingCount), 1);
      await tester.runAsync(reopened.close);
      await tester.runAsync(() => folder.delete(recursive: true));
      expect(tester.takeException(), isNull);
    },
  );
}
