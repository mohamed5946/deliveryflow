// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get aboutApp => 'عن DeliveryFlow';

  @override
  String get activeSession => 'جلسة نشطة';

  @override
  String get appSection => 'التطبيق';

  @override
  String get appTitle => 'DeliveryFlow';

  @override
  String get appearanceSection => 'المظهر';

  @override
  String get applyToSelected => 'تطبيق على المحدد';

  @override
  String get avgHoursWorkingDay => 'متوسط الساعات / يوم عمل';

  @override
  String get avgOrdersPerDay => 'متوسط الأوردرات / يوم';

  @override
  String get avgOrdersWorkingDay => 'متوسط الأوردرات / يوم عمل';

  @override
  String get backupCreated => 'تم إنشاء النسخة الاحتياطية';

  @override
  String get backupData => 'نسخ احتياطي للبيانات';

  @override
  String get backupFailed => 'فشل النسخ الاحتياطي';

  @override
  String get backupRestored => 'تمت استعادة النسخة الاحتياطية';

  @override
  String get bestDay => 'أفضل يوم';

  @override
  String get breakMinutes => 'الراحة (بالدقائق)';

  @override
  String get breakTime => 'مدة الراحة';

  @override
  String get cancel => 'إلغاء';

  @override
  String get channelReminders => 'التذكيرات';

  @override
  String get channelRemindersDesc => 'تذكيرات الجدول واليومية والتقرير';

  @override
  String get clearAllConfirmBody =>
      'سيؤدي هذا إلى حذف جميع الجداول والسجلات والإعدادات نهائياً. لا يمكن التراجع.';

  @override
  String get clearAllConfirmTitle => 'حذف كل شيء؟';

  @override
  String get clearAllData => 'مسح جميع البيانات';

  @override
  String get close => 'إغلاق';

  @override
  String completeDays(Object count) {
    return '$count أيام مكتملة';
  }

  @override
  String get confirm => 'تأكيد';

  @override
  String get confirmed => 'تم التأكيد';

  @override
  String get copyDay => 'نسخ هذا اليوم';

  @override
  String get copyToDays => 'نسخ إلى أيام';

  @override
  String get correctSession => 'تصحيح يدوي';

  @override
  String get createSchedule => 'إنشاء الجدول';

  @override
  String get csvExported => 'تم تصدير CSV';

  @override
  String get currentWeek => 'الأسبوع الحالي';

  @override
  String get dailyBreakdown => 'التفاصيل اليومية';

  @override
  String get dailyReminderEnabled => 'التذكير اليومي';

  @override
  String get dailyReminderTime => 'تذكير الأوردرات اليومي';

  @override
  String get dailySummary => 'ملخص اليوم';

  @override
  String get dataSection => 'إدارة البيانات';

  @override
  String get dayOff => 'يوم إجازة';

  @override
  String get defaultBreakLabel => 'الراحة الافتراضية (بالدقائق)';

  @override
  String get delete => 'حذف';

  @override
  String get designedBy => 'تم تصميم التطبيق بواسطة';

  @override
  String get designerName => 'eng/Mohamed El Sayed';

  @override
  String get contactLabel => 'للتواصل';

  @override
  String get navProfile => 'حسابي';

  @override
  String get profileSetup => 'إعداد الحساب';

  @override
  String get fullName => 'الاسم الكامل';

  @override
  String get driverRole => 'سائق توصيل';

  @override
  String get changePhoto => 'تغيير الصورة';

  @override
  String get tapToAddPhoto => 'اضغط لإضافة صورة';

  @override
  String get helpSupport => 'مساعدة ودعم';

  @override
  String get quickActions => 'إجراءات سريعة';

  @override
  String get geoAddressNotFound => 'مقدرناش نلاقي العنوان ده على الخريطة.';

  @override
  String get geoPreparingOrder => 'بنجهز الأوردر...';

  @override
  String get geoShareFailedBody =>
      'مقدرناش نفهم الموقع اللي اتبعت من التطبيق التاني. جرب تشاركه تاني.';

  @override
  String get geoShareFailedTitle => 'تعذر فتح الموقع المشارك';

  @override
  String get geoShareFailedWithLabelTitle => 'تعذر فتح الموقع المشارك';

  @override
  String get geoShareReceivedText => 'النص المستلم:';

  @override
  String get geoShareFailureReason => 'السبب';

  @override
  String get autoNavSection => 'الملاحة التلقائية';

  @override
  String get autoNavInApp => 'داخل التطبيق';

  @override
  String get autoNavGoogleMaps => 'خرائط جوجل';

  @override
  String get autoNavGoogleMapsDesc =>
      'مشاركة الموقع تفتح خرائط جوجل تلقائيًا، وحساب المسافة يستمر في الخلفية';

  @override
  String get activeOrderBanner => 'أوردر نشط — جارٍ التتبع';

  @override
  String get activeOrderBannerTap => 'اضغط للعودة للأوردر';

  @override
  String get greetingHello => 'مرحباً';

  @override
  String get reportsMenu => 'التقارير والإحصائيات';

  @override
  String get callUs => 'اتصل بنا';

  @override
  String get displayNameHint => 'مثال: أحمد';

  @override
  String get displayNameLabel => 'الاسم المعروض';

  @override
  String get done => 'تم';

  @override
  String get edit => 'تعديل';

  @override
  String get editSchedule => 'تعديل الجدول';

  @override
  String get elapsedTime => 'الوقت المنقضي';

  @override
  String get emptyStateAction => 'سجّل أوردرات اليوم';

  @override
  String get emptyStateBody =>
      'ابدأ بتسجيل أوردرات اليوم أو إعداد جدولك الأسبوعي.';

  @override
  String get emptyStateTitle => 'لا توجد سجلات بعد';

  @override
  String get endTime => 'وقت النهاية';

  @override
  String get endOrder => 'إنهاء الـ Order';

  @override
  String get exportCsv => 'تصدير CSV';

  @override
  String get exportRecordsCsv => 'تصدير السجلات (CSV)';

  @override
  String get finishWork => 'إنهاء العمل';

  @override
  String get followUpReminderEnabled => 'تذكير المتابعة';

  @override
  String get followUpReminderTime => 'تذكير المتابعة';

  @override
  String get shiftEndReminder => 'تذكير نهاية الشيفت';

  @override
  String get shiftEndReminderDesc =>
      'تنبيه عند نهاية شيفتك (من الجدول) لتسجيل أوردرات اليوم';

  @override
  String get friday => 'الجمعة';

  @override
  String get getStarted => 'ابدأ';

  @override
  String get greetingAfternoon => 'مساء الخير';

  @override
  String get greetingEvening => 'مساء الخير';

  @override
  String get greetingMorning => 'صباح الخير';

  @override
  String get historyTitle => 'السجل';

  @override
  String get hoursChartTitle => 'ساعات العمل اليومية';

  @override
  String hoursShort(Object hours) {
    return '$hours س';
  }

  @override
  String get hoursTitle => 'ساعات العمل';

  @override
  String get howManyOrders => 'كم أوردر خلصت النهارده؟';

  @override
  String get enterCountHint => 'اكتب العدد';

  @override
  String get incompleteWeek => 'أسبوع غير مكتمل — بعض الأيام بدون سجلات.';

  @override
  String get invalidBreak => 'مدة الراحة لا يمكن أن تتجاوز مدة الشيفت.';

  @override
  String get invalidOrderCount => 'عدد الأوردرات لا يمكن أن يكون سالباً.';

  @override
  String get invalidShift =>
      'وقت النهاية يجب أن يكون بعد وقت البداية (الشيفتات الليلية مسموحة).';

  @override
  String get invalidTimeRange => 'وقت النهاية يجب أن يختلف عن وقت البداية.';

  @override
  String get languageSection => 'اللغة';

  @override
  String get manualEntry => 'إدخال يدوي';

  @override
  String get markDaysOff => 'تحديد أيام الإجازة';

  @override
  String get missingRecords => 'سجلات ناقصة';

  @override
  String get monday => 'الاثنين';

  @override
  String get navHistory => 'السجل';

  @override
  String get navHome => 'الرئيسية';

  @override
  String get navReports => 'التقارير';

  @override
  String get navSchedule => 'الجدول';

  @override
  String get navSettings => 'الإعدادات';

  @override
  String get netHours => 'صافي وقت العمل';

  @override
  String get next => 'التالي';

  @override
  String get nextWeek => 'الأسبوع القادم';

  @override
  String get noData => 'لا توجد بيانات';

  @override
  String get noScheduleYet => 'لا يوجد جدول لهذا الأسبوع بعد.';

  @override
  String get notesOptional => 'ملاحظات (اختياري)';

  @override
  String get notifDailyBody =>
      'سجّل أوردرات النهارده وساعات شغلك عشان تقريرك يفضل دقيق.';

  @override
  String get notifDailyTitle =>
      'مساء الخير! 🚚 خلصت شغل النهارده؟ سجل عدد الأوردرات اللي عملتها.';

  @override
  String get notifFollowUpBody => 'لسه مسجلتش أوردرات النهارده.';

  @override
  String get notifFollowUpTitle => 'تذكير';

  @override
  String get notifReportBody =>
      'تقرير الأسبوع جاهز! شوف إجمالي أوردراتك وساعات شغلك.';

  @override
  String get notifReportTitle => 'تقرير الأسبوع جاهز 📊';

  @override
  String get notifScheduleBody =>
      'جهّز جدول الأسبوع الجديد! حدّد مواعيد شغلك من الأحد للسبت. 📅';

  @override
  String get notifScheduleTitle => 'خطط للأسبوع القادم';

  @override
  String get notificationPermissionNeeded =>
      'يرجى السماح بالإشعارات من إعدادات النظام.';

  @override
  String get notificationsEnabled => 'تفعيل الإشعارات';

  @override
  String get appLock => 'قفل التطبيق بالبصمة';

  @override
  String get appLockDesc =>
      'اطلب البصمة أو قفل الجهاز كل ما التطبيق يرجع من الخلفية';

  @override
  String get appLockUnavailable => 'مفيش بصمة أو قفل جهاز متاح على الموبايل ده';

  @override
  String get appLockUnlockTitle => 'التطبيق مقفول';

  @override
  String get appLockUnlockHint =>
      'أكّد هويتك بالبصمة أو بقفل الجهاز عشان تفتح التطبيق';

  @override
  String get appLockRetry => 'حاول تاني';

  @override
  String get appLockAuthFailed => 'التحقق فشل، حاول تاني';

  @override
  String get appLockAuthReason => 'أكّد هويتك عشان تفتح DeliveryFlow';

  @override
  String get appLockNoBiometrics =>
      'مفيش بصمة متسجلة على الموبايل ده — سجّل بصمة من إعدادات الموبايل الأول';

  @override
  String get appLockHardwareUnavailable =>
      'مستشعر البصمة مش متاح دلوقتي — جرّب تاني';

  @override
  String get appLockLockedOut =>
      'البصمة اتقفلت مؤقتًا من كتر المحاولات الغلط — استنى شوية أو استخدم قفل الجهاز';

  @override
  String get appLockBusy => 'في تحقق شغال بالفعل — استنى ثانية وحاول تاني';

  @override
  String get appLockAuthCancelled => 'تم إلغاء التحقق — القفل لسه مقفول';

  @override
  String get liquidGlass => 'تأثير الزجاج السائل (تجريبي)';

  @override
  String get liquidGlassDesc =>
      'لمسة زجاج سائل خفيفة على شريط التنقل وبطاقات الرئيسية بس — اقفلها لو حسيت بتقل';

  @override
  String get notificationsSection => 'الإشعارات';

  @override
  String get ok => 'حسناً';

  @override
  String get onBreak => 'في راحة';

  @override
  String get onboardingSubtitle =>
      'جدولك الأسبوعي وأوردراتك وساعات شغلك — كلهم في مكان واحد.';

  @override
  String get onboardingTitle => 'أهلاً بيك في DeliveryFlow';

  @override
  String get openWeek => 'فتح الأسبوع';

  @override
  String get orderNotesHint => 'ملاحظات اختيارية';

  @override
  String get ordersChartTitle => 'الأوردرات اليومية';

  @override
  String ordersCount(Object count) {
    return '$count أوردر';
  }

  @override
  String ordersForDate(Object date) {
    return 'أوردرات $date';
  }

  @override
  String get ordersPerHour => 'أوردر/ساعة';

  @override
  String get ordersTitle => 'أوردرات اليوم';

  @override
  String get overlapWarning =>
      'عندك جلسة نشطة بالفعل. أنهها قبل ما تبدأ واحدة جديدة.';

  @override
  String plannedHours(Object hours) {
    return 'المخطط: $hours س';
  }

  @override
  String get preferredLanguage => 'اللغة المفضلة';

  @override
  String get preferredTheme => 'المظهر المفضل';

  @override
  String get previousWeek => 'الأسبوع السابق';

  @override
  String get privacyBody =>
      'يخزن DeliveryFlow جميع بياناتك محلياً على هذا الجهاز. لا حاجة لحساب، ولا يتم تتبع الموقع، ولا يتم إرسال أي شيء لأي خادم.';

  @override
  String get privacyInfo => 'الخصوصية';

  @override
  String get quickBrowseHistory => 'السجل';

  @override
  String get quickRecordHours => 'تسجيل ساعات العمل';

  @override
  String get quickRecordOrders => 'تسجيل أوردرات اليوم';

  @override
  String get quickViewReport => 'التقرير الأسبوعي';

  @override
  String get quickViewSchedule => 'جدول الأسبوع';

  @override
  String get recordCounts => 'السجلات المخزنة';

  @override
  String get recordSaved => 'تم حفظ السجل';

  @override
  String get recordUpdated => 'تم تحديث السجل';

  @override
  String get recordedDays => 'أيام مسجلة';

  @override
  String get registerError => 'رمز غير صحيح، حاول مرة أخرى';

  @override
  String get registerHint => 'أدخل رمز التسجيل';

  @override
  String get registerTitle => 'رمز التسجيل';

  @override
  String get otpVerified => 'تم التحقق بنجاح';

  @override
  String get remindMeLater => 'لاحقاً';

  @override
  String get reminderTimeLabel => 'تذكير نهاية اليوم';

  @override
  String reportForWeek(Object end, Object start) {
    return 'التقرير: $start – $end';
  }

  @override
  String get reportReminderEnabled => 'تذكير التقرير';

  @override
  String get reportReminderTime => 'تذكير التقرير الأسبوعي';

  @override
  String get reportTitle => 'التقرير الأسبوعي';

  @override
  String get restoreBackup => 'استعادة نسخة احتياطية';

  @override
  String get resumeWork => 'استئناف العمل';

  @override
  String get saturday => 'السبت';

  @override
  String get saturdayPromptBody =>
      'حدد جدول شغلك للأسبوع القادم (الأحد – السبت).';

  @override
  String get saturdayPromptTitle => 'خطط للأسبوع القادم';

  @override
  String get save => 'حفظ';

  @override
  String get saveRecord => 'حفظ';

  @override
  String get saveSchedule => 'حفظ الجدول';

  @override
  String scheduleForWeek(Object end, Object start) {
    return 'جدول $start – $end';
  }

  @override
  String get scheduleReminderEnabled => 'تذكير الجدول';

  @override
  String get scheduleReminderTime => 'تذكير الجدول';

  @override
  String get scheduleSaved => 'تم حفظ الجدول';

  @override
  String get scheduleSummary => 'ملخص الأسبوع';

  @override
  String get scheduleTitle => 'الجدول الأسبوعي';

  @override
  String get scheduledVsActual => 'المخطط مقابل الفعلي';

  @override
  String get sessionRestored => 'تمت استعادة الجلسة السابقة';

  @override
  String get sessionTimer => 'مؤقت العمل';

  @override
  String get settingsTitle => 'الإعدادات';

  @override
  String get shareSummary => 'مشاركة الملخص';

  @override
  String get skip => 'تخطي';

  @override
  String get startTime => 'وقت البداية';

  @override
  String get startWork => 'بدء العمل';

  @override
  String get sunday => 'الأحد';

  @override
  String get takeBreak => 'أخذ راحة';

  @override
  String get testNotification => 'إرسال إشعار تجريبي';

  @override
  String get testNotificationSent => 'تم إرسال الإشعار التجريبي';

  @override
  String get themeDark => 'الوضع الداكن';

  @override
  String get themeLight => 'الوضع الفاتح';

  @override
  String get themeSystem => 'حسب النظام';

  @override
  String get thursday => 'الخميس';

  @override
  String get todayHours => 'ساعات اليوم';

  @override
  String get todayOrders => 'أوردرات اليوم';

  @override
  String get totalOrders => 'إجمالي الأوردرات';

  @override
  String totalPlannedHours(Object hours) {
    return 'إجمالي المخطط: $hours س';
  }

  @override
  String get totalPlannedHoursLabel => 'إجمالي الساعات المخططة';

  @override
  String get totalRecordedHours => 'الساعات المسجلة';

  @override
  String get tuesday => 'الثلاثاء';

  @override
  String get unrecorded => 'غير مسجل';

  @override
  String get versionLabel => 'الإصدار';

  @override
  String get vsLastWeek => 'مقارنة بالأسبوع الماضي';

  @override
  String get wednesday => 'الأربعاء';

  @override
  String weekCardRange(Object end, Object start) {
    return '$start – $end';
  }

  @override
  String get weekHours => 'ساعات هذا الأسبوع';

  @override
  String get weekOrders => 'أوردرات هذا الأسبوع';

  @override
  String get weeklyGoalProgress => 'هدف الأسبوع';

  @override
  String get weeklyHoursGoal => 'هدف ساعات العمل الأسبوعي (اختياري)';

  @override
  String get weeklyHoursGoalLabel => 'هدف الساعات الأسبوعي';

  @override
  String get weeklyOrderGoal => 'هدف الأوردرات الأسبوعي (اختياري)';

  @override
  String get weeklyOrderGoalLabel => 'هدف الأوردرات الأسبوعي';

  @override
  String get workEnd => 'نهاية العمل';

  @override
  String get workPrefsSection => 'تفضيلات العمل';

  @override
  String get workStart => 'بداية العمل';

  @override
  String get workingDay => 'يوم عمل';

  @override
  String get zeroOrders => '0 أوردر';

  @override
  String get addOrder => 'أضف أوردر';

  @override
  String get logCountOnly => 'تسجيل العدد فقط';

  @override
  String get bulkCountTitle => 'عدد أوردرات اليوم';

  @override
  String get bulkCountHint =>
      'اكتب العدد الإجمالي — هيتسجل من غير تفاصيل لكل أوردر.';

  @override
  String bulkCountIncludesDetails(int count) {
    return 'يشمل $count أوردر مسجل بالتفاصيل — الإجمالي ميقدرش يقل عن كده.';
  }

  @override
  String get editOrder => 'تعديل الأوردر';

  @override
  String get deleteOrderTitle => 'حذف الأوردر؟';

  @override
  String get deleteOrderConfirm => 'هيتمسح الأوردر ده من سجل اليوم.';

  @override
  String get didYouDeliverOrder => 'هل أنت وصلت الـ Order؟';

  @override
  String get invalidKm => 'أدخل رقمًا أكبر من صفر';

  @override
  String get kmOutLabel => 'رايح';

  @override
  String get kmBackLabel => 'راجع';

  @override
  String get kmUnit => 'كم';

  @override
  String get noOrdersYet => 'لا توجد أوردرات مسجلة — أضف أول أوردر';

  @override
  String get orderAdded => 'تمت إضافة الأوردر';

  @override
  String get orderDeleted => 'تم حذف الأوردر';

  @override
  String get orderUpdated => 'تم حفظ التعديلات';

  @override
  String get recenter => 'موقعي الحالي';

  @override
  String get openInGoogleMaps => 'افتح في خرائط جوجل';

  @override
  String get orderTime => 'وقت الأوردر';

  @override
  String get ordersLabel => 'أوردرات';

  @override
  String ordersWithoutDetails(int count) {
    return '+$count أوردرات مسجلة بدون تفاصيل مسافة';
  }

  @override
  String get totalKmLabel => 'إجمالي المسافة';

  @override
  String get todayKm => 'مسافة اليوم';

  @override
  String get weekKmLabel => 'مسافة الأسبوع';

  @override
  String get avgKmPerDay => 'متوسط / يوم';

  @override
  String get chooseTheme => 'اختار الثيم';

  @override
  String get salarySection => 'المرتب';

  @override
  String get orderPriceLabel => 'سعر الأوردر (جنيه)';

  @override
  String get dailyFixedLabel => 'الثابت اليومي (جنيه)';

  @override
  String get weeklySalary => 'المرتب الأسبوعي';

  @override
  String get attendanceDays => 'أيام الحضور';

  @override
  String get setSalaryHint =>
      'حدد سعر الأوردر والثابت اليومي من الإعدادات عشان يتحسب المرتب الأسبوعي';

  @override
  String get egpUnit => 'جنيه';

  @override
  String get orderDetails => 'تفاصيل الأوردر';

  @override
  String get statusPending => 'إشعارات مجدولة حاليًا';

  @override
  String get statusToCustomer => 'في الطريق للعميل';

  @override
  String get statusToMart => 'راجع للمارت';

  @override
  String get statusCompleted => 'مكتمل';

  @override
  String get startDelivery => 'بدأ التوصيل';

  @override
  String get arrivedAtCustomer => 'وصلت للعميل';

  @override
  String get arrivedAtMart => 'وصلت للمارت';

  @override
  String get orderCompleted => 'تم إكمال الأوردر بنجاح';

  @override
  String get trackingToCustomer => 'التتبع: إلى العميل';

  @override
  String get trackingToMart => 'التتبع: عودة للمارت';

  @override
  String get distanceSoFar => 'المسافة حتى الآن';

  @override
  String get timeElapsed => 'الوقت المنقضي';

  @override
  String get gpsAccuracyNote => 'يتم حساب المسافة بالـ GPS تلقائياً بدقة عالية';

  @override
  String get tripBreakdown => 'تفاصيل الرحلة';

  @override
  String get pickupTime => 'وقت الاستلام من المارت';

  @override
  String get outgoingLeg => 'الذهاب (مارت ← عميل)';

  @override
  String get deliveryTime => 'وقت التوصيل للعميل';

  @override
  String get returnLeg => 'الرجوع (عميل ← مارت)';

  @override
  String get martArrivalTime => 'وقت الوصول للمارت';

  @override
  String get totalTripTime => 'إجمالي وقت الأوردر';

  @override
  String get totalTripDistance => 'إجمالي مسافة الأوردر';

  @override
  String get locationPermissionRequired =>
      'لازم تسمح بالوصول للموقع عشان التتبع يشتغل';

  @override
  String get pleaseWait => 'استنى…';

  @override
  String get routeMapTitle => 'خريطة خط السير';

  @override
  String get martLabel => 'المارت';

  @override
  String get customerLabel => 'العميل';

  @override
  String get outgoingLegShort => 'الذهاب';

  @override
  String get returnLegShort => 'الرجوع';

  @override
  String get noRouteData =>
      'لا توجد بيانات خط سير لهذا الأوردر (تم قبل تفعيل التتبع)';

  @override
  String get tapToStartTracking => 'دوس عشان تبدأ التتبع بالـ GPS';

  @override
  String get weeklyHeatmap => 'الخريطة الحرارية';

  @override
  String get noHeatmapData =>
      'لا توجد بيانات خط سير لهذا الأسبوع بعد. ابدأ تتبع أوردرات بالـ GPS وهتظهر هنا.';

  @override
  String get heatmapHot => 'الأكثر زيارة';

  @override
  String get heatmapWarm => 'متوسط';

  @override
  String get heatmapCold => 'نادر';

  @override
  String heatmapSubtitle(int count) {
    return 'عدد النقاط المسجلة هذا الأسبوع: $count';
  }

  @override
  String get dayOrdersTitle => 'أوردرات اليوم';

  @override
  String get noOrdersThisDay => 'لا توجد أوردرات مسجلة في هذا اليوم';

  @override
  String get deleteWeekTitle => 'حذف الأسبوع؟';

  @override
  String get deleteWeekBody =>
      'متأكد؟ الحذف نهائي — هيتمسح الأسبوع كامل بكل أوردراته.';

  @override
  String get liveTripMapTitle => 'خريطة الرحلة المباشرة';

  @override
  String get waitingForGps => 'في انتظار إشارة الـ GPS…';

  @override
  String get tripNote => 'ملاحظة';

  @override
  String get tripNoteHint => 'اكتب العنوان أو أي ملاحظة…';

  @override
  String get phoneNumber => 'رقم الموبايل';

  @override
  String get phoneNumberHint => 'اختياري';

  @override
  String get portfolioWebsite => 'الموقع الشخصي';

  @override
  String get trackingFailedTitle => 'فشل تشغيل التتبع';

  @override
  String get returnTrackingFailed =>
      'تم حفظ مسافة الذهاب، لكن تعذر تشغيل تتبع العودة.';

  @override
  String get retry => 'حاول تاني';

  @override
  String get trackingStartFailed => 'تعذر تشغيل التتبع';

  @override
  String get enterManualKm => 'إدخال الكيلومترات يدويًا';

  @override
  String get manualKmLabel => 'المسافة (كم)';

  @override
  String get manualKmHint => 'مثال: 3.5';

  @override
  String get manualBadge => 'يدوي';

  @override
  String get editManualDistance => 'تعديل يدوي للمسافة';

  @override
  String get trackingStoppedTitle => 'التتبع متوقف';

  @override
  String get trackingStoppedBody =>
      'التتبع مش شغال للأوردر ده، والكيلومترات مش بتتحسب. تحب تشغله تاني ولا تدخل المسافة يدويًا؟';

  @override
  String get startTracking => 'تشغيل التتبع';

  @override
  String get weekProgress => 'تقدم الأسبوع';

  @override
  String get setWeeklyGoalHint => 'اضغط لتحديد الهدف';

  @override
  String get viewWeekDetails => 'عرض تفاصيل الأسبوع';

  @override
  String get daySummary => 'ملخص اليوم';

  @override
  String get totalDistances => 'إجمالي المسافات';

  @override
  String get ordersBreakdown => 'تفاصيل الأوردرات';

  @override
  String get statusInProgress => 'قيد التوصيل';

  @override
  String get viewFullReport => 'عرض التقرير الكامل';

  @override
  String get liveTrackingNow => 'التوصيل الآن';

  @override
  String get onWayToCustomer => 'في طريقك للعميل';

  @override
  String get onWayToMart => 'في طريقك للمارت';

  @override
  String get viewDetails => 'عرض التفاصيل';

  @override
  String get endOfDayNotif => 'إشعارات نهاية اليوم';

  @override
  String get weeklyScheduleNotif => 'تذكير الجدول الأسبوعي';

  @override
  String get notifTime => 'وقت الإشعار';

  @override
  String get splashLoading => 'جاري التحميل...';

  @override
  String completedOrdersChip(Object count) {
    return '$count أوردرات مكتملة';
  }

  @override
  String get workSmarterTagline => 'Work Smarter • Deliver Faster';

  @override
  String get deliverFaster => 'توصيل أسرع بذكاء أكبر';

  @override
  String get completedOrdersLabel => 'أوردرات مكتملة';

  @override
  String get statusNotStarted => 'لم يبدأ';

  @override
  String get navigate => 'توجيه';

  @override
  String get searchCustomers => 'بحث عن عميل';

  @override
  String get searchPhoneHint => 'اكتب رقم موبايل العميل';

  @override
  String customerVisits(Object count) {
    return 'رحت للعميل ده $count مرة';
  }

  @override
  String get customerOrdersTitle => 'أوردرات العميل';

  @override
  String get noCustomersFound => 'لا يوجد عملاء بهذا الرقم';

  @override
  String get typeMoreDigits => 'اكتب 3 أرقام على الأقل';

  @override
  String get notificationsTitle => 'الإشعارات';

  @override
  String get noNotifications => 'لا توجد إشعارات بعد';

  @override
  String get markAllRead => 'تحديد الكل كمقروء';

  @override
  String get notificationDismissed => 'تم مسح الإشعار';

  @override
  String get notifOrderCompleted => 'تم إكمال الأوردر';

  @override
  String get notifManualKm => 'مسافة يدوية مسجلة';

  @override
  String get showDetails => 'عرض التفاصيل';

  @override
  String get call => 'اتصال';

  @override
  String get copyNumber => 'نسخ الرقم';

  @override
  String get copied => 'تم نسخ الرقم';

  @override
  String get navigatingNow => 'التوصيل الآن';

  @override
  String get locatingYou => 'جاري تحديد موقعك…';

  @override
  String get minute => 'دقيقة';

  @override
  String get navRouteFailed => 'تعذر حساب الطريق، حاول مرة أخرى';

  @override
  String get reroutingNow => 'جاري إعادة حساب الطريق…';

  @override
  String routeRecommendBoth(Object km, Object min) {
    return 'نرشحلك: الطريق الأسرع والأقصر ✅ ($km كم، $min دقيقة)';
  }

  @override
  String routeRecommendShortest(Object km, Object min) {
    return 'نرشحلك: الطريق الأقصر ($km كم، $min دقيقة) — يوفّر بنزين ⛽';
  }

  @override
  String get mapModeNorthUp => 'اتجاه الشمال';

  @override
  String get mapModeHeadingUp => 'اتجاه السير';

  @override
  String get mapModeOverview => 'نظرة عامة';

  @override
  String get mapModeFollowCam => 'منظور المتابعة';

  @override
  String get exactAlarmOffTitle => 'المنبّه الدقيق مش مفعّل';

  @override
  String get exactAlarmOffDesc =>
      'من غير إذن المنبّه الدقيق، أندرويد ممكن يأخّر التذكيرات عن معادها. فعّل الإذن عشان توصلك في وقتها بالظبط.';

  @override
  String get batteryExemptTitle => 'استثناء من توفير البطارية';

  @override
  String get batteryExemptDesc =>
      'توفير البطارية ممكن يأخّر التذكيرات أو يمنعها خالص — خصوصًا على موبايلات Infinix. استثنِ التطبيق عشان التذكيرات توصلك في معادها.';

  @override
  String get enableAction => 'تفعيل';

  @override
  String get testNotificationNow => 'اختبار إشعار فوري';

  @override
  String get testNotificationScheduled => 'اختبار إشعار مجدول (بعد دقيقة)';

  @override
  String get testNotificationTitle => 'اختبار الإشعارات';

  @override
  String get testNotificationBody =>
      'الإشعار الفوري وصل ✅ لو شايف الرسالة دي، يبقى الإشعارات شغالة.';

  @override
  String get testScheduledBody =>
      'الإشعار المجدول وصل ✅ التذكيرات المجدولة شغالة تمام.';

  @override
  String get testScheduledInstructions =>
      'اتجدول إشعار بعد دقيقة. اقفل التطبيق دلوقتي واستناه — لو وصلك وانت قافل التطبيق، يبقى التذكيرات شغالة.';

  @override
  String get testScheduledFailed =>
      'معرفناش نجدول إشعار الاختبار — اتأكد إن الإشعارات مسموحة وحاول تاني.';

  @override
  String get testScheduledFailedTitle => 'فشلت جدولة إشعار الاختبار';

  @override
  String get technicalReason => 'السبب التقني';

  @override
  String get diagnosticsLog => 'سجل التشخيص';

  @override
  String get diagnosticsLogTitle => 'سجل التشخيص';

  @override
  String get diagnosticsLogEmpty =>
      'لا توجد سجلات بعد — هتظهر هنا أحداث التطبيق وأخطاؤه.';

  @override
  String get diagnosticsLogAll => 'الكل';

  @override
  String get diagnosticsLogCopied => 'تم نسخ السجل';

  @override
  String get diagnosticsLogCopy => 'نسخ الكل';

  @override
  String get diagnosticsLogShare => 'مشاركة';

  @override
  String get diagnosticsLogClear => 'مسح السجل';

  @override
  String get diagnosticsLogClearConfirmTitle => 'مسح سجل التشخيص؟';

  @override
  String get diagnosticsLogClearConfirmBody =>
      'سيتم مسح كل إدخالات السجل نهائيًا.';

  @override
  String get logCategoryNotifications => 'الإشعارات';

  @override
  String get logCategoryTracking => 'التتبع';

  @override
  String get logCategoryOrders => 'الأوردرات';

  @override
  String get logCategoryShare => 'المشاركة';

  @override
  String get logCategorySystem => 'النظام';

  @override
  String get logCategorySettings => 'الإعدادات';

  @override
  String get logLevelInfo => 'معلومة';

  @override
  String get logLevelWarn => 'تحذير';

  @override
  String get logLevelError => 'خطأ';

  @override
  String get countOnlyOrder => 'أوردر (عدد فقط)';

  @override
  String get addOrderDetailed => 'أوردر بتفاصيل';

  @override
  String get addOrderDetailedDesc =>
      'أوردر جديد بيتفتح على طول — عشان تبدأ التوصيل وتتتبّع المسافة.';

  @override
  String get developerMode => 'نسخة المطور';

  @override
  String get developerModeOn => 'مفعّلة';

  @override
  String get developerModeOff => 'غير مفعّلة';

  @override
  String get developerPasswordTitle => 'تفعيل نسخة المطور';

  @override
  String get developerPasswordHint => 'اكتب كلمة المرور';

  @override
  String get developerPasswordError => 'كلمة المرور غير صحيحة';

  @override
  String get developerUnlock => 'تفعيل';

  @override
  String get developerDisableTitle => 'إيقاف نسخة المطور؟';

  @override
  String get developerDisableBody =>
      'هتختفي أدوات التشخيص (اختبارات الإشعارات وسجل التشخيص وحالة الإشعارات) لحد ما تفعّلها تاني بكلمة المرور.';

  @override
  String get developerDisable => 'إيقاف';

  @override
  String get notificationStatusTitle => 'حالة الإشعارات';

  @override
  String get statusPermNotifications => 'إذن الإشعارات';

  @override
  String get statusExactAlarm => 'إذن المنبه الدقيق';

  @override
  String get statusBattery => 'استثناء تحسين البطارية';

  @override
  String get statusChannel => 'أولوية قناة التذكيرات';

  @override
  String get statusOk => 'تمام';

  @override
  String get statusProblem => 'في مشكلة';

  @override
  String get statusUnknown => 'غير معروف';

  @override
  String get weekEarningsSoFar => 'مكاسب الأسبوع لحد دلوقتي';

  @override
  String get exportPdfAllWeeks => 'تصدير كل الأسابيع PDF';

  @override
  String get pdfReportTitle => 'تقرير الأسابيع';

  @override
  String get pdfGeneratedOn => 'اتعمل بتاريخ';

  @override
  String get pdfColDate => 'التاريخ';

  @override
  String get pdfColStatus => 'الحالة';

  @override
  String get pdfColHours => 'الساعات';

  @override
  String get pdfColEarnings => 'المكاسب';

  @override
  String get pdfWeekTotals => 'إجمالي الأسبوع';

  @override
  String get pdfGrandTotals => 'الإجمالي الكلي';

  @override
  String get pdfNoWeeks => 'لا توجد أسابيع مسجلة بعد';

  @override
  String get pdfFailedTitle => 'فشل إنشاء ملف PDF';

  @override
  String get pdfExportScopeTitle => 'تصدير PDF';

  @override
  String get pdfAllWeeksOption => 'كل الأسابيع';

  @override
  String get distanceBonusLabel => 'بونص المسافة';

  @override
  String get distanceBonusWeekLabel => 'بونص المسافة لهذا الأسبوع';

  @override
  String distanceBonusTier(int tier) {
    return 'شريحة البونص $tier';
  }

  @override
  String get distanceBonusFromKmTitle => 'تبدأ الشريحة من (كم)';

  @override
  String get distanceBonusAmountTitle => 'قيمة البونص (ج.م.)';

  @override
  String get manualBonusLabel => 'بونص يدوي';

  @override
  String get extraBonusLabel => 'بونص إضافي';

  @override
  String get extraBonusNone => 'لا يوجد';

  @override
  String get flatOrderBonusLabel => 'بونص ثابت لكل أوردر';

  @override
  String get flatOrdersBonusLabel => 'بونص ثابت للأوردرات';

  @override
  String get martLocationLabel => 'موقع المارت';

  @override
  String get martNotSaved => 'لم يُحفظ بعد — بيتعلم تلقائيًا من رحلاتك';

  @override
  String martObservations(int count) {
    return 'اتعلم من $count مشاهدة';
  }

  @override
  String get martClear => 'مسح الموقع';

  @override
  String get martPickerTitle => 'تحديد موقع المارت';

  @override
  String get martPickerHint => 'حرّك الخريطة لحد ما الدبوس يبقى على المارت';

  @override
  String get martPickerConfirm => 'تأكيد موقع المارت';

  @override
  String get martPickerUseMyLocation => 'استخدام موقعي الحالي';

  @override
  String get martPickerClear => 'مسح موقع المارت';

  @override
  String get martPickerManual => 'اتحدد يدويًا من الخريطة';

  @override
  String get martPickerLocationUnavailable => 'تعذر تحديد موقعك الحالي';

  @override
  String get arrivalAtCustomerTitle => 'هل وصلت إلى العميل؟';

  @override
  String get arrivalAtMartTitle => 'هل وصلت للمارت؟';

  @override
  String get arrivalAutoConfirmBody =>
      'هيتم تأكيد الوصول تلقائيًا خلال ١٠ ثوانٍ لو ما دوستش «لا»';

  @override
  String get arrivalNo => 'لا';

  @override
  String get invalidAmount => 'اكتب مبلغ صحيح';

  @override
  String get logCategoryReports => 'التقارير';

  @override
  String get logCategorySchedule => 'الجدول';

  @override
  String get emailLabel => 'البريد الإلكتروني';

  @override
  String get yes => 'نعم';

  @override
  String get no => 'لا';

  @override
  String get dayHoursSection => 'ساعات اليوم';

  @override
  String dayShiftRange(Object end, Object start) {
    return 'هتبدأ $start - هتخلص $end';
  }

  @override
  String workedRemaining(Object remaining, Object worked) {
    return 'اشتغلت $worked ساعة - فاضل $remaining ساعة';
  }

  @override
  String get hourWorked => 'اشتغلتها';

  @override
  String get hourCurrent => 'الساعة الحالية';

  @override
  String get hourUpcoming => 'جاية';

  @override
  String get hourBreak => 'استراحة';

  @override
  String get noScheduleForDay => 'مفيش جدول لليوم ده';

  @override
  String registeredBreak(Object minutes) {
    return 'استراحة مسجلة: $minutes دقيقة';
  }

  @override
  String breakHoursCount(Object count) {
    return 'استراحة: $count ساعة';
  }

  @override
  String get timeFormatSection => 'صيغة الوقت';

  @override
  String get timeFormatSystem => 'حسب الجهاز';

  @override
  String get timeFormat24 => '24 ساعة';

  @override
  String get timeFormat12 => '12 ساعة';

  @override
  String get confirmDeleteBlock => 'هل أنت متأكد من حذف البلوكاية؟';

  @override
  String get confirmAddBlock => 'هل أنت متأكد من إضافة البلوكاية؟';

  @override
  String get assign => 'تسجيل';

  @override
  String get assignHourTitle => 'اختر ساعة لإضافتها';

  @override
  String get blockBreak => 'بريك';

  @override
  String get blockRestore => 'استعادة';

  @override
  String get blockProtected => 'محمي';

  @override
  String get blockProtectedHasOrders =>
      'لا يمكن حذف هذه البلوكاية لأنها تحتوي على أوردرات';

  @override
  String get softwareUpdateTitle => 'تحديث البرنامج';

  @override
  String get automaticUpdates => 'التحديثات التلقائية';

  @override
  String get updateAutoCheckTitle => 'التحديثات التلقائية';

  @override
  String get updateAutoCheckDesc =>
      'التحقق من وجود إصدار جديد عند تشغيل DeliveryFlow. هذا تحقق فقط — لا ينزّل ولا يثبّت أي شيء من تلقاء نفسه.';

  @override
  String get updateAutoCheckOn => 'تشغيل';

  @override
  String get updateAutoCheckOff => 'إيقاف';

  @override
  String get updateNow => 'حدّث الآن';

  @override
  String get remindMeTonight => 'ذكّرني الليلة';

  @override
  String get updateTermsLine =>
      'بالتحديث، تقوم بتثبيت أحدث إصدار من DeliveryFlow.';

  @override
  String get updateChangelogFallback =>
      'هذا التحديث يتضمن أحدث التحسينات والإصلاحات لـ DeliveryFlow.';

  @override
  String get updateErrorTitle => 'فشل التحديث';

  @override
  String get updatePermissionTitle => 'السماح بتثبيت التطبيقات';

  @override
  String get updatePermissionBody =>
      'لتثبيت التحديث، اسمح لـ DeliveryFlow بتثبيت التطبيقات من هذا المصدر: افتح الإعدادات، فعّل “السماح من هذا المصدر” لـ DeliveryFlow، ثم ارجع واضغط “حدّث الآن” مرة أخرى. سيطلب منك Android تأكيد التثبيت بضغطة واحدة.';

  @override
  String get updateOpenSettings => 'فتح الإعدادات';

  @override
  String get updateChecking => 'جارٍ التحقق من التحديثات…';

  @override
  String get updateUpToDate => 'إنت على آخر تحديث';

  @override
  String get updateUpToDateBody => 'لديك بالفعل أحدث إصدار من DeliveryFlow.';

  @override
  String get updates => 'التحديثات';

  @override
  String get currentVersion => 'الإصدار الحالي';

  @override
  String get updateVerifying => 'جارٍ التحقق…';

  @override
  String updateDownloading(int percent) {
    return 'جارٍ التنزيل… $percent٪';
  }

  @override
  String get checkForUpdates => 'التحقق من التحديثات';
}
