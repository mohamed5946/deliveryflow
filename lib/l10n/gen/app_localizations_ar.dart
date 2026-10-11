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
  String get editOrder => 'تعديل الأوردر';

  @override
  String get deleteOrderTitle => 'حذف الأوردر؟';

  @override
  String get deleteOrderConfirm => 'هيتمسح الأوردر ده من سجل اليوم.';

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
  String get statusPending => 'في الانتظار';

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
}
