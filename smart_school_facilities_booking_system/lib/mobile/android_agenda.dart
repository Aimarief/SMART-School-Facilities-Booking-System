import 'package:flutter/material.dart';                        // UI widgets
import 'package:flutter_screenutil/flutter_screenutil.dart';   // responsive sizes (.w .h .sp)
import 'package:intl/intl.dart';                               // date formatting
import 'package:firebase_auth/firebase_auth.dart';             // current user id
import 'package:cloud_firestore/cloud_firestore.dart';         // Firestore

// bottom bar
import 'android_bottom_menu.dart';
import 'android_list_of_facilities.dart';
import 'android_view_booking.dart';
import 'android_notifications.dart';
import 'android_account.dart';

class AndroidAgenda extends StatefulWidget {
  @override
  State<AndroidAgenda> createState() => _AndroidAgendaState();
}

class _AndroidAgendaState extends State<AndroidAgenda> {
  // ---------------- bottom bar state ----------------
  int _currentIndex = 0; // this page index in bottom menu

  // ---------------- agenda state ----------------
  DateTime _selectedDate = DateTime.now();  // which date user is viewing
  String _viewMode = 'daily';               // 'daily' or 'weekly' (default daily)

  // ---------------- working hours (minutes since midnight) ----------------
  int _workStartMin = 8 * 60;  // default 08:00 => 480
  int _workEndMin   = 18 * 60; // default 18:00 => 1080
  bool _loadingWorkHours = true; // show small loading until we read SystemInformation

  // ---------------- user id ----------------
  String? _userId; // will fill in initState

  // ---------------- simple cache for facility names ----------------
  final Map<String, String> _facNameCache = {}; // facilityId -> name

  // -------------- lifecycle: init --------------
  @override
  void initState() {
    super.initState();                        // call parent init
    _readUserId();                            // get current user id
    _loadWorkingHours();                      // read SystemInformation/Setting start/end
  }

  // -------------- bottom tabs handler --------------
  void _onTabSelected(int i) {
    // change bottom nav or navigate to other pages
    if (i == 0) {
      setState(() { _currentIndex = 0; });
    } else if (i == 1) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidViewBooking()));
    } else if (i == 2) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidListOfFacilities()));
    } else if (i == 3) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidNotifications()));
    } else if (i == 4) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidAccount()));
    }
  }

  // -------------- read current user id --------------
  void _readUserId() {
    // use ?. so if currentUser is null, uid is also null
    _userId = FirebaseAuth.instance.currentUser?.uid;
  }

  // -------------- load working hours from SystemInformation/Setting --------------
  Future<void> _loadWorkingHours() async {
    try {
      final DocumentSnapshot<Map<String, dynamic>> doc = await FirebaseFirestore.instance
          .collection('SystemInformation')
          .doc('Setting')
          .get();

      // if doc.data() is null, make it empty map using ??
      final Map<String, dynamic> data = doc.data() ?? {};

      // read start/end strings from multiple possible keys (helper below)
      final String startStr = _readFirstStr(data, <String>['start','workingHourStart','startTime','startWorkingHour']);
      final String endStr   = _readFirstStr(data, <String>['end','workingHourEnd','endTime','endWorkingHour']);

      // try parse; if invalid, keep defaults using plain if/else
      final int s = _parse24ToMinutes(startStr);
      if (s >= 0) { _workStartMin = s; } else { _workStartMin = 8 * 60; }

      final int e = _parse24ToMinutes(endStr);
      if (e > 0) { _workEndMin = e; } else { _workEndMin = 18 * 60; }
    } catch (e) {
      // keep defaults on error
    }

    // ensure at least 1 hour window
    if (_workEndMin <= _workStartMin) {
      _workEndMin = _workStartMin + 60;
    }

    setState(() { _loadingWorkHours = false; });
  }

  // -------------- helpers: text + dates --------------
  // reads the first non-null value from a set of keys and returns .toString()
  String _readFirstStr(Map<String, dynamic> m, List<String> keys) {
    for (int i = 0; i < keys.length; i = i + 1) {
      final String k = keys[i];
      // m[k] may be null → use ?.toString(), then ?? to fallback null to null
      final String? val = m[k]?.toString();
      if (val != null) {
        return val; // found a non-null string
      }
    }
    return ''; // not found
  }

  // parses "13:30", "1330", "13.30", "8", "08" → minutes since midnight; -1 if invalid
  int _parse24ToMinutes(String s) {
    String t = s.trim();
    if (t.isEmpty) { return -1; }
    t = t.replaceAll(' ', '');
    t = t.replaceAll('.', ':');

    if (t.contains(':')) {
      final List<String> parts = t.split(':');
      int hh = -1;
      int mm = 0;

      final int? p0 = int.tryParse(parts[0]);
      if (p0 != null) { hh = p0; } else { hh = -1; }

      if (parts.length >= 2) {
        final int? p1 = int.tryParse(parts[1]);
        if (p1 != null) { mm = p1; } else { mm = 0; }
      }

      if (hh >= 0 && hh <= 23 && mm >= 0 && mm <= 59) {
        return hh * 60 + mm;
      } else {
        return -1;
      }
    } else {
      if (t.length <= 2) {
        int hh = -1;
        final int? p = int.tryParse(t);
        if (p != null) { hh = p; } else { hh = -1; }
        if (hh >= 0 && hh <= 23) { return hh * 60; } else { return -1; }
      } else if (t.length == 3) {
        final String hStr = t.substring(0, 1);
        final String mStr = t.substring(1, 3);
        int hh = -1;
        int mm = -1;
        final int? p0 = int.tryParse(hStr);
        if (p0 != null) { hh = p0; } else { hh = -1; }
        final int? p1 = int.tryParse(mStr);
        if (p1 != null) { mm = p1; } else { mm = -1; }
        if (hh >= 0 && hh <= 23 && mm >= 0 && mm <= 59) { return hh * 60 + mm; } else { return -1; }
      } else if (t.length == 4) {
        final String hStr = t.substring(0, 2);
        final String mStr = t.substring(2, 4);
        int hh = -1;
        int mm = -1;
        final int? p0 = int.tryParse(hStr);
        if (p0 != null) { hh = p0; } else { hh = -1; }
        final int? p1 = int.tryParse(mStr);
        if (p1 != null) { mm = p1; } else { mm = -1; }
        if (hh >= 0 && hh <= 23 && mm >= 0 && mm <= 59) { return hh * 60 + mm; } else { return -1; }
      } else {
        return -1;
      }
    }
  }

  // make a date key like "2025-05-23"
  String _dateKey(DateTime d) {
    final String y = d.year.toString().padLeft(4, '0');
    final String m = d.month.toString().padLeft(2, '0');
    final String day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  // formats "23 May 2025"
  String _formatDateNoDay(DateTime d) {
    return DateFormat('d MMMM yyyy').format(d);
  }

  // formats "23 May"
  String _formatShortDate(DateTime d) {
    return DateFormat('d MMM').format(d);
  }

  // returns day name like "Wednesday"
  String _dayName(DateTime d) {
    return DateFormat('EEEE').format(d);
  }

  // formats minutes → "h.mm am/pm"
  String _formatHourLabel(int minutes) {
    final int hh24 = minutes ~/ 60;
    final int mm = minutes % 60;
    int hh12 = hh24 % 12;
    if (hh12 == 0) { hh12 = 12; }
    final String ampm = hh24 >= 12 ? 'pm' : 'am'; // this is simple and clear
    final String mmStr = mm.toString().padLeft(2, '0');
    return '$hh12.$mmStr $ampm';
  }

  // week start (Sunday) and 7 dates list
  DateTime _weekStartSunday(DateTime d) {
    final int wd = d.weekday; // Mon=1 ... Sun=7
    final int daysToSunday = wd % 7; // Sun=0, Mon=1, ... Sat=6
    return DateTime(d.year, d.month, d.day).subtract(Duration(days: daysToSunday));
  }

  // build 7 days for the current week
  List<DateTime> _weekDates(DateTime anchor) {
    final DateTime start = _weekStartSunday(anchor);
    final List<DateTime> out = <DateTime>[];
    for (int i = 0; i < 7; i = i + 1) {
      out.add(start.add(Duration(days: i)));
    }
    return out;
  }

  // safe bottom padding so content doesn't hide behind bottom bar
  double _bottomSafePadding(BuildContext context) {
    final double sysBottom = MediaQuery.of(context).padding.bottom;
    return 16.h + 60.h + sysBottom;
  }

  // -------------- open date picker --------------
  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
      builder: (context, child) {
        // return child directly; you can theme later if needed
        return child!;
      },
    );
    if (picked != null) {
      setState(() { _selectedDate = picked; });
    }
  }

  // -------------- bookings streams --------------
  Stream<QuerySnapshot<Map<String, dynamic>>> _bookingsStreamDaily() {
    // use ?? so if _userId is null, we use a placeholder not in DB
    final String uid = _userId ?? '__no_user__';
    final String dayKey = _dateKey(_selectedDate);
    return FirebaseFirestore.instance
        .collection('Bookings')
        .where('userId', isEqualTo: uid)
        .where('bookingDate', isEqualTo: dayKey)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _bookingsStreamWeekly() {
    final String uid = _userId ?? '__no_user__';
    final List<DateTime> days = _weekDates(_selectedDate);
    final List<String> keys = <String>[];
    for (int i = 0; i < days.length; i = i + 1) {
      keys.add(_dateKey(days[i]));
    }

    return FirebaseFirestore.instance
        .collection('Bookings')
        .where('userId', isEqualTo: uid)
        .where('bookingDate', whereIn: keys)   // 7 values (<=10), OK
        .snapshots();
  }

  // -------------- read booking fields safely --------------
  String _readApproval(Map<String, dynamic> m) {
    // try multiple keys; use ?.toString() + ?? '-' then normalize later
    String val = m['approval']?.toString() ?? '';
    if (val.isEmpty) { val = m['approvalStatus']?.toString() ?? ''; }
    if (val.isEmpty) { val = m['statusApproval']?.toString() ?? ''; }
    return val;
  }

  String _readFacilityId(Map<String, dynamic> m) {
    String id = m['facilityId']?.toString() ?? '';
    if (id.isEmpty) { id = m['facilityID']?.toString() ?? ''; }
    if (id.isEmpty) { id = m['facilityDocId']?.toString() ?? ''; }
    return id;
  }

  String _readStartStr(Map<String, dynamic> m) {
    String s = m['start']?.toString() ?? '';
    if (s.isEmpty) { s = m['startTime']?.toString() ?? ''; }
    return s;
  }

  String _readEndStr(Map<String, dynamic> m) {
    String s = m['end']?.toString() ?? '';
    if (s.isEmpty) { s = m['endTime']?.toString() ?? ''; }
    return s;
  }

  int _readSeatIndex(Map<String, dynamic> m) {
    // take value → toString only if not null → tryParse → if null then -1
    return int.tryParse(m['seatIndex']?.toString() ?? '') ?? -1;
  }

  // -------------- facility name fetch with simple cache --------------
  Future<String> _getFacilityName(String facilityId) async {
    // if no id, return '-'
    if (facilityId.isEmpty) { return '-'; }

    // check cache first
    if (_facNameCache.containsKey(facilityId)) {
      final String? cached = _facNameCache[facilityId];
      if (cached != null) { return cached; }
    }

    // read once from Facilities collection
    try {
      final DocumentSnapshot<Map<String, dynamic>> d = await FirebaseFirestore.instance
          .collection('Facilities')
          .doc(facilityId)
          .get();
      if (d.exists) {
        final Map<String, dynamic>? data = d.data();
        if (data != null) {
          String nm = data['name']?.toString() ?? '';
          if (nm.isEmpty) { nm = data['facilityName']?.toString() ?? ''; }
          if (nm.isEmpty) { nm = '-'; }
          _facNameCache[facilityId] = nm; // save to cache
          return nm;
        } else {
          return '-';
        }
      } else {
        return '-';
      }
    } catch (e) {
      return '-';
    }
  }

  // -------------- Accepted status (Upcoming/Ongoing/Ended) for accepted bookings --------------
  String _acceptedStatusFor(DateTime day, int startMin, int endMin) {
    final DateTime now = DateTime.now();
    if (DateUtils.isSameDay(day, now)) {
      final int nowMin = now.hour * 60 + now.minute;
      if (nowMin < startMin) {
        return 'Upcoming';
      } else {
        if (nowMin >= startMin && nowMin < endMin) {
          return 'Ongoing';
        } else {
          return 'Ended';
        }
      }
    } else {
      // future day → Upcoming; past day → Ended
      final DateTime today = DateTime(now.year, now.month, now.day);
      if (day.isAfter(today)) {
        return 'Upcoming';
      } else {
        return 'Ended';
      }
    }
  }

  // -------------- Booking card (for a specific day) --------------
  Widget _bookingCardForDay(Map<String, dynamic> m, DateTime day) {
    // read fields
    final String approval = _readApproval(m);
    final String facilityId = _readFacilityId(m);
    final int seatIndex = _readSeatIndex(m);

    final String startStr = _readStartStr(m);
    final String endStr   = _readEndStr(m);
    final int stMin = _parse24ToMinutes(startStr);
    final int enMin = _parse24ToMinutes(endStr);

    // badge text and color
    String badge = '';
    Color badgeColor = Colors.grey;

    if (approval.toLowerCase() == 'pending') {
      badge = 'Pending';
      badgeColor = Colors.amber;
    } else {
      if (approval.toLowerCase() == 'accepted') {
        final String st = _acceptedStatusFor(day, stMin, enMin);
        badge = st;
        if (st == 'Upcoming') {
          badgeColor = Colors.green;
        } else {
          if (st == 'Ongoing') {
            badgeColor = Colors.amber;
          } else {
            badgeColor = Colors.grey;
          }
        }
      } else {
        // rejected or unknown → no badge text (we already filtered rejected above in lists)
        badge = '';
      }
    }

    String badgeText = badge;
    if (badgeText.isEmpty) { badgeText = '-'; }

    // get facility name (cached) and build the card
    return FutureBuilder<String>(
      future: _getFacilityName(facilityId),     // async name lookup
      builder: (context, snap) {
        // if not done yet → show "..."; if done but null → '-'
        String nm;
        if (snap.connectionState == ConnectionState.done) {
          final String? v = snap.data;
          if (v != null) { nm = v; } else { nm = '-'; }
        } else {
          nm = '...';
        }
        return _buildBookingCardBody(nm, seatIndex, stMin, enMin, badgeText, badgeColor);
      },
    );
  }

  // builds the visible booking card (moved out to keep builder short)
  Widget _buildBookingCardBody(String nm, int seatIndex, int stMin, int enMin, String badgeText, Color badgeColor) {
    // slot label
    String slotText = 'Slot: -';
    if (seatIndex >= 0) {
      slotText = 'Slot: $seatIndex';
    }

    return Container(
      width: 1.0.sw,
      margin: EdgeInsets.symmetric(vertical: 6.h),
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.w),
        border: Border.all(color: const Color(0xFFE5E5E5), width: 1.w),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6.w,
            offset: Offset(0, 2.h),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // left: name + slot + time
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // facility name (wrap/ellipsis to avoid overflow on web zoom)
                Text(
                  nm,
                  style: TextStyle(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 4.h),
                Text(
                  slotText,
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: const Color(0xFF555555),
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  _formatHourLabel(stMin) + ' - ' + _formatHourLabel(enMin),
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: const Color(0xFF777777),
                  ),
                ),
              ],
            ),
          ),

          // right: badge
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
            decoration: BoxDecoration(
              color: badgeColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(999.w),
              border: Border.all(color: badgeColor, width: 1.w),
            ),
            child: Text(
              badgeText,
              style: TextStyle(
                fontSize: 12.sp,
                color: badgeColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -------------- DAILY: hour row + list --------------
  Widget _hourRow(int hourMin, List<Map<String, dynamic>> bookingsInHour, DateTime day) {
    return Container(
      width: 1.0.sw,
      padding: EdgeInsets.symmetric(vertical: 8.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // left time label
          SizedBox(
            width: 72.w,
            child: Text(
              _formatHourLabel(hourMin),
              style: TextStyle(
                fontSize: 12.sp,
                color: const Color(0xFF666666),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          SizedBox(width: 8.w),
          // right cards
          Expanded(
            child: Column(
              children: _buildBookingCardsForDay(bookingsInHour, day),
            ),
          ),
        ],
      ),
    );
  }

  // builds all cards in this hour; if none, shows a thin divider
  List<Widget> _buildBookingCardsForDay(List<Map<String, dynamic>> list, DateTime day) {
    final List<Widget> out = <Widget>[];
    for (int i = 0; i < list.length; i = i + 1) {
      out.add(_bookingCardForDay(list[i], day));
    }
    if (list.isEmpty) {
      out.add(Container(
        width: 1.0.sw,
        height: 1.h,
        color: const Color(0xFFEFEFEF),
        margin: EdgeInsets.only(top: 6.h),
      ));
    }
    return out;
  }

  // the whole Daily agenda body
  Widget _dailyAgendaBody(AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snap) {
    if (_loadingWorkHours) {
      return Center(
        child: SizedBox(
          width: 28.w,
          height: 28.w,
          child: const CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    // build hour marks from start to end by 60 minutes
    final List<int> hourMarks = <int>[];
    int h = _workStartMin;
    while (h <= _workEndMin) {
      hourMarks.add(h);
      h = h + 60;
    }

    // collect items (skip rejected)
    final List<Map<String, dynamic>> items = <Map<String, dynamic>>[];
    if (snap.hasData) {
      final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs = snap.data!.docs;
      for (int i = 0; i < docs.length; i = i + 1) {
        final Map<String, dynamic> m = docs[i].data();
        final String approval = _readApproval(m);
        if (approval.toLowerCase() == 'rejected') {
          // skip
        } else {
          items.add(m);
        }
      }
    }

    // sort by start time ascending (earliest first)
    items.sort((a, b) {
      final int sa = _parse24ToMinutes(_readStartStr(a));
      final int sb = _parse24ToMinutes(_readStartStr(b));
      if (sa < sb) { return -1; } else { if (sa > sb) { return 1; } else { return 0; } }
    });

    // make buckets: hour → list of bookings overlapping that hour
    final Map<int, List<Map<String, dynamic>>> buckets = <int, List<Map<String, dynamic>>>{};
    for (int i = 0; i < hourMarks.length; i = i + 1) {
      buckets[hourMarks[i]] = <Map<String, dynamic>>[];
    }

    for (int i = 0; i < items.length; i = i + 1) {
      final Map<String, dynamic> m = items[i];
      final int st = _parse24ToMinutes(_readStartStr(m));
      final int en = _parse24ToMinutes(_readEndStr(m));
      for (int j = 0; j < hourMarks.length; j = j + 1) {
        final int hm = hourMarks[j];
        final int hStart = hm;
        final int hEnd = hm + 60;
        if (st < hEnd && en > hStart) {
          // add to this bucket
          (buckets[hm] ??= <Map<String, dynamic>>[]).add(m);
        }
      }
    }

    // render by hour
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, _bottomSafePadding(context)),
      itemCount: hourMarks.length,
      itemBuilder: (context, index) {
        final int hm = hourMarks[index];
        final List<Map<String, dynamic>> list = buckets[hm] ?? <Map<String, dynamic>>[];
        return _hourRow(hm, list, _selectedDate);
      },
    );
  }

  // -------------- WEEKLY: build sections Sunday→Saturday --------------
  Widget _weeklyAgendaBody(AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snap) {
    final List<DateTime> days = _weekDates(_selectedDate);

    // Prepare day->list mapping
    final Map<String, List<Map<String, dynamic>>> byDay = <String, List<Map<String, dynamic>>>{};
    for (int i = 0; i < days.length; i = i + 1) {
      byDay[_dateKey(days[i])] = <Map<String, dynamic>>[];
    }

    // fill lists (skip rejected)
    if (snap.hasData) {
      final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs = snap.data!.docs;
      for (int i = 0; i < docs.length; i = i + 1) {
        final Map<String, dynamic> m = docs[i].data();
        final String approval = _readApproval(m);
        if (approval.toLowerCase() == 'rejected') {
          // skip
        } else {
          final String k = m['bookingDate']?.toString() ?? '';
          if (byDay.containsKey(k)) {
            (byDay[k] ??= <Map<String, dynamic>>[]).add(m);
          }
        }
      }
    }

    // sort each day's list by start time ascending
    for (int i = 0; i < days.length; i = i + 1) {
      final String k = _dateKey(days[i]);
      final List<Map<String, dynamic>>? lst = byDay[k];
      if (lst != null) {
        lst.sort((a, b) {
          final int sa = _parse24ToMinutes(_readStartStr(a));
          final int sb = _parse24ToMinutes(_readStartStr(b));
          if (sa < sb) { return -1; } else { if (sa > sb) { return 1; } else { return 0; } }
        });
      }
    }

    // render by day
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, _bottomSafePadding(context)),
      itemCount: days.length,
      itemBuilder: (context, index) {
        final DateTime d = days[index];
        final String k = _dateKey(d);
        List<Map<String, dynamic>> items = <Map<String, dynamic>>[];
        if (byDay.containsKey(k)) {
          final List<Map<String, dynamic>>? tmp = byDay[k];
          if (tmp != null) { items = tmp; } else { items = <Map<String, dynamic>>[]; }
        }
        return _weeklyDaySection(d, items);
      },
    );
  }

  // one weekly day section (Day name + date + cards)
  Widget _weeklyDaySection(DateTime day, List<Map<String, dynamic>> items) {
    final bool isSelectedDay = DateUtils.isSameDay(day, _selectedDate);

    Color dayColor = Colors.black;
    if (isSelectedDay == true) {
      dayColor = const Color(0xFF7B61FF); // purple if selected
    } else {
      dayColor = Colors.black;
    }

    return Container(
      width: 1.0.sw,
      padding: EdgeInsets.symmetric(vertical: 10.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Day name (maybe purple)
          Text(
            _dayName(day),
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.w700,
              color: dayColor,
            ),
          ),
          SizedBox(height: 2.h),
          // Date like "23 May"
          Text(
            _formatShortDate(day),
            style: TextStyle(
              fontSize: 13.sp,
              color: const Color(0xFF666666),
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 8.h),

          // divider
          Container(width: 1.0.sw, height: 1.h, color: const Color(0xFFEFEFEF)),

          // bookings for this day
          Column(
            children: _buildBookingCardsForDay(items, day),
          ),
        ],
      ),
    );
  }

  // -------------- UI: top date row with calendar picker --------------
  Widget _dateHeader() {
    // show "Wednesday · 23 May 2025", with "Wednesday" purple
    final String dayWord = _dayName(_selectedDate);
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 8.h),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6.w,
              children: <Widget>[
                Text(
                  dayWord,
                  style: TextStyle(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF7B61FF), // purple
                  ),
                ),
                Text(
                  '·',
                  style: TextStyle(fontSize: 18.sp, color: Colors.black),
                ),
                Text(
                  _formatDateNoDay(_selectedDate),
                  style: TextStyle(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
          ),
          InkWell(
            onTap: _pickDate, // open date picker
            child: Container(
              width: 36.w,
              height: 36.w,
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(8.w),
                border: Border.all(color: const Color(0xFFE5E5E5), width: 1.w),
              ),
              child: Icon(Icons.calendar_today, size: 18.w, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  // -------------- UI: daily / weekly toggle row --------------
  Widget _modeToggle() {
    final bool isDaily = _viewMode == 'daily';
    final bool isWeekly = _viewMode == 'weekly';

    Color dailyBg = Colors.white;
    if (isDaily == true) { dailyBg = const Color(0xFFEEE5FF); } else { dailyBg = Colors.white; }
    Color weeklyBg = Colors.white;
    if (isWeekly == true) { weeklyBg = const Color(0xFFEEE5FF); } else { weeklyBg = Colors.white; }

    Color dailyBorder = const Color(0xFFE5E5E5);
    if (isDaily == true) { dailyBorder = const Color(0xFF7B61FF); } else { dailyBorder = const Color(0xFFE5E5E5); }
    Color weeklyBorder = const Color(0xFFE5E5E5);
    if (isWeekly == true) { weeklyBorder = const Color(0xFF7B61FF); } else { weeklyBorder = const Color(0xFFE5E5E5); }

    Color dailyText = const Color(0xFF444444);
    if (isDaily == true) { dailyText = const Color(0xFF7B61FF); } else { dailyText = const Color(0xFF444444); }
    Color weeklyText = const Color(0xFF444444);
    if (isWeekly == true) { weeklyText = const Color(0xFF7B61FF); } else { weeklyText = const Color(0xFF444444); }

    Color dailyIcon = const Color(0xFF666666);
    if (isDaily == true) { dailyIcon = const Color(0xFF7B61FF); } else { dailyIcon = const Color(0xFF666666); }
    Color weeklyIcon = const Color(0xFF666666);
    if (isWeekly == true) { weeklyIcon = const Color(0xFF7B61FF); } else { weeklyIcon = const Color(0xFF666666); }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
      child: Row(
        children: <Widget>[
          Expanded(
            child: InkWell(
              onTap: () { setState(() { _viewMode = 'daily'; }); },
              child: Container(
                height: 40.h,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: dailyBg,
                  borderRadius: BorderRadius.circular(10.w),
                  border: Border.all(color: dailyBorder, width: 1.w),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(Icons.calendar_view_day, size: 18.w, color: dailyIcon),
                    SizedBox(width: 6.w),
                    Text('Daily', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600, color: dailyText)),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: InkWell(
              onTap: () { setState(() { _viewMode = 'weekly'; }); },
              child: Container(
                height: 40.h,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: weeklyBg,
                  borderRadius: BorderRadius.circular(10.w),
                  border: Border.all(color: weeklyBorder, width: 1.w),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(Icons.view_week, size: 18.w, color: weeklyIcon),
                    SizedBox(width: 6.w),
                    Text('Weekly', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600, color: weeklyText)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -------------- build --------------
  @override
  Widget build(BuildContext context) {
    // height for AppBar & bottom bar (scaled)
    final double barHeight = 56.h;

    // choose content by mode
    Widget content;
    if (_viewMode == 'daily') {
      content = StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _bookingsStreamDaily(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Failed to load', style: TextStyle(fontSize: 13.sp, color: Colors.red)));
          } else {
            if (snap.connectionState == ConnectionState.waiting) {
              return Center(child: SizedBox(width: 28.w, height: 28.w, child: const CircularProgressIndicator(strokeWidth: 2)));
            } else {
              return _dailyAgendaBody(snap);
            }
          }
        },
      );
    } else {
      content = StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _bookingsStreamWeekly(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Failed to load', style: TextStyle(fontSize: 13.sp, color: Colors.red)));
          } else {
            if (snap.connectionState == ConnectionState.waiting) {
              return Center(child: SizedBox(width: 28.w, height: 28.w, child: const CircularProgressIndicator(strokeWidth: 2)));
            } else {
              return _weeklyAgendaBody(snap);
            }
          }
        },
      );
    }

    // scaffold with curved AppBar and bottom bar
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(barHeight),
        child: AppBar(
          backgroundColor: const Color(0xFF9747FF),
          elevation: 0,
          centerTitle: true,
          automaticallyImplyLeading: false,
          title: Text(
            "Agenda",
            style: TextStyle(color: Colors.white, fontSize: 20.sp, fontWeight: FontWeight.w600),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(40.r),
              bottomRight: Radius.circular(40.r),
            ),
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            _dateHeader(),   // "Wednesday · 23 May 2025" (Wednesday in purple)
            _modeToggle(),   // Daily / Weekly
            Expanded(child: content),
          ],
        ),
      ),
      bottomNavigationBar: BottomMenuBar(
        height: 60.h,
        currentIndex: _currentIndex,
        onTabSelected: _onTabSelected,
      ),
    );
  }
}
