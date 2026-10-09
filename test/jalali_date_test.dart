import 'package:flutter_test/flutter_test.dart';
import 'package:hajqasem_app/domain/jalali_date.dart';

class _FakeDateService implements JalaliDateService {
  @override
  String formatDate(DateTime dateTime) => 'تاریخ فرضی';

  @override
  String formatDateTime(DateTime dateTime) => 'تاریخ و زمان فرضی';

  @override
  String formatShort(DateTime dateTime) => '۱۴۰۵/۰۱/۰۱';

  @override
  String relativeDate(DateTime dateTime, {DateTime? now}) => 'چند لحظه پیش';
}

void main() {
  group('ShamsiDateService (using package:shamsi_date)', () {
    const service = ShamsiDateService();

    test('converts known Gregorian dates to Solar Hijri accurately', () {
      // 2026-10-09 is 17 Mehr 1405
      final dt1 = DateTime(2026, 10, 9);
      expect(service.formatDate(dt1), '۱۷ مهر ۱۴۰۵');
      expect(service.formatShort(dt1), '۱۴۰۵/۰۷/۱۷');

      // Nowruz 2024: 2024-03-20 is 1 Farvardin 1403 (leap year)
      final dt2 = DateTime(2024, 3, 20);
      expect(service.formatDate(dt2), '۱ فروردین ۱۴۰۳');

      // Nowruz 2023: 2023-03-21 is 1 Farvardin 1402
      final dt3 = DateTime(2023, 3, 21);
      expect(service.formatDate(dt3), '۱ فروردین ۱۴۰۲');

      // Yalda night 2024: 2024-12-20 is 30 Azar 1403
      final dt4 = DateTime(2024, 12, 20);
      expect(service.formatDate(dt4), '۳۰ آذر ۱۴۰۳');
    });

    test('formatDateTime formats date and time with Persian numerals', () {
      final dt = DateTime(2026, 10, 9, 14, 30);
      expect(service.formatDateTime(dt), '۱۷ مهر ۱۴۰۵ · ۱۴:۳۰');
    });

    test('relativeDate computes today, yesterday, recent days, and full date', () {
      final now = DateTime(2026, 10, 9, 12, 0);

      expect(service.relativeDate(DateTime(2026, 10, 9, 8, 0), now: now), 'امروز');
      expect(service.relativeDate(DateTime(2026, 10, 8, 12, 0), now: now), 'دیروز');
      expect(service.relativeDate(DateTime(2026, 10, 6, 12, 0), now: now), '۳ روز پیش');
      expect(service.relativeDate(DateTime(2026, 9, 20, 12, 0), now: now), '۲۹ شهریور ۱۴۰۵');
    });

    test('dependency injection allows custom JalaliDateService implementations', () {
      final JalaliDateService custom = _FakeDateService();
      expect(custom.formatDate(DateTime(2026, 10, 9)), 'تاریخ فرضی');
      expect(custom.formatDateTime(DateTime(2026, 10, 9)), 'تاریخ و زمان فرضی');
      expect(custom.relativeDate(DateTime(2026, 10, 9)), 'چند لحظه پیش');
    });
  });

  group('JalaliDate compatibility adapter', () {
    test('provides backward compatible fields and formatting', () {
      final j = JalaliDate.fromDateTime(DateTime(2026, 10, 9));
      expect(j.year, 1405);
      expect(j.month, 7);
      expect(j.day, 17);
      expect(j.monthName, 'مهر');
      expect(j.formatFull(), '۱۷ مهر ۱۴۰۵');
      expect(j.formatShort(), '۱۴۰۵/۰۷/۱۷');
    });
  });
}
