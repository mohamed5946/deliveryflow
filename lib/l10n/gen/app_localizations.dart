import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en')
  ];

  /// No description provided for @aboutApp.
  ///
  /// In en, this message translates to:
  /// **'About DeliveryFlow'**
  String get aboutApp;

  /// No description provided for @activeSession.
  ///
  /// In en, this message translates to:
  /// **'Active session'**
  String get activeSession;

  /// No description provided for @appSection.
  ///
  /// In en, this message translates to:
  /// **'Application'**
  String get appSection;

  /// Application display name
  ///
  /// In en, this message translates to:
  /// **'DeliveryFlow'**
  String get appTitle;

  /// No description provided for @appearanceSection.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearanceSection;

  /// No description provided for @applyToSelected.
  ///
  /// In en, this message translates to:
  /// **'Apply to selected'**
  String get applyToSelected;

  /// No description provided for @avgHoursWorkingDay.
  ///
  /// In en, this message translates to:
  /// **'Avg hours / working day'**
  String get avgHoursWorkingDay;

  /// No description provided for @avgOrdersPerDay.
  ///
  /// In en, this message translates to:
  /// **'Avg orders / day'**
  String get avgOrdersPerDay;

  /// No description provided for @avgOrdersWorkingDay.
  ///
  /// In en, this message translates to:
  /// **'Avg orders / working day'**
  String get avgOrdersWorkingDay;

  /// No description provided for @backupCreated.
  ///
  /// In en, this message translates to:
  /// **'Backup created'**
  String get backupCreated;

  /// No description provided for @backupData.
  ///
  /// In en, this message translates to:
  /// **'Back up data'**
  String get backupData;

  /// No description provided for @backupFailed.
  ///
  /// In en, this message translates to:
  /// **'Backup failed'**
  String get backupFailed;

  /// No description provided for @backupRestored.
  ///
  /// In en, this message translates to:
  /// **'Backup restored'**
  String get backupRestored;

  /// No description provided for @bestDay.
  ///
  /// In en, this message translates to:
  /// **'Best day'**
  String get bestDay;

  /// No description provided for @breakMinutes.
  ///
  /// In en, this message translates to:
  /// **'Break (minutes)'**
  String get breakMinutes;

  /// No description provided for @breakTime.
  ///
  /// In en, this message translates to:
  /// **'Break time'**
  String get breakTime;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @channelReminders.
  ///
  /// In en, this message translates to:
  /// **'Reminders'**
  String get channelReminders;

  /// No description provided for @channelRemindersDesc.
  ///
  /// In en, this message translates to:
  /// **'Schedule, daily and report reminders'**
  String get channelRemindersDesc;

  /// No description provided for @clearAllConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This permanently deletes all schedules, records and settings. This cannot be undone.'**
  String get clearAllConfirmBody;

  /// No description provided for @clearAllConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete everything?'**
  String get clearAllConfirmTitle;

  /// No description provided for @clearAllData.
  ///
  /// In en, this message translates to:
  /// **'Clear all data'**
  String get clearAllData;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @completeDays.
  ///
  /// In en, this message translates to:
  /// **'{count} complete days'**
  String completeDays(Object count);

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @confirmed.
  ///
  /// In en, this message translates to:
  /// **'Confirmed'**
  String get confirmed;

  /// No description provided for @copyDay.
  ///
  /// In en, this message translates to:
  /// **'Copy this day'**
  String get copyDay;

  /// No description provided for @copyToDays.
  ///
  /// In en, this message translates to:
  /// **'Copy to days'**
  String get copyToDays;

  /// No description provided for @correctSession.
  ///
  /// In en, this message translates to:
  /// **'Correct manually'**
  String get correctSession;

  /// No description provided for @createSchedule.
  ///
  /// In en, this message translates to:
  /// **'Create schedule'**
  String get createSchedule;

  /// No description provided for @csvExported.
  ///
  /// In en, this message translates to:
  /// **'CSV exported'**
  String get csvExported;

  /// No description provided for @currentWeek.
  ///
  /// In en, this message translates to:
  /// **'Current week'**
  String get currentWeek;

  /// No description provided for @dailyBreakdown.
  ///
  /// In en, this message translates to:
  /// **'Daily breakdown'**
  String get dailyBreakdown;

  /// No description provided for @dailyReminderEnabled.
  ///
  /// In en, this message translates to:
  /// **'Daily reminder'**
  String get dailyReminderEnabled;

  /// No description provided for @dailyReminderTime.
  ///
  /// In en, this message translates to:
  /// **'Daily order reminder'**
  String get dailyReminderTime;

  /// No description provided for @dailySummary.
  ///
  /// In en, this message translates to:
  /// **'Daily summary'**
  String get dailySummary;

  /// No description provided for @dataSection.
  ///
  /// In en, this message translates to:
  /// **'Data management'**
  String get dataSection;

  /// No description provided for @dayOff.
  ///
  /// In en, this message translates to:
  /// **'Day off'**
  String get dayOff;

  /// No description provided for @defaultBreakLabel.
  ///
  /// In en, this message translates to:
  /// **'Default break (minutes)'**
  String get defaultBreakLabel;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @displayNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Ahmed'**
  String get displayNameHint;

  /// No description provided for @displayNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get displayNameLabel;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @editSchedule.
  ///
  /// In en, this message translates to:
  /// **'Edit schedule'**
  String get editSchedule;

  /// No description provided for @elapsedTime.
  ///
  /// In en, this message translates to:
  /// **'Elapsed'**
  String get elapsedTime;

  /// No description provided for @emptyStateAction.
  ///
  /// In en, this message translates to:
  /// **'Record today\'s orders'**
  String get emptyStateAction;

  /// No description provided for @emptyStateBody.
  ///
  /// In en, this message translates to:
  /// **'Start by recording today\'s orders or setting your weekly schedule.'**
  String get emptyStateBody;

  /// No description provided for @emptyStateTitle.
  ///
  /// In en, this message translates to:
  /// **'No records yet'**
  String get emptyStateTitle;

  /// No description provided for @endTime.
  ///
  /// In en, this message translates to:
  /// **'End time'**
  String get endTime;

  /// No description provided for @exportCsv.
  ///
  /// In en, this message translates to:
  /// **'Export CSV'**
  String get exportCsv;

  /// No description provided for @exportRecordsCsv.
  ///
  /// In en, this message translates to:
  /// **'Export records (CSV)'**
  String get exportRecordsCsv;

  /// No description provided for @finishWork.
  ///
  /// In en, this message translates to:
  /// **'Finish work'**
  String get finishWork;

  /// No description provided for @followUpReminderEnabled.
  ///
  /// In en, this message translates to:
  /// **'Follow-up reminder'**
  String get followUpReminderEnabled;

  /// No description provided for @followUpReminderTime.
  ///
  /// In en, this message translates to:
  /// **'Follow-up reminder'**
  String get followUpReminderTime;

  /// No description provided for @friday.
  ///
  /// In en, this message translates to:
  /// **'Friday'**
  String get friday;

  /// No description provided for @getStarted.
  ///
  /// In en, this message translates to:
  /// **'Get started'**
  String get getStarted;

  /// No description provided for @greetingAfternoon.
  ///
  /// In en, this message translates to:
  /// **'Good afternoon'**
  String get greetingAfternoon;

  /// No description provided for @greetingEvening.
  ///
  /// In en, this message translates to:
  /// **'Good evening'**
  String get greetingEvening;

  /// No description provided for @greetingMorning.
  ///
  /// In en, this message translates to:
  /// **'Good morning'**
  String get greetingMorning;

  /// No description provided for @historyTitle.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get historyTitle;

  /// No description provided for @hoursChartTitle.
  ///
  /// In en, this message translates to:
  /// **'Daily working hours'**
  String get hoursChartTitle;

  /// No description provided for @hoursShort.
  ///
  /// In en, this message translates to:
  /// **'{hours}h'**
  String hoursShort(Object hours);

  /// No description provided for @hoursTitle.
  ///
  /// In en, this message translates to:
  /// **'Working hours'**
  String get hoursTitle;

  /// No description provided for @howManyOrders.
  ///
  /// In en, this message translates to:
  /// **'How many orders did you complete?'**
  String get howManyOrders;

  /// No description provided for @incompleteWeek.
  ///
  /// In en, this message translates to:
  /// **'Incomplete week — some days have no records.'**
  String get incompleteWeek;

  /// No description provided for @invalidBreak.
  ///
  /// In en, this message translates to:
  /// **'Break cannot exceed the shift length.'**
  String get invalidBreak;

  /// No description provided for @invalidOrderCount.
  ///
  /// In en, this message translates to:
  /// **'Order count cannot be negative.'**
  String get invalidOrderCount;

  /// No description provided for @invalidShift.
  ///
  /// In en, this message translates to:
  /// **'End time must be after start time (overnight shifts allowed).'**
  String get invalidShift;

  /// No description provided for @invalidTimeRange.
  ///
  /// In en, this message translates to:
  /// **'End time must differ from start time.'**
  String get invalidTimeRange;

  /// No description provided for @languageSection.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageSection;

  /// No description provided for @manualEntry.
  ///
  /// In en, this message translates to:
  /// **'Manual entry'**
  String get manualEntry;

  /// No description provided for @markDaysOff.
  ///
  /// In en, this message translates to:
  /// **'Mark days off'**
  String get markDaysOff;

  /// No description provided for @missingRecords.
  ///
  /// In en, this message translates to:
  /// **'Missing records'**
  String get missingRecords;

  /// No description provided for @monday.
  ///
  /// In en, this message translates to:
  /// **'Monday'**
  String get monday;

  /// No description provided for @navHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get navHistory;

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navReports.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get navReports;

  /// No description provided for @navSchedule.
  ///
  /// In en, this message translates to:
  /// **'Schedule'**
  String get navSchedule;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @netHours.
  ///
  /// In en, this message translates to:
  /// **'Net working time'**
  String get netHours;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @nextWeek.
  ///
  /// In en, this message translates to:
  /// **'Next week'**
  String get nextWeek;

  /// No description provided for @noData.
  ///
  /// In en, this message translates to:
  /// **'No data'**
  String get noData;

  /// No description provided for @noScheduleYet.
  ///
  /// In en, this message translates to:
  /// **'No schedule for this week yet.'**
  String get noScheduleYet;

  /// No description provided for @notesOptional.
  ///
  /// In en, this message translates to:
  /// **'Notes (optional)'**
  String get notesOptional;

  /// No description provided for @notifDailyBody.
  ///
  /// In en, this message translates to:
  /// **'Record today\'s orders and working hours to keep your weekly report accurate.'**
  String get notifDailyBody;

  /// No description provided for @notifDailyTitle.
  ///
  /// In en, this message translates to:
  /// **'Good evening!'**
  String get notifDailyTitle;

  /// No description provided for @notifFollowUpBody.
  ///
  /// In en, this message translates to:
  /// **'You haven\'t recorded today\'s orders yet.'**
  String get notifFollowUpBody;

  /// No description provided for @notifFollowUpTitle.
  ///
  /// In en, this message translates to:
  /// **'Reminder'**
  String get notifFollowUpTitle;

  /// No description provided for @notifReportBody.
  ///
  /// In en, this message translates to:
  /// **'Your weekly report is ready. Review your orders and working hours.'**
  String get notifReportBody;

  /// No description provided for @notifReportTitle.
  ///
  /// In en, this message translates to:
  /// **'Weekly report ready'**
  String get notifReportTitle;

  /// No description provided for @notifScheduleBody.
  ///
  /// In en, this message translates to:
  /// **'Prepare your next work week. Set your Sunday-to-Saturday schedule.'**
  String get notifScheduleBody;

  /// No description provided for @notifScheduleTitle.
  ///
  /// In en, this message translates to:
  /// **'Plan next week'**
  String get notifScheduleTitle;

  /// No description provided for @notificationPermissionNeeded.
  ///
  /// In en, this message translates to:
  /// **'Please allow notifications in system settings.'**
  String get notificationPermissionNeeded;

  /// No description provided for @notificationsEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enable notifications'**
  String get notificationsEnabled;

  /// No description provided for @notificationsSection.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notificationsSection;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @onBreak.
  ///
  /// In en, this message translates to:
  /// **'On break'**
  String get onBreak;

  /// No description provided for @onboardingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your weekly schedule, orders and working hours — all in one place.'**
  String get onboardingSubtitle;

  /// No description provided for @onboardingTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome to DeliveryFlow'**
  String get onboardingTitle;

  /// No description provided for @openWeek.
  ///
  /// In en, this message translates to:
  /// **'Open week'**
  String get openWeek;

  /// No description provided for @orderNotesHint.
  ///
  /// In en, this message translates to:
  /// **'Optional notes'**
  String get orderNotesHint;

  /// No description provided for @ordersChartTitle.
  ///
  /// In en, this message translates to:
  /// **'Daily orders'**
  String get ordersChartTitle;

  /// No description provided for @ordersCount.
  ///
  /// In en, this message translates to:
  /// **'{count} orders'**
  String ordersCount(Object count);

  /// No description provided for @ordersForDate.
  ///
  /// In en, this message translates to:
  /// **'Orders for {date}'**
  String ordersForDate(Object date);

  /// No description provided for @ordersPerHour.
  ///
  /// In en, this message translates to:
  /// **'Orders/hour'**
  String get ordersPerHour;

  /// No description provided for @ordersTitle.
  ///
  /// In en, this message translates to:
  /// **'Daily orders'**
  String get ordersTitle;

  /// No description provided for @overlapWarning.
  ///
  /// In en, this message translates to:
  /// **'You already have an active session. Finish it before starting a new one.'**
  String get overlapWarning;

  /// No description provided for @plannedHours.
  ///
  /// In en, this message translates to:
  /// **'Planned: {hours}h'**
  String plannedHours(Object hours);

  /// No description provided for @preferredLanguage.
  ///
  /// In en, this message translates to:
  /// **'Preferred language'**
  String get preferredLanguage;

  /// No description provided for @preferredTheme.
  ///
  /// In en, this message translates to:
  /// **'Preferred theme'**
  String get preferredTheme;

  /// No description provided for @previousWeek.
  ///
  /// In en, this message translates to:
  /// **'Previous week'**
  String get previousWeek;

  /// No description provided for @privacyBody.
  ///
  /// In en, this message translates to:
  /// **'DeliveryFlow stores all your data locally on this device. No account is required, no location is tracked, and nothing is sent to any server.'**
  String get privacyBody;

  /// No description provided for @privacyInfo.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get privacyInfo;

  /// No description provided for @quickBrowseHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get quickBrowseHistory;

  /// No description provided for @quickRecordHours.
  ///
  /// In en, this message translates to:
  /// **'Record working hours'**
  String get quickRecordHours;

  /// No description provided for @quickRecordOrders.
  ///
  /// In en, this message translates to:
  /// **'Record today\'s orders'**
  String get quickRecordOrders;

  /// No description provided for @quickViewReport.
  ///
  /// In en, this message translates to:
  /// **'Weekly report'**
  String get quickViewReport;

  /// No description provided for @quickViewSchedule.
  ///
  /// In en, this message translates to:
  /// **'Weekly schedule'**
  String get quickViewSchedule;

  /// No description provided for @recordCounts.
  ///
  /// In en, this message translates to:
  /// **'Stored records'**
  String get recordCounts;

  /// No description provided for @recordSaved.
  ///
  /// In en, this message translates to:
  /// **'Record saved'**
  String get recordSaved;

  /// No description provided for @recordUpdated.
  ///
  /// In en, this message translates to:
  /// **'Record updated'**
  String get recordUpdated;

  /// No description provided for @recordedDays.
  ///
  /// In en, this message translates to:
  /// **'Recorded days'**
  String get recordedDays;

  /// No description provided for @remindMeLater.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get remindMeLater;

  /// No description provided for @reminderTimeLabel.
  ///
  /// In en, this message translates to:
  /// **'Daily end-of-day reminder'**
  String get reminderTimeLabel;

  /// No description provided for @reportForWeek.
  ///
  /// In en, this message translates to:
  /// **'Report: {start} – {end}'**
  String reportForWeek(Object end, Object start);

  /// No description provided for @reportReminderEnabled.
  ///
  /// In en, this message translates to:
  /// **'Report reminder'**
  String get reportReminderEnabled;

  /// No description provided for @reportReminderTime.
  ///
  /// In en, this message translates to:
  /// **'Weekly report reminder'**
  String get reportReminderTime;

  /// No description provided for @reportTitle.
  ///
  /// In en, this message translates to:
  /// **'Weekly report'**
  String get reportTitle;

  /// No description provided for @restoreBackup.
  ///
  /// In en, this message translates to:
  /// **'Restore backup'**
  String get restoreBackup;

  /// No description provided for @resumeWork.
  ///
  /// In en, this message translates to:
  /// **'Resume work'**
  String get resumeWork;

  /// No description provided for @saturday.
  ///
  /// In en, this message translates to:
  /// **'Saturday'**
  String get saturday;

  /// No description provided for @saturdayPromptBody.
  ///
  /// In en, this message translates to:
  /// **'Set your working schedule for next week (Sunday – Saturday).'**
  String get saturdayPromptBody;

  /// No description provided for @saturdayPromptTitle.
  ///
  /// In en, this message translates to:
  /// **'Plan next week'**
  String get saturdayPromptTitle;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @saveRecord.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get saveRecord;

  /// No description provided for @saveSchedule.
  ///
  /// In en, this message translates to:
  /// **'Save schedule'**
  String get saveSchedule;

  /// No description provided for @scheduleForWeek.
  ///
  /// In en, this message translates to:
  /// **'Schedule for {start} – {end}'**
  String scheduleForWeek(Object end, Object start);

  /// No description provided for @scheduleReminderEnabled.
  ///
  /// In en, this message translates to:
  /// **'Schedule reminder'**
  String get scheduleReminderEnabled;

  /// No description provided for @scheduleReminderTime.
  ///
  /// In en, this message translates to:
  /// **'Schedule reminder'**
  String get scheduleReminderTime;

  /// No description provided for @scheduleSaved.
  ///
  /// In en, this message translates to:
  /// **'Schedule saved'**
  String get scheduleSaved;

  /// No description provided for @scheduleSummary.
  ///
  /// In en, this message translates to:
  /// **'Week summary'**
  String get scheduleSummary;

  /// No description provided for @scheduleTitle.
  ///
  /// In en, this message translates to:
  /// **'Weekly schedule'**
  String get scheduleTitle;

  /// No description provided for @scheduledVsActual.
  ///
  /// In en, this message translates to:
  /// **'Scheduled vs actual'**
  String get scheduledVsActual;

  /// No description provided for @sessionRestored.
  ///
  /// In en, this message translates to:
  /// **'Previous session restored'**
  String get sessionRestored;

  /// No description provided for @sessionTimer.
  ///
  /// In en, this message translates to:
  /// **'Work timer'**
  String get sessionTimer;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @shareSummary.
  ///
  /// In en, this message translates to:
  /// **'Share summary'**
  String get shareSummary;

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// No description provided for @startTime.
  ///
  /// In en, this message translates to:
  /// **'Start time'**
  String get startTime;

  /// No description provided for @startWork.
  ///
  /// In en, this message translates to:
  /// **'Start work'**
  String get startWork;

  /// No description provided for @sunday.
  ///
  /// In en, this message translates to:
  /// **'Sunday'**
  String get sunday;

  /// No description provided for @takeBreak.
  ///
  /// In en, this message translates to:
  /// **'Take a break'**
  String get takeBreak;

  /// No description provided for @testNotification.
  ///
  /// In en, this message translates to:
  /// **'Send test notification'**
  String get testNotification;

  /// No description provided for @testNotificationSent.
  ///
  /// In en, this message translates to:
  /// **'Test notification sent'**
  String get testNotificationSent;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get themeSystem;

  /// No description provided for @thursday.
  ///
  /// In en, this message translates to:
  /// **'Thursday'**
  String get thursday;

  /// No description provided for @todayHours.
  ///
  /// In en, this message translates to:
  /// **'Today\'s hours'**
  String get todayHours;

  /// No description provided for @todayOrders.
  ///
  /// In en, this message translates to:
  /// **'Today\'s orders'**
  String get todayOrders;

  /// No description provided for @totalOrders.
  ///
  /// In en, this message translates to:
  /// **'Total orders'**
  String get totalOrders;

  /// No description provided for @totalPlannedHours.
  ///
  /// In en, this message translates to:
  /// **'Total planned: {hours}h'**
  String totalPlannedHours(Object hours);

  /// No description provided for @totalPlannedHoursLabel.
  ///
  /// In en, this message translates to:
  /// **'Planned hours'**
  String get totalPlannedHoursLabel;

  /// No description provided for @totalRecordedHours.
  ///
  /// In en, this message translates to:
  /// **'Recorded hours'**
  String get totalRecordedHours;

  /// No description provided for @tuesday.
  ///
  /// In en, this message translates to:
  /// **'Tuesday'**
  String get tuesday;

  /// No description provided for @unrecorded.
  ///
  /// In en, this message translates to:
  /// **'Not recorded'**
  String get unrecorded;

  /// No description provided for @versionLabel.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get versionLabel;

  /// No description provided for @vsLastWeek.
  ///
  /// In en, this message translates to:
  /// **'vs last week'**
  String get vsLastWeek;

  /// No description provided for @wednesday.
  ///
  /// In en, this message translates to:
  /// **'Wednesday'**
  String get wednesday;

  /// No description provided for @weekCardRange.
  ///
  /// In en, this message translates to:
  /// **'{start} – {end}'**
  String weekCardRange(Object end, Object start);

  /// No description provided for @weekHours.
  ///
  /// In en, this message translates to:
  /// **'This week\'s hours'**
  String get weekHours;

  /// No description provided for @weekOrders.
  ///
  /// In en, this message translates to:
  /// **'This week\'s orders'**
  String get weekOrders;

  /// No description provided for @weeklyGoalProgress.
  ///
  /// In en, this message translates to:
  /// **'Weekly goal'**
  String get weeklyGoalProgress;

  /// No description provided for @weeklyHoursGoal.
  ///
  /// In en, this message translates to:
  /// **'Weekly working-hours goal (optional)'**
  String get weeklyHoursGoal;

  /// No description provided for @weeklyHoursGoalLabel.
  ///
  /// In en, this message translates to:
  /// **'Weekly hours goal'**
  String get weeklyHoursGoalLabel;

  /// No description provided for @weeklyOrderGoal.
  ///
  /// In en, this message translates to:
  /// **'Weekly order goal (optional)'**
  String get weeklyOrderGoal;

  /// No description provided for @weeklyOrderGoalLabel.
  ///
  /// In en, this message translates to:
  /// **'Weekly order goal'**
  String get weeklyOrderGoalLabel;

  /// No description provided for @workEnd.
  ///
  /// In en, this message translates to:
  /// **'Work end'**
  String get workEnd;

  /// No description provided for @workPrefsSection.
  ///
  /// In en, this message translates to:
  /// **'Work preferences'**
  String get workPrefsSection;

  /// No description provided for @workStart.
  ///
  /// In en, this message translates to:
  /// **'Work start'**
  String get workStart;

  /// No description provided for @workingDay.
  ///
  /// In en, this message translates to:
  /// **'Working day'**
  String get workingDay;

  /// No description provided for @zeroOrders.
  ///
  /// In en, this message translates to:
  /// **'0 orders'**
  String get zeroOrders;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
