// android_view_booking.dart
//
// Bookings grouped by bookingDate; reads start/end as 24h strings (e.g. "13:30","1330","13.30")
// and shows "h.mm am/pm" like your mock. Adds slot icon + slot number (seatIndex) under
// facility name. Uses only if/else, no ?: or ??, and .w .h .sp .sw .sh everywhere.

import 'package:cloud_firestore/cloud_firestore.dart';         // Firestore
import 'package:firebase_auth/firebase_auth.dart';             // current user
import 'package:flutter/material.dart';                        // UI
import 'package:flutter_screenutil/flutter_screenutil.dart';   // responsive sizes
import 'package:intl/intl.dart';                               // date/time formatting
import 'android_booking_details.dart';

// Bottom bar + other pages (unchanged)
import 'android_bottom_menu.dart';
import 'android_calendar.dart';
import 'android_list_of_facilities.dart';
import 'android_notifications.dart';
import 'android_account.dart';
import 'android_login.dart';

class AndroidViewBooking extends StatefulWidget {
  @override
  State<AndroidViewBooking> createState() => _AndroidViewBookingState();
}

class _AndroidViewBookingState extends State<AndroidViewBooking> {
  // -------------------- basic UI state --------------------
  int _currentIndex = 1;             // bottom bar: this page index
  DateTime? _filterDate;             // user-picked date (null = show all)
  late DateTime _today;              // today's date for header
  bool _use24HourFormat = false;     // false so we display "10.00 am" like the mock
  bool _didRunHousekeeping = false;
  // cache facility names to reduce reads
  final Map<String, String> _facilityNameCache = {};

  @override
  void initState() {
    super.initState();
    _today = DateTime.now();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runHousekeepingOnce();
    });
  }


  // -------------------- bottom tab handler --------------------
  void _onTabSelected(int i) {
    // simple navigation for bottom bar
    if (i == 0) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidCalendar()));
    } else if (i == 1) {
      setState(() { _currentIndex = 1; });
    } else if (i == 2) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidListOfFacilities()));
    } else if (i == 3) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidNotifications()));
    } else if (i == 4) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidAccount()));
    }
  }

  // -------------------- open date picker --------------------
  Future<void> _pickDate() async {
    // open a calendar so user can pick a date to filter
    final DateTime now = DateTime.now();
    final DateTime first = DateTime(now.year - 5, 1, 1);
    final DateTime last  = DateTime(now.year + 5, 12, 31);

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _filterDate == null ? now : _filterDate!,
      firstDate: first,
      lastDate: last,
    );

    // if a date is chosen, store it (only date part)
    if (picked != null) {
      setState(() {
        _filterDate = DateTime(picked.year, picked.month, picked.day);
      });
    }
  }

  // -------------------- clear date filter --------------------
  void _clearDate() {
    // remove filter so all bookings show
    setState(() { _filterDate = null; });
  }

  // -------------------- formatting helpers --------------------
  String _formatFullDate(DateTime d) {
    // Example: Thu, 28 Aug 2025
    final DateFormat f = DateFormat('EEE, d MMM yyyy');
    return f.format(d);
  }

  String _formatTime(DateTime d) {
    String s = '';
    if (_use24HourFormat == true) {
      final DateFormat f24 = DateFormat('HH.mm');
      s = f24.format(d);
    } else {
      final DateFormat f12 = DateFormat('h.mm a');
      s = f12.format(d).toLowerCase();
    }
    // change normal spaces to non-breaking spaces so "10.00 am" stays on one line
    s = s.replaceAll(' ', '\u00A0');
    return s;
  }


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

  // -------------------- safe readers --------------------
  String _readFirstString(Map<String, dynamic> m, List<String> keys) {
    // tries multiple keys and returns first found as string
    int i = 0;
    while (i < keys.length) {
      final String k = keys[i];
      if (m.containsKey(k)) {
        final dynamic v = m[k];
        if (v != null) {
          return v.toString();
        }
      }
      i = i + 1;
    }
    return '';
  }

  DateTime? _readFirstDateTime(Map<String, dynamic> m, List<String> keys) {
    // reads DateTime from Timestamp/DateTime fields (legacy support)
    int i = 0;
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
            // ignore other types
          }
        }
      }
      i = i + 1;
    }
    return null;
  }

  // Read *date only* for bookingDate (Timestamp/DateTime/String "yyyy-MM-dd").
  DateTime? _readFirstDateOnly(Map<String, dynamic> m, List<String> keys) {
    int i = 0;
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
      i = i + 1;
    }
    return null;
  }

  // -------- parse 24h time string like "13:30", "1330", "13.30", "9:05" to hour/min --------
  List<int>? _parseHourMinute(String s) {
    // return [hour, minute] or null if cannot parse
    if (s.isEmpty == true) {
      return null;
    } else {
      String t = s.trim();

      // unify separators and remove spaces
      t = t.replaceAll(' ', '');
      t = t.replaceAll('.', ':');
      t = t.replaceAll('-', ':');

      // case 1: has colon "HH:MM" or "H:MM"
      if (t.contains(':') == true) {
        final List<String> parts = t.split(':');
        int h = 0;
        int m = 0;

        // hour
        if (parts.isNotEmpty == true) {
          try { h = int.parse(parts[0]); } catch (_) { h = -1; }
        }

        // minute (if missing, 0)
        if (parts.length > 1) {
          try { m = int.parse(parts[1]); } catch (_) { m = -1; }
        } else {
          m = 0;
        }

        if (h >= 0 && h <= 23 && m >= 0 && m <= 59) {
          return [h, m];
        } else {
          return null;
        }
      } else {
        // case 2: digits only like "1330" or "930" or "09"
        // remove any non-digits (safety)
        String d = '';
        int i = 0;
        while (i < t.length) {
          final String ch = t.substring(i, i + 1);
          if (ch.codeUnitAt(0) >= 48 && ch.codeUnitAt(0) <= 57) {
            d = d + ch;
          }
          i = i + 1;
        }

        int h = -1;
        int m = -1;

        if (d.length == 4) {
          // HHMM
          try { h = int.parse(d.substring(0, 2)); } catch (_) { h = -1; }
          try { m = int.parse(d.substring(2, 4)); } catch (_) { m = -1; }
        } else {
          if (d.length == 3) {
            // HMM
            try { h = int.parse(d.substring(0, 1)); } catch (_) { h = -1; }
            try { m = int.parse(d.substring(1, 3)); } catch (_) { m = -1; }
          } else {
            if (d.length == 2) {
              // HH (assume minutes = 00)
              try { h = int.parse(d); } catch (_) { h = -1; }
              m = 0;
            } else {
              // not supported
              h = -1;
              m = -1;
            }
          }
        }

        if (h >= 0 && h <= 23 && m >= 0 && m <= 59) {
          return [h, m];
        } else {
          return null;
        }
      }
    }
  }

  // build DateTime from bookingDate + time string OR fallback to existing Timestamp
  DateTime? _composeDateTime(Map<String, dynamic> m, List<String> timeKeys) {
    // 1) if Timestamp/DateTime exists in these keys, use it
    final DateTime? ts = _readFirstDateTime(m, timeKeys);
    if (ts != null) {
      return ts;
    }

    // 2) else try to read 24h string and combine with bookingDate
    final String tStr = _readFirstString(m, timeKeys);
    if (tStr.isEmpty == false) {
      final List<int>? hm = _parseHourMinute(tStr);
      if (hm != null) {
        // read booking date
        DateTime? base = _readFirstDateOnly(m, ['bookingDate', 'booking_date', 'date']);
        if (base == null) {
          // fallback: use today (only for display)
          base = DateTime.now();
        }
        return DateTime(base.year, base.month, base.day, hm[0], hm[1]);
      }
    }

    // 3) nothing found
    return null;
  }

  // normalize approval string
  String _approvalText(dynamic approvalValue) {
    if (approvalValue is bool) {
      if (approvalValue == true) { return 'approved'; } else { return 'pending'; }
    } else {
      if (approvalValue == null) { return ''; } else { return approvalValue.toString().toLowerCase(); }
    }
  }

  // -------------------- facility name lookup --------------------
  Future<String> _getFacilityName(String facilityId) async {
    // return cached name if present
    if (_facilityNameCache.containsKey(facilityId) == true) {
      return _facilityNameCache[facilityId]!;
    }

    // else fetch from Facilities
    try {
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

  // -------------------- chip builder --------------------
  Widget _buildChip(String text, Color fill, Color border) {
    // simple rounded chip with padding and border
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

  // choose chip colors by label (lowercased)
  List<Color> _chipColors(String labelLower) {
    // returns [fill, border]
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
            // default neutral
            return [Colors.grey.shade200, Colors.grey];
          }
        }
      }
    }
  }

  // -------------------- one booking row --------------------
  Widget _buildBookingRow(Map<String, dynamic> m) {
    // facility id
    final String facilityId = _readFirstString(m, ['facilityId', 'facilityID', 'facilityDocId']);

    // start/end times (string 24h or timestamp)
    final DateTime? start = _composeDateTime(m, ['start', 'startTime', 'start_at', 'start_time']);
    final DateTime? end   = _composeDateTime(m,   ['end',   'endTime',   'end_at',   'end_time']);

    // approval + status
    final String approval = _approvalText(m['approval']).trim();
    final String status   = _readFirstString(m, ['status', 'state']).toLowerCase().trim();

    // slot number (seatIndex)
    final String seatRaw = _readFirstString(m, ['seatIndex', 'slotIndex', 'seat', 'slot']);
    String seatText = '';
    if (seatRaw.isNotEmpty == true) {
      seatText = seatRaw;
    } else {
      seatText = '-';
    }

    // time strings (no "start/end" words)
    String startStr = '--.--';
    if (start != null) {
      startStr = _formatTime(start);
    }
    String endStr = '--.--';
    if (end != null) {
      endStr = _formatTime(end);
    }

    // decide which chips to show
    final List<Widget> chips = [];

    // approval chip (always if not empty)
    if (approval.isNotEmpty == true) {
      final List<Color> c = _chipColors(approval);
      chips.add(_buildChip(_capitalize(approval), c[0], c[1]));
    }

    // show status chip ONLY if approval is not pending/rejected (your rule)
    if (approval != 'pending' && approval != 'rejected') {
      if (status.isNotEmpty == true) {
        final List<Color> s = _chipColors(status);
        chips.add(_buildChip(_capitalize(status), s[0], s[1]));
      }
    }

    // UI row
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
            if (snap.data != null) { facilityName = snap.data!; } else { facilityName = 'Facility'; }
          }
        }

        return InkWell(
          onTap: () {
            // read bookingId that you stored earlier as m['__id']
            String bookingId = '';
            if (m.containsKey('__id')) {
              final dynamic v = m['__id'];
              if (v != null) {
                bookingId = v.toString();
              }
            }

            // use the facilityId we already read at the top of this function
            String facId = facilityId;

            // navigate to booking details page
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

          child: Container(
            // card
            width: 1.0.sw,
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
            margin: EdgeInsets.only(bottom: 12.h),
            decoration: BoxDecoration(
              color: const Color(0xFFE9D7FF), // soft lavender like mock
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
                // left times (top = start time, bottom = end time)
                SizedBox(
                  width: 78.w,   // a bit wider so "10.00 am" fits on A32/web
                  height: 68.h,  // give it height so center works reliably
                  child: Stack(
                    children: [
                      // top: start time (single line)
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

                      // middle: the "|" exactly centered vertically, left aligned
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text('       |', style: TextStyle(fontSize: 16.sp, color: Colors.black45)),
                      ),

                      // bottom: end time (single line)
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

                // thin vertical divider
                Container(
                  width: 2.w,
                  height: 50.h,
                  margin: EdgeInsets.symmetric(horizontal: 12.w),
                  color: const Color(0xFF7E57C2), // purple line
                ),

                // middle: facility + slot + chips
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // facility name
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

                      // slot row (icon + number)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.event_seat, size: 18.w, color: Colors.black54),
                          Text("Slot : ",
                              style: TextStyle(fontSize: 13.sp, color: Colors.black87, fontWeight: FontWeight.w600),),
                          SizedBox(width: 6.w),
                          Text(
                            seatText,
                            style: TextStyle(fontSize: 13.sp, color: Colors.black87, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),

                      SizedBox(height: 8.h),

                      // chips in a Wrap so they wrap lines if narrow / zoomed
                      Wrap(
                        children: chips,
                      ),
                    ],
                  ),
                ),

                // right chevron
                Icon(Icons.chevron_right, size: 26.w, color: Colors.black54),
              ],
            ),
          ),
        );
      },
    );
  }

  // capitalize helper
  String _capitalize(String s) {
    if (s.isEmpty == true) { return s; } else {
      final String first = s.substring(0, 1).toUpperCase();
      final String rest  = s.substring(1);
      return first + rest;
    }
  }

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

// booking date from common fields (date-only)
  DateTime? _readBookingDate(Map<String, dynamic> m) {
    return _readFirstDateOnly(m, ['bookingDate', 'booking_date', 'date']);
  }

// read lowercase trimmed string for first present key
  String _readLowerStr(Map<String, dynamic> m, List<String> keys) {
    final String s = _readFirstString(m, keys);
    if (s.isEmpty == true) {
      return '';
    } else {
      return s.toLowerCase().trim();
    }
  }

// read time from keys -> TimeOfDay (supports Timestamp/DateTime or strings like "13:30","1330","13.30")
  TimeOfDay? _readTime(Map<String, dynamic> m, List<String> keys) {
    int i = 0;
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
      i = i + 1;
    }
    return null;
  }

  // ====== ONE-TIME HOUSEKEEPING ======
  Future<void> _runHousekeepingOnce() async {
    if (_didRunHousekeeping == true) {
      return;
    } else {
      _didRunHousekeeping = true;
    }

    try {
      final DateTime now = DateTime.now();
      final DateTime todayStart = DateTime(now.year, now.month, now.day);

      // accepted -> set ongoing/ended by time
      final List<String> acceptedValues = <String>[
        'accepted',
        'Accepted',
        'ACCEPTED',
        'approved',
        'Approved',
        'APPROVED',
      ];

      final QuerySnapshot<Map<String, dynamic>> acceptedSnap = await FirebaseFirestore.instance
          .collection('Bookings')
          .where('approval', whereIn: acceptedValues)
          .get();

      int i = 0;
      while (i < acceptedSnap.docs.length) {
        final doc = acceptedSnap.docs[i];
        final Map<String, dynamic>? m = doc.data();
        if (m != null) {
          final DateTime? bookDate = _readBookingDate(m);
          if (bookDate != null) {
            final DateTime bookDayStart = DateTime(bookDate.year, bookDate.month, bookDate.day);
            String newStatus = '';

            if (bookDayStart.isBefore(todayStart) == true) {
              newStatus = 'ended';
            } else {
              if (_isSameYMD(bookDate, now) == true) {
                final TimeOfDay? tStart = _readTime(m, ['start', 'startTime', 'timeStart']);
                final TimeOfDay? tEnd   = _readTime(m, ['end',   'endTime',   'timeEnd']);

                if (tStart != null && tEnd != null) {
                  final DateTime startDT = DateTime(bookDate.year, bookDate.month, bookDate.day,
                      tStart.hour, tStart.minute, 0);
                  final DateTime endDT = DateTime(bookDate.year, bookDate.month, bookDate.day,
                      tEnd.hour, tEnd.minute, 0);

                  if (endDT.isAfter(startDT) == true) {
                    if (now.isBefore(startDT) == true) {
                      // keep as-is
                    } else {
                      if (now.isBefore(endDT) == true) {
                        newStatus = 'ongoing';
                      } else {
                        newStatus = 'ended';
                      }
                    }
                  }
                }
              }
            }

            if (newStatus.isNotEmpty == true) {
              final String current = _readLowerStr(m, ['status']);
              if (current != newStatus) {
                await doc.reference.update({'status': newStatus});
              }
            }
          }
        }
        i = i + 1;
      }

      // pending -> auto-reject if past start time/day
      final QuerySnapshot<Map<String, dynamic>> pendingSnap = await FirebaseFirestore.instance
          .collection('Bookings')
          .where('approval', whereIn: ['pending', 'Pending', 'PENDING'])
          .get();

      int j = 0;
      while (j < pendingSnap.docs.length) {
        final doc = pendingSnap.docs[j];
        final Map<String, dynamic>? m = doc.data();
        if (m != null) {
          final DateTime? bookDate = _readBookingDate(m);
          if (bookDate != null) {
            final DateTime bookDayStart = DateTime(bookDate.year, bookDate.month, bookDate.day);
            bool shouldReject = false;

            if (bookDayStart.isBefore(todayStart) == true) {
              shouldReject = true;
            } else {
              if (_isSameYMD(bookDate, now) == true) {
                final TimeOfDay? tStart = _readTime(m, ['start', 'startTime', 'timeStart']);
                if (tStart != null) {
                  final DateTime startDT = DateTime(bookDate.year, bookDate.month, bookDate.day,
                      tStart.hour, tStart.minute, 0);
                  if (now.isBefore(startDT) == false) {
                    shouldReject = true;
                  }
                }
              }
            }

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
        j = j + 1;
      }
    } catch (e) {
      debugPrint('housekeeping error: $e');
    }
  }



  // -------------------- main build --------------------
  @override
  Widget build(BuildContext context) {
    final double barHeight = 0.07.sh;
    final User? user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: Colors.white,

      // AppBar
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

      // Body
      body: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // today
            Center(
              child: Text(
                _formatFullDate(_today),
                style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700, color: Colors.black87),
              ),
            ),
            SizedBox(height: 8.h),

// calendar icon (pick date) + Clear below when applicable
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 48.w,
                    height: 48.w,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(24.r),
                        onTap: _pickDate,
                        child: Icon(Icons.calendar_month, size: 28.w, color: const Color(0xFF9747FF)),
                      ),
                    ),
                  ),
                  if (_filterDate != null)
                    Padding(
                      padding: EdgeInsets.only(top: 4.h),
                      child: TextButton(
                        onPressed: _clearDate,
                        child: Text(
                          "Clear",
                          style: TextStyle(fontSize: 13.sp, color: const Color(0xFF9747FF), fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            SizedBox(height: 8.h),
            Divider(height: 1.h, color: const Color(0xFFEAEAEA)),
            SizedBox(height: 8.h),
            // if not logged in
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
            // bookings stream for this user
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('Bookings')
                      .where('userId', isEqualTo: user.uid) // change to 'userID' if your field uses that
                      .snapshots(),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (snap.hasError == true) {
                      return Center(
                        child: Text(
                          "Failed to load bookings",
                          style: TextStyle(fontSize: 14.sp, color: Colors.redAccent),
                        ),
                      );
                    }

                    if (snap.hasData != true || snap.data == null || snap.data!.docs.isEmpty == true) {
                      return Center(
                        child: Text(
                          "No bookings found.",
                          style: TextStyle(fontSize: 14.sp, color: Colors.black54),
                        ),
                      );
                    }

                    // copy docs into a list of maps
                    final List<Map<String, dynamic>> items = [];
                    int i = 0;
                    while (i < snap.data!.docs.length) {
                      final doc = snap.data!.docs[i];
                      final Map<String, dynamic> m = {};
                      final Map<String, dynamic> data = doc.data();
                      data.forEach((k, v) { m[k] = v; });
                      m['__id'] = doc.id;
                      items.add(m);
                      i = i + 1;
                    }

                    // filter by picked date using bookingDate (with fallbacks)
                    List<Map<String, dynamic>> filtered = [];
                    if (_filterDate == null) {
                      filtered = items;
                    } else {
                      int j = 0;
                      while (j < items.length) {
                        final Map<String, dynamic> m = items[j];
                        DateTime? bdate = _readFirstDateOnly(m, ['bookingDate', 'booking_date', 'date']);
                        if (bdate == null) {
                          final DateTime? st = _readFirstDateTime(m, ['startTime','start','start_at','start_time']);
                          if (st != null) {
                            bdate = DateTime(st.year, st.month, st.day);
                          }
                        }
                        if (bdate != null) {
                          if (_isSameDay(bdate, _filterDate!) == true) {
                            filtered.add(m);
                          }
                        }
                        j = j + 1;
                      }
                    }

                    if (filtered.isEmpty == true) {
                      return Center(
                        child: Text(
                          "No bookings for this date.",
                          style: TextStyle(fontSize: 14.sp, color: Colors.black54),
                        ),
                      );
                    }

                    // sort by start time ascending
                    filtered.sort((a, b) {
                      final DateTime? sa = _composeDateTime(a, ['start','startTime','start_at','start_time']);
                      final DateTime? sb = _composeDateTime(b, ['start','startTime','start_at','start_time']);
                      if (sa == null && sb == null) { return 0; }
                      if (sa == null) { return 1; }
                      if (sb == null) { return -1; }
                      return sa.compareTo(sb);
                    });

                    // group by bookingDate
                    final Map<String, List<Map<String, dynamic>>> byDate = {};
                    final DateFormat keyFmt = DateFormat('yyyy-MM-dd');
                    int k = 0;
                    while (k < filtered.length) {
                      final Map<String, dynamic> m = filtered[k];
                      DateTime? bdate = _readFirstDateOnly(m, ['bookingDate', 'booking_date', 'date']);
                      if (bdate == null) {
                        final DateTime? st = _readFirstDateTime(m, ['startTime','start','start_at','start_time']);
                        if (st != null) {
                          bdate = DateTime(st.year, st.month, st.day);
                        }
                      }
                      if (bdate != null) {
                        final String key = keyFmt.format(bdate);
                        if (byDate.containsKey(key) == false) {
                          byDate[key] = <Map<String, dynamic>>[];
                        }
                        byDate[key]!.add(m);
                      }
                      k = k + 1;
                    }

                    // order groups by date
                    // --- ORDER GROUPS: upcoming (today/future) on top, past 7 days at bottom ---
                    final List<String> allKeys = byDate.keys.toList();
                    final DateTime now = DateTime.now();
                    final DateTime todayOnly = DateTime(now.year, now.month, now.day);
                    final DateTime weekAgo = todayOnly.subtract(const Duration(days: 7));

                    final List<String> upcomingKeys = <String>[];
                    final List<String> past7Keys = <String>[];

// split into upcoming (>= today) and past (< today within last 7 days)
                    int z = 0;
                    while (z < allKeys.length) {
                      final String kd = allKeys[z];
                      final DateTime d = DateTime.parse(kd);
                      final DateTime dOnly = DateTime(d.year, d.month, d.day);

                      if (dOnly.isBefore(todayOnly) == true) {
                        // past
                        if (dOnly.isAfter(weekAgo) == true || _isSameDay(dOnly, weekAgo) == true) {
                          past7Keys.add(kd);
                        }
                      } else {
                        // today or future
                        upcomingKeys.add(kd);
                      }
                      z = z + 1;
                    }

// upcoming sorted ascending (nearest first)
                    upcomingKeys.sort((a, b) {
                      final DateTime da = DateTime.parse(a);
                      final DateTime db = DateTime.parse(b);
                      return da.compareTo(db);
                    });

// past 7 days sorted descending (nearest first at top of bottom section)
                    past7Keys.sort((a, b) {
                      final DateTime da = DateTime.parse(a);
                      final DateTime db = DateTime.parse(b);
                      return db.compareTo(da);
                    });

// final order: upcoming first, then past 7 days
                    final List<String> keys = <String>[];
                    keys.addAll(upcomingKeys);
                    keys.addAll(past7Keys);


                    // build list with date headers + rows
                    return ListView.builder(
                      padding: EdgeInsets.only(top: 6.h, bottom: 14.h),
                      itemCount: keys.length,
                      itemBuilder: (context, idx) {
                        final String kdate = keys[idx];
                        final DateTime parsed = DateTime.parse(kdate);
                        final String headerText = _formatFullDate(parsed);
                        final List<Map<String, dynamic>> group = byDate[kdate] ?? <Map<String, dynamic>>[];

                        return Container(
                          width: 1.0.sw,
                          margin: EdgeInsets.only(bottom: 16.h),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // date header
                              Padding(
                                padding: EdgeInsets.only(left: 4.w, bottom: 8.h),
                                child: Text(
                                  headerText,
                                  style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w700, color: Colors.black87),
                                ),
                              ),
                              // bookings for this date
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

      // Bottom nav
      bottomNavigationBar: BottomMenuBar(
        height: barHeight,
        currentIndex: _currentIndex,
        onTabSelected: _onTabSelected,
      ),
    );
  }
}
