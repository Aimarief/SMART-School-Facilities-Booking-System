// android_edit_booking.dart
//
// Edit Booking (design-matched date/time UI)
// - Time slots source: Facilities/{id}/customTimeSlots [{start:"HH:MM", end:"HH:MM"}, ...]
// - Per-date slot availability: Facilities/{id}/Days/{YYYY-MM-DD}/Slots/{HHmm}.booked
//   full if booked >= capacity (prefer Slots.capacity else Facilities.availableSlots)
// - Seat picker: Facilities/{id}/Days/{YMD}/Slots/{HHmm}/Seats/{index}.taken
// - Confirm: uses BookingService.moveAcceptedBookingByIdTx for accepted+upcoming;
//            else patches booking. bookingDate stored as "YYYY-MM-DD".
//
// Kept your simple style: no ?: no ?? ; .w .h .sp .sw .sh everywhere.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';

import 'package:smart_school_facilities_booking_system/booking_service.dart';

import 'android_bottom_menu.dart';
import 'android_calendar.dart';
import 'android_view_booking.dart';
import 'android_list_of_facilities.dart';
import 'android_notifications.dart';
import 'android_account.dart';

class AndroidEditBooking extends StatefulWidget {
  final String bookingId;

  const AndroidEditBooking({
    Key? key,
    required this.bookingId,
  }) : super(key: key);

  @override
  State<AndroidEditBooking> createState() => _AndroidEditBookingState();
}

class _AndroidEditBookingState extends State<AndroidEditBooking> {
  // ---------------- bottom menu ----------------
  int _currentIndex = 1;
  void _onTabSelected(int i) {
    if (i == 0) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidCalendar()));
    } else {
      if (i == 1) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidViewBooking()));
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

  // ---------------- state (booking + facility) ----------------
  bool _initApplied = false;

  // from booking
  String _facilityId = '';
  DateTime? _origDate;
  String _origStartStr = '';
  String _origEndStr = '';
  String _origSeatText = '-';

  // facility data
  String _facilityName = '';
  int _capacity = 0; // Facilities.availableSlots (default seats count)
  // time choices now from customTimeSlots
  final List<String> _timeChoices = <String>[]; // "HH:MM" to display
  final Map<String, String> _startToEnd = <String, String>{}; // "HH:MM" -> "HH:MM" end

  // selection
  final List<DateTime> _dateChoices = <DateTime>[];
  DateTime? _selectedDate;
  String _selectedTime = '';
  int _selectedSeat = -1;

  // per selected date -> slot meta
  final Map<String, int> _slotBooked = <String, int>{};         // key "HHmm" -> booked
  final Map<String, int> _slotCapOverride = <String, int>{};    // key "HHmm" -> capacity

  // guard to avoid refetch loops
  String _loadedKey = ''; // "facilityId|YYYY-MM-DD"

  // off rules (optional)
  Set<int> _offWeekdays = <int>{};     // 1..7
  Set<String> _offDatesYmd = <String>{};

  // ---------------- helpers: format ----------------
  String _formatFullDate(DateTime d) {
    final DateFormat f = DateFormat('EEE, d MMM yyyy');
    return f.format(d);
  }

  String _toAmPmDot(String hhmm) {
    final List<String> parts = hhmm.split(':');
    int h = 0;
    int m = 0;
    if (parts.isNotEmpty == true) {
      final int? p = int.tryParse(parts[0]);
      if (p != null) { h = p; }
    }
    if (parts.length > 1) {
      final int? p = int.tryParse(parts[1]);
      if (p != null) { m = p; }
    }
    String suf = 'am';
    if (h >= 12) { suf = 'pm'; }
    int h12 = h % 12;
    if (h12 == 0) { h12 = 12; }
    final String mm = m.toString().padLeft(2, '0');
    return '$h12.$mm $suf';
  }

  String _monthYearText(DateTime d) {
    const List<String> months = <String>[
      'January','February','March','April','May','June','July','August','September','October','November','December'
    ];
    return months[d.month - 1] + ' ' + d.year.toString();
  }

  String _weekdayLetter(DateTime d) {
    if (d.weekday == DateTime.sunday) { return 'S'; } else {
      if (d.weekday == DateTime.monday) { return 'M'; } else {
        if (d.weekday == DateTime.tuesday) { return 'T'; } else {
          if (d.weekday == DateTime.wednesday) { return 'W'; } else {
            if (d.weekday == DateTime.thursday) { return 'T'; } else {
              if (d.weekday == DateTime.friday) { return 'F'; } else { return 'S'; }
            }
          }
        }
      }
    }
  }

  String _ymd(DateTime d) {
    final String mo = d.month.toString().padLeft(2, '0');
    final String da = d.day.toString().padLeft(2, '0');
    return d.year.toString() + '-' + mo + '-' + da;
  }

  String _slotKey4FromHHmm(String s) {
    String t = s.replaceAll(':', '');
    if (t.length < 4) { t = t.padLeft(4, '0'); }
    return t;
  }

  // ---------------- system info (optional) ----------------
  void _applyWeekdayBooleans(Map<String, dynamic> m) {
    void add(String k, int wd) {
      if (m.containsKey(k)) {
        final dynamic v = m[k];
        bool isFalse = false;
        if (v is bool) {
          if (v == false) { isFalse = true; }
        } else {
          if (v is String) {
            final String s = v.toLowerCase().trim();
            if (s == 'false' || s == '0' || s == 'no') { isFalse = true; }
          } else {
            if (v is num) {
              if (v == 0) { isFalse = true; }
            }
          }
        }
        if (isFalse == true) { _offWeekdays.add(wd); }
      }
    }
    add('Monday', 1);
    add('Tuesday', 2);
    add('Wednesday', 3);
    add('Thursday', 4);
    add('Friday', 5);
    add('Saturday', 6);
    add('Sunday', 7);
  }

  void _collectOffDatesFromMap(Map<String, dynamic> m) {
    List<dynamic>? arr;
    if (m.containsKey('offDays')) {
      final dynamic v = m['offDays'];
      if (v is List) { arr = v; }
    }
    if (arr == null) {
      if (m.containsKey('dates')) {
        final dynamic v = m['dates'];
        if (v is List) { arr = v; }
      }
    }
    if (arr == null) {
      if (m.containsKey('list')) {
        final dynamic v = m['list'];
        if (v is List) { arr = v; }
      }
    }
    if (arr != null) {
      int i = 0;
      while (i < arr.length) {
        final String s = arr[i].toString().trim();
        if (s.isNotEmpty == true) { _offDatesYmd.add(s); }
        i = i + 1;
      }
    } else {
      if (m.containsKey('date')) {
        final String s = m['date'].toString().trim();
        if (s.isNotEmpty == true) { _offDatesYmd.add(s); }
      }
    }
  }

  String _normalizeYmdString(String s) {
    // Accept "YYYY-MM-DD" or "YYYY/MM/DD" and normalize to "YYYY-MM-DD"
    final String t = s.trim().replaceAll('/', '-');
    try {
      final DateTime? d = DateTime.tryParse(t);
      if (d != null) {
        final String mo = d.month.toString().padLeft(2, '0');
        final String da = d.day.toString().padLeft(2, '0');
        return '${d.year}-$mo-$da';
      }
    } catch (_) {}
    return t; // fallback
  }

  void _applyWeekdayBooleansFromMap(Map<String, dynamic> m) {
    void add(String k, int wd) {
      if (m.containsKey(k)) {
        final dynamic v = m[k];
        bool isFalse = false;
        if (v is bool) {
          isFalse = (v == false);
        } else if (v is String) {
          final String s = v.toLowerCase().trim();
          if (s == 'false' || s == '0' || s == 'no') { isFalse = true; }
        } else if (v is num) {
          if (v == 0) { isFalse = true; }
        }
        if (isFalse == true) { _offWeekdays.add(wd); }
      }
    }
    add('Monday', 1);
    add('Tuesday', 2);
    add('Wednesday', 3);
    add('Thursday', 4);
    add('Friday', 5);
    add('Saturday', 6);
    add('Sunday', 7);
  }

  void _collectOffDaysFromMap(Map<String, dynamic> m) {
    if (m.containsKey('offDays')) {
      final dynamic v = m['offDays'];
      if (v is List) {
        int i = 0;
        while (i < v.length) {
          final String raw = v[i].toString();
          final String norm = _normalizeYmdString(raw);
          if (norm.isNotEmpty == true) { _offDatesYmd.add(norm); }
          i = i + 1;
        }
      }
    }
  }

  Future<void> _loadWorkRules() async {
    _offWeekdays = <int>{};
    _offDatesYmd = <String>{};

    // ---- read weekday booleans from SystemInformation/Setting ----
    try {
      final DocumentSnapshot<Map<String, dynamic>> ds =
      await FirebaseFirestore.instance.collection('SystemInformation').doc('Setting').get();

      if (ds.exists) {
        final Map<String, dynamic>? m = ds.data();
        if (m != null) {
          // support both top-level and nested "Setting" map
          _applyWeekdayBooleansFromMap(m);
          if (m.containsKey('Setting')) {
            final dynamic nested = m['Setting'];
            if (nested is Map<String, dynamic>) {
              _applyWeekdayBooleansFromMap(nested);
            }
          }
        }
      }
    } catch (_) {}

    // ---- read holiday dates from SystemInformation/OffDays (field: offDays[]) ----
    try {
      final DocumentSnapshot<Map<String, dynamic>> off =
      await FirebaseFirestore.instance.collection('SystemInformation').doc('OffDays').get();

      if (off.exists) {
        final Map<String, dynamic>? m = off.data();
        if (m != null) {
          if (m.containsKey('offDays')) {
            final dynamic arr = m['offDays'];
            if (arr is List) {
              int i = 0;
              while (i < arr.length) {
                final String raw = arr[i].toString().trim();
                final String norm = _normalizeYmdString(raw); // keeps YYYY-MM-DD
                if (norm.isNotEmpty == true) { _offDatesYmd.add(norm); }
                i = i + 1;
              }
            }
          }
        }
      }
    } catch (_) {}
  }






  bool _isPickableDay(DateTime d) {
    final int wd = d.weekday;              // Monday = 1 ... Sunday = 7
    final String ymd = _ymd(d);
    bool ok = true;

    // Block weekdays that are false in SystemInformation/Setting
    if (_offWeekdays.contains(wd) == true) { ok = false; }

    // (Optional) specific off-date strings "YYYY-MM-DD" if you use them later
    if (ok == true && _offDatesYmd.contains(ymd) == true) { ok = false; }

    return ok;
  }


  // ---------------- facility helpers ----------------
  void _applyFacilityData(Map<String, dynamic> fac) {
    if (fac.containsKey('name')) {
      if (fac['name'] != null) { _facilityName = fac['name'].toString(); }
    }

    // base capacity from facility
    if (fac.containsKey('availableSlots')) {
      final dynamic v = fac['availableSlots'];
      if (v is int) { _capacity = v; } else {
        if (v is double) { _capacity = v.toInt(); } else {
          try { _capacity = int.parse(v.toString()); } catch (_) { _capacity = 0; }
        }
      }
    } else {
      if (fac.containsKey('capacity')) {
        final dynamic v = fac['capacity'];
        if (v is int) { _capacity = v; } else {
          if (v is double) { _capacity = v.toInt(); } else {
            try { _capacity = int.parse(v.toString()); } catch (_) { _capacity = 0; }
          }
        }
      }
    }
    if (_capacity <= 0) { _capacity = 1; }

    // build time choices from customTimeSlots
    _timeChoices.clear();
    _startToEnd.clear();

    if (fac.containsKey('customTimeSlots')) {
      final dynamic arr = fac['customTimeSlots'];
      if (arr is List) {
        int i = 0;
        while (i < arr.length) {
          final dynamic it = arr[i];

          String start = '';
          String end = '';

          if (it is Map) {
            if (it.containsKey('start')) { if (it['start'] != null) { start = it['start'].toString().trim(); } }
            if (it.containsKey('end'))   { if (it['end'] != null)   { end   = it['end'].toString().trim(); } }
          } else {
            if (it is String) {
              final String s = it.trim();
              if (s.contains('-') == true) {
                final List<String> p = s.split('-');
                if (p.isNotEmpty == true) { start = p[0].trim(); }
                if (p.length > 1) { end = p[1].trim(); }
              } else {
                start = s;
              }
            }
          }

          if (start.isNotEmpty == true) {
            final String normStart = _normalizeHHmm(start);
            String normEnd = end;
            if (end.isNotEmpty == true) { normEnd = _normalizeHHmm(end); }

            if (_startToEnd.containsKey(normStart) == false) {
              _timeChoices.add(normStart);
              if (normEnd.isNotEmpty == true) {
                _startToEnd[normStart] = normEnd;
              }
            }
          }
          i = i + 1;
        }

        _timeChoices.sort((a, b) {
          final int ma = _minutesOf(a);
          final int mb = _minutesOf(b);
          if (ma < mb) { return -1; } else { if (ma > mb) { return 1; } else { return 0; } }
        });
      }
    }
  }

  String _normalizeHHmm(String s) {
    String t = s.trim();
    t = t.replaceAll(' ', '');
    t = t.replaceAll('.', ':');
    t = t.replaceAll('-', ':');
    if (t.contains(':') == false) {
      String d = '';
      int i = 0;
      while (i < t.length) {
        final String ch = t.substring(i, i + 1);
        final int code = ch.codeUnitAt(0);
        if (code >= 48 && code <= 57) { d = d + ch; }
        i = i + 1;
      }
      if (d.length == 3) { d = '0' + d; }
      if (d.length >= 4) {
        final String hh = d.substring(0, 2);
        final String mm = d.substring(2, 4);
        return hh + ':' + mm;
      } else {
        return t;
      }
    } else {
      final List<String> p = t.split(':');
      String hh = '00';
      String mm = '00';
      if (p.isNotEmpty == true) { hh = p[0].padLeft(2, '0'); }
      if (p.length > 1) { mm = p[1].padLeft(2, '0'); }
      return hh + ':' + mm;
    }
  }

  int _minutesOf(String hhmm) {
    final List<String> p = hhmm.split(':');
    int h = 0;
    int m = 0;
    if (p.isNotEmpty == true) {
      final int? a = int.tryParse(p[0]);
      if (a != null) { h = a; }
    }
    if (p.length > 1) {
      final int? b = int.tryParse(p[1]);
      if (b != null) { m = b; }
    }
    return h * 60 + m;
  }

  // ---------------- slot meta for selected date ----------------
  Future<void> _loadSlotMetaForSelectedDate() async {
    _slotBooked.clear();
    _slotCapOverride.clear();
    if (_facilityId.isEmpty == true) { return; }
    if (_selectedDate == null) { return; }

    final String ymd = _ymd(_selectedDate!);
    try {
      final QuerySnapshot<Map<String, dynamic>> q = await FirebaseFirestore.instance
          .collection('Facilities').doc(_facilityId)
          .collection('Days').doc(ymd)
          .collection('Slots')
          .get();

      int i = 0;
      while (i < q.docs.length) {
        final d = q.docs[i];
        final String key = d.id.trim(); // "HHmm"
        final Map<String, dynamic> m = d.data();

        int booked = 0;
        if (m.containsKey('booked')) {
          final dynamic v = m['booked'];
          if (v is int) { booked = v; } else {
            final int? p = int.tryParse(v.toString());
            if (p != null) { booked = p; }
          }
        }
        if (booked < 0) { booked = 0; }
        _slotBooked[key] = booked;

        if (m.containsKey('capacity')) {
          final dynamic c = m['capacity'];
          int cap = 0;
          if (c is int) { cap = c; } else {
            final int? p = int.tryParse(c.toString());
            if (p != null) { cap = p; }
          }
          if (cap > 0) { _slotCapOverride[key] = cap; }
        }
        i = i + 1;
      }
    } catch (_) {}
  }

  // queue/load only when needed (prevents rebuild loop)
  void _queueLoadIfNeeded() {
    if (_facilityId.isEmpty == true) { return; }
    if (_selectedDate == null) { return; }
    final String key = _facilityId + '|' + _ymd(_selectedDate!);
    if (_loadedKey != key) {
      _loadedKey = key;
      _loadSlotMetaForSelectedDate().then((_) {
        if (mounted) { setState(() {}); }
      });
    }
  }

  // same-day compare
  bool _sameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  // parse seat text like "4" -> 4
  int _parseSeatText(String s) {
    try { return int.parse(s); } catch (_) { return -1; }
  }

  // keep function (unused for logic now) to avoid breaking call site
  bool _isMyOriginalSeat(int idx) {
    return false; // no bypass anymore
  }

  // last-second guard against race
  Future<bool> _validateSeatAvailable() async {
    if (_selectedDate == null) { return false; }
    if (_selectedTime.isEmpty == true) { return false; }
    if (_selectedSeat <= 0) { return false; }

    final String ymd = _ymd(_selectedDate!);
    final String key4 = _slotKey4FromHHmm(_selectedTime);
    final String seatId = _selectedSeat.toString();

    try {
      final doc = await FirebaseFirestore.instance
          .collection('Facilities').doc(_facilityId)
          .collection('Days').doc(ymd)
          .collection('Slots').doc(key4)
          .collection('Seats').doc(seatId)
          .get();

      bool taken = false;
      if (doc.exists) {
        final data = doc.data();
        if (data != null) {
          if (data.containsKey('taken')) {
            final dynamic v = data['taken'];
            if (v is bool) {
              if (v == true) { taken = true; }
            } else {
              if (v is String) {
                final String s = v.toLowerCase().trim();
                if (s == 'true' || s == '1' || s == 'yes') { taken = true; }
              } else {
                if (v is num) {
                  if (v != 0) { taken = true; }
                }
              }
            }
          }
        }
      }

      if (taken == true) { return false; } else { return true; }
    } catch (_) {
      return true;
    }
  }

  // ---------------- confirm write ----------------
  Future<void> _onConfirm() async {
    if (_selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Please pick a date', style: TextStyle(fontSize: 13.sp))));
    } else {
      if (_selectedTime.isEmpty == true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Please pick a time', style: TextStyle(fontSize: 13.sp))));
      } else {
        if (_selectedSeat <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Please pick a slot', style: TextStyle(fontSize: 13.sp))));
        } else {
          final String key4 = _slotKey4FromHHmm(_selectedTime);
          int cap = _capacity;
          if (_slotCapOverride.containsKey(key4) == true) {
            cap = _slotCapOverride[key4]!;
          }
          if (_selectedSeat > cap) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Selected slot is out of range', style: TextStyle(fontSize: 13.sp))));
            return;
          }

          final bool ok = await _validateSeatAvailable();
          if (ok == false) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Selected slot just got taken. Please pick another one.', style: TextStyle(fontSize: 13.sp))));
            return;
          }

          final String newStart = _selectedTime;        // "HH:MM"
          String newEnd = '';
          if (_startToEnd.containsKey(newStart) == true) {
            newEnd = _startToEnd[newStart]!;
          } else {
            newEnd = '';
          }
          final String newDateYMD = _ymd(_selectedDate!); // "YYYY-MM-DD"
          final String newSlotKey = _slotKey4FromHHmm(newStart);
          final int newSeat = _selectedSeat;

          try {
            final doc = await FirebaseFirestore.instance.collection('Bookings').doc(widget.bookingId).get();
            if (!doc.exists) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Booking not found', style: TextStyle(fontSize: 13.sp))));
              return;
            }
            final Map<String, dynamic> b = doc.data() as Map<String, dynamic>;

            String approval = '';
            if (b.containsKey('approval') && b['approval'] != null) { approval = b['approval'].toString().toLowerCase(); }
            String status = '';
            if (b.containsKey('status') && b['status'] != null) { status = b['status'].toString().toLowerCase(); }

            final bool isAcceptedUpcoming = (approval == 'accepted' || approval == 'approved') && status == 'upcoming';

            if (isAcceptedUpcoming == true) {
              await BookingService.moveAcceptedBookingByIdTx(
                bookingId: widget.bookingId,
                newFacilityId: _facilityId,
                newDateYMD: newDateYMD,
                newSlotKey: newSlotKey,
                newSeatIndex: newSeat,
                newStartStr: newStart,
                newEndStr: newEnd.isNotEmpty == true ? newEnd : null,
              );
            } else {
              // PENDING booking: update booking doc (only start/end) + ensure seat doc exists with taken=false
              try {
                final WriteBatch batch = FirebaseFirestore.instance.batch();

                final bookingRef = FirebaseFirestore.instance
                    .collection('Bookings')
                    .doc(widget.bookingId);

                batch.set(bookingRef, {
                  'facilityId': _facilityId,
                  'bookingDate': newDateYMD,        // "YYYY-MM-DD"
                  'slotKey': newSlotKey,            // "HHmm"
                  'start': newStart,                // "HH:MM"
                  'end': newEnd,                    // may be ""
                  'seatIndex': newSeat,
                  'seen': false,
                  'userSeen': false,
                  'updatedAt': FieldValue.serverTimestamp(),
                }, SetOptions(merge: true));

                // Seat doc for this pending booking: explicitly record taken = false
                final seatRef = FirebaseFirestore.instance
                    .collection('Facilities').doc(_facilityId)
                    .collection('Days').doc(newDateYMD)
                    .collection('Slots').doc(newSlotKey)
                    .collection('Seats').doc(newSeat.toString());

                batch.set(seatRef, {
                  'taken': false,
                  'updatedAt': FieldValue.serverTimestamp(),
                }, SetOptions(merge: true));

                await batch.commit();
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Update failed: $e', style: TextStyle(fontSize: 13.sp)))
                );
                return;
              }
            }

            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Booking updated', style: TextStyle(fontSize: 13.sp))));
            if (Navigator.canPop(context)) { Navigator.pop(context); }
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update failed: $e', style: TextStyle(fontSize: 13.sp))));
          }
        }
      }
    }
  }

  // ---------------- lifecycle ----------------
  @override
  void initState() {
    super.initState();
    _loadWorkRules().then((_) {
      _buildNext6Days();
      if (mounted) { setState(() {}); }
    });
  }

  void _buildNext6Days() {
    _dateChoices.clear();
    final DateTime t = DateTime.now();
    int i = 0;
    while (i <= 6) {
      _dateChoices.add(DateTime(t.year, t.month, t.day).add(Duration(days: i)));
      i = i + 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final double sw = 1.0.sw;

    final Stream<DocumentSnapshot<Map<String, dynamic>>> bookingStream =
    FirebaseFirestore.instance.collection('Bookings').doc(widget.bookingId).snapshots();

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(60.h),
        child: AppBar(
          backgroundColor: const Color(0xFF9747FF),
          elevation: 0,
          centerTitle: true,
          automaticallyImplyLeading: false,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () { if (Navigator.canPop(context)) { Navigator.pop(context); } },
            tooltip: 'Back',
          ),
          title: Text('Edit Booking', style: TextStyle(color: Colors.white, fontSize: 20.sp, fontWeight: FontWeight.w600)),
          actions: [
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () { if (Navigator.canPop(context)) { Navigator.pop(context); } },
              tooltip: 'Close',
            ),
          ],
        ),
      ),

      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: bookingStream,
        builder: (context, bookSnap) {
          if (bookSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!bookSnap.hasData || !bookSnap.data!.exists) {
            return Center(child: Text('Booking not found', style: TextStyle(fontSize: 14.sp)));
          }

          final Map<String, dynamic> bk = bookSnap.data!.data()!;

          // facility id from booking
          String fid = '';
          if (bk.containsKey('facilityId')) {
            if (bk['facilityId'] != null) { fid = bk['facilityId'].toString(); }
          } else {
            if (bk.containsKey('facilityID')) {
              if (bk['facilityID'] != null) { fid = bk['facilityID'].toString(); }
            }
          }
          if (_facilityId.isEmpty == true) { _facilityId = fid; }

          // booking date
          DateTime? bd;
          if (bk.containsKey('bookingDate')) {
            final dynamic v = bk['bookingDate'];
            if (v is Timestamp) {
              final DateTime t = v.toDate(); bd = DateTime(t.year, t.month, t.day);
            } else {
              if (v is DateTime) {
                bd = DateTime(v.year, v.month, v.day);
              } else {
                if (v is String) {
                  try {
                    final DateTime? p = DateTime.tryParse(v);
                    if (p != null) { bd = DateTime(p.year, p.month, p.day); }
                  } catch (_) {}
                }
              }
            }
          } else {
            if (bk.containsKey('booking_date')) {
              final dynamic v = bk['booking_date'];
              if (v is Timestamp) {
                final DateTime t = v.toDate(); bd = DateTime(t.year, t.month, t.day);
              } else {
                if (v is DateTime) {
                  bd = DateTime(v.year, v.month, v.day);
                } else {
                  if (v is String) {
                    try {
                      final DateTime? p = DateTime.tryParse(v);
                      if (p != null) { bd = DateTime(p.year, p.month, p.day); }
                    } catch (_) {}
                  }
                }
              }
            }
          }

          // start / end strings
          String st = '';
          if (bk.containsKey('start')) {
            if (bk['start'] != null) { st = bk['start'].toString(); }
          } else {
            if (bk.containsKey('startTime')) {
              if (bk['startTime'] != null) { st = bk['startTime'].toString(); }
            }
          }

          String et = '';
          if (bk.containsKey('end')) {
            if (bk['end'] != null) { et = bk['end'].toString(); }
          } else {
            if (bk.containsKey('endTime')) {
              if (bk['endTime'] != null) { et = bk['endTime'].toString(); }
            }
          }

          // seat text
          String seatText = '-';
          if (bk.containsKey('seatIndex')) {
            if (bk['seatIndex'] != null) { seatText = bk['seatIndex'].toString(); }
          } else {
            if (bk.containsKey('slotIndex')) {
              if (bk['slotIndex'] != null) { seatText = bk['slotIndex'].toString(); }
            }
          }

          if (_initApplied == false) {
            _origDate = bd;
            _origStartStr = st;
            _origEndStr = et;
            _origSeatText = seatText;

            if (bd != null) { _selectedDate = bd; } else { _selectedDate = DateTime.now(); }
            if (st.isNotEmpty == true) { _selectedTime = st; } else { _selectedTime = ''; }
            if (seatText != '-') {
              try { _selectedSeat = int.parse(seatText); } catch (_) { _selectedSeat = -1; }
            } else { _selectedSeat = -1; }

            _initApplied = true;
            _queueLoadIfNeeded(); // trigger first load safely
          }

          if (_facilityId.isEmpty == true) {
            return Center(child: Text('Missing facility info', style: TextStyle(fontSize: 14.sp)));
          }

          final Stream<DocumentSnapshot<Map<String, dynamic>>> facilityStream =
          FirebaseFirestore.instance.collection('Facilities').doc(_facilityId).snapshots();

          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: facilityStream,
            builder: (context, facSnap) {
              if (facSnap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!facSnap.hasData || !facSnap.data!.exists) {
                return Center(child: Text('Facility not found', style: TextStyle(fontSize: 14.sp)));
              }

              final Map<String, dynamic> fac = facSnap.data!.data()!;
              _applyFacilityData(fac);

              // load per-date slot meta if needed
              _queueLoadIfNeeded();

              // ---------------- UI ----------------
              return SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // ---------- TOP SUMMARY ----------
                    Container(
                      width: sw * 0.95,
                      padding: EdgeInsets.all(14.w),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE9D7FF),
                        borderRadius: BorderRadius.circular(14.r),
                        boxShadow: [BoxShadow(color: const Color(0x22000000), blurRadius: 8.r, offset: Offset(0, 3.h))],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _kvLine(label: 'Current Facility', value: _facilityName),
                          SizedBox(height: 6.h),
                          _kvLine(label: 'Booking Date', value: _origDate == null ? '-' : _formatFullDate(_origDate!)),
                          SizedBox(height: 6.h),
                          _kvLine(label: 'Booking Time', value: _origStartStr.isEmpty == true ? '-' : _origStartStr),
                          SizedBox(height: 6.h),
                          _kvLine(label: 'Slot Number', value: _origSeatText),
                        ],
                      ),
                    ),

                    SizedBox(height: 16.h),

                    // ---------- MONTH HEADER + CALENDAR ICON ----------
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_monthYearText(_selectedDate ?? DateTime.now()),
                            style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600)),
                        SizedBox(width: 8.w),
                        SizedBox(
                          width: 28.w,
                          height: 28.w,
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            onPressed: () async {
                              final DateTime base = DateTime.now();
                              final DateTime first = DateTime(base.year, base.month, base.day);
                              final DateTime last  = first.add(const Duration(days: 6));
                              final DateTime initial = _selectedDate ?? first;

                              final DateTime? picked = await showDatePicker(
                                context: context,
                                initialDate: initial,
                                firstDate: first,
                                lastDate: last,
                                helpText: 'Select date',
                                selectableDayPredicate: (d) {
                                  bool inRange = !d.isBefore(first) && !d.isAfter(last);
                                  bool ok = inRange;
                                  if (ok == true) { ok = _isPickableDay(d); }
                                  return ok;
                                },
                              );

                              if (picked != null) {
                                setState(() {
                                  _selectedDate = DateTime(picked.year, picked.month, picked.day);
                                  _selectedTime = '';
                                  _selectedSeat = -1;
                                  _buildNext6Days();
                                });
                                _queueLoadIfNeeded();
                              }
                            },
                            icon: const Icon(Icons.calendar_month),
                            iconSize: 20.sp,
                            tooltip: 'Pick date',
                          ),
                        ),
                      ],
                    ),

                    SizedBox(height: 10.h),

                    // ---------- WEEKDAY LETTERS ----------
                    Row(
                      children: List.generate(_dateChoices.length, (i) {
                        final DateTime d = _dateChoices[i];
                        final bool enabled = _isPickableDay(d);
                        final Color c;
                        if (enabled == true) { c = Colors.black87; } else { c = Colors.black38; }
                        return Expanded(
                          child: Center(
                            child: Text(_weekdayLetter(d), style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600, color: c)),
                          ),
                        );
                      }),
                    ),

                    SizedBox(height: 6.h),

                    // ---------- DATE NUMBER CIRCLES ----------
                    Row(
                      children: List.generate(_dateChoices.length, (i) {
                        final DateTime d = _dateChoices[i];

                        bool isSelected = false;
                        if (_selectedDate != null) {
                          if (d.year == _selectedDate!.year && d.month == _selectedDate!.month && d.day == _selectedDate!.day) {
                            isSelected = true;
                          }
                        }

                        final bool enabled = _isPickableDay(d);

                        Color bg;
                        Color fg;
                        if (isSelected == true) {
                          bg = const Color(0xFF9747FF);
                          fg = Colors.white;
                        } else {
                          if (enabled == true) {
                            bg = Colors.transparent;
                            fg = Colors.black87;
                          } else {
                            bg = Colors.transparent;
                            fg = Colors.black38;
                          }
                        }

                        return Expanded(
                          child: Center(
                            child: InkWell(
                              onTap: () {
                                if (enabled == true) {
                                  setState(() {
                                    _selectedDate = d;
                                    _selectedTime = '';
                                    _selectedSeat = -1;
                                  });
                                  _queueLoadIfNeeded();
                                }
                              },
                              borderRadius: BorderRadius.circular(20.r),
                              child: Container(
                                width: 36.w,
                                height: 36.w,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                                child: Text(d.day.toString(), style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600, color: fg)),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),

                    SizedBox(height: 12.h),
                    Container(width: 1.0.sw, height: 1.h, color: Colors.black12),
                    SizedBox(height: 12.h),

                    // ---------- TIME SLOT SECTION ----------
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Time Slot Available', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
                    ),
                    SizedBox(height: 6.h),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, size: 16.sp, color: Colors.black54),
                        SizedBox(width: 6.w),
                        Expanded(
                          child: Text(
                            'Choose more than 1 slots is allowed',
                            style: TextStyle(fontSize: 12.5.sp, color: Colors.black54, fontWeight: FontWeight.w600),
                            softWrap: true,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 12.h),

                    // time chips from customTimeSlots + per-date booked check
                    LayoutBuilder(
                      builder: (context, bc) {
                        final double maxW = bc.maxWidth;
                        final double gap = 8.w;
                        final double itemW = (maxW - (gap * 2.0)) / 3.0;

                        final List<Widget> chips = <Widget>[];
                        int i = 0;
                        while (i < _timeChoices.length) {
                          final String hhmm = _timeChoices[i];
                          final String key4 = _slotKey4FromHHmm(hhmm);

                          int capForThis = _capacity;
                          if (_slotCapOverride.containsKey(key4) == true) { capForThis = _slotCapOverride[key4]!; }
                          int booked = 0;
                          if (_slotBooked.containsKey(key4) == true) { booked = _slotBooked[key4]!; }
                          if (booked < 0) { booked = 0; }
                          if (capForThis <= 0) { capForThis = 1; }

                          final bool isFull = booked >= capForThis;

                          bool selected = false;
                          if (_selectedTime == hhmm) { selected = true; }

                          bool allowTap = true;
                          if (isFull == true) { allowTap = false; }

                          Color fillColor;
                          Color borderColor;
                          Color textColor;
                          if (isFull == true) {
                            fillColor = const Color(0xFFFFCDD2);
                            borderColor = const Color(0xFFFF0707);
                            textColor = const Color(0xFFB00020);
                          } else {
                            if (selected == true) {
                              fillColor = const Color(0xFF9747FF);
                              borderColor = const Color(0xFF4A00B8);
                              textColor = Colors.white;
                            } else {
                              fillColor = const Color(0xFFB779F1);
                              borderColor = const Color(0xFF6E00D4);
                              textColor = Colors.white;
                            }
                          }

                          chips.add(
                            ConstrainedBox(
                              constraints: BoxConstraints.tightFor(width: itemW, height: 44.h),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () {
                                    if (allowTap == true) {
                                      setState(() {
                                        _selectedTime = hhmm;
                                        _selectedSeat = -1;
                                      });
                                    }
                                  },
                                  borderRadius: BorderRadius.circular(20.r),
                                  child: Container(
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: fillColor,
                                      borderRadius: BorderRadius.circular(20.r),
                                      border: Border.all(color: borderColor, width: 1.5.w),
                                    ),
                                    child: Text(
                                      _toAmPmDot(hhmm),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: textColor),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );

                          i = i + 1;
                        }

                        return Align(
                          alignment: Alignment.centerLeft,
                          child: Wrap(spacing: gap, runSpacing: gap, children: chips),
                        );
                      },
                    ),

                    SizedBox(height: 16.h),

                    // ---------- SLOT AVAILABLE CARD ----------
                    if (_selectedTime.isNotEmpty == true)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text('Slot Available', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
                          ),
                          SizedBox(height: 8.h),

                          _SeatPickerForOneTime(
                            facilityId: _facilityId,
                            dateYMD: _selectedDate == null ? '' : _ymd(_selectedDate!),
                            slotKey4: _slotKey4FromHHmm(_selectedTime),
                            timeLabel: _toAmPmDot(_selectedTime),
                            capacity: (() {
                              final String k = _slotKey4FromHHmm(_selectedTime);
                              if (_slotCapOverride.containsKey(k) == true) { return _slotCapOverride[k]!; } else { return _capacity; }
                            })(),
                            initialSeat: _selectedSeat > 0 ? _selectedSeat : _parseSeatText(_origSeatText),
                            isMyOriginalSeatChecker: (int idx) => false, // no bypass
                            onPick: (int idx) {
                              setState(() { _selectedSeat = idx; });
                            },
                          ),
                        ],
                      ),

                    SizedBox(height: 18.h),

                    // ---------- CONFIRM ----------
                    SizedBox(
                      width: sw * 0.95,
                      height: 48.h,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF9747FF),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28.r)),
                        ),
                        onPressed: _onConfirm,
                        child: Text('Confirm', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700, color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),

      bottomNavigationBar: BottomMenuBar(
        height: 0.07.sh,
        currentIndex: _currentIndex,
        onTabSelected: _onTabSelected,
      ),
    );
  }
}

// ---------- Small UI helper ----------
Widget _kvLine({required String label, required String value}) {
  return Padding(
    padding: EdgeInsets.only(bottom: 6.h),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label + ': ', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: Colors.black)),
        Expanded(child: Text(value, style: TextStyle(fontSize: 13.sp, color: Colors.black87))),
      ],
    ),
  );
}

// ---------- Single-time seat picker using Seats/{idx} stream ----------
class _SeatPickerForOneTime extends StatefulWidget {
  const _SeatPickerForOneTime({
    Key? key,
    required this.facilityId,
    required this.dateYMD,
    required this.slotKey4,
    required this.timeLabel,
    required this.capacity,
    required this.initialSeat,
    required this.isMyOriginalSeatChecker,
    required this.onPick,
  }) : super(key: key);

  final String facilityId;                   // Facilities/{id}
  final String dateYMD;                      // Days/{YYYY-MM-DD}
  final String slotKey4;                     // Slots/{HHmm}
  final String timeLabel;                    // "8.00 am"
  final int capacity;                        // number of seats/chips
  final int initialSeat;                     // pre-select if >0
  final bool Function(int) isMyOriginalSeatChecker; // kept in signature
  final ValueChanged<int> onPick;            // notify parent

  @override
  State<_SeatPickerForOneTime> createState() => _SeatPickerForOneTimeState();
}

class _SeatPickerForOneTimeState extends State<_SeatPickerForOneTime> with AutomaticKeepAliveClientMixin {
  int? _chosen; // current selection in this box

  @override
  void initState() {
    super.initState();
    if (widget.initialSeat > 0) {
      _chosen = widget.initialSeat;
    } else {
      _chosen = null;
    }
  }

  @override
  bool get wantKeepAlive => true;

  int _idxFromSeatDocId(String id) {
    final int? a = int.tryParse(id);
    if (a != null) { return a; } else {
      final String onlyNum = id.replaceAll(RegExp(r'[^0-9]'), '');
      final int? b = int.tryParse(onlyNum);
      if (b != null) { return b; } else { return -1; }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final Stream<QuerySnapshot<Map<String, dynamic>>> seatsStream =
    FirebaseFirestore.instance
        .collection('Facilities').doc(widget.facilityId)
        .collection('Days').doc(widget.dateYMD)
        .collection('Slots').doc(widget.slotKey4)
        .collection('Seats')
        .snapshots();

    return Container(
      width: 1.0.sw,
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF5FF),
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: Colors.black26, width: 1.w),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.timeLabel, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700)),
          SizedBox(height: 10.h),

          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: seatsStream,
            builder: (context, snap) {
              final Set<int> takenTrue = <int>{};

              if (snap.hasData) {
                int i = 0;
                while (i < snap.data!.docs.length) {
                  final d = snap.data!.docs[i];
                  final int idx = _idxFromSeatDocId(d.id);
                  if (idx > 0) {
                    bool hard = false;
                    final Map<String, dynamic> m = d.data();
                    if (m.containsKey('taken')) {
                      final dynamic v = m['taken'];
                      if (v is bool) {
                        if (v == true) { hard = true; }
                      } else {
                        if (v is String) {
                          final String s = v.toLowerCase().trim();
                          if (s == 'true' || s == '1' || s == 'yes') { hard = true; }
                        } else {
                          if (v is num) {
                            if (v != 0) { hard = true; }
                          }
                        }
                      }
                    }
                    if (hard == true) { takenTrue.add(idx); }
                  }
                  i = i + 1;
                }
              }

              return LayoutBuilder(
                builder: (context, bc) {
                  final double gap = 8.w;
                  final double chipW = (bc.maxWidth - (gap * 2.0)) / 3.0;

                  final List<Widget> chips = <Widget>[];
                  int k = 1;
                  while (k <= widget.capacity) {
                    final int idx = k;

                    final bool blocked = takenTrue.contains(idx);

                    bool isChosen = false;
                    if (_chosen != null) {
                      if (_chosen == idx) { isChosen = true; }
                    }
                    if (blocked == true) { isChosen = false; }

                    Color fill;
                    Color border;
                    Color text;
                    double bw = 1.5;

                    if (blocked == true) {
                      fill = const Color(0xFFFFE7E9);
                      border = const Color(0xFFFF6B7A);
                      text = const Color(0xFFB00020);
                    } else {
                      if (isChosen == true) {
                        fill = const Color(0xFF9747FF);
                        border = const Color(0xFF4A00B8);
                        text = Colors.white;
                        bw = 2.0;
                      } else {
                        fill = const Color(0xFFB779F1);
                        border = const Color(0xFF6E00D4);
                        text = Colors.white;
                      }
                    }

                    VoidCallback? onTap;
                    if (blocked == true) {
                      onTap = null;
                    } else {
                      onTap = () {
                        setState(() { _chosen = idx; });
                        widget.onPick(idx);
                      };
                    }

                    chips.add(
                      ConstrainedBox(
                        constraints: BoxConstraints.tightFor(width: chipW, height: 40.h),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: onTap,
                            borderRadius: BorderRadius.circular(20.r),
                            child: Container(
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: fill,
                                borderRadius: BorderRadius.circular(20.r),
                                border: Border.all(color: border, width: bw),
                              ),
                              child: Text(
                                'Slot ' + idx.toString(),
                                style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: text),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );

                    k = k + 1;
                  }

                  return Wrap(spacing: gap, runSpacing: gap, children: chips);
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
