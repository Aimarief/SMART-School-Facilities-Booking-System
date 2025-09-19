import 'package:cloud_firestore/cloud_firestore.dart';        // Firestore access
import 'package:flutter/material.dart';                       // Flutter UI
import 'package:flutter_screenutil/flutter_screenutil.dart';  // Responsive units
import 'package:intl/intl.dart';                              // Date formatting
import 'package:firebase_auth/firebase_auth.dart';

import 'package:smart_school_facilities_booking_system/booking_service.dart'; // Delete flow
import 'package:smart_school_facilities_booking_system/notification_service.dart';

import 'android_bottom_menu.dart';
import 'android_agenda.dart';
import 'android_view_booking.dart';
import 'android_list_of_facilities.dart';
import 'android_notifications.dart';
import 'android_account.dart';

// ---------------- widget: AndroidEditBooking ----------------
class AndroidEditBooking extends StatefulWidget {
  // booking id to edit
  final String bookingId;
  // optional, for callers that pass approval; we still read live doc
  final String? approval;

  const AndroidEditBooking({
    Key? key,
    required this.bookingId,
    this.approval,
  }) : super(key: key);

  @override
  State<AndroidEditBooking> createState() => _AndroidEditBookingState();
}

// ---------------- state: AndroidEditBooking ----------------
class _AndroidEditBookingState extends State<AndroidEditBooking> {
  int _currentIndex = 1;

  // one-time init guard
  bool _initApplied = false;

  // booking-derived fields
  String _facilityId = '';
  DateTime? _origDate;
  String _origStartStr = '';
  String _origEndStr = '';
  String _origSeatText = '-';
  int _reasonLen = 0;
// --- memoized streams to prevent flicker on rebuilds ---
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _bookingStream;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _facilityStream;
  String _facilityStreamForId = '';

  // facility data
  String _facilityName = '';
  int _capacity = 0;                                  // facility fallback capacity
  final List<String> _timeChoices = <String>[];       // "HH:mm"
  final Map<String, String> _startToEnd = <String, String>{}; // start -> end

  // user selections
  final List<DateTime> _dateChoices = <DateTime>[];
  DateTime? _selectedDate;
  String _selectedTime = '';
  int _selectedSeat = -1;

  // per-date slot metadata
  final Map<String, int> _slotBooked = <String, int>{};      // "HHmm" -> booked
  final Map<String, int> _slotCapOverride = <String, int>{}; // "HHmm" -> capacity

  // prevent redundant loads
  String _loadedKey = ''; // "facilityId|YYYY-MM-DD"

  // off rules from SystemInformation
  Set<int> _offWeekdays = <int>{};      // 1..7 (Mon..Sun) off
  Set<String> _offDatesYmd = <String>{};

  // facility inactive window (inclusive). If either is null, ignore.
  DateTime? _inactiveFrom;
  DateTime? _inactiveTo;

  // Reason (required only for accepted->amendment)
  final TextEditingController _reasonCtrl = TextEditingController();


  @override
  void initState() {
    super.initState();
    _bookingStream = FirebaseFirestore.instance
        .collection('Bookings')
        .doc(widget.bookingId)
        .snapshots();

    _loadWorkRules().then((_) {
      _buildNext6Days();
      if (mounted) setState(() {});
    });
    _reasonCtrl.addListener(() {
      setState(() => _reasonLen = _reasonCtrl.text.characters.length.clamp(0, 200));
    });
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  // ---------------- bottom bar: on tab selected ----------------
  void _onTabSelected(int i) {
    if (i == 0) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidAgenda()));
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

  // ---------------- small format helpers ----------------
  String _formatFullDate(DateTime d) => DateFormat('EEE, d MMM yyyy').format(d);

  String _toAmPmDot(String hhmm) {
    final p = hhmm.split(':');
    int h = int.tryParse(p[0]) ?? 0;
    final int m = int.tryParse(p.length > 1 ? p[1] : '0') ?? 0;
    final String mm = m.toString().padLeft(2, '0');
    final String suf = h >= 12 ? 'pm' : 'am';
    h = h % 12;
    if (h == 0) h = 12;
    return '$h.$mm $suf';
  }

  String _minutesToHHmm(int mins) {
    int h = mins ~/ 60;
    int m = mins % 60;
    h = h.clamp(0, 23);
    m = m.clamp(0, 59);
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  String _normalizeHHmm(String s) {
    String t = s.trim().replaceAll(' ', '').replaceAll('.', ':').replaceAll('-', ':');
    if (!t.contains(':')) {
      final digits = RegExp(r'\d+').allMatches(t).map((e) => e.group(0)!).join();
      if (digits.isEmpty) return t;
      final four = digits.length == 3 ? '0$digits' : digits.padLeft(4, '0').substring(0, 4);
      return '${four.substring(0, 2)}:${four.substring(2, 4)}';
    }
    final p = t.split(':');
    final hh = (p.isNotEmpty ? p[0] : '0').padLeft(2, '0');
    final mm = (p.length > 1 ? p[1] : '0').padLeft(2, '0');
    return '$hh:$mm';
  }

  int _minutesOf(String hhmm) {
    final p = hhmm.split(':');
    final h = int.tryParse(p[0]) ?? 0;
    final m = int.tryParse(p.length > 1 ? p[1] : '0') ?? 0;
    return h * 60 + m;
  }

  String _slotKey4FromHHmm(String s) => _normalizeHHmm(s).replaceAll(':', '');

  String _ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  DateTime? _dateOnly(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) {
      final t = v.toDate();
      return DateTime(t.year, t.month, t.day);
    }
    if (v is DateTime) return DateTime(v.year, v.month, v.day);
    if (v is String) {
      final p = DateTime.tryParse(v);
      if (p != null) return DateTime(p.year, p.month, p.day);
    }
    return null;
  }

  // ---------------- SystemInformation rules ----------------
  void _applyWeekdayBooleansFromMap(Map<String, dynamic> m) {
    void add(String k, int wd) {
      if (!m.containsKey(k)) return;
      final v = m[k];
      bool off = false;
      if (v is bool) off = !v;
      else if (v is String) off = v.toLowerCase().trim() == 'false';
      else if (v is num) off = v == 0;
      if (off) _offWeekdays.add(wd);
    }
    add('Monday', 1); add('Tuesday', 2); add('Wednesday', 3);
    add('Thursday', 4); add('Friday', 5); add('Saturday', 6); add('Sunday', 7);
  }

  String _normalizeYmdString(String s) {
    final t = s.trim().replaceAll('/', '-');
    final d = DateTime.tryParse(t);
    if (d == null) return t;
    return _ymd(d);
  }

  Future<void> _loadWorkRules() async {
    _offWeekdays = <int>{};
    _offDatesYmd = <String>{};
    try {
      final ds = await FirebaseFirestore.instance.collection('SystemInformation').doc('Setting').get();
      if (ds.exists) {
        final m = ds.data();
        if (m != null) {
          _applyWeekdayBooleansFromMap(m);
          final nested = m['Setting'];
          if (nested is Map<String, dynamic>) _applyWeekdayBooleansFromMap(nested);
        }
      }
    } catch (_) {}
    try {
      final off = await FirebaseFirestore.instance.collection('SystemInformation').doc('OffDays').get();
      if (off.exists) {
        final m = off.data();
        if (m != null && m['offDays'] is List) {
          for (final e in (m['offDays'] as List)) {
            final norm = _normalizeYmdString(e.toString());
            if (norm.isNotEmpty) _offDatesYmd.add(norm);
          }
        }
      }
    } catch (_) {}
  }

  bool _isPickableDay(DateTime d) {
    final ymd = _ymd(d);
    if (_offWeekdays.contains(d.weekday)) return false;
    if (_offDatesYmd.contains(ymd)) return false;
    if (_inactiveFrom != null && _inactiveTo != null) {
      final only = DateTime(d.year, d.month, d.day);
      if (!only.isBefore(_inactiveFrom!) && !only.isAfter(_inactiveTo!)) return false;
    }
    return true;
  }

  // ---------------- facility parsing ----------------
  void _applyFacilityData(Map<String, dynamic> fac) {
    _facilityName = (fac['name'] ?? '').toString();

    final v = fac['availableSlots'] ?? fac['capacity'];
    if (v is int) _capacity = v;
    else if (v is double) _capacity = v.toInt();
    else _capacity = int.tryParse((v ?? '').toString()) ?? 0;
    if (_capacity <= 0) _capacity = 1;

    _inactiveFrom = _dateOnly(fac['inactiveFrom']);
    _inactiveTo   = _dateOnly(fac['inactiveTo']);

    _timeChoices.clear();
    _startToEnd.clear();
    final arr = fac['customTimeSlots'];
    if (arr is List) {
      for (final it in arr) {
        String start = '', end = '';
        if (it is Map) {
          start = (it['start'] ?? '').toString().trim();
          end   = (it['end']   ?? '').toString().trim();
        } else if (it is String) {
          final s = it.trim();
          if (s.contains('-')) { final p = s.split('-'); start = p[0].trim(); end = (p.length > 1 ? p[1].trim() : ''); }
          else { start = s; }
        }
        if (start.isEmpty) continue;
        final ns = _normalizeHHmm(start);
        final ne = end.isNotEmpty ? _normalizeHHmm(end) : '';
        if (!_startToEnd.containsKey(ns)) {
          _timeChoices.add(ns);
          if (ne.isNotEmpty) _startToEnd[ns] = ne;
        }
      }
    }
    _timeChoices.sort((a, b) => _minutesOf(a).compareTo(_minutesOf(b)));
  }

  // ---------------- day/time helpers ----------------
  void _buildNext6Days() {
    _dateChoices.clear();
    final t = DateTime.now();
    for (int i = 0; i <= 6; i++) {
      _dateChoices.add(DateTime(t.year, t.month, t.day).add(Duration(days: i)));
    }
  }

  bool _isSelectedDayToday() {
    if (_selectedDate == null) return false;
    final now = DateTime.now();
    final d = _selectedDate!;
    return now.year == d.year && now.month == d.month && now.day == d.day;
  }

  bool _isTimePastForSelectedDay(String hhmm) {
    if (!_isSelectedDayToday()) return false;
    final now = DateTime.now();
    return (now.hour * 60 + now.minute) >= _minutesOf(_normalizeHHmm(hhmm));
  }

  Future<void> _loadSlotMetaForSelectedDate() async {
    _slotBooked.clear();
    _slotCapOverride.clear();
    if (_facilityId.isEmpty || _selectedDate == null) return;
    final ymd = _ymd(_selectedDate!);
    try {
      final q = await FirebaseFirestore.instance
          .collection('Facilities').doc(_facilityId)
          .collection('Days').doc(ymd)
          .collection('Slots')
          .get();
      for (final d in q.docs) {
        final key = d.id.trim();
        final m = d.data();
        int booked = 0;
        final bv = m['booked'];
        if (bv is int) booked = bv; else booked = int.tryParse((bv ?? '0').toString()) ?? 0;
        _slotBooked[key] = booked.clamp(0, 1 << 30);
        final cv = m['capacity'];
        if (cv != null) {
          int cap = 0;
          if (cv is int) cap = cv;
          else cap = int.tryParse(cv.toString()) ?? 0;
          if (cap > 0) _slotCapOverride[key] = cap;
        }
      }
    } catch (_) {}
  }

  void _queueLoadIfNeeded() {
    if (_facilityId.isEmpty || _selectedDate == null) return;
    final key = '$_facilityId|${_ymd(_selectedDate!)}';
    if (_loadedKey != key) {
      _loadedKey = key;
      _loadSlotMetaForSelectedDate().then((_) { if (mounted) setState(() {}); });
    }
  }

  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  int _parseSeatText(String s) => int.tryParse(s) ?? -1;

  String _lookupEndFromFacilityByStart(String start) {
    final s = _normalizeHHmm(start);
    final e = _startToEnd[s];
    return e == null ? '' : _normalizeHHmm(e);
  }

  String _endForStartFallback(String start) {
    final e = _lookupEndFromFacilityByStart(start);
    return e.isNotEmpty ? e : _minutesToHHmm(_minutesOf(_normalizeHHmm(start)) + 60);
  }

  // ----------------------------------------------
// Show confirm dialog for deleting a booking
// - same design as your logout dialog
// - returns true if user confirms
// ----------------------------------------------
  Future<bool> _confirmDeleteDialog() async {
    final bool? yes = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // cannot tap outside to close
      builder: (ctx) {
        return AlertDialog(
          // square corners (no rounding)
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          title: Text(
            'Delete booking?',
            style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w600),
          ),
          content: Text(
            'This will mark the booking as deleted.',
            style: TextStyle(fontSize: 14.sp),
          ),
          actions: [
            // Cancel button = close dialog, return false
            TextButton(
              onPressed: () { Navigator.of(ctx).pop(false); },
              child: Text('Cancel', style: TextStyle(fontSize: 14.sp)),
            ),
            // Red Confirm button = close dialog, return true
            ElevatedButton(
              onPressed: () { Navigator.of(ctx).pop(true); },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF0707), // red
                foregroundColor: Colors.white,
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              ),
              child: Text('Confirm', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
            ),
          ],
        );
      },
    );
    return yes == true;
  }


  // ---------------- delete (soft-delete) current booking ----------------
  Future<void> _onDelete() async {
    // 1) Ask user with the new confirmation popup
    final bool ok = await _confirmDeleteDialog();
    // 2) If user did not confirm, stop here (logic unchanged)
    if (ok != true) return;

    try {
      // read once to build notification payload
      final doc = await FirebaseFirestore.instance.collection('Bookings').doc(widget.bookingId).get();
      if (!doc.exists || doc.data() == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Booking not found')));
        return;
      }
      final m = doc.data()!;
      String facilityId = (m['facilityId'] ?? m['facilityID'] ?? '').toString().trim();
      final String userId = (m['userId'] ?? m['uid'] ?? m['bookedBy'] ?? m['bookBy'] ?? '').toString().trim();
      String managerId = (m['managerId'] ?? m['managerUID'] ?? m['managerUid'] ?? '').toString().trim();
      if (managerId.isEmpty && facilityId.isNotEmpty) {
        try {
          final fac = await FirebaseFirestore.instance.collection('Facilities').doc(facilityId).get();
          final fm = fac.data();
          if (fm != null) {
            managerId = (fm['managerId'] ?? fm['managerUID'] ?? fm['managerUid'] ?? '').toString().trim();
            if (facilityId.isEmpty) facilityId = fac.id;
          }
        } catch (_) {}
      }

      String _hhmmStrict(String raw) {
        final digits = RegExp(r'\d+').allMatches(raw).map((e) => e.group(0)!).join();
        if (digits.isEmpty) return '';
        final four = digits.length == 3 ? '0$digits' : digits.padLeft(4, '0').substring(0, 4);
        int hh = int.tryParse(four.substring(0, 2)) ?? 0; hh = hh.clamp(0, 23);
        int mm = int.tryParse(four.substring(2, 4)) ?? 0; mm = mm.clamp(0, 59);
        return '${hh.toString().padLeft(2, '0')}:${mm.toString().padLeft(2, '0')}';
      }

      final int seatIndex = int.tryParse((m['seatIndex'] ?? m['slotIndex'] ?? '').toString()) ?? -1;
      final String start = _hhmmStrict((m['start'] ?? m['startTime'] ?? '').toString());
      final String end   = _hhmmStrict((m['end']   ?? m['endTime']   ?? '').toString());

      DateTime? _dateOnlyAny(dynamic v) => _dateOnly(v) ?? _dateOnly(m['booking_date']) ?? _dateOnly(m['date']);
      final DateTime? bd = _dateOnlyAny(m['bookingDate']);
      final String bookingDate = bd != null
          ? _ymd(bd)
          : _normalizeYmdString((m['bookingDate'] ?? m['booking_date'] ?? m['date'] ?? '').toString());

      final String actor = FirebaseAuth.instance.currentUser?.uid ?? '';

      await BookingService.deleteAcceptedBookingByIdTx(bookingId: widget.bookingId);

      await NotificationService.sendBookingDeletedMails(
        bookingId: widget.bookingId,
        userId: userId,
        bookedBy: actor,
        facilityId: facilityId,
        managerId: managerId,
        seatIndex: seatIndex,
        start: start,
        end: end,
        bookingDate: bookingDate,
      );

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Booking deleted')));
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => AndroidViewBooking()), (_) => false);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  // Small red "Delete" chip button used in the header row
  Widget _buildDeleteButton() {
    return Container(
      width: 110.w,
      height: 36.h,
      decoration: BoxDecoration(
        color: const Color(0xFFFFE7E9),
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: const Color(0xFFD32F2F), width: 1.w),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _onDelete,
          borderRadius: BorderRadius.circular(10.r),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(Icons.delete, size: 16.sp, color: const Color(0xFFD32F2F)),
              SizedBox(width: 6.w),
              Text(
                'Cancel',
                style: TextStyle(
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFFD32F2F),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  // --- overlap check helper (same-day, exclude current booking) ---
  Future<Map<String, String>?> _findOverlapWithMyOtherBookings({
    required String userId,
    required String dateYMD,
    required String newStart,        // "HH:mm"
    required String newEnd,          // "HH:mm"
    required String excludeBookingId,
  }) async {
    try {
      final qs = await FirebaseFirestore.instance
          .collection('Bookings')
          .where('userId', isEqualTo: userId)
          .where('bookingDate', isEqualTo: dateYMD)
          .get();

      final int newS = _minutesOf(_normalizeHHmm(newStart));
      final int newE = _minutesOf(_normalizeHHmm(newEnd));

      for (final d in qs.docs) {
        if (d.id == excludeBookingId) continue;           // ignore the booking being edited
        final m = d.data();
        if (m['deleted'] == true) continue;

        final ap = (m['approval'] ?? '').toString().toLowerCase().trim();
        if (!(ap == 'accepted' || ap == 'approved' || ap == 'pending')) continue;

        // existing booking times
        String s = _normalizeHHmm((m['start'] ?? m['startTime'] ?? '').toString());
        String e = (m['end'] ?? m['endTime'] ?? '').toString().trim();

        if (e.isEmpty) {
          // try facility template, else +60m
          final fromTpl = _lookupEndFromFacilityByStart(s);
          e = fromTpl.isNotEmpty ? _normalizeHHmm(fromTpl) : _minutesToHHmm(_minutesOf(s) + 60);
        } else {
          e = _normalizeHHmm(e);
        }

        final int sM = _minutesOf(s);
        final int eM = _minutesOf(e);

        // overlap: [newS,newE) vs [sM,eM)
        if (newS < eM && newE > sM) {
          return {'start': s, 'end': e};
        }
      }
    } catch (_) {}
    return null; // no overlap found
  }



  // ---------------- CONFIRM: pending edit or accepted→amendment ----------------
  Future<void> _onConfirm() async {
    if (_selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Please pick a date', style: TextStyle(fontSize: 13.sp))));
      return;
    }
    if (_selectedTime.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Please pick a time', style: TextStyle(fontSize: 13.sp))));
      return;
    }
    if (_isTimePastForSelectedDay(_selectedTime)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Selected time has already passed', style: TextStyle(fontSize: 13.sp))));
      return;
    }
    if (_selectedSeat <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Please pick a slot', style: TextStyle(fontSize: 13.sp))));
      return;
    }

    // capacity check
    final String key4 = _slotKey4FromHHmm(_selectedTime);
    int cap = _slotCapOverride[key4] ?? _capacity;
    if (_selectedSeat > cap) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Selected slot is out of range', style: TextStyle(fontSize: 13.sp))));
      return;
    }

    // live seat availability check
    final bool ok = await _validateSeatAvailable();
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Selected slot just got taken. Please pick another one.', style: TextStyle(fontSize: 13.sp))),
      );
      return;
    }

    final String newStart = _normalizeHHmm(_selectedTime);
    String newEnd = _startToEnd.containsKey(newStart) ? _startToEnd[newStart]! : '';
    if (newEnd.isEmpty) newEnd = _endForStartFallback(newStart);
    final String newDateYMD = _ymd(_selectedDate!);
    final String newSlotKey = _slotKey4FromHHmm(newStart);
    final int newSeat = _selectedSeat;

    try {
      // read booking once
      final doc = await FirebaseFirestore.instance.collection('Bookings').doc(widget.bookingId).get();
      if (!doc.exists || doc.data() == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Booking not found', style: TextStyle(fontSize: 13.sp))));
        return;
      }
      final Map<String, dynamic> b = doc.data()!;

      // owner
      String userId = (b['userId'] ?? '').toString();
      if (userId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not verify user on booking', style: TextStyle(fontSize: 13.sp))));
        return;
      }

      // compute acceptance
      final String approvalStr = (b['approval'] ?? '').toString().toLowerCase().trim();
      final String statusStr   = (b['status']   ?? '').toString().toLowerCase().trim();
      final bool isAcceptedUpcoming =
          (approvalStr == 'accepted' || approvalStr == 'approved') && statusStr == 'upcoming';

      // manager (prefer booking, else facility)
      String managerId = (b['managerId'] ?? '').toString().trim();
      if (managerId.isEmpty) {
        try {
          final facSnap = await FirebaseFirestore.instance.collection('Facilities').doc(_facilityId).get();
          final fac = facSnap.data();
          if (fac != null) {
            managerId = (fac['managerId'] ?? fac['managerUID'] ?? fac['managerUid'] ?? '').toString().trim();
          }
        } catch (_) {}
      }

      final String actorUid = FirebaseAuth.instance.currentUser?.uid ?? '';

      // ---- overlap guard vs my other bookings on the same day ----
      final overlap = await _findOverlapWithMyOtherBookings(
        userId: userId,
        dateYMD: newDateYMD,
        newStart: newStart,
        newEnd: newEnd,
        excludeBookingId: widget.bookingId,
      );
      if (overlap != null) {
        final s = overlap['start']!;
        final e = overlap['end']!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Overlap with your existing booking ${_toAmPmDot(s)} - ${_toAmPmDot(e)}.',
              style: TextStyle(fontSize: 13.sp),
            ),
          ),
        );
        return;
      }


      if (isAcceptedUpcoming) {
        // ---------- ACCEPTED → create Amendment (required reason) ----------
        final String reason = _reasonCtrl.text.trim();
        if (reason.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Please enter your reason', style: TextStyle(fontSize: 13.sp))));
          return;
        }

        // optional: prevent multiple pending amendments
        final amendCol = FirebaseFirestore.instance
            .collection('Bookings').doc(widget.bookingId)
            .collection('Amendments');

        final existingPending = await amendCol.where('approval', isEqualTo: 'pending').limit(1).get();
        if (existingPending.docs.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('You already have a pending amendment for this booking.', style: TextStyle(fontSize: 13.sp))),
          );
          return;
        }

        // payload mirrors "pending booking" style
        final Map<String, dynamic> data = <String, dynamic>{
          'approval': 'pending',
          'approvalReason': reason,
          'facilityId': _facilityId,
          'bookingDate': newDateYMD,
          'slotKey': newSlotKey,
          'start': newStart,
          'end': newEnd,
          'seatIndex': newSeat,
          'userId': userId,
          'managerId': managerId,
          'createdAt': FieldValue.serverTimestamp(),
          'createdBy': actorUid,
          // keep a snapshot of current accepted booking (for admin diff)
          'original': b,
          'seen':false,
        };

        final ref = await amendCol.add(data);
        // write back amendmentId into the doc (optional)
        await ref.set({'amendmentId': ref.id}, SetOptions(merge: true));

        

        // Make the parent booking bubble up in admin list and show a red dot
        await FirebaseFirestore.instance
            .collection('Bookings')
            .doc(widget.bookingId)
            .set({
          'seen': false, // admin hasn't seen the new amendment
          'hasPendingAmendment': true,
          'lastActivityAt': FieldValue.serverTimestamp(),
          'amendmentPreview': {
            'bookingDate': newDateYMD,
            'start': newStart,
            'end': newEnd,
            'seatIndex': newSeat,
            'reason': reason,
          },
        }, SetOptions(merge: true));

        // soft seat placeholder for proposed seat
        try {
          await FirebaseFirestore.instance
              .collection('Facilities').doc(_facilityId)
              .collection('Days').doc(newDateYMD)
              .collection('Slots').doc(newSlotKey)
              .collection('Seats').doc(newSeat.toString())
              .set({'taken': false, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
        } catch (_) {}

        // inbox: treat as "created" pending (amendment pending)
        try {
          await NotificationService.sendBookingCreatedMails(
            bookingId: widget.bookingId,     // keep parent bookingId in inbox
            userId: userId,
            bookedBy: actorUid,
            facilityId: _facilityId,
            managerId: managerId,
            approval: 'pending',
            seatIndex: newSeat,
            bookingDate: newDateYMD,
            start: newStart,
            end: newEnd,
            amendmentId: ref.id,
          );
        } catch (_) {}

        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Amendment request submitted', style: TextStyle(fontSize: 13.sp))));
        if (!mounted) return;
        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => AndroidViewBooking()), (_) => false);
        return;
      }

      // ---------- PENDING booking → update in place (NO reason) ----------
      final WriteBatch batch = FirebaseFirestore.instance.batch();
      final bookingRef = FirebaseFirestore.instance.collection('Bookings').doc(widget.bookingId);

      final Map<String, dynamic> patch = <String, dynamic>{
        'facilityId': _facilityId,
        'bookingDate': newDateYMD,
        'slotKey': newSlotKey,
        'start': newStart,
        'end': newEnd,
        'seatIndex': newSeat,
        'approval': 'pending',          // keep pending (all bookings require approval)
        'seen': false,
        'userSeen': false,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      batch.set(bookingRef, patch, SetOptions(merge: true));

      // placeholder seat doc
      final seatRef = FirebaseFirestore.instance
          .collection('Facilities').doc(_facilityId)
          .collection('Days').doc(newDateYMD)
          .collection('Slots').doc(newSlotKey)
          .collection('Seats').doc(newSeat.toString());
      batch.set(seatRef, {'taken': false, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));

      await batch.commit();

      // inbox for edit-pending → use "created" pending mail with timing/seat
      try {
        await NotificationService.sendBookingCreatedMails(
          bookingId: widget.bookingId,
          userId: userId,
          bookedBy: actorUid,
          facilityId: _facilityId,
          managerId: managerId,
          approval: 'pending',
          seatIndex: newSeat,
          bookingDate: newDateYMD,
          start: newStart,
          end: newEnd,
        );
      } catch (_) {}

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Request updated (pending)', style: TextStyle(fontSize: 13.sp))));
      if (Navigator.canPop(context)) Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update failed: $e', style: TextStyle(fontSize: 13.sp))));
    }
  }

  // ---------------- seat availability read (soft check) ----------------
  Future<bool> _validateSeatAvailable() async {
    if (_selectedDate == null || _selectedTime.isEmpty || _selectedSeat <= 0) return false;
    final ymd = _ymd(_selectedDate!);
    final key4 = _slotKey4FromHHmm(_selectedTime);
    final seatId = _selectedSeat.toString();
    try {
      final doc = await FirebaseFirestore.instance
          .collection('Facilities').doc(_facilityId)
          .collection('Days').doc(ymd)
          .collection('Slots').doc(key4)
          .collection('Seats').doc(seatId)
          .get();
      if (!doc.exists) return true;
      final m = doc.data();
      if (m == null) return true;
      final v = m['taken'];
      if (v is bool) return v == false;
      if (v is String) return !(v.toLowerCase().trim() == 'true' || v == '1' || v == 'yes');
      if (v is num) return v == 0;
      return true;
    } catch (_) {
      return true;
    }
  }

  // ---------------- build ----------------
  @override
  Widget build(BuildContext context) {
    final double sw = 1.0.sw;



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
            onPressed: () { if (Navigator.canPop(context)) Navigator.pop(context); },
            tooltip: 'Back',
          ),
          title: Text('Edit Booking', style: TextStyle(color: Colors.white, fontSize: 20.sp, fontWeight: FontWeight.w600)),
          actions: <Widget>[
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () { if (Navigator.canPop(context)) Navigator.pop(context); },
              tooltip: 'Close',
            ),
          ],
        ),
      ),

      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _bookingStream,
        builder: (context, bookSnap) {
          if (bookSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!bookSnap.hasData || !bookSnap.data!.exists) {
            return Center(child: Text('Booking not found', style: TextStyle(fontSize: 14.sp)));
          }

          final Map<String, dynamic> bk = bookSnap.data!.data()!;

          // facility id (from booking)
          String fid = (bk['facilityId'] ?? bk['facilityID'] ?? '').toString();
          if (_facilityId.isEmpty) _facilityId = fid;
          if (_facilityStream == null || _facilityStreamForId != fid) {
            _facilityStream = FirebaseFirestore.instance
                .collection('Facilities')
                .doc(fid)
                .snapshots();
            _facilityStreamForId = fid;
          }

          // booking date
          DateTime? bd;
          final v1 = bk['bookingDate'];
          final v2 = bk['booking_date'];
          final v3 = bk['date'];
          bd = _dateOnly(v1) ?? _dateOnly(v2) ?? _dateOnly(v3);

          // start / end
          final String st = (bk['start'] ?? bk['startTime'] ?? '').toString();
          final String et = (bk['end']   ?? bk['endTime']   ?? '').toString();

          // seat
          String seatText = '-';
          if (bk['seatIndex'] != null) seatText = bk['seatIndex'].toString();
          else if (bk['slotIndex'] != null) seatText = bk['slotIndex'].toString();

          // initialize one-time values
          if (!_initApplied) {
            _origDate = bd;
            _origStartStr = st;
            _origEndStr = et;
            _origSeatText = seatText;

            _selectedDate = bd ?? DateTime.now();
            _selectedTime = st.isNotEmpty ? _normalizeHHmm(st) : '';
            _selectedSeat = seatText != '-' ? (int.tryParse(seatText) ?? -1) : -1;

            _initApplied = true;
            _queueLoadIfNeeded();
          }

          if (_facilityId.isEmpty) {
            return Center(child: Text('Missing facility info', style: TextStyle(fontSize: 14.sp)));
          }


          // compute branch (accepted→amendment or pending edit) for UI
          final String approvalStr = (bk['approval'] ?? '').toString().toLowerCase().trim();
          final String statusStr   = (bk['status']   ?? '').toString().toLowerCase().trim();
          final bool isAcceptedUpcoming =
              (approvalStr == 'accepted' || approvalStr == 'approved') && statusStr == 'upcoming';

          final bool sameSlotAsOriginal =
              _origDate != null &&
                  _selectedDate != null &&
                  _sameDay(_origDate!, _selectedDate!) &&
                  _normalizeHHmm(_origStartStr) == _normalizeHHmm(_selectedTime);

          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: _facilityStream,
            builder: (context, facSnap) {
              if (facSnap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!facSnap.hasData || !facSnap.data!.exists) {
                return Center(child: Text('Facility not found', style: TextStyle(fontSize: 14.sp)));
              }

              final Map<String, dynamic> fac = facSnap.data!.data()!;
              _applyFacilityData(fac);
              _queueLoadIfNeeded();

              return SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    // --- TOP RIGHT DELETE BUTTON ---
                    Row(mainAxisAlignment: MainAxisAlignment.end, children: <Widget>[_buildDeleteButton()]),
                    SizedBox(height: 10.h),

                    // summary card (current)
                    Container(
                      width: sw * 0.95,
                      padding: EdgeInsets.all(14.w),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE9D7FF),
                        borderRadius: BorderRadius.circular(14.r),
                        boxShadow: <BoxShadow>[BoxShadow(color: const Color(0x22000000), blurRadius: 8.r, offset: Offset(0, 3.h))],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          _kvLine(label: 'Current Facility', value: _facilityName),
                          SizedBox(height: 6.h),
                          _kvLine(label: 'Booking Date', value: _origDate == null ? '-' : _formatFullDate(_origDate!)),
                          SizedBox(height: 6.h),
                          _kvLine(label: 'Booking Time', value: _origStartStr.isEmpty ? '-' : _origStartStr),
                          SizedBox(height: 6.h),
                          _kvLine(label: 'Slot Number', value: _origSeatText),
                        ],
                      ),
                    ),

                    SizedBox(height: 16.h),

                    // month header + calendar
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Text(DateFormat('MMMM yyyy').format(_selectedDate ?? DateTime.now()),
                            style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600)),
                        SizedBox(width: 8.w),
                        SizedBox(
                          width: 28.w,
                          height: 28.w,
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            onPressed: () async {
                              final base = DateTime.now();
                              final first = DateTime(base.year, base.month, base.day);
                              final last  = first.add(const Duration(days: 6));
                              final initial = _selectedDate ?? first;

                              final picked = await showDatePicker(
                                context: context,
                                initialDate: initial,
                                firstDate: first,
                                lastDate: last,
                                helpText: 'Select date',
                                selectableDayPredicate: (d) => !d.isBefore(first) && !d.isAfter(last) && _isPickableDay(d),
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

                    // weekday letters
                    Row(
                      children: List.generate(_dateChoices.length, (i) {
                        final d = _dateChoices[i];
                        final enabled = _isPickableDay(d);
                        final c = enabled ? Colors.black87 : Colors.black38;
                        return Expanded(child: Center(child: Text(DateFormat('E').format(d)[0], style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600, color: c))));
                      }),
                    ),

                    SizedBox(height: 6.h),

                    // date circles
                    Row(
                      children: List.generate(_dateChoices.length, (i) {
                        final d = _dateChoices[i];
                        final isSelected = _selectedDate != null && _sameDay(d, _selectedDate!);
                        final enabled = _isPickableDay(d);
                        final bg = isSelected ? const Color(0xFF9747FF) : Colors.transparent;
                        final fg = isSelected ? Colors.white : (enabled ? Colors.black87 : Colors.black38);

                        return Expanded(
                          child: Center(
                            child: InkWell(
                              onTap: enabled ? () {
                                setState(() { _selectedDate = d; _selectedTime = ''; _selectedSeat = -1; });
                                _queueLoadIfNeeded();
                              } : null,
                              borderRadius: BorderRadius.circular(20.r),
                              child: Container(
                                width: 36.w,
                                height: 36.w,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                                child: Text('${d.day}', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600, color: fg)),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),

                    SizedBox(height: 12.h),
                    Container(width: 1.0.sw, height: 1.h, color: Colors.black12),
                    SizedBox(height: 12.h),

                    // time section title
                    Align(alignment: Alignment.centerLeft, child: Text('Time Slot Available', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700))),
                    SizedBox(height: 6.h),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Icon(Icons.info_outline, size: 16.sp, color: Colors.black54),
                        SizedBox(width: 6.w),
                        Expanded(
                          child: Text('Choose more than 1 slots is allowed',
                            style: TextStyle(fontSize: 12.5.sp, color: Colors.black54, fontWeight: FontWeight.w600),
                            softWrap: true,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 12.h),

                    // time chips
                    LayoutBuilder(
                      builder: (context, bc) {
                        final double maxW = bc.maxWidth;
                        final double gap = 8.w;
                        final double itemW = (maxW - (gap * 2.0)) / 3.0;

                        final List<Widget> chips = <Widget>[];
                        for (final hhmm in _timeChoices) {
                          final key4 = _slotKey4FromHHmm(hhmm);
                          int capForThis = _slotCapOverride[key4] ?? _capacity;
                          int booked = _slotBooked[key4] ?? 0;
                          booked = booked.clamp(0, 1 << 30);
                          if (capForThis <= 0) capForThis = 1;

                          final bool isFull = booked >= capForThis;
                          final bool isPast = _isTimePastForSelectedDay(hhmm);

                          final bool selected = _selectedTime == hhmm && !isPast;
                          final bool allowTap = !isFull && !isPast;

                          Color fillColor, borderColor, textColor;
                          if (isPast) {
                            fillColor  = const Color(0xFFE5E7EB);
                            borderColor= const Color(0xFFCBD5E1);
                            textColor  = const Color(0xFF9CA3AF);
                          } else if (isFull) {
                            fillColor  = const Color(0xFFFFCDD2);
                            borderColor= const Color(0xFFFF0707);
                            textColor  = const Color(0xFFB00020);
                          } else if (selected) {
                            fillColor  = const Color(0xFF9747FF);
                            borderColor= const Color(0xFF4A00B8);
                            textColor  = Colors.white;
                          } else {
                            fillColor  = const Color(0xFFB779F1);
                            borderColor= const Color(0xFF6E00D4);
                            textColor  = Colors.white;
                          }

                          chips.add(
                            ConstrainedBox(
                              constraints: BoxConstraints.tightFor(width: itemW, height: 44.h),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: allowTap ? () {
                                    setState(() { _selectedTime = hhmm; _selectedSeat = -1; });
                                  } : null,
                                  borderRadius: BorderRadius.circular(20.r),
                                  child: Container(
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: fillColor,
                                      borderRadius: BorderRadius.circular(20.r),
                                      border: Border.all(color: borderColor, width: 1.5.w),
                                    ),
                                    child: Text(_toAmPmDot(hhmm), maxLines: 1, overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: textColor)),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }

                        return Align(alignment: Alignment.centerLeft, child: Wrap(spacing: gap, runSpacing: gap, children: chips));
                      },
                    ),

                    SizedBox(height: 16.h),

                    // seat picker for selected time
                    if (_selectedTime.isNotEmpty && !_isTimePastForSelectedDay(_selectedTime))
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Align(alignment: Alignment.centerLeft, child: Text('Slot Available', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700))),
                          SizedBox(height: 8.h),

                          _SeatPickerForOneTime(
                            key: ValueKey('$_facilityId|${_selectedDate == null ? '' : _ymd(_selectedDate!)}|${_slotKey4FromHHmm(_selectedTime)}'),
                            facilityId: _facilityId,
                            dateYMD: _selectedDate == null ? '' : _ymd(_selectedDate!),
                            slotKey4: _slotKey4FromHHmm(_selectedTime),
                            timeLabel: _toAmPmDot(_selectedTime),
                            capacity: (() {
                              final k = _slotKey4FromHHmm(_selectedTime);
                              return _slotCapOverride[k] ?? _capacity;
                            })(),
                            initialSeat: sameSlotAsOriginal ? _parseSeatText(_origSeatText) : 0,
                            isMyOriginalSeatChecker: (int idx) => false,
                            onPick: (int idx) { _selectedSeat = idx; },
                          ),
                        ],
                      ),

                    SizedBox(height: 18.h),

                    // Reason text box ONLY when accepted -> amendment
                    if (isAcceptedUpcoming) ...[
                      Align(alignment: Alignment.centerLeft,
                          child: Text('Reason (required)', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700))),
                      SizedBox(height: 6.h),
                      Stack(
                        children: <Widget>[
                          TextField(
                            controller: _reasonCtrl,
                            maxLength: 200,
                            maxLines: 3,
                            decoration: InputDecoration(
                              counterText: '',
                              isDense: true,
                              hintText: 'Why do you need to amend this booking?',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r)),
                              fillColor: Colors.grey.shade200,
                              filled: true,
                            ),
                          ),
                          Positioned(
                            right: 10.w,
                            bottom: 8.h,
                            child: Text('$_reasonLen/200', style: TextStyle(fontSize: 12.sp, color: Colors.black54)),
                          ),
                        ],
                      ),
                      SizedBox(height: 18.h),
                    ],

                    // confirm button
                    SizedBox(
                      width: sw * 0.95,
                      height: 48.h,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF9747FF),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28.r)),
                        ),
                        onPressed: _onConfirm,
                        child: Text(
                          isAcceptedUpcoming ? 'Submit Amendment' : 'Confirm',
                          style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
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

// ---------------- small ui helper: key:value line ----------------
Widget _kvLine({required String label, required String value}) {
  return Padding(
    padding: EdgeInsets.only(bottom: 6.h),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('$label: ', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: Colors.black)),
        Expanded(child: Text(value, style: TextStyle(fontSize: 13.sp, color: Colors.black87))),
      ],
    ),
  );
}

// ---------------- seat picker: one time slot using Seats/{idx} stream ----------------
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

  final String facilityId;   // Facilities/{id}
  final String dateYMD;      // Days/{YYYY-MM-DD}
  final String slotKey4;     // Slots/{HHmm}

  final String timeLabel;
  final int capacity;
  final int initialSeat;

  final bool Function(int) isMyOriginalSeatChecker;
  final ValueChanged<int> onPick;

  @override
  State<_SeatPickerForOneTime> createState() => _SeatPickerForOneTimeState();
}

class _SeatPickerForOneTimeState extends State<_SeatPickerForOneTime>
    with AutomaticKeepAliveClientMixin {

  int? _chosen;

  @override
  void initState() {
    super.initState();
    _chosen = widget.initialSeat > 0 ? widget.initialSeat : null;
  }

  @override
  void didUpdateWidget(covariant _SeatPickerForOneTime oldWidget) {
    super.didUpdateWidget(oldWidget);
    final idChanged = oldWidget.facilityId != widget.facilityId ||
        oldWidget.dateYMD != widget.dateYMD ||
        oldWidget.slotKey4 != widget.slotKey4;
    if (idChanged) {
      if (mounted) setState(() { _chosen = null; });
      return;
    }
    if (oldWidget.initialSeat != widget.initialSeat) {
      if (_chosen == null && widget.initialSeat > 0) {
        if (mounted) setState(() { _chosen = widget.initialSeat; });
      }
    }
  }

  @override
  bool get wantKeepAlive => true;

  int _idxFromSeatDocId(String id) {
    final a = int.tryParse(id);
    if (a != null) return a;
    final onlyNum = id.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(onlyNum) ?? -1;
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
        .snapshots(includeMetadataChanges: false);

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
        children: <Widget>[
          Text(widget.timeLabel, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700)),
          SizedBox(height: 10.h),

          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: seatsStream,
            builder: (context, snap) {
              final Set<int> takenTrue = <int>{};

              if (snap.hasData) {
                for (final d in snap.data!.docs) {
                  final idx = _idxFromSeatDocId(d.id);
                  if (idx <= 0) continue;
                  final m = d.data();
                  final v = m['taken'];
                  bool hard = false;
                  if (v is bool) hard = v;
                  else if (v is String) hard = (v.toLowerCase().trim() == 'true' || v == '1' || v == 'yes');
                  else if (v is num) hard = v != 0;
                  if (hard) takenTrue.add(idx);
                }
              }

              return LayoutBuilder(
                builder: (context, bc) {
                  final gap = 8.w;
                  final chipW = (bc.maxWidth - (gap * 2.0)) / 3.0;

                  final List<Widget> chips = <Widget>[];
                  for (int k = 1; k <= widget.capacity; k++) {
                    final idx = k;
                    final blocked = takenTrue.contains(idx);

                    bool isChosen = (_chosen != null && _chosen == idx);
                    if (blocked) isChosen = false;

                    Color fill, border, text;
                    double bw = 1.5;

                    if (blocked) {
                      fill = const Color(0xFFFFE7E9);
                      border = const Color(0xFFFF6B7A);
                      text = const Color(0xFFB00020);
                    } else if (isChosen) {
                      fill = const Color(0xFF9747FF);
                      border = const Color(0xFF4A00B8);
                      text = Colors.white;
                      bw = 2.0;
                    } else {
                      fill = const Color(0xFFB779F1);
                      border = const Color(0xFF6E00D4);
                      text = Colors.white;
                    }

                    final onTap = blocked ? null : () {
                      setState(() { _chosen = idx; });
                      widget.onPick(idx);
                    };

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
                              child: Text('Slot $idx', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: text)),
                            ),
                          ),
                        ),
                      ),
                    );
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
