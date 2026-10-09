import 'package:shamsi_date/shamsi_date.dart';

String faDigits(Object value) => value.toString().split('').map((c) {
  final digit = int.tryParse(c);
  return digit == null ? c : '۰۱۲۳۴۵۶۷۸۹'[digit];
}).join();

/// Abstract contract for Jalali / Solar Hijri date formatting and conversion,
/// adhering to dependency injection principles.
abstract class JalaliDateService {
  String formatDateTime(DateTime dateTime);
  String formatDate(DateTime dateTime);
  String formatShort(DateTime dateTime);
  String relativeDate(DateTime dateTime, {DateTime? now});
}

/// Concrete implementation of [JalaliDateService] powered by `package:shamsi_date`.
class ShamsiDateService implements JalaliDateService {
  const ShamsiDateService();

  @override
  String formatDateTime(DateTime dateTime) {
    final local = dateTime.toLocal();
    final j = Jalali.fromDateTime(local);
    final f = j.formatter;
    String two(int n) => n.toString().padLeft(2, '0');
    final time = faDigits('${two(local.hour)}:${two(local.minute)}');
    return '${faDigits(j.day)} ${f.mN} ${faDigits(j.year)} · $time';
  }

  @override
  String formatDate(DateTime dateTime) {
    final local = dateTime.toLocal();
    final j = Jalali.fromDateTime(local);
    final f = j.formatter;
    return '${faDigits(j.day)} ${f.mN} ${faDigits(j.year)}';
  }

  @override
  String formatShort(DateTime dateTime) {
    final local = dateTime.toLocal();
    final j = Jalali.fromDateTime(local);
    final f = j.formatter;
    return faDigits('${f.yyyy}/${f.mm}/${f.dd}');
  }

  @override
  String relativeDate(DateTime dateTime, {DateTime? now}) {
    final local = dateTime.toLocal();
    final current = (now ?? DateTime.now()).toLocal();
    final diff = current.difference(local);
    final days = diff.inDays;

    if (days <= 0 &&
        local.day == current.day &&
        local.month == current.month &&
        local.year == current.year) {
      return 'امروز';
    }
    if (days == 1 || (days <= 1 && local.day != current.day)) {
      return 'دیروز';
    }
    if (days < 7) {
      return '${faDigits(days)} روز پیش';
    }
    return formatDate(local);
  }
}

/// Compatibility and utility model wrapping [Jalali] from `shamsi_date`.
class JalaliDate {
  final Jalali _jalali;

  const JalaliDate._(this._jalali);

  factory JalaliDate(int year, [int month = 1, int day = 1]) =>
      JalaliDate._(Jalali(year, month, day));

  factory JalaliDate.fromDateTime(DateTime dateTime) =>
      JalaliDate._(Jalali.fromDateTime(dateTime.toLocal()));

  int get year => _jalali.year;
  int get month => _jalali.month;
  int get day => _jalali.day;
  String get monthName => _jalali.formatter.mN;

  String formatFull() => '${faDigits(day)} $monthName ${faDigits(year)}';
  String formatShort() =>
      faDigits('${_jalali.formatter.yyyy}/${_jalali.formatter.mm}/${_jalali.formatter.dd}');

  static String formatDateTime(
    DateTime dateTime, {
    JalaliDateService service = const ShamsiDateService(),
  }) => service.formatDateTime(dateTime);
}
