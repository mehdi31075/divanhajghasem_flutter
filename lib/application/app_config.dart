/// پیکربندی و متغیرهای سراسری برنامه
/// برای تغییر نام برنامه یا نسخه، تنها تغییر مقادیر این کلاس کافی است.
class AppConfig {
  const AppConfig._();

  /// نام سراسری برنامه
  static const String appName = 'دیوان انصارالحسین(ع)';

  /// نسخهٔ نمایشی برنامه
  static const String appVersion = '۰.۱.۰';

  /// پیام خوش‌آمدگویی در صفحه نخست
  static String get welcomeMessage => 'به $appName خوش آمدید';

  /// عنوان بخش دسته‌بندی‌ها
  static String get categoriesTitle => 'دسته‌بندی‌های $appName';

  /// پیام عدم وجود دسته‌بندی
  static String get emptyCategoriesMessage => 'هنوز دسته‌ای در $appName نیست.';

  /// عنوان مطالعه مطالب
  static String get readerTitle => 'مطالعهٔ $appName';

  /// برچسب فرستنده پشتیبانی
  static String get supportLabel => 'پشتیبانی $appName';

  /// راهنمای ورود مدیریت
  static String get serverLoginPrompt =>
      'برای ایجاد، ویرایش و حذف مطالب وارد حساب مدیر $appName شوید.';
}
