// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get aboutApp => 'About DeliveryFlow';

  @override
  String get activeSession => 'Active session';

  @override
  String get appSection => 'Application';

  @override
  String get appTitle => 'DeliveryFlow';

  @override
  String get appearanceSection => 'Appearance';

  @override
  String get applyToSelected => 'Apply to selected';

  @override
  String get avgHoursWorkingDay => 'Avg hours / working day';

  @override
  String get avgOrdersPerDay => 'Avg orders / day';

  @override
  String get avgOrdersWorkingDay => 'Avg orders / working day';

  @override
  String get backupCreated => 'Backup created';

  @override
  String get backupData => 'Back up data';

  @override
  String get backupFailed => 'Backup failed';

  @override
  String get backupRestored => 'Backup restored';

  @override
  String get bestDay => 'Best day';

  @override
  String get breakMinutes => 'Break (minutes)';

  @override
  String get breakTime => 'Break time';

  @override
  String get cancel => 'Cancel';

  @override
  String get channelReminders => 'Reminders';

  @override
  String get channelRemindersDesc => 'Schedule, daily and report reminders';

  @override
  String get clearAllConfirmBody =>
      'This permanently deletes all schedules, records and settings. This cannot be undone.';

  @override
  String get clearAllConfirmTitle => 'Delete everything?';

  @override
  String get clearAllData => 'Clear all data';

  @override
  String get close => 'Close';

  @override
  String completeDays(Object count) {
    return '$count complete days';
  }

  @override
  String get confirm => 'Confirm';

  @override
  String get confirmed => 'Confirmed';

  @override
  String get copyDay => 'Copy this day';

  @override
  String get copyToDays => 'Copy to days';

  @override
  String get correctSession => 'Correct manually';

  @override
  String get createSchedule => 'Create schedule';

  @override
  String get csvExported => 'CSV exported';

  @override
  String get currentWeek => 'Current week';

  @override
  String get dailyBreakdown => 'Daily breakdown';

  @override
  String get dailyReminderEnabled => 'Daily reminder';

  @override
  String get dailyReminderTime => 'Daily order reminder';

  @override
  String get dailySummary => 'Daily summary';

  @override
  String get dataSection => 'Data management';

  @override
  String get dayOff => 'Day off';

  @override
  String get defaultBreakLabel => 'Default break (minutes)';

  @override
  String get delete => 'Delete';

  @override
  String get designedBy => 'Designed by';

  @override
  String get designerName => 'eng/Mohamed El Sayed';

  @override
  String get contactLabel => 'Contact';

  @override
  String get navProfile => 'My Account';

  @override
  String get profileSetup => 'Set Up Account';

  @override
  String get fullName => 'Full Name';

  @override
  String get driverRole => 'Delivery Driver';

  @override
  String get changePhoto => 'Change Photo';

  @override
  String get tapToAddPhoto => 'Tap to add photo';

  @override
  String get helpSupport => 'Help & Support';

  @override
  String get quickActions => 'Quick actions';

  @override
  String get geoAddressNotFound => 'Couldn\'t find that address on the map.';

  @override
  String get geoPreparingOrder => 'Preparing your order…';

  @override
  String get geoShareFailedBody =>
      'We couldn\'t understand the location shared from the other app. Try sharing it again.';

  @override
  String get geoShareFailedTitle => 'Couldn\'t open the shared location';

  @override
  String get greetingHello => 'Hello';

  @override
  String get reportsMenu => 'Reports & Statistics';

  @override
  String get callUs => 'Call us';

  @override
  String get displayNameHint => 'e.g. Ahmed';

  @override
  String get displayNameLabel => 'Display name';

  @override
  String get done => 'Done';

  @override
  String get edit => 'Edit';

  @override
  String get editSchedule => 'Edit schedule';

  @override
  String get elapsedTime => 'Elapsed';

  @override
  String get emptyStateAction => 'Record today\'s orders';

  @override
  String get emptyStateBody =>
      'Start by recording today\'s orders or setting your weekly schedule.';

  @override
  String get emptyStateTitle => 'No records yet';

  @override
  String get endTime => 'End time';

  @override
  String get exportCsv => 'Export CSV';

  @override
  String get exportRecordsCsv => 'Export records (CSV)';

  @override
  String get finishWork => 'Finish work';

  @override
  String get followUpReminderEnabled => 'Follow-up reminder';

  @override
  String get followUpReminderTime => 'Follow-up reminder';

  @override
  String get friday => 'Friday';

  @override
  String get getStarted => 'Get started';

  @override
  String get greetingAfternoon => 'Good afternoon';

  @override
  String get greetingEvening => 'Good evening';

  @override
  String get greetingMorning => 'Good morning';

  @override
  String get historyTitle => 'History';

  @override
  String get hoursChartTitle => 'Daily working hours';

  @override
  String hoursShort(Object hours) {
    return '${hours}h';
  }

  @override
  String get hoursTitle => 'Working hours';

  @override
  String get howManyOrders => 'How many orders did you complete?';

  @override
  String get enterCountHint => 'Type the number';

  @override
  String get incompleteWeek => 'Incomplete week — some days have no records.';

  @override
  String get invalidBreak => 'Break cannot exceed the shift length.';

  @override
  String get invalidOrderCount => 'Order count cannot be negative.';

  @override
  String get invalidShift =>
      'End time must be after start time (overnight shifts allowed).';

  @override
  String get invalidTimeRange => 'End time must differ from start time.';

  @override
  String get languageSection => 'Language';

  @override
  String get manualEntry => 'Manual entry';

  @override
  String get markDaysOff => 'Mark days off';

  @override
  String get missingRecords => 'Missing records';

  @override
  String get monday => 'Monday';

  @override
  String get navHistory => 'History';

  @override
  String get navHome => 'Home';

  @override
  String get navReports => 'Reports';

  @override
  String get navSchedule => 'Schedule';

  @override
  String get navSettings => 'Settings';

  @override
  String get netHours => 'Net working time';

  @override
  String get next => 'Next';

  @override
  String get nextWeek => 'Next week';

  @override
  String get noData => 'No data';

  @override
  String get noScheduleYet => 'No schedule for this week yet.';

  @override
  String get notesOptional => 'Notes (optional)';

  @override
  String get notifDailyBody =>
      'Record today\'s orders and working hours to keep your weekly report accurate.';

  @override
  String get notifDailyTitle => 'Good evening!';

  @override
  String get notifFollowUpBody => 'You haven\'t recorded today\'s orders yet.';

  @override
  String get notifFollowUpTitle => 'Reminder';

  @override
  String get notifReportBody =>
      'Your weekly report is ready. Review your orders and working hours.';

  @override
  String get notifReportTitle => 'Weekly report ready';

  @override
  String get notifScheduleBody =>
      'Prepare your next work week. Set your Sunday-to-Saturday schedule.';

  @override
  String get notifScheduleTitle => 'Plan next week';

  @override
  String get notificationPermissionNeeded =>
      'Please allow notifications in system settings.';

  @override
  String get notificationsEnabled => 'Enable notifications';

  @override
  String get notificationsSection => 'Notifications';

  @override
  String get ok => 'OK';

  @override
  String get onBreak => 'On break';

  @override
  String get onboardingSubtitle =>
      'Your weekly schedule, orders and working hours — all in one place.';

  @override
  String get onboardingTitle => 'Welcome to DeliveryFlow';

  @override
  String get openWeek => 'Open week';

  @override
  String get orderNotesHint => 'Optional notes';

  @override
  String get ordersChartTitle => 'Daily orders';

  @override
  String ordersCount(Object count) {
    return '$count orders';
  }

  @override
  String ordersForDate(Object date) {
    return 'Orders for $date';
  }

  @override
  String get ordersPerHour => 'Orders/hour';

  @override
  String get ordersTitle => 'Daily orders';

  @override
  String get overlapWarning =>
      'You already have an active session. Finish it before starting a new one.';

  @override
  String plannedHours(Object hours) {
    return 'Planned: ${hours}h';
  }

  @override
  String get preferredLanguage => 'Preferred language';

  @override
  String get preferredTheme => 'Preferred theme';

  @override
  String get previousWeek => 'Previous week';

  @override
  String get privacyBody =>
      'DeliveryFlow stores all your data locally on this device. No account is required, no location is tracked, and nothing is sent to any server.';

  @override
  String get privacyInfo => 'Privacy';

  @override
  String get quickBrowseHistory => 'History';

  @override
  String get quickRecordHours => 'Record working hours';

  @override
  String get quickRecordOrders => 'Record today\'s orders';

  @override
  String get quickViewReport => 'Weekly report';

  @override
  String get quickViewSchedule => 'Weekly schedule';

  @override
  String get recordCounts => 'Stored records';

  @override
  String get recordSaved => 'Record saved';

  @override
  String get recordUpdated => 'Record updated';

  @override
  String get recordedDays => 'Recorded days';

  @override
  String get registerError => 'Incorrect code, try again';

  @override
  String get registerHint => 'Enter the registration code';

  @override
  String get registerTitle => 'Registration Code';

  @override
  String get remindMeLater => 'Later';

  @override
  String get reminderTimeLabel => 'Daily end-of-day reminder';

  @override
  String reportForWeek(Object end, Object start) {
    return 'Report: $start – $end';
  }

  @override
  String get reportReminderEnabled => 'Report reminder';

  @override
  String get reportReminderTime => 'Weekly report reminder';

  @override
  String get reportTitle => 'Weekly report';

  @override
  String get restoreBackup => 'Restore backup';

  @override
  String get resumeWork => 'Resume work';

  @override
  String get saturday => 'Saturday';

  @override
  String get saturdayPromptBody =>
      'Set your working schedule for next week (Sunday – Saturday).';

  @override
  String get saturdayPromptTitle => 'Plan next week';

  @override
  String get save => 'Save';

  @override
  String get saveRecord => 'Save';

  @override
  String get saveSchedule => 'Save schedule';

  @override
  String scheduleForWeek(Object end, Object start) {
    return 'Schedule for $start – $end';
  }

  @override
  String get scheduleReminderEnabled => 'Schedule reminder';

  @override
  String get scheduleReminderTime => 'Schedule reminder';

  @override
  String get scheduleSaved => 'Schedule saved';

  @override
  String get scheduleSummary => 'Week summary';

  @override
  String get scheduleTitle => 'Weekly schedule';

  @override
  String get scheduledVsActual => 'Scheduled vs actual';

  @override
  String get sessionRestored => 'Previous session restored';

  @override
  String get sessionTimer => 'Work timer';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get shareSummary => 'Share summary';

  @override
  String get skip => 'Skip';

  @override
  String get startTime => 'Start time';

  @override
  String get startWork => 'Start work';

  @override
  String get sunday => 'Sunday';

  @override
  String get takeBreak => 'Take a break';

  @override
  String get testNotification => 'Send test notification';

  @override
  String get testNotificationSent => 'Test notification sent';

  @override
  String get themeDark => 'Dark';

  @override
  String get themeLight => 'Light';

  @override
  String get themeSystem => 'System default';

  @override
  String get thursday => 'Thursday';

  @override
  String get todayHours => 'Today\'s hours';

  @override
  String get todayOrders => 'Today\'s orders';

  @override
  String get totalOrders => 'Total orders';

  @override
  String totalPlannedHours(Object hours) {
    return 'Total planned: ${hours}h';
  }

  @override
  String get totalPlannedHoursLabel => 'Planned hours';

  @override
  String get totalRecordedHours => 'Recorded hours';

  @override
  String get tuesday => 'Tuesday';

  @override
  String get unrecorded => 'Not recorded';

  @override
  String get versionLabel => 'Version';

  @override
  String get vsLastWeek => 'vs last week';

  @override
  String get wednesday => 'Wednesday';

  @override
  String weekCardRange(Object end, Object start) {
    return '$start – $end';
  }

  @override
  String get weekHours => 'This week\'s hours';

  @override
  String get weekOrders => 'This week\'s orders';

  @override
  String get weeklyGoalProgress => 'Weekly goal';

  @override
  String get weeklyHoursGoal => 'Weekly working-hours goal (optional)';

  @override
  String get weeklyHoursGoalLabel => 'Weekly hours goal';

  @override
  String get weeklyOrderGoal => 'Weekly order goal (optional)';

  @override
  String get weeklyOrderGoalLabel => 'Weekly order goal';

  @override
  String get workEnd => 'Work end';

  @override
  String get workPrefsSection => 'Work preferences';

  @override
  String get workStart => 'Work start';

  @override
  String get workingDay => 'Working day';

  @override
  String get zeroOrders => '0 orders';

  @override
  String get addOrder => 'Add order';

  @override
  String get editOrder => 'Edit order';

  @override
  String get deleteOrderTitle => 'Delete order?';

  @override
  String get deleteOrderConfirm =>
      'This order will be removed from the day\'s log.';

  @override
  String get invalidKm => 'Enter a number greater than zero';

  @override
  String get kmOutLabel => 'Going';

  @override
  String get kmBackLabel => 'Returning';

  @override
  String get kmUnit => 'km';

  @override
  String get noOrdersYet => 'No orders logged yet — add the first one';

  @override
  String get orderAdded => 'Order added';

  @override
  String get orderDeleted => 'Order deleted';

  @override
  String get orderUpdated => 'Changes saved';

  @override
  String get recenter => 'My location';

  @override
  String get orderTime => 'Order time';

  @override
  String get ordersLabel => 'Orders';

  @override
  String ordersWithoutDetails(int count) {
    return '+$count orders logged without distance details';
  }

  @override
  String get totalKmLabel => 'Total distance';

  @override
  String get todayKm => 'Today\'s distance';

  @override
  String get weekKmLabel => 'Week distance';

  @override
  String get avgKmPerDay => 'Avg / day';

  @override
  String get chooseTheme => 'Choose theme';

  @override
  String get salarySection => 'Salary';

  @override
  String get orderPriceLabel => 'Price per order (EGP)';

  @override
  String get dailyFixedLabel => 'Daily fixed pay (EGP)';

  @override
  String get weeklySalary => 'Weekly salary';

  @override
  String get attendanceDays => 'Days attended';

  @override
  String get setSalaryHint =>
      'Set the order price and daily fixed pay in Settings to calculate the weekly salary';

  @override
  String get egpUnit => 'EGP';

  @override
  String get orderDetails => 'Order details';

  @override
  String get statusPending => 'Pending';

  @override
  String get statusToCustomer => 'On the way to customer';

  @override
  String get statusToMart => 'Returning to mart';

  @override
  String get statusCompleted => 'Completed';

  @override
  String get startDelivery => 'Start delivery';

  @override
  String get arrivedAtCustomer => 'Arrived at customer';

  @override
  String get arrivedAtMart => 'Arrived at mart';

  @override
  String get orderCompleted => 'Order completed successfully';

  @override
  String get trackingToCustomer => 'Tracking: to customer';

  @override
  String get trackingToMart => 'Tracking: back to mart';

  @override
  String get distanceSoFar => 'Distance so far';

  @override
  String get timeElapsed => 'Time elapsed';

  @override
  String get gpsAccuracyNote =>
      'Distance is calculated automatically via GPS with high accuracy';

  @override
  String get tripBreakdown => 'Trip breakdown';

  @override
  String get pickupTime => 'Pickup time from mart';

  @override
  String get outgoingLeg => 'Outgoing (mart → customer)';

  @override
  String get deliveryTime => 'Delivery time to customer';

  @override
  String get returnLeg => 'Return (customer → mart)';

  @override
  String get martArrivalTime => 'Mart arrival time';

  @override
  String get totalTripTime => 'Total order time';

  @override
  String get totalTripDistance => 'Total order distance';

  @override
  String get locationPermissionRequired =>
      'Location permission is required for tracking';

  @override
  String get pleaseWait => 'Please wait…';

  @override
  String get routeMapTitle => 'Route map';

  @override
  String get martLabel => 'Mart';

  @override
  String get customerLabel => 'Customer';

  @override
  String get outgoingLegShort => 'Outgoing';

  @override
  String get returnLegShort => 'Return';

  @override
  String get noRouteData =>
      'No route data for this order (created before tracking)';

  @override
  String get tapToStartTracking => 'Tap to start GPS tracking';

  @override
  String get weeklyHeatmap => 'Heatmap';

  @override
  String get noHeatmapData =>
      'No route data for this week yet. Track orders with GPS and they will appear here.';

  @override
  String get heatmapHot => 'Most visited';

  @override
  String get heatmapWarm => 'Average';

  @override
  String get heatmapCold => 'Rare';

  @override
  String heatmapSubtitle(int count) {
    return 'Recorded points this week: $count';
  }

  @override
  String get dayOrdersTitle => 'Day\'s orders';

  @override
  String get noOrdersThisDay => 'No orders recorded this day';

  @override
  String get deleteWeekTitle => 'Delete week?';

  @override
  String get deleteWeekBody =>
      'Are you sure? Deletion is permanent — the whole week with all its orders will be removed.';

  @override
  String get liveTripMapTitle => 'Live trip map';

  @override
  String get waitingForGps => 'Waiting for GPS signal…';

  @override
  String get tripNote => 'Note';

  @override
  String get tripNoteHint => 'Write the address or any note…';

  @override
  String get phoneNumber => 'Phone number';

  @override
  String get phoneNumberHint => 'Optional';

  @override
  String get trackingFailedTitle => 'Tracking failed to start';

  @override
  String get returnTrackingFailed =>
      'Outgoing distance was saved, but return tracking failed to start.';

  @override
  String get retry => 'Retry';

  @override
  String get trackingStartFailed => 'Couldn\'t start tracking';

  @override
  String get enterManualKm => 'Enter kilometers manually';

  @override
  String get manualKmLabel => 'Distance (km)';

  @override
  String get manualKmHint => 'e.g. 3.5';

  @override
  String get manualBadge => 'Manual';

  @override
  String get editManualDistance => 'Edit distance manually';

  @override
  String get trackingStoppedTitle => 'Tracking stopped';

  @override
  String get trackingStoppedBody =>
      'Tracking isn\'t running for this order, so kilometers aren\'t being counted. Restart it or enter the distance manually?';

  @override
  String get startTracking => 'Start tracking';

  @override
  String get weekProgress => 'Week progress';

  @override
  String get setWeeklyGoalHint => 'Tap to set your goal';

  @override
  String get viewWeekDetails => 'View week details';

  @override
  String get daySummary => 'Day summary';

  @override
  String get totalDistances => 'Total distances';

  @override
  String get ordersBreakdown => 'Orders breakdown';

  @override
  String get statusInProgress => 'In progress';

  @override
  String get viewFullReport => 'View full report';

  @override
  String get liveTrackingNow => 'Live delivery';

  @override
  String get onWayToCustomer => 'On your way to the customer';

  @override
  String get onWayToMart => 'On your way back to the mart';

  @override
  String get viewDetails => 'View details';

  @override
  String get endOfDayNotif => 'End-of-day notifications';

  @override
  String get weeklyScheduleNotif => 'Weekly schedule reminder';

  @override
  String get notifTime => 'Notification time';

  @override
  String get splashLoading => 'Loading...';

  @override
  String completedOrdersChip(Object count) {
    return '$count completed orders';
  }

  @override
  String get workSmarterTagline => 'Work Smarter • Deliver Faster';

  @override
  String get deliverFaster => 'Work smarter, deliver faster';

  @override
  String get completedOrdersLabel => 'completed orders';

  @override
  String get statusNotStarted => 'Not started';

  @override
  String get navigate => 'Navigate';

  @override
  String get searchCustomers => 'Search customers';

  @override
  String get searchPhoneHint => 'Type customer phone number';

  @override
  String customerVisits(Object count) {
    return 'Visited this customer $count times';
  }

  @override
  String get customerOrdersTitle => 'Customer orders';

  @override
  String get noCustomersFound => 'No customers with this number';

  @override
  String get typeMoreDigits => 'Type at least 3 digits';

  @override
  String get notificationsTitle => 'Notifications';

  @override
  String get noNotifications => 'No notifications yet';

  @override
  String get markAllRead => 'Mark all as read';

  @override
  String get notificationDismissed => 'Notification dismissed';

  @override
  String get notifOrderCompleted => 'Order completed';

  @override
  String get notifManualKm => 'Manual distance recorded';

  @override
  String get showDetails => 'Show details';

  @override
  String get call => 'Call';

  @override
  String get copyNumber => 'Copy number';

  @override
  String get copied => 'Number copied';

  @override
  String get navigatingNow => 'Navigating now';

  @override
  String get locatingYou => 'Locating you…';

  @override
  String get minute => 'min';

  @override
  String get navRouteFailed => 'Could not calculate the route, try again';
}
