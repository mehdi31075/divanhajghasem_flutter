import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:hajqasem_app/application/notebook_controller.dart';
import 'package:hajqasem_app/data/legacy_api.dart';
import 'package:hajqasem_app/data/notebook_database.dart';
import 'package:hajqasem_app/ui/support_screen.dart';
import 'package:hajqasem_app/ui/theme.dart';

void main() {
  sqfliteFfiInit();

  test('the app typography follows its four-size scale', () {
    final textTheme = notebookTheme().textTheme;
    final sizes = <double>{
      textTheme.displayLarge!.fontSize!,
      textTheme.displayMedium!.fontSize!,
      textTheme.displaySmall!.fontSize!,
      textTheme.headlineLarge!.fontSize!,
      textTheme.headlineMedium!.fontSize!,
      textTheme.headlineSmall!.fontSize!,
      textTheme.titleLarge!.fontSize!,
      textTheme.titleMedium!.fontSize!,
      textTheme.titleSmall!.fontSize!,
      textTheme.bodyLarge!.fontSize!,
      textTheme.bodyMedium!.fontSize!,
      textTheme.bodySmall!.fontSize!,
      textTheme.labelLarge!.fontSize!,
      textTheme.labelMedium!.fontSize!,
      textTheme.labelSmall!.fontSize!,
    };
    expect(sizes, {16.0, 20.0, 24.0, 28.0});
  });

  testWidgets('support asks for account only when an anonymous user sends', (
    tester,
  ) async {
    final calls = <String>[];
    final registeredNames = <String>[];
    var sent = false;
    final token = List.filled(64, 'a').join();
    final database = (await tester.runAsync(
      () => NotebookDatabase.open(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      ),
    ))!;
    final controller = NotebookController(
      database,
      api: LegacyApi(
        client: MockClient((request) async {
          final action = request.url.queryParameters['action']!;
          calls.add(action);
          final body = switch (action) {
            'user_start' => {
              'ok': true,
              'challenge_id': List.filled(64, 'b').join(),
              'test_otp': '042613',
              'mode': 'register',
            },
            'user_verify' when request.bodyFields['name'] == null => {
              'ok': true,
              'needs_name': true,
              'mode': 'register',
            },
            'user_verify' => (() {
              registeredNames.add(request.bodyFields['name']!);
              return {
                'ok': true,
                'access_token': token,
                'user': {'name': 'کاربر آزمایشی', 'mobile': '+989123456789'},
              };
            })(),
            'support_send' => {'ok': sent = true},
            'support_mine' => {
              'ok': true,
              'messages': sent
                  ? [
                      {
                        'id': '31',
                        'message': 'پیشنهاد فارسی',
                        'reply': 'پاسخ مدیر',
                        'created_at': '2026-10-09T12:00:00Z',
                        'replied_at': '2026-10-09T13:00:00Z',
                      },
                    ]
                  : [],
            },
            _ => {'ok': true},
          };
          return http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
        }),
      ),
    );
    await tester.runAsync(controller.load);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fa'),
        supportedLocales: const [Locale('fa')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: notebookTheme(),
        home: SupportScreen(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('support-send')), findsOneWidget);
    expect(find.byKey(const Key('account-mobile')), findsNothing);
    await tester.enterText(
      find.byKey(const Key('support-message')),
      'پیشنهاد فارسی',
    );
    await tester.ensureVisible(find.byKey(const Key('support-send')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('support-send')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('account-mobile')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('account-mobile')), '۱۲۳');
    await tester.tap(find.byKey(const Key('account-request-otp')));
    await tester.pumpAndSettle();
    expect(
      find.text('شمارهٔ موبایل را به شکل ۰۹۱۲۳۴۵۶۷۸۹ وارد کنید.'),
      findsOneWidget,
    );
    expect(calls, isEmpty);

    await tester.enterText(
      find.byKey(const Key('account-mobile')),
      '۰۹۱۲۳۴۵۶۷۸۹',
    );
    await tester.ensureVisible(find.byKey(const Key('account-request-otp')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('account-request-otp')));
    await tester.pumpAndSettle();
    expect(find.text('042613'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('account-otp')), '123');
    await tester.ensureVisible(find.byKey(const Key('account-verify-otp')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('account-verify-otp')));
    await tester.pumpAndSettle();
    expect(find.text('کد باید دقیقاً ۶ رقم باشد.'), findsOneWidget);
    expect(calls, ['user_start']);
    await tester.enterText(find.byKey(const Key('account-otp')), '۰۴۲۶۱۳');
    await tester.tap(find.byKey(const Key('account-verify-otp')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('account-otp')), findsNothing);
    expect(find.byKey(const Key('account-first-name')), findsOneWidget);
    expect(find.byKey(const Key('account-last-name')), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const Key('account-finish-registration')),
    );
    await tester.tap(find.byKey(const Key('account-finish-registration')));
    await tester.pumpAndSettle();
    expect(find.text('نام را وارد کنید.'), findsOneWidget);
    expect(calls, ['user_start', 'user_verify']);
    await tester.enterText(
      find.byKey(const Key('account-first-name')),
      'مهدی1',
    );
    await tester.enterText(
      find.byKey(const Key('account-last-name')),
      'آزمایشی',
    );
    await tester.tap(find.byKey(const Key('account-finish-registration')));
    await tester.pumpAndSettle();
    expect(find.text('نام را با حروف وارد کنید.'), findsOneWidget);
    expect(calls, ['user_start', 'user_verify']);
    await tester.enterText(find.byKey(const Key('account-first-name')), 'مهدی');
    await tester.enterText(
      find.byKey(const Key('account-last-name')),
      'آزمایشی',
    );
    await tester.ensureVisible(
      find.byKey(const Key('account-finish-registration')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('account-finish-registration')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('account-mobile')), findsNothing);
    expect(calls, [
      'user_start',
      'user_verify',
      'user_verify',
      'support_send',
      'support_mine',
    ]);
    expect(registeredNames, ['مهدی آزمایشی']);
    await tester.drag(
      find.byKey(const Key('support-page')).last,
      const Offset(0, -1200),
    );
    await tester.pumpAndSettle();
    expect(find.text('پاسخ مدیر'), findsNothing);
    expect(find.byKey(const Key('support-message')), findsNothing);
    expect(find.byKey(const Key('support-new-ticket')), findsOneWidget);
    expect(find.text('پشتیبانی دیوان'), findsNothing);
    await tester.tap(find.byKey(const Key('support-ticket-31')));
    await tester.pumpAndSettle();
    expect(find.text('پیشنهاد فارسی'), findsOneWidget);
    expect(find.text('پشتیبانی دیوان'), findsOneWidget);
    expect(find.text('پاسخ مدیر'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(database.close);
    controller.dispose();
  });

  testWidgets('user can send reply to an existing ticket conversation', (
    tester,
  ) async {
    final calls = <String>[];
    final sentReplies = <Map<String, String>>[];
    final token = List.filled(64, 'a').join();
    final database = (await tester.runAsync(
      () => NotebookDatabase.open(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      ),
    ))!;
    final controller = NotebookController(
      database,
      api: LegacyApi(
        client: MockClient((request) async {
          final action = request.url.queryParameters['action']!;
          calls.add(action);
          final body = switch (action) {
            'support_mine' => {
              'ok': true,
              'messages': [
                {
                  'id': '31',
                  'message': 'پیام اول کاربر',
                  'reply': 'پاسخ اول مدیر',
                  'created_at': '2026-10-09T12:00:00Z',
                  'replied_at': '2026-10-09T12:10:00Z',
                  'replies': [
                    {
                      'id': '1',
                      'ticket_id': '31',
                      'sender': 'admin',
                      'message': 'پاسخ اول مدیر',
                      'created_at': '2026-10-09T12:10:00Z',
                    },
                    if (sentReplies.isNotEmpty)
                      {
                        'id': '2',
                        'ticket_id': '31',
                        'sender': 'user',
                        'message': sentReplies.last['message']!,
                        'created_at': '2026-10-09T12:15:00Z',
                      },
                  ],
                },
              ],
            },
            'support_send' => (() {
              sentReplies.add(Map<String, String>.from(request.bodyFields));
              return {'ok': true};
            })(),
            _ => {'ok': true},
          };
          return http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
        }),
      ),
    );
    await tester.runAsync(controller.load);
    controller.accountToken = token;
    controller.accountUser = {'name': 'کاربر', 'mobile': '+989123456789'};

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fa'),
        supportedLocales: const [Locale('fa')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: notebookTheme(),
        home: SupportScreen(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const Key('support-page')).last,
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('support-ticket-31')));
    await tester.pumpAndSettle();

    expect(find.text('پیام اول کاربر'), findsOneWidget);
    expect(find.text('پاسخ اول مدیر'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('support-ticket-reply-input-31')),
      'تشکر از پیگیری، مشکلم حل شد',
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('support-page')).last,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('support-ticket-reply-send-31')));
    await tester.pumpAndSettle();

    expect(sentReplies, hasLength(1));
    expect(sentReplies.first['ticket_id'], '31');
    expect(sentReplies.first['message'], 'تشکر از پیگیری، مشکلم حل شد');
    expect(find.text('تشکر از پیگیری، مشکلم حل شد'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(database.close);
    controller.dispose();
  });
}
