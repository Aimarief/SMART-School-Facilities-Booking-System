import 'package:cloud_firestore/cloud_firestore.dart';         // Firestore
import 'package:firebase_auth/firebase_auth.dart';             // current user
import 'package:flutter/material.dart';                        // UI
import 'package:flutter_screenutil/flutter_screenutil.dart';   // responsive sizes
import 'package:intl/intl.dart';                               // date/time formatting
import 'android_booking_details.dart';

// Bottom bar + other pages (unchanged)
import 'android_bottom_menu.dart';
import 'android_agenda.dart';
import 'android_list_of_facilities.dart';
import 'android_notifications.dart';
import 'android_account.dart';
import 'android_login.dart';

// ------------------------------
// Page: AndroidViewBooking
// ------------------------------
class AndroidViewBooking extends StatefulWidget {
  @override
  State<AndroidViewBooking> createState() => _AndroidViewBookingState();
}

class _AndroidViewBookingState extends State<AndroidViewBooking> {
  // keep bottom bar index (1 = Booking)
  int _currentIndex = 1;

  // optional date filter (null = show all days)
  DateTime? _filterDate;

  // cache today's date for header (no day-name)
  late DateTime _today;

  // time display format (kept false → "10.00 am")
  bool _use24HourFormat = false;

  // ensure housekeeping executes once per page life
  bool _didRunHousekeeping = false;

  // cache facility ids → names to reduce re-reads
  final Map<String, String> _facilityNameCache = {};

  // init: set today + schedule housekeeping after first frame
  @override
  void initState() {
    super.initState();
    _today = DateTime.now();

    // do the one-time status sweep after first layout
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runHousekeepingOnce();
    });
  }

  // -------------------- bottom tab handler (routes only) --------------------
  void _onTabSelected(int i) {
    if (i == 0) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidAgenda()));
    } else {
      if (i == 1) {
        setState(() { _currentIndex = 1; }); // stay on this page
      } else {
        if (i == 2) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidListOfFacilities()));
        } else {
          if (i == 3) {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidNotifications()));
          } else {
            if (i == 4) {
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidAccount()));
            }
          }
        }
      }
    }
  }

  // -------------------- open date picker (same UX as Agenda) --------------------
  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime first = DateTime(now.year - 5, 1, 1);
    final DateTime last  = DateTime(now.year + 5, 12, 31);

    // modal native date picker (returns a DateTime or null)
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _filterDate == null ? now : _filterDate!,
      firstDate: first,
      lastDate: last,
    );

    // store only Y/M/D (no time) to compare dates cleanly
    if (picked != null) {
      setState(() {
        _filterDate = DateTime(picked.year, picked.month, picked.day);
      });
    }
  }

  // -------------------- header date formatting (no weekday) --------------------
  String _formatLongDateNoDay(DateTime d) {
    // display as "23 May 2025"
    final DateFormat f = DateFormat('d MMMM yyyy');
    return f.format(d);
  }

  // pick header date (filter or today's date)
  DateTime _headerDate() {
    if (_filterDate != null) {
      return _filterDate!;
    } else {
      return _today;
    }
  }

  // -------------------- header row: date text + calendar button --------------------
  Widget _dateHeaderRow() {
    final DateTime d = _headerDate();
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 8.h),
      child: Row(
        children: <Widget>[
          // left: formatted date (bold)
          Expanded(
            child: Text(
              _formatLongDateNoDay(d),
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.w700,
                color: Colors.black,
              ),
            ),
          ),
          // right: calendar icon triggers picker
          InkWell(
            onTap: _pickDate,
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

  // -------------------- "Clear" link (only visible when filter is applied) --------------------
  Widget _clearCenterIfNeeded() {
    if (_filterDate != null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.only(top: 4.h),
          child: TextButton(
            onPressed: _clearDate,
            child: Text(
              "Clear",
              style: TextStyle(fontSize: 13.sp, color: const Color(0xFF9747FF), fontWeight: FontWeight.w600),
            ),
          ),
        ),
      );
    } else {
      return SizedBox(height: 0.h);
    }
  }

  // -------------------- remove date filter --------------------
  void _clearDate() {
    setState(() { _filterDate = null; });
  }

  // -------------------- common formatting helpers --------------------
  String _formatFullDate(DateTime d) {
    // "Fri, 23 May 2025"
    final DateFormat f = DateFormat('EEE, d MMM yyyy');
    return f.format(d);
  }

  // format start/end time as "h.mm am" or "HH.mm" then keep it unbroken
  String _formatTime(DateTime d) {
    String s = '';
    if (_use24HourFormat == true) {
      final DateFormat f24 = DateFormat('HH.mm');
      s = f24.format(d);
    } else {
      final DateFormat f12 = DateFormat('h.mm a');
      s = f12.format(d).toLowerCase();
    }
    // replace space with non-breaking space so "10.00 am" stays together
    s = s.replaceAll(' ', '\u00A0');
    return s;
  }

  // compare only Y/M/D equality
  bool _isSameDay(DateTime a, DateTime b) {
    if (a.year == b.year) {
      if (a.month == b.month) {
        if (a.day == b.day) {
          return true;
        } else {
          return false;
        }
      } else {
        return false;
      }
    } else {
      return false;
    }
  }

  // -------------------- safe readers: strings + timestamps --------------------
  String _readFirstString(Map<String, dynamic> m, List<String> keys) {
    // scan keys in order and return first non-null value as string
    int i = 0;                              // counter i walks through keys list
    while (i < keys.length) {
      final String k = keys[i];
      if (m.containsKey(k)) {
        final dynamic v = m[k];
        if (v != null) {
          return v.toString();
        }
      }
      i = i + 1;                            // increment i at end of each iteration
    }
    return '';
  }

  DateTime? _readFirstDateTime(Map<String, dynamic> m, List<String> keys) {
    // scan keys and return first Timestamp/DateTime value (as DateTime)
    int i = 0;                              // counter i for keys traversal
    while (i < keys.length) {
      final String k = keys[i];
      if (m.containsKey(k)) {
        final dynamic v = m[k];
        if (v is Timestamp) {
          return v.toDate();
        } else {
          if (v is DateTime) {
            return v;
          } else {
            // ignore non-date types
          }
        }
      }
      i = i + 1;                            // step i to check next key
    }
    return null;
  }

  // read a date-only value from first match (Timestamp/DateTime/String 'yyyy-MM-dd')
  DateTime? _readFirstDateOnly(Map<String, dynamic> m, List<String> keys) {
    int i = 0;                              // counter i to loop keys
    while (i < keys.length) {
      final String k = keys[i];
      if (m.containsKey(k)) {
        final dynamic v = m[k];

        if (v is Timestamp) {
          final DateTime d = v.toDate();
          return DateTime(d.year, d.month, d.day);
        }

        if (v is DateTime) {
          return DateTime(v.year, v.month, v.day);
        }

        if (v is String) {
          DateTime? parsed;
          try { parsed = DateTime.tryParse(v); } catch (_) { parsed = null; }
          if (parsed == null) {
            try {
              final DateFormat fmt = DateFormat('yyyy-MM-dd');
              parsed = fmt.parseStrict(v);
            } catch (_) { parsed = null; }
          }
          if (parsed != null) {
            return DateTime(parsed.year, parsed.month, parsed.day);
          }
        }
      }
      i = i + 1;                            // increment i after checking current key
    }
    return null;
  }

  // -------------------- parse flexible "HH:mm" into [hour, minute] --------------------
  List<int>? _parseHourMinute(String s) {
    if (s.isEmpty == true) {
      return null;
    } else {
      String t = s.trim();
      t = t.replaceAll(' ', '');
      t = t.replaceAll('.', ':');
      t = t.replaceAll('-', ':');

      // case A: time with colon present → split and parse
      if (t.contains(':') == true) {
        final List<String> parts = t.split(':');
        int h = 0;
        int m = 0;

        if (parts.isNotEmpty == true) {
          try { h = int.parse(parts[0]); } catch (_) { h = -1; }
        }
        if (parts.length > 1) {
          try { m = int.parse(parts[1]); } catch (_) { m = -1; }
        } else {
          m = 0;
        }

        // return only valid 24h times
        if (h >= 0 && h <= 23 && m >= 0 && m <= 59) {
          return [h, m];
        } else {
          return null;
        }
      } else {
        // case B: pure digits like "1330" or "930" or "13"
        String d = '';
        int i = 0;                          // counter i scans characters
        while (i < t.length) {
          final String ch = t.substring(i, i + 1);
          if (ch.codeUnitAt(0) >= 48 && ch.codeUnitAt(0) <= 57) {
            d = d + ch;
          }
          i = i + 1;                        // move i to next char
        }

        int h = -1;
        int m = -1;

        if (d.length == 4) {
          // "1330" → 13:30
          try { h = int.parse(d.substring(0, 2)); } catch (_) { h = -1; }
          try { m = int.parse(d.substring(2, 4)); } catch (_) { m = -1; }
        } else {
          if (d.length == 3) {
            // "930"  → 9:30
            try { h = int.parse(d.substring(0, 1)); } catch (_) { h = -1; }
            try { m = int.parse(d.substring(1, 3)); } catch (_) { m = -1; }
          } else {
            if (d.length == 2) {
              // "13"   → 13:00
              try { h = int.parse(d); } catch (_) { h = -1; }
              m = 0;
            } else {
              // unsupported length → invalid
              h = -1;
              m = -1;
            }
          }
        }

        // return only valid bounds
        if (h >= 0 && h <= 23 && m >= 0 && m <= 59) {
          return [h, m];
        } else {
          return null;
        }
      }
    }
  }

  // -------------------- compose DateTime from booking date + time fields --------------------
  DateTime? _composeDateTime(Map<String, dynamic> m, List<String> timeKeys) {
    // prefer real Timestamp/DateTime if present
    final DateTime? ts = _readFirstDateTime(m, timeKeys);
    if (ts != null) {
      return ts;
    }

    // otherwise parse flexible time string and combine with bookingDate
    final String tStr = _readFirstString(m, timeKeys);
    if (tStr.isNotEmpty == true) {
      final List<int>? hm = _parseHourMinute(tStr);
      if (hm != null) {
        DateTime? base = _readFirstDateOnly(m, ['bookingDate', 'booking_date', 'date']);
        if (base == null) {
          base = DateTime.now();
        }
        return DateTime(base.year, base.month, base.day, hm[0], hm[1]);
      }
    }

    return null;
  }

  // -------------------- normalize approval values to "approved/pending/rejected" --------------------
  String _approvalText(dynamic approvalValue) {
    if (approvalValue is bool) {
      if (approvalValue == true) { return 'approved'; } else { return 'pending'; }
    } else {
      if (approvalValue == null) { return ''; } else { return approvalValue.toString().toLowerCase(); }
    }
  }

  // -------------------- facility name lookup with local cache --------------------
  Future<String> _getFacilityName(String facilityId) async {
    // return cached value if known
    if (_facilityNameCache.containsKey(facilityId) == true) {
      return _facilityNameCache[facilityId]!;
    }

    try {
      // read Facilities/{id} and pick "name" (fallbacks allowed)
      final DocumentSnapshot<Map<String, dynamic>> d =
      await FirebaseFirestore.instance.collection('Facilities').doc(facilityId).get();

      if (d.exists == true) {
        final Map<String, dynamic>? data = d.data();
        if (data != null) {
          final String name = _readFirstString(data, ['name', 'facilityName', 'title']);
          if (name.isNotEmpty == true) {
            _facilityNameCache[facilityId] = name;
            return name;
          } else {
            _facilityNameCache[facilityId] = 'Facility';
            return 'Facility';
          }
        } else {
          _facilityNameCache[facilityId] = 'Facility';
          return 'Facility';
        }
      } else {
        _facilityNameCache[facilityId] = 'Facility';
        return 'Facility';
      }
    } catch (_) {
      _facilityNameCache[facilityId] = 'Facility';
      return 'Facility';
    }
  }

  // -------------------- small chip UI helper --------------------
  Widget _buildChip(String text, Color fill, Color border) {
    // pill chip with border and bold text
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
      margin: EdgeInsets.only(right: 8.w, top: 6.h),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(40.r),
        border: Border.all(color: border, width: 1.w),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: Colors.black87),
      ),
    );
  }

  // -------------------- status-to-color pair --------------------
  List<Color> _chipColors(String labelLower) {
    // choose consistent color coding by status/approval string
    if (labelLower == 'approved' || labelLower == 'accept' || labelLower == 'accepted' || labelLower == 'upcoming') {
      return [Colors.green.shade200, Colors.green];
    } else {
      if (labelLower == 'rejected') {
        return [Colors.red.shade200, Colors.red];
      } else {
        if (labelLower == 'pending' || labelLower == 'ongoing') {
          return [Colors.amber.shade200, Colors.amber];
        } else {
          if (labelLower == 'ended' || labelLower == 'complete' || labelLower == 'completed') {
            return [Colors.grey.shade300, Colors.grey];
          } else {
            return [Colors.grey.shade200, Colors.grey];
          }
        }
      }
    }
  }

  // -------------------- single booking row (tappable) --------------------
  Widget _buildBookingRow(Map<String, dynamic> m) {
    // extract facility id from known keys
    final String facilityId = _readFirstString(m, ['facilityId', 'facilityID', 'facilityDocId']);

    // compute start/end DateTime using robust parser/composer
    final DateTime? start = _composeDateTime(m, ['start', 'startTime', 'start_at', 'start_time']);
    final DateTime? end   = _composeDateTime(m,   ['end',   'endTime',   'end_at',   'end_time']);

    // normalize approval + status text
    final String approval = _approvalText(m['approval']).trim();
    final String status   = _readFirstString(m, ['status', 'state']).toLowerCase().trim();

    // show seat/slot index as text or "-" if missing
    final String seatRaw = _readFirstString(m, ['seatIndex', 'slotIndex', 'seat', 'slot']);
    String seatText = '';
    if (seatRaw.isNotEmpty == true) {
      seatText = seatRaw;
    } else {
      seatText = '-';
    }

    // format start/end into final strings for left time rail
    String startStr = '--.--';
    if (start != null) {
      startStr = _formatTime(start);
    }
    String endStr = '--.--';
    if (end != null) {
      endStr = _formatTime(end);
    }

    // assemble status/approval chips (pending/rejected suppresses status chip)
    final List<Widget> chips = [];
    if (approval.isNotEmpty == true) {
      final List<Color> c = _chipColors(approval);
      chips.add(_buildChip(_capitalize(approval), c[0], c[1]));
    }
    if (approval != 'pending' && approval != 'rejected') {
      if (status.isNotEmpty == true) {
        final List<Color> s = _chipColors(status);
        chips.add(_buildChip(_capitalize(status), s[0], s[1]));
      }
    }

    // lookup facility name (cached) then build row
    return FutureBuilder<String>(
      future: _getFacilityName(facilityId),
      builder: (context, snap) {
        String facilityName = 'Facility';
        if (snap.connectionState == ConnectionState.waiting) {
          facilityName = 'Loading...';
        } else {
          if (snap.hasError == true) {
            facilityName = 'Facility';
          } else {
            if (snap.data != null) {
              facilityName = snap.data!;
            } else {
              facilityName = 'Facility';
            }
          }
        }

        return InkWell(
          onTap: () {
            // read booking id for details page (kept same)
            String bookingId = '';
            if (m.containsKey('__id')) {
              final dynamic v = m['__id'];
              if (v != null) {
                bookingId = v.toString();
              }
            }
            String facId = facilityId;

            // navigate into details view
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AndroidBookingDetails(
                  bookingId: bookingId,
                  facilityId: facId,
                ),
              ),
            );
          },

          // lavender card with left time rail + right info
          child: Container(
            width: 1.0.sw,
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
            margin: EdgeInsets.only(bottom: 12.h),
            decoration: BoxDecoration(
              color: const Color(0xFFE9D7FF),
              borderRadius: BorderRadius.circular(14.r),
              boxShadow: [
                BoxShadow(
                  color: const Color(0x22000000),
                  blurRadius: 8.r,
                  offset: Offset(0, 3.h),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // left time rail: start | end stacked
                SizedBox(
                  width: 78.w,
                  height: 68.h,
                  child: Stack(
                    children: [
                      Align(
                        alignment: Alignment.topLeft,
                        child: Text(
                          startStr,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.clip,
                          style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w700, color: Colors.black87),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text('       |', style: TextStyle(fontSize: 16.sp, color: Colors.black45)),
                      ),
                      Align(
                        alignment: Alignment.bottomLeft,
                        child: Text(
                          endStr,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.clip,
                          style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w700, color: Colors.black54),
                        ),
                      ),
                    ],
                  ),
                ),

                // separator bar
                Container(
                  width: 2.w,
                  height: 50.h,
                  margin: EdgeInsets.symmetric(horizontal: 12.w),
                  color: const Color(0xFF7E57C2),
                ),

                // right info: facility name, seat, chips
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // facility name (bold)
                      Text(
                        facilityName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 18.sp,
                          fontWeight: FontWeight.w800,
                          color: Colors.black87,
                        ),
                      ),

                      SizedBox(height: 6.h),

                      // seat/slot row with icon
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.event_seat, size: 18.w, color: Colors.black54),
                          Text(
                            "Slot : ",
                            style: TextStyle(fontSize: 13.sp, color: Colors.black87, fontWeight: FontWeight.w600),
                          ),
                          SizedBox(width: 6.w),
                          Text(
                            seatText,
                            style: TextStyle(fontSize: 13.sp, color: Colors.black87, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),

                      SizedBox(height: 8.h),

                      // status chips
                      Wrap(children: chips),
                    ],
                  ),
                ),

                // chevron
                Icon(Icons.chevron_right, size: 26.w, color: Colors.black54),
              ],
            ),
          ),
        );
      },
    );
  }

  // -------------------- capitalize first letter helper --------------------
  String _capitalize(String s) {
    if (s.isEmpty == true) { return s; } else {
      final String first = s.substring(0, 1).toUpperCase();
      final String rest  = s.substring(1);
      return first + rest;
    }
  }

  // -------------------- same-day helper (Y/M/D) --------------------
  bool _isSameYMD(DateTime a, DateTime b) {
    if (a.year == b.year) {
      if (a.month == b.month) {
        if (a.day == b.day) {
          return true;
        } else {
          return false;
        }
      } else {
        return false;
      }
    } else {
      return false;
    }
  }

  // -------------------- booking date reader from common field names --------------------
  DateTime? _readBookingDate(Map<String, dynamic> m) {
    return _readFirstDateOnly(m, ['bookingDate', 'booking_date', 'date']);
  }

  // -------------------- read lowercased trimmed string --------------------
  String _readLowerStr(Map<String, dynamic> m, List<String> keys) {
    final String s = _readFirstString(m, keys);
    if (s.isEmpty == true) {
      return '';
    } else {
      return s.toLowerCase().trim();
    }
  }

  // -------------------- read time-of-day from multiple possible shapes --------------------
  TimeOfDay? _readTime(Map<String, dynamic> m, List<String> keys) {
    int i = 0;                              // counter i loops keys list
    while (i < keys.length) {
      final String k = keys[i];
      if (m.containsKey(k)) {
        final dynamic v = m[k];

        if (v is Timestamp) {
          final DateTime dt = v.toDate();
          return TimeOfDay(hour: dt.hour, minute: dt.minute);
        } else {
          if (v is DateTime) {
            return TimeOfDay(hour: v.hour, minute: v.minute);
          } else {
            if (v is String) {
              final List<int>? hm = _parseHourMinute(v);
              if (hm != null) {
                return TimeOfDay(hour: hm[0], minute: hm[1]);
              }
            }
          }
        }
      }
      i = i + 1;                            // increment i to check next key
    }
    return null;
  }

  // ==================== ONE-TIME HOUSEKEEPING (status maintenance) ====================
  Future<void> _runHousekeepingOnce() async {
    // guard: run only once while page lives
    if (_didRunHousekeeping == true) {
      return;
    } else {
      _didRunHousekeeping = true;
    }

    try {
      // compute "today 00:00" to compare date-only
      final DateTime now = DateTime.now();
      final DateTime todayStart = DateTime(now.year, now.month, now.day);

      // acceptable "accepted" spellings for approval field
      final List<String> acceptedValues = <String>[
        'accepted',
        'Accepted',
        'ACCEPTED',
        'approved',
        'Approved',
        'APPROVED',
      ];

      // 1) Sweep ACCEPTED bookings → update status "ongoing"/"ended" (do not alter "pending"/"rejected")
      final QuerySnapshot<Map<String, dynamic>> acceptedSnap = await FirebaseFirestore.instance
          .collection('Bookings')
          .where('approval', whereIn: acceptedValues)
          .get();

      // loop counter i: iterates over accepted documents
      int i = 0;
      while (i < acceptedSnap.docs.length) {
        final doc = acceptedSnap.docs[i];
        final Map<String, dynamic>? m = doc.data();
        if (m != null) {
          // read booking date (date-only), else skip status logic
          final DateTime? bookDate = _readBookingDate(m);
          if (bookDate != null) {
            // align booking date to 00:00 for comparison
            final DateTime bookDayStart = DateTime(bookDate.year, bookDate.month, bookDate.day);
            String newStatus = '';

            // CASE A: day already before today → ended
            if (bookDayStart.isBefore(todayStart) == true) {
              newStatus = 'ended';
            } else {
              // CASE B: same day → compute by current clock vs start/end
              if (_isSameYMD(bookDate, now) == true) {
                // read time-of-day values for the booking
                final TimeOfDay? tStart = _readTime(m, ['start', 'startTime', 'timeStart']);
                final TimeOfDay? tEnd   = _readTime(m, ['end',   'endTime',   'timeEnd']);

                // only if both present do we determine ongoing vs ended
                if (tStart != null && tEnd != null) {
                  final DateTime startDT = DateTime(bookDate.year, bookDate.month, bookDate.day,
                      tStart.hour, tStart.minute, 0);
                  final DateTime endDT = DateTime(bookDate.year, bookDate.month, bookDate.day,
                      tEnd.hour, tEnd.minute, 0);

                  // only when end > start is the window valid
                  if (endDT.isAfter(startDT) == true) {
                    if (now.isBefore(startDT) == true) {
                      // upcoming today → leave status as-is
                    } else {
                      if (now.isBefore(endDT) == true) {
                        newStatus = 'ongoing'; // within window
                      } else {
                        newStatus = 'ended';   // past window
                      }
                    }
                  }
                }
              }
            }

            // update status only when changed (saving writes)
            if (newStatus.isNotEmpty == true) {
              final String current = _readLowerStr(m, ['status']);
              if (current != newStatus) {
                await doc.reference.update({'status': newStatus});
              }
            }
          }
        }
        i = i + 1; // increment loop counter i after processing one doc
      }

      // 2) Sweep PENDING bookings → auto "rejected" if start time/day already passed
      final QuerySnapshot<Map<String, dynamic>> pendingSnap = await FirebaseFirestore.instance
          .collection('Bookings')
          .where('approval', whereIn: ['pending', 'Pending', 'PENDING'])
          .get();

      // loop counter j: iterates over pending documents
      int j = 0;
      while (j < pendingSnap.docs.length) {
        final doc = pendingSnap.docs[j];
        final Map<String, dynamic>? m = doc.data();
        if (m != null) {
          // read booking date (date-only) to compare day
          final DateTime? bookDate = _readBookingDate(m);
          if (bookDate != null) {
            // align to 00:00 for day comparison
            final DateTime bookDayStart = DateTime(bookDate.year, bookDate.month, bookDate.day);
            bool shouldReject = false;

            // CASE A: booking day is already before today → reject
            if (bookDayStart.isBefore(todayStart) == true) {
              shouldReject = true;
            } else {
              // CASE B: booking is today → compare with start time
              if (_isSameYMD(bookDate, now) == true) {
                final TimeOfDay? tStart = _readTime(m, ['start', 'startTime', 'timeStart']);
                if (tStart != null) {
                  final DateTime startDT = DateTime(bookDate.year, bookDate.month, bookDate.day,
                      tStart.hour, tStart.minute, 0);
                  if (now.isBefore(startDT) == false) {
                    shouldReject = true; // past or equal to start time → reject pending
                  }
                }
              }
            }

            // only write when status actually needs flipping to rejected
            if (shouldReject == true) {
              final String currAppr = _readLowerStr(m, ['approval', 'approve', 'approvalStatus']);
              if (currAppr != 'rejected') {
                await doc.reference.update({
                  'approval': 'rejected',
                  'approvalStatus': 'rejected',
                });
              }
            }
          }
        }
        j = j + 1; // increment loop counter j after processing one doc
      }
    } catch (e) {
      // swallow housekeeping errors and just log locally
      debugPrint('housekeeping error: $e');
    }
  }

  // -------------------- main UI build --------------------
  @override
  Widget build(BuildContext context) {
    // bottom bar height as a fraction of screen height (ScreenUtil)
    final double barHeight = 0.07.sh;

    // current user (null → ask to sign in)
    final User? user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: Colors.white,

      // purple app bar with rounded bottom corners and sign-out action
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(60.h),
        child: AppBar(
          backgroundColor: const Color(0xFF9747FF),
          elevation: 0,
          centerTitle: true,
          automaticallyImplyLeading: false,
          title: Text("Booking List", style: TextStyle(color: Colors.white, fontSize: 20.sp, fontWeight: FontWeight.w600)),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout, color: Colors.white),
              onPressed: () async {
                // sign out and clear stack to login page
                await FirebaseAuth.instance.signOut();
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => AndroidLoginPage()),
                      (route) { return false; },
                );
              },
            ),
          ],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(40.r),
              bottomRight: Radius.circular(40.r),
            ),
          ),
        ),
      ),

      // content area with header + list
      body: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // top header row with date + calendar button
            _dateHeaderRow(),

            // optional "Clear" under header when a filter is active
            _clearCenterIfNeeded(),

            SizedBox(height: 8.h),
            Divider(height: 1.h, color: const Color(0xFFEAEAEA)),
            SizedBox(height: 8.h),

            // Case: user not logged in → show prompt
            if (user == null)
              Expanded(
                child: Center(
                  child: Text(
                    "Please sign in to see your bookings.",
                    style: TextStyle(fontSize: 14.sp, color: Colors.black54),
                  ),
                ),
              )
            else
            // Case: user logged in → live stream bookings belonging to user
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('Bookings')
                      .where('userId', isEqualTo: user.uid)
                      .where('deleted', isEqualTo: false)
                      .snapshots(),
                  builder: (context, snap) {
                    // loading spinner while waiting for first snapshot
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    // error state (keep minimal text)
                    if (snap.hasError == true) {
                      return Center(
                        child: Text(
                          "Failed to load bookings",
                          style: TextStyle(fontSize: 14.sp, color: Colors.redAccent),
                        ),
                      );
                    }

                    // no data or empty list → show message
                    if (snap.hasData != true || snap.data == null || snap.data!.docs.isEmpty == true) {
                      return Center(
                        child: Text(
                          "No bookings found.",
                          style: TextStyle(fontSize: 14.sp, color: Colors.black54),
                        ),
                      );
                    }

                    // -------- COPY DOCS INTO MUTABLE LIST --------
                    // We'll copy to local 'items' so we can add computed fields (e.g., '__id')
                    final List<Map<String, dynamic>> items = [];
                    int i = 0;                                      // counter i walks all returned docs
                    while (i < snap.data!.docs.length) {
                      final doc = snap.data!.docs[i];
                      final Map<String, dynamic> m = {};
                      final Map<String, dynamic> data = doc.data();

                      // copy every k/v pair into 'm' (shallow copy)
                      data.forEach((k, v) { m[k] = v; });

                      // store the Firestore doc id to use in navigation
                      m['__id'] = doc.id;

                      // push into items
                      items.add(m);

                      // ++i to move to next document in stream page
                      i = i + 1;
                    }

                    // -------- FILTER BY DATE (if user picked a day) --------
                    // We'll check 'bookingDate' (fallback to 'startTime' date) and keep same-day matches only.
                    List<Map<String, dynamic>> filtered = [];
                    if (_filterDate == null) {
                      // no filter → keep all items
                      filtered = items;
                    } else {
                      int j = 0;                                    // counter j scans 'items' to filter
                      while (j < items.length) {
                        final Map<String, dynamic> m = items[j];

                        // read date-only bookingDate, with flexible fallbacks
                        DateTime? bdate = _readFirstDateOnly(m, ['bookingDate', 'booking_date', 'date']);

                        // fallback: derive date from start time if bookingDate missing
                        if (bdate == null) {
                          final DateTime? st = _readFirstDateTime(m, ['startTime','start','start_at','start_time']);
                          if (st != null) {
                            bdate = DateTime(st.year, st.month, st.day);
                          }
                        }

                        // keep record only when its date equals the filter day
                        if (bdate != null) {
                          if (_isSameDay(bdate, _filterDate!) == true) {
                            filtered.add(m);
                          }
                        }

                        // ++j to advance the filtering pass
                        j = j + 1;
                      }
                    }

                    // empty after filtering → show empty message
                    if (filtered.isEmpty == true) {
                      return Center(
                        child: Text(
                          "No bookings for this date.",
                          style: TextStyle(fontSize: 14.sp, color: Colors.black54),
                        ),
                      );
                    }

                    // -------- SORT BY START TIME ASC --------
                    // Use composed DateTime for a robust comparison
                    filtered.sort((a, b) {
                      final DateTime? sa = _composeDateTime(a, ['start','startTime','start_at','start_time']);
                      final DateTime? sb = _composeDateTime(b, ['start','startTime','start_at','start_time']);

                      // keep nulls at the bottom
                      if (sa == null && sb == null) { return 0; }
                      if (sa == null) { return 1; }
                      if (sb == null) { return -1; }

                      // ascending chronological order
                      return sa.compareTo(sb);
                    });

                    // -------- GROUP BY BOOKING DATE --------
                    // We'll build a map keyed by "yyyy-MM-dd" with lists of bookings as values.
                    final Map<String, List<Map<String, dynamic>>> byDate = {};
                    final DateFormat keyFmt = DateFormat('yyyy-MM-dd');

                    int k = 0;                                      // counter k steps through 'filtered'
                    while (k < filtered.length) {
                      final Map<String, dynamic> m = filtered[k];

                      // get the bookingDate for grouping, fallback from start time if needed
                      DateTime? bdate = _readFirstDateOnly(m, ['bookingDate', 'booking_date', 'date']);
                      if (bdate == null) {
                        final DateTime? st = _readFirstDateTime(m, ['startTime','start','start_at','start_time']);
                        if (st != null) {
                          bdate = DateTime(st.year, st.month, st.day);
                        }
                      }

                      // only group when we have a date
                      if (bdate != null) {
                        // group key like "2025-05-23"
                        final String key = keyFmt.format(bdate);

                        // init group if first time we see this key
                        if (byDate.containsKey(key) == false) {
                          byDate[key] = <Map<String, dynamic>>[];
                        }

                        // append item to that date bucket
                        byDate[key]!.add(m);
                      }

                      // ++k to process next lined-up item
                      k = k + 1;
                    }

                    // -------- ORDER GROUPS: upcoming on top, last 7 days below --------
                    final List<String> allKeys = byDate.keys.toList();

                    // build today baseline and a week-ago baseline
                    final DateTime now = DateTime.now();
                    final DateTime todayOnly = DateTime(now.year, now.month, now.day);
                    final DateTime weekAgo = todayOnly.subtract(const Duration(days: 7));

                    // prepare two lists for ordering sections
                    final List<String> upcomingKeys = <String>[];
                    final List<String> past7Keys = <String>[];

                    int z = 0;                                      // counter z traverses all date keys
                    while (z < allKeys.length) {
                      final String kd = allKeys[z];
                      final DateTime d = DateTime.parse(kd);
                      final DateTime dOnly = DateTime(d.year, d.month, d.day);

                      // fill upcoming (today & future) OR past7 (last 7 days) buckets
                      if (dOnly.isBefore(todayOnly) == true) {
                        if (dOnly.isAfter(weekAgo) == true || _isSameDay(dOnly, weekAgo) == true) {
                          past7Keys.add(kd);
                        }
                      } else {
                        upcomingKeys.add(kd);
                      }

                      // ++z moves to next date key
                      z = z + 1;
                    }

                    // sort upcoming ascending (nearest future first)
                    upcomingKeys.sort((a, b) {
                      final DateTime da = DateTime.parse(a);
                      final DateTime db = DateTime.parse(b);
                      return da.compareTo(db);
                    });

                    // sort past7 descending (most recent past first)
                    past7Keys.sort((a, b) {
                      final DateTime da = DateTime.parse(a);
                      final DateTime db = DateTime.parse(b);
                      return db.compareTo(da);
                    });

                    // final ordered key list for list builder
                    final List<String> keys = <String>[];
                    keys.addAll(upcomingKeys);
                    keys.addAll(past7Keys);

                    // -------- BUILD THE LIST VIEW --------
                    // Build date header + its rows for each key in order.
                    return ListView.builder(
                      padding: EdgeInsets.only(top: 6.h, bottom: 14.h),
                      itemCount: keys.length,
                      itemBuilder: (context, idx) {
                        // get group key and parse back to DateTime for header text
                        final String kdate = keys[idx];
                        final DateTime parsed = DateTime.parse(kdate);
                        final String headerText = _formatFullDate(parsed);

                        // fetch group items from map (safe fallback to empty)
                        final List<Map<String, dynamic>> group = byDate[kdate] ?? <Map<String, dynamic>>[];

                        // section container with header + list of booking rows
                        return Container(
                          width: 1.0.sw,
                          margin: EdgeInsets.only(bottom: 16.h),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // date header label (bold)
                              Padding(
                                padding: EdgeInsets.only(left: 4.w, bottom: 8.h),
                                child: Text(
                                  headerText,
                                  style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w700, color: Colors.black87),
                                ),
                              ),

                              // render each booking row for this date
                              Column(
                                children: group.map((m) => _buildBookingRow(m)).toList(),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),

      // bottom nav bar (kept)
      bottomNavigationBar: BottomMenuBar(
        height: barHeight,
        currentIndex: _currentIndex,
        onTabSelected: _onTabSelected,
      ),
    );
  }
}
