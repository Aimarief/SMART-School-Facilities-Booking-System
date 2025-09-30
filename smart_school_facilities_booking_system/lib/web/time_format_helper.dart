import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class TimeFormatHelper {
//---------------------------------------
//
//---------------------------------------

  static String formatTimeOfDayTo12Hour(TimeOfDay time) {
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day, time.hour, time.minute);
    final formatter = DateFormat('hh:mm a'); // 12-hour format with AM/PM
    return formatter.format(dt);
  }

  /// Converts a DateTime to 12-hour format string like "02:30 PM"
  static String formatDateTimeTo12Hour(DateTime dateTime) {
    final formatter = DateFormat('hh:mm a');
    return formatter.format(dateTime);
  }

  /// Parses a 24-hour time string "HH:mm" and converts to 12-hour with AM/PM
  static String format24HourStringTo12Hour(String time24) {
    try {
      final dateTime = DateFormat('HH:mm').parse(time24);
      return formatDateTimeTo12Hour(dateTime);
    } catch (e) {
      return time24; // Return original if parsing fails
    }
  }
}
