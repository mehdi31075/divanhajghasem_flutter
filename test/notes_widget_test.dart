import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:hajqasem_app/application/notebook_controller.dart';
import 'package:hajqasem_app/data/notebook_database.dart';
import 'package:hajqasem_app/domain/note.dart';
import 'package:hajqasem_app/main.dart';

void main() {
  sqfliteFfiInit();

  testWidgets(
    'drafts are hidden from public navigation and remain available to admins',
    (tester) async {
      final database = (await tester.runAsync(
        () => NotebookDatabase.open(
          path: inMemoryDatabasePath,
          factory: databaseFactoryFfi,
        ),
      ))!;
      final controller = NotebookController(database);
      await tester.runAsync(controller.load);
      await tester.runAsync(
        () => controller.save(
          Note.empty().copyWith(title: 'یادداشت آزمایشی', body: 'متن یادداشت'),
        ),
      );
      await tester.pumpWidget(HajQasemApp(controller: controller));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('notes-tab')), findsNothing);
      expect(find.text('یادداشت آزمایشی'), findsNothing);
      controller.posts.api.authenticated = true;
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings-tab')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('پیش‌نویس‌های ادمین'));
      await tester.runAsync(controller.refreshNotes);
      await tester.pumpAndSettle();
      expect(find.text('یادداشت آزمایشی'), findsOneWidget);
      expect(find.text('متن یادداشت'), findsOneWidget);
      expect(find.text('پیش‌نویسی ندارید'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(database.close);
      controller.dispose();
    },
  );
}
