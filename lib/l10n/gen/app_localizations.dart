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

  /// No description provided for @designedBy.
  ///
  /// In en, this message translates to:
  /// **'Designed by'**
  String get designedBy;

  /// No description provided for @designerName.
  ///
  /// In en, this message translates to:
  /// **'eng/Mohamed El Sayed'**
  String get designerName;

  /// No description provided for @contactLabel.
  ///
  /// In en, this message translates to:
  /// **'Contact'**
  String get contactLabel;

  /// No description provided for @navProfile.
  ///
  /// In en, this message translates to:
  /// **'My Account'**
  String get navProfile;

  /// No description provided for @profileSetup.
  ///
  /// In en, this message translates to:
  /// **'Set Up Account'**
  String get profileSetup;

  /// No description provided for @fullName.
  ///
  /// In en, this message translates to:
  /// **'Full Name'**
  String get fullName;

  /// No description provided for @driverRole.
  ///
  /// In en, this message translates to:
  /// **'Delivery Driver'**
  String get driverRole;

  /// No description provided for @changePhoto.
  ///
  /// In en, this message translates to:
  /// **'Change Photo'**
  String get changePhoto;

  /// No description provided for @tapToAddPhoto.
  ///
  /// In en, this message translates to:
  /// **'Tap to add photo'**
  String get tapToAddPhoto;

  /// No description provided for @helpSupport.
  ///
  /// In en, this message translates to:
  /// **'Help & Support'**
  String get helpSupport;

  /// No description provided for @quickActions.
  ///
  /// In en, this message translates to:
  /// **'Quick actions'**
  String get quickActions;

  /// No description provided for @geoAddressNotFound.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t find that address on the map.'**
  String get geoAddressNotFound;

  /// No description provided for @geoPreparingOrder.
  ///
  /// In en, this message translates to:
  /// **'Preparing your order…'**
  String get geoPreparingOrder;

  /// No description provided for @geoShareFailedBody.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t understand the location shared from the other app. Try sharing it again.'**
  String get geoShareFailedBody;

  /// No description provided for @geoShareFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the shared location'**
  String get geoShareFailedTitle;

  /// No description provided for @geoShareFailedWithLabelTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the shared location'**
  String get geoShareFailedWithLabelTitle;

  /// No description provided for @geoShareReceivedText.
  ///
  /// In en, this message translates to:
  /// **'Received text:'**
  String get geoShareReceivedText;

  /// No description provided for @geoShareFailureReason.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get geoShareFailureReason;

  /// No description provided for @autoNavSection.
  ///
  /// In en, this message translates to:
  /// **'Automatic navigation'**
  String get autoNavSection;

  /// No description provided for @autoNavInApp.
  ///
  /// In en, this message translates to:
  /// **'In-app'**
  String get autoNavInApp;

  /// No description provided for @autoNavGoogleMaps.
  ///
  /// In en, this message translates to:
  /// **'Google Maps'**
  String get autoNavGoogleMaps;

  /// No description provided for @autoNavGoogleMapsDesc.
  ///
  /// In en, this message translates to:
  /// **'Shared locations open Google Maps automatically; distance tracking keeps running in the background'**
  String get autoNavGoogleMapsDesc;

  /// No description provided for @activeOrderBanner.
  ///
  /// In en, this message translates to:
  /// **'Active order — tracking'**
  String get activeOrderBanner;

  /// No description provided for @activeOrderBannerTap.
  ///
  /// In en, this message translates to:
  /// **'Tap to return to the order'**
  String get activeOrderBannerTap;

  /// No description provided for @greetingHello.
  ///
  /// In en, this message translates to:
  /// **'Hello'**
  String get greetingHello;

  /// No description provided for @reportsMenu.
  ///
  /// In en, this message translates to:
  /// **'Reports & Statistics'**
  String get reportsMenu;

  /// No description provided for @callUs.
  ///
  /// In en, this message translates to:
  /// **'Call us'**
  String get callUs;

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

  /// No description provided for @shiftEndReminder.
  ///
  /// In en, this message translates to:
  /// **'Shift-end reminder'**
  String get shiftEndReminder;

  /// No description provided for @shiftEndReminderDesc.
  ///
  /// In en, this message translates to:
  /// **'A reminder at your shift end (from your schedule) to log the day\'s orders'**
  String get shiftEndReminderDesc;

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

  /// No description provided for @enterCountHint.
  ///
  /// In en, this message translates to:
  /// **'Type the number'**
  String get enterCountHint;

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

  /// No description provided for @registerError.
  ///
  /// In en, this message translates to:
  /// **'Incorrect code, try again'**
  String get registerError;

  /// No description provided for @registerHint.
  ///
  /// In en, this message translates to:
  /// **'Enter the registration code'**
  String get registerHint;

  /// No description provided for @registerTitle.
  ///
  /// In en, this message translates to:
  /// **'Registration Code'**
  String get registerTitle;

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

  /// No description provided for @addOrder.
  ///
  /// In en, this message translates to:
  /// **'Add order'**
  String get addOrder;

  /// No description provided for @logCountOnly.
  ///
  /// In en, this message translates to:
  /// **'Log count only'**
  String get logCountOnly;

  /// No description provided for @bulkCountTitle.
  ///
  /// In en, this message translates to:
  /// **'Orders count for this day'**
  String get bulkCountTitle;

  /// No description provided for @bulkCountHint.
  ///
  /// In en, this message translates to:
  /// **'Enter the total count — it is saved without per-order details.'**
  String get bulkCountHint;

  /// No description provided for @bulkCountIncludesDetails.
  ///
  /// In en, this message translates to:
  /// **'Includes {count} order(s) already logged with details — the total can\'t be lower.'**
  String bulkCountIncludesDetails(int count);

  /// No description provided for @editOrder.
  ///
  /// In en, this message translates to:
  /// **'Edit order'**
  String get editOrder;

  /// No description provided for @deleteOrderTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete order?'**
  String get deleteOrderTitle;

  /// No description provided for @deleteOrderConfirm.
  ///
  /// In en, this message translates to:
  /// **'This order will be removed from the day\'s log.'**
  String get deleteOrderConfirm;

  /// No description provided for @invalidKm.
  ///
  /// In en, this message translates to:
  /// **'Enter a number greater than zero'**
  String get invalidKm;

  /// No description provided for @kmOutLabel.
  ///
  /// In en, this message translates to:
  /// **'Going'**
  String get kmOutLabel;

  /// No description provided for @kmBackLabel.
  ///
  /// In en, this message translates to:
  /// **'Returning'**
  String get kmBackLabel;

  /// No description provided for @kmUnit.
  ///
  /// In en, this message translates to:
  /// **'km'**
  String get kmUnit;

  /// No description provided for @noOrdersYet.
  ///
  /// In en, this message translates to:
  /// **'No orders logged yet — add the first one'**
  String get noOrdersYet;

  /// No description provided for @orderAdded.
  ///
  /// In en, this message translates to:
  /// **'Order added'**
  String get orderAdded;

  /// No description provided for @orderDeleted.
  ///
  /// In en, this message translates to:
  /// **'Order deleted'**
  String get orderDeleted;

  /// No description provided for @orderUpdated.
  ///
  /// In en, this message translates to:
  /// **'Changes saved'**
  String get orderUpdated;

  /// No description provided for @recenter.
  ///
  /// In en, this message translates to:
  /// **'My location'**
  String get recenter;

  /// No description provided for @openInGoogleMaps.
  ///
  /// In en, this message translates to:
  /// **'Open in Google Maps'**
  String get openInGoogleMaps;

  /// No description provided for @orderTime.
  ///
  /// In en, this message translates to:
  /// **'Order time'**
  String get orderTime;

  /// No description provided for @ordersLabel.
  ///
  /// In en, this message translates to:
  /// **'Orders'**
  String get ordersLabel;

  /// No description provided for @ordersWithoutDetails.
  ///
  /// In en, this message translates to:
  /// **'+{count} orders logged without distance details'**
  String ordersWithoutDetails(int count);

  /// No description provided for @totalKmLabel.
  ///
  /// In en, this message translates to:
  /// **'Total distance'**
  String get totalKmLabel;

  /// No description provided for @todayKm.
  ///
  /// In en, this message translates to:
  /// **'Today\'s distance'**
  String get todayKm;

  /// No description provided for @weekKmLabel.
  ///
  /// In en, this message translates to:
  /// **'Week distance'**
  String get weekKmLabel;

  /// No description provided for @avgKmPerDay.
  ///
  /// In en, this message translates to:
  /// **'Avg / day'**
  String get avgKmPerDay;

  /// No description provided for @chooseTheme.
  ///
  /// In en, this message translates to:
  /// **'Choose theme'**
  String get chooseTheme;

  /// No description provided for @salarySection.
  ///
  /// In en, this message translates to:
  /// **'Salary'**
  String get salarySection;

  /// No description provided for @orderPriceLabel.
  ///
  /// In en, this message translates to:
  /// **'Price per order (EGP)'**
  String get orderPriceLabel;

  /// No description provided for @dailyFixedLabel.
  ///
  /// In en, this message translates to:
  /// **'Daily fixed pay (EGP)'**
  String get dailyFixedLabel;

  /// No description provided for @weeklySalary.
  ///
  /// In en, this message translates to:
  /// **'Weekly salary'**
  String get weeklySalary;

  /// No description provided for @attendanceDays.
  ///
  /// In en, this message translates to:
  /// **'Days attended'**
  String get attendanceDays;

  /// No description provided for @setSalaryHint.
  ///
  /// In en, this message translates to:
  /// **'Set the order price and daily fixed pay in Settings to calculate the weekly salary'**
  String get setSalaryHint;

  /// No description provided for @egpUnit.
  ///
  /// In en, this message translates to:
  /// **'EGP'**
  String get egpUnit;

  /// No description provided for @orderDetails.
  ///
  /// In en, this message translates to:
  /// **'Order details'**
  String get orderDetails;

  /// No description provided for @statusPending.
  ///
  /// In en, this message translates to:
  /// **'Currently scheduled notifications'**
  String get statusPending;

  /// No description provided for @statusToCustomer.
  ///
  /// In en, this message translates to:
  /// **'On the way to customer'**
  String get statusToCustomer;

  /// No description provided for @statusToMart.
  ///
  /// In en, this message translates to:
  /// **'Returning to mart'**
  String get statusToMart;

  /// No description provided for @statusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get statusCompleted;

  /// No description provided for @startDelivery.
  ///
  /// In en, this message translates to:
  /// **'Start delivery'**
  String get startDelivery;

  /// No description provided for @arrivedAtCustomer.
  ///
  /// In en, this message translates to:
  /// **'Arrived at customer'**
  String get arrivedAtCustomer;

  /// No description provided for @arrivedAtMart.
  ///
  /// In en, this message translates to:
  /// **'Arrived at mart'**
  String get arrivedAtMart;

  /// No description provided for @orderCompleted.
  ///
  /// In en, this message translates to:
  /// **'Order completed successfully'**
  String get orderCompleted;

  /// No description provided for @trackingToCustomer.
  ///
  /// In en, this message translates to:
  /// **'Tracking: to customer'**
  String get trackingToCustomer;

  /// No description provided for @trackingToMart.
  ///
  /// In en, this message translates to:
  /// **'Tracking: back to mart'**
  String get trackingToMart;

  /// No description provided for @distanceSoFar.
  ///
  /// In en, this message translates to:
  /// **'Distance so far'**
  String get distanceSoFar;

  /// No description provided for @timeElapsed.
  ///
  /// In en, this message translates to:
  /// **'Time elapsed'**
  String get timeElapsed;

  /// No description provided for @gpsAccuracyNote.
  ///
  /// In en, this message translates to:
  /// **'Distance is calculated automatically via GPS with high accuracy'**
  String get gpsAccuracyNote;

  /// No description provided for @tripBreakdown.
  ///
  /// In en, this message translates to:
  /// **'Trip breakdown'**
  String get tripBreakdown;

  /// No description provided for @pickupTime.
  ///
  /// In en, this message translates to:
  /// **'Pickup time from mart'**
  String get pickupTime;

  /// No description provided for @outgoingLeg.
  ///
  /// In en, this message translates to:
  /// **'Outgoing (mart → customer)'**
  String get outgoingLeg;

  /// No description provided for @deliveryTime.
  ///
  /// In en, this message translates to:
  /// **'Delivery time to customer'**
  String get deliveryTime;

  /// No description provided for @returnLeg.
  ///
  /// In en, this message translates to:
  /// **'Return (customer → mart)'**
  String get returnLeg;

  /// No description provided for @martArrivalTime.
  ///
  /// In en, this message translates to:
  /// **'Mart arrival time'**
  String get martArrivalTime;

  /// No description provided for @totalTripTime.
  ///
  /// In en, this message translates to:
  /// **'Total order time'**
  String get totalTripTime;

  /// No description provided for @totalTripDistance.
  ///
  /// In en, this message translates to:
  /// **'Total order distance'**
  String get totalTripDistance;

  /// No description provided for @locationPermissionRequired.
  ///
  /// In en, this message translates to:
  /// **'Location permission is required for tracking'**
  String get locationPermissionRequired;

  /// No description provided for @pleaseWait.
  ///
  /// In en, this message translates to:
  /// **'Please wait…'**
  String get pleaseWait;

  /// No description provided for @routeMapTitle.
  ///
  /// In en, this message translates to:
  /// **'Route map'**
  String get routeMapTitle;

  /// No description provided for @martLabel.
  ///
  /// In en, this message translates to:
  /// **'Mart'**
  String get martLabel;

  /// No description provided for @customerLabel.
  ///
  /// In en, this message translates to:
  /// **'Customer'**
  String get customerLabel;

  /// No description provided for @outgoingLegShort.
  ///
  /// In en, this message translates to:
  /// **'Outgoing'**
  String get outgoingLegShort;

  /// No description provided for @returnLegShort.
  ///
  /// In en, this message translates to:
  /// **'Return'**
  String get returnLegShort;

  /// No description provided for @noRouteData.
  ///
  /// In en, this message translates to:
  /// **'No route data for this order (created before tracking)'**
  String get noRouteData;

  /// No description provided for @tapToStartTracking.
  ///
  /// In en, this message translates to:
  /// **'Tap to start GPS tracking'**
  String get tapToStartTracking;

  /// No description provided for @weeklyHeatmap.
  ///
  /// In en, this message translates to:
  /// **'Heatmap'**
  String get weeklyHeatmap;

  /// No description provided for @noHeatmapData.
  ///
  /// In en, this message translates to:
  /// **'No route data for this week yet. Track orders with GPS and they will appear here.'**
  String get noHeatmapData;

  /// No description provided for @heatmapHot.
  ///
  /// In en, this message translates to:
  /// **'Most visited'**
  String get heatmapHot;

  /// No description provided for @heatmapWarm.
  ///
  /// In en, this message translates to:
  /// **'Average'**
  String get heatmapWarm;

  /// No description provided for @heatmapCold.
  ///
  /// In en, this message translates to:
  /// **'Rare'**
  String get heatmapCold;

  /// No description provided for @heatmapSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Recorded points this week: {count}'**
  String heatmapSubtitle(int count);

  /// No description provided for @dayOrdersTitle.
  ///
  /// In en, this message translates to:
  /// **'Day\'s orders'**
  String get dayOrdersTitle;

  /// No description provided for @noOrdersThisDay.
  ///
  /// In en, this message translates to:
  /// **'No orders recorded this day'**
  String get noOrdersThisDay;

  /// No description provided for @deleteWeekTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete week?'**
  String get deleteWeekTitle;

  /// No description provided for @deleteWeekBody.
  ///
  /// In en, this message translates to:
  /// **'Are you sure? Deletion is permanent — the whole week with all its orders will be removed.'**
  String get deleteWeekBody;

  /// No description provided for @liveTripMapTitle.
  ///
  /// In en, this message translates to:
  /// **'Live trip map'**
  String get liveTripMapTitle;

  /// No description provided for @waitingForGps.
  ///
  /// In en, this message translates to:
  /// **'Waiting for GPS signal…'**
  String get waitingForGps;

  /// No description provided for @tripNote.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get tripNote;

  /// No description provided for @tripNoteHint.
  ///
  /// In en, this message translates to:
  /// **'Write the address or any note…'**
  String get tripNoteHint;

  /// No description provided for @phoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Phone number'**
  String get phoneNumber;

  /// No description provided for @phoneNumberHint.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get phoneNumberHint;

  /// No description provided for @trackingFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Tracking failed to start'**
  String get trackingFailedTitle;

  /// No description provided for @returnTrackingFailed.
  ///
  /// In en, this message translates to:
  /// **'Outgoing distance was saved, but return tracking failed to start.'**
  String get returnTrackingFailed;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @trackingStartFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t start tracking'**
  String get trackingStartFailed;

  /// No description provided for @enterManualKm.
  ///
  /// In en, this message translates to:
  /// **'Enter kilometers manually'**
  String get enterManualKm;

  /// No description provided for @manualKmLabel.
  ///
  /// In en, this message translates to:
  /// **'Distance (km)'**
  String get manualKmLabel;

  /// No description provided for @manualKmHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. 3.5'**
  String get manualKmHint;

  /// No description provided for @manualBadge.
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get manualBadge;

  /// No description provided for @editManualDistance.
  ///
  /// In en, this message translates to:
  /// **'Edit distance manually'**
  String get editManualDistance;

  /// No description provided for @trackingStoppedTitle.
  ///
  /// In en, this message translates to:
  /// **'Tracking stopped'**
  String get trackingStoppedTitle;

  /// No description provided for @trackingStoppedBody.
  ///
  /// In en, this message translates to:
  /// **'Tracking isn\'t running for this order, so kilometers aren\'t being counted. Restart it or enter the distance manually?'**
  String get trackingStoppedBody;

  /// No description provided for @startTracking.
  ///
  /// In en, this message translates to:
  /// **'Start tracking'**
  String get startTracking;

  /// No description provided for @weekProgress.
  ///
  /// In en, this message translates to:
  /// **'Week progress'**
  String get weekProgress;

  /// No description provided for @setWeeklyGoalHint.
  ///
  /// In en, this message translates to:
  /// **'Tap to set your goal'**
  String get setWeeklyGoalHint;

  /// No description provided for @viewWeekDetails.
  ///
  /// In en, this message translates to:
  /// **'View week details'**
  String get viewWeekDetails;

  /// No description provided for @daySummary.
  ///
  /// In en, this message translates to:
  /// **'Day summary'**
  String get daySummary;

  /// No description provided for @totalDistances.
  ///
  /// In en, this message translates to:
  /// **'Total distances'**
  String get totalDistances;

  /// No description provided for @ordersBreakdown.
  ///
  /// In en, this message translates to:
  /// **'Orders breakdown'**
  String get ordersBreakdown;

  /// No description provided for @statusInProgress.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get statusInProgress;

  /// No description provided for @viewFullReport.
  ///
  /// In en, this message translates to:
  /// **'View full report'**
  String get viewFullReport;

  /// No description provided for @liveTrackingNow.
  ///
  /// In en, this message translates to:
  /// **'Live delivery'**
  String get liveTrackingNow;

  /// No description provided for @onWayToCustomer.
  ///
  /// In en, this message translates to:
  /// **'On your way to the customer'**
  String get onWayToCustomer;

  /// No description provided for @onWayToMart.
  ///
  /// In en, this message translates to:
  /// **'On your way back to the mart'**
  String get onWayToMart;

  /// No description provided for @viewDetails.
  ///
  /// In en, this message translates to:
  /// **'View details'**
  String get viewDetails;

  /// No description provided for @endOfDayNotif.
  ///
  /// In en, this message translates to:
  /// **'End-of-day notifications'**
  String get endOfDayNotif;

  /// No description provided for @weeklyScheduleNotif.
  ///
  /// In en, this message translates to:
  /// **'Weekly schedule reminder'**
  String get weeklyScheduleNotif;

  /// No description provided for @notifTime.
  ///
  /// In en, this message translates to:
  /// **'Notification time'**
  String get notifTime;

  /// No description provided for @splashLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get splashLoading;

  /// No description provided for @completedOrdersChip.
  ///
  /// In en, this message translates to:
  /// **'{count} completed orders'**
  String completedOrdersChip(Object count);

  /// No description provided for @workSmarterTagline.
  ///
  /// In en, this message translates to:
  /// **'Work Smarter • Deliver Faster'**
  String get workSmarterTagline;

  /// No description provided for @deliverFaster.
  ///
  /// In en, this message translates to:
  /// **'Work smarter, deliver faster'**
  String get deliverFaster;

  /// No description provided for @completedOrdersLabel.
  ///
  /// In en, this message translates to:
  /// **'completed orders'**
  String get completedOrdersLabel;

  /// No description provided for @statusNotStarted.
  ///
  /// In en, this message translates to:
  /// **'Not started'**
  String get statusNotStarted;

  /// No description provided for @navigate.
  ///
  /// In en, this message translates to:
  /// **'Navigate'**
  String get navigate;

  /// No description provided for @searchCustomers.
  ///
  /// In en, this message translates to:
  /// **'Search customers'**
  String get searchCustomers;

  /// No description provided for @searchPhoneHint.
  ///
  /// In en, this message translates to:
  /// **'Type customer phone number'**
  String get searchPhoneHint;

  /// No description provided for @customerVisits.
  ///
  /// In en, this message translates to:
  /// **'Visited this customer {count} times'**
  String customerVisits(Object count);

  /// No description provided for @customerOrdersTitle.
  ///
  /// In en, this message translates to:
  /// **'Customer orders'**
  String get customerOrdersTitle;

  /// No description provided for @noCustomersFound.
  ///
  /// In en, this message translates to:
  /// **'No customers with this number'**
  String get noCustomersFound;

  /// No description provided for @typeMoreDigits.
  ///
  /// In en, this message translates to:
  /// **'Type at least 3 digits'**
  String get typeMoreDigits;

  /// No description provided for @notificationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notificationsTitle;

  /// No description provided for @noNotifications.
  ///
  /// In en, this message translates to:
  /// **'No notifications yet'**
  String get noNotifications;

  /// No description provided for @markAllRead.
  ///
  /// In en, this message translates to:
  /// **'Mark all as read'**
  String get markAllRead;

  /// No description provided for @notificationDismissed.
  ///
  /// In en, this message translates to:
  /// **'Notification dismissed'**
  String get notificationDismissed;

  /// No description provided for @notifOrderCompleted.
  ///
  /// In en, this message translates to:
  /// **'Order completed'**
  String get notifOrderCompleted;

  /// No description provided for @notifManualKm.
  ///
  /// In en, this message translates to:
  /// **'Manual distance recorded'**
  String get notifManualKm;

  /// No description provided for @showDetails.
  ///
  /// In en, this message translates to:
  /// **'Show details'**
  String get showDetails;

  /// No description provided for @call.
  ///
  /// In en, this message translates to:
  /// **'Call'**
  String get call;

  /// No description provided for @copyNumber.
  ///
  /// In en, this message translates to:
  /// **'Copy number'**
  String get copyNumber;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Number copied'**
  String get copied;

  /// No description provided for @navigatingNow.
  ///
  /// In en, this message translates to:
  /// **'Navigating now'**
  String get navigatingNow;

  /// No description provided for @locatingYou.
  ///
  /// In en, this message translates to:
  /// **'Locating you…'**
  String get locatingYou;

  /// No description provided for @minute.
  ///
  /// In en, this message translates to:
  /// **'min'**
  String get minute;

  /// No description provided for @navRouteFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not calculate the route, try again'**
  String get navRouteFailed;

  /// No description provided for @reroutingNow.
  ///
  /// In en, this message translates to:
  /// **'Recalculating route…'**
  String get reroutingNow;

  /// No description provided for @routeRecommendBoth.
  ///
  /// In en, this message translates to:
  /// **'Recommended: fastest & shortest route ✅ ({km} km, {min} min)'**
  String routeRecommendBoth(Object km, Object min);

  /// No description provided for @routeRecommendShortest.
  ///
  /// In en, this message translates to:
  /// **'Recommended: shortest route ({km} km, {min} min) — saves fuel ⛽'**
  String routeRecommendShortest(Object km, Object min);

  /// No description provided for @mapModeNorthUp.
  ///
  /// In en, this message translates to:
  /// **'North up'**
  String get mapModeNorthUp;

  /// No description provided for @mapModeHeadingUp.
  ///
  /// In en, this message translates to:
  /// **'Heading up'**
  String get mapModeHeadingUp;

  /// No description provided for @mapModeOverview.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get mapModeOverview;

  /// No description provided for @mapModeFollowCam.
  ///
  /// In en, this message translates to:
  /// **'Follow cam'**
  String get mapModeFollowCam;

  /// No description provided for @exactAlarmOffTitle.
  ///
  /// In en, this message translates to:
  /// **'Exact alarms are off'**
  String get exactAlarmOffTitle;

  /// No description provided for @exactAlarmOffDesc.
  ///
  /// In en, this message translates to:
  /// **'Without the exact-alarm permission, Android may deliver reminders late. Grant it so they arrive right on time.'**
  String get exactAlarmOffDesc;

  /// No description provided for @batteryExemptTitle.
  ///
  /// In en, this message translates to:
  /// **'Battery optimization exemption'**
  String get batteryExemptTitle;

  /// No description provided for @batteryExemptDesc.
  ///
  /// In en, this message translates to:
  /// **'Battery saving can delay or even block reminders — especially on Infinix phones. Exempt the app so reminders arrive on time.'**
  String get batteryExemptDesc;

  /// No description provided for @enableAction.
  ///
  /// In en, this message translates to:
  /// **'Enable'**
  String get enableAction;

  /// No description provided for @testNotificationNow.
  ///
  /// In en, this message translates to:
  /// **'Instant notification test'**
  String get testNotificationNow;

  /// No description provided for @testNotificationScheduled.
  ///
  /// In en, this message translates to:
  /// **'Scheduled test (in 1 minute)'**
  String get testNotificationScheduled;

  /// No description provided for @testNotificationTitle.
  ///
  /// In en, this message translates to:
  /// **'Notification test'**
  String get testNotificationTitle;

  /// No description provided for @testNotificationBody.
  ///
  /// In en, this message translates to:
  /// **'Instant notification received — if you can read this, notifications work.'**
  String get testNotificationBody;

  /// No description provided for @testScheduledBody.
  ///
  /// In en, this message translates to:
  /// **'The scheduled notification arrived — scheduled reminders work.'**
  String get testScheduledBody;

  /// No description provided for @testScheduledInstructions.
  ///
  /// In en, this message translates to:
  /// **'A notification was scheduled for 1 minute from now. Close the app and wait — if it arrives while the app is closed, reminders work.'**
  String get testScheduledInstructions;

  /// No description provided for @testScheduledFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t schedule the test notification — make sure notifications are allowed, then try again.'**
  String get testScheduledFailed;

  /// No description provided for @testScheduledFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Scheduled test failed'**
  String get testScheduledFailedTitle;

  /// No description provided for @technicalReason.
  ///
  /// In en, this message translates to:
  /// **'Technical reason'**
  String get technicalReason;

  /// No description provided for @diagnosticsLog.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics log'**
  String get diagnosticsLog;

  /// No description provided for @diagnosticsLogTitle.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics log'**
  String get diagnosticsLogTitle;

  /// No description provided for @diagnosticsLogEmpty.
  ///
  /// In en, this message translates to:
  /// **'No log entries yet — app events and errors will appear here.'**
  String get diagnosticsLogEmpty;

  /// No description provided for @diagnosticsLogAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get diagnosticsLogAll;

  /// No description provided for @diagnosticsLogCopied.
  ///
  /// In en, this message translates to:
  /// **'Log copied'**
  String get diagnosticsLogCopied;

  /// No description provided for @diagnosticsLogCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy all'**
  String get diagnosticsLogCopy;

  /// No description provided for @diagnosticsLogShare.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get diagnosticsLogShare;

  /// No description provided for @diagnosticsLogClear.
  ///
  /// In en, this message translates to:
  /// **'Clear log'**
  String get diagnosticsLogClear;

  /// No description provided for @diagnosticsLogClearConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear the diagnostics log?'**
  String get diagnosticsLogClearConfirmTitle;

  /// No description provided for @diagnosticsLogClearConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'All log entries will be permanently deleted.'**
  String get diagnosticsLogClearConfirmBody;

  /// No description provided for @logCategoryNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get logCategoryNotifications;

  /// No description provided for @logCategoryTracking.
  ///
  /// In en, this message translates to:
  /// **'Tracking'**
  String get logCategoryTracking;

  /// No description provided for @logCategoryOrders.
  ///
  /// In en, this message translates to:
  /// **'Orders'**
  String get logCategoryOrders;

  /// No description provided for @logCategoryShare.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get logCategoryShare;

  /// No description provided for @logCategorySystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get logCategorySystem;

  /// No description provided for @logCategorySettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get logCategorySettings;

  /// No description provided for @logLevelInfo.
  ///
  /// In en, this message translates to:
  /// **'Info'**
  String get logLevelInfo;

  /// No description provided for @logLevelWarn.
  ///
  /// In en, this message translates to:
  /// **'Warning'**
  String get logLevelWarn;

  /// No description provided for @logLevelError.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get logLevelError;

  /// No description provided for @countOnlyOrder.
  ///
  /// In en, this message translates to:
  /// **'Order (count only)'**
  String get countOnlyOrder;

  /// No description provided for @addOrderDetailed.
  ///
  /// In en, this message translates to:
  /// **'Order with details'**
  String get addOrderDetailed;

  /// No description provided for @addOrderDetailedDesc.
  ///
  /// In en, this message translates to:
  /// **'A new order that opens right away — so you can start delivery and track the distance.'**
  String get addOrderDetailedDesc;

  /// No description provided for @developerMode.
  ///
  /// In en, this message translates to:
  /// **'Developer Mode'**
  String get developerMode;

  /// No description provided for @developerModeOn.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get developerModeOn;

  /// No description provided for @developerModeOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get developerModeOff;

  /// No description provided for @developerPasswordTitle.
  ///
  /// In en, this message translates to:
  /// **'Enable Developer Mode'**
  String get developerPasswordTitle;

  /// No description provided for @developerPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Enter the password'**
  String get developerPasswordHint;

  /// No description provided for @developerPasswordError.
  ///
  /// In en, this message translates to:
  /// **'Incorrect password'**
  String get developerPasswordError;

  /// No description provided for @developerUnlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get developerUnlock;

  /// No description provided for @developerDisableTitle.
  ///
  /// In en, this message translates to:
  /// **'Turn off Developer Mode?'**
  String get developerDisableTitle;

  /// No description provided for @developerDisableBody.
  ///
  /// In en, this message translates to:
  /// **'The diagnostics tools (notification tests, diagnostics log and notification status) will be hidden until you unlock again with the password.'**
  String get developerDisableBody;

  /// No description provided for @developerDisable.
  ///
  /// In en, this message translates to:
  /// **'Turn off'**
  String get developerDisable;

  /// No description provided for @notificationStatusTitle.
  ///
  /// In en, this message translates to:
  /// **'Notification status'**
  String get notificationStatusTitle;

  /// No description provided for @statusPermNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications permission'**
  String get statusPermNotifications;

  /// No description provided for @statusExactAlarm.
  ///
  /// In en, this message translates to:
  /// **'Exact alarm permission'**
  String get statusExactAlarm;

  /// No description provided for @statusBattery.
  ///
  /// In en, this message translates to:
  /// **'Battery optimization exemption'**
  String get statusBattery;

  /// No description provided for @statusChannel.
  ///
  /// In en, this message translates to:
  /// **'Reminders channel priority'**
  String get statusChannel;

  /// No description provided for @statusOk.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get statusOk;

  /// No description provided for @statusProblem.
  ///
  /// In en, this message translates to:
  /// **'Problem'**
  String get statusProblem;

  /// No description provided for @statusUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get statusUnknown;

  /// No description provided for @weekEarningsSoFar.
  ///
  /// In en, this message translates to:
  /// **'This week\'s earnings so far'**
  String get weekEarningsSoFar;

  /// No description provided for @exportPdfAllWeeks.
  ///
  /// In en, this message translates to:
  /// **'Export all weeks as PDF'**
  String get exportPdfAllWeeks;

  /// No description provided for @pdfReportTitle.
  ///
  /// In en, this message translates to:
  /// **'Weeks report'**
  String get pdfReportTitle;

  /// No description provided for @pdfGeneratedOn.
  ///
  /// In en, this message translates to:
  /// **'Generated on'**
  String get pdfGeneratedOn;

  /// No description provided for @pdfColDate.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get pdfColDate;

  /// No description provided for @pdfColStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get pdfColStatus;

  /// No description provided for @pdfColHours.
  ///
  /// In en, this message translates to:
  /// **'Hours'**
  String get pdfColHours;

  /// No description provided for @pdfColEarnings.
  ///
  /// In en, this message translates to:
  /// **'Earnings'**
  String get pdfColEarnings;

  /// No description provided for @pdfWeekTotals.
  ///
  /// In en, this message translates to:
  /// **'Week total'**
  String get pdfWeekTotals;

  /// No description provided for @pdfGrandTotals.
  ///
  /// In en, this message translates to:
  /// **'Grand totals'**
  String get pdfGrandTotals;

  /// No description provided for @pdfNoWeeks.
  ///
  /// In en, this message translates to:
  /// **'No recorded weeks yet'**
  String get pdfNoWeeks;

  /// No description provided for @pdfFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'PDF generation failed'**
  String get pdfFailedTitle;

  /// No description provided for @logCategoryReports.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get logCategoryReports;

  /// No description provided for @emailLabel.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get emailLabel;
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
