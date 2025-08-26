// // android_phone_notifications.dart
// //
// // Purpose: Handle *phone* notifications on Android only (no in-app UI).
// // Free + simple: local notifications, no server / Cloud Functions.
// // What it does: schedule "1 day before" reminders using dateYMD + start HH:mm.
// // Huawei friendly: allow while idle so Doze won't block it.
// // Privacy: no facility name in message, just a generic reminder.
//
// import 'package:flutter/foundation.dart'; // kIsWeb check
// import 'package:flutter_local_notifications/flutter_local_notifications.dart';
// import 'package:timezone/timezone.dart' as tz;            // timezone objects
// import 'package:timezone/data/latest.dart' as tzdata;     // timezone data
//
// class PhoneNotifications {
//   // Keep one plugin instance so we can schedule/cancel with the same object.
//   static final FlutterLocalNotificationsPlugin _plugin =
//   FlutterLocalNotificationsPlugin();
//
//   // Android channel constants (must be stable).
//   static const String _channelId = 'booking_reminders';
//   static const String _channelName = 'Booking Reminders';
//
//   // ---------------------------------------
//   // init() -> call once on app start (main.dart)
//   // Why: setup timezone + initialize plugin + ask Android permission.
//   // ---------------------------------------
//   static Future<void> init() async {
//     // We do NOT run on web to avoid plugin calls on web builds.
//     if (kIsWeb) {
//       return;
//     }
//
//     // 1) Timezone setup (use local "Asia/Kuala_Lumpur")
//     // Why: we want the exact local time to avoid wrong scheduling.
//     tzdata.initializeTimeZones();
//     try {
//       tz.setLocalLocation(tz.getLocation('Asia/Kuala_Lumpur'));
//     } catch (_) {
//       // If this fails, device local tz will still be used.
//     }
//
//     // 2) Initialize Android side of the plugin
//     // Why: plugin needs settings per platform before use.
//     const AndroidInitializationSettings androidInit =
//     AndroidInitializationSettings('@mipmap/ic_launcher'); // app icon
//
//     final InitializationSettings settings = InitializationSettings(
//       android: androidInit,    // we only set Android to keep things simple
//       // iOS/macOS not included on purpose to avoid Darwin types
//     );
//
//     // We keep onSelectNotification/payload handling minimal (open app).
//     await _plugin.initialize(settings);
//
//     // 3) Ask Android (13+) runtime permission
//     await _requestAndroidPermission();
//   }
//
//   // ---------------------------------------
//   // scheduleBookingReminder(ymd, hhmm)
//   // Why: schedule "1 day before" notification for a booking slot.
//   // - ymd must be "YYYY-MM-DD"
//   // - hhmm must be "HH:mm" (24h)
//   // ---------------------------------------
//   static Future<void> scheduleBookingReminder(String ymd, String hhmm) async {
//     // Safety: skip on web (not supported)
//     if (kIsWeb) {
//       return;
//     }
//
//     try {
//       // Create a unique ID from date/time (e.g., 202509040800)
//       // Why: so we can cancel/edit the same reminder later if needed.
//       final String digits = ymd.replaceAll('-', '') + hhmm.replaceAll(':', '');
//       int id = int.tryParse(digits) ?? DateTime.now().millisecondsSinceEpoch;
//       if (id > 2147483647) {
//         id = id % 2147483647; // keep it in 32-bit int range (safety)
//       }
//
//       // Parse date/time strings using simple int parsing (diploma level)
//       final List<String> dp = ymd.split('-');
//       final List<String> tp = hhmm.split(':');
//
//       int y = 0;
//       int m = 0;
//       int d = 0;
//       int h = 0;
//       int min = 0;
//
//       if (dp.length == 3) {
//         final int? yy = int.tryParse(dp[0]);
//         final int? mm = int.tryParse(dp[1]);
//         final int? dd = int.tryParse(dp[2]);
//         if (yy != null) y = yy;
//         if (mm != null) m = mm;
//         if (dd != null) d = dd;
//       }
//
//       if (tp.length >= 2) {
//         final int? hh = int.tryParse(tp[0]);
//         final int? mn = int.tryParse(tp[1]);
//         if (hh != null) h = hh;
//         if (mn != null) min = mn;
//       }
//
//       // Build the booking start time in local timezone
//       final tz.TZDateTime startAt = tz.TZDateTime(tz.local, y, m, d, h, min);
//
//       // Reminder time is 24 hours before start
//       final tz.TZDateTime reminderAt = startAt.subtract(const Duration(days: 1));
//
//       // If reminder time is already in the past, skip scheduling
//       final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
//       if (reminderAt.isBefore(now)) {
//         return;
//       }
//
//       // Android notification style and behaviour (simple + audible)
//       const AndroidNotificationDetails androidDetails =
//       AndroidNotificationDetails(
//         _channelId,
//         _channelName,
//         channelDescription:
//         'Sends reminders 1 day before your booking starts.',
//         importance: Importance.high,
//         priority: Priority.high,
//         playSound: true,
//         enableVibration: true,
//       );
//
//       // Build cross-platform details object (Android only here)
//       const NotificationDetails details = NotificationDetails(
//         android: androidDetails,
//       );
//
//       // Schedule the notification exactly at reminderAt.
//       // NOTE:
//       // - Newer plugin versions need androidScheduleMode.
//       // - Older versions used androidAllowWhileIdle: true.
//       // We use the newer required parameter. If your plugin is older,
//       // update it in pubspec.yaml to ^17.x to match this call.
//       await _plugin.zonedSchedule(
//         id, // unique id
//         'Booking Reminder', // title
//         'One of your bookings will be active tomorrow. Open the app to check.', // body (no facility name)
//         reminderAt, // when
//         details, // how it looks
//         androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle, // do not miss due to Doze
//         uiLocalNotificationDateInterpretation:
//         UILocalNotificationDateInterpretation.absoluteTime, // treat as fixed point in time
//         payload: 'open_bookings', // simple payload for future deep-link if needed
//       );
//     } catch (e) {
//       if (kDebugMode) {
//         print('scheduleBookingReminder error: $e'); // help during testing
//       }
//     }
//   }
//
//   // ---------------------------------------
//   // cancelBookingReminder(ymd, hhmm)
//   // Why: helper to cancel a scheduled reminder if booking is edited/cancelled.
//   // ---------------------------------------
//   static Future<void> cancelBookingReminder(String ymd, String hhmm) async {
//     if (kIsWeb) {
//       return;
//     }
//     final String digits = ymd.replaceAll('-', '') + hhmm.replaceAll(':', '');
//     int id = int.tryParse(digits) ?? 0;
//     if (id > 2147483647) {
//       id = id % 2147483647;
//     }
//     await _plugin.cancel(id);
//   }
//
//   // ---------------------------------------
//   // _requestAndroidPermission()
//   // Why: Android 13+ requires runtime permission to post notifications.
//   // ---------------------------------------
//   static Future<void> _requestAndroidPermission() async {
//     final AndroidFlutterLocalNotificationsPlugin? androidImpl =
//     _plugin.resolvePlatformSpecificImplementation<
//         AndroidFlutterLocalNotificationsPlugin>();
//
//     if (androidImpl != null) {
//       await androidImpl.requestNotificationsPermission(); // shows system dialog on API 33+
//     }
//   }
// }
