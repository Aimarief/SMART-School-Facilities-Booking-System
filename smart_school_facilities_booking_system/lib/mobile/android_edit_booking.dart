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

class AndroidEditBooking extends StatefulWidget {
//---------------------------------------
// get the booking id and approval from previous
//---------------------------------------
  final String bookingId;
  final String? approval;

  const AndroidEditBooking({
    Key? key,
    required this.bookingId,
    this.approval,
  }) : super(key: key);

  @override
  State<AndroidEditBooking> createState() => _AndroidEditBookingState();
}

class _AndroidEditBookingState extends State<AndroidEditBooking> {
//---------------------------------------
// current page
//---------------------------------------
  int _currentIndex = 1;

  bool _initApplied = false;

  String _facilityId = '';
  DateTime? _origDate;
  String _origStartStr = '';
  String _origEndStr = '';
  String _origSeatText = '-';
  int _reasonLen = 0;
//---------------------------------------
// booking stream and facility steam
//---------------------------------------

  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _bookingStream;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _facilityStream;
  String _facilityStreamForId = '';

  String _facilityName = '';
  int _capacity = 0;
  final List<String> _timeChoices = <String>[];
  final Map<String, String> _startToEnd = <String, String>{};

  final List<DateTime> _dateChoices = <DateTime>[];
  DateTime? _selectedDate;
  String _selectedTime = '';
  int _selectedSeat = -1;


  final Map<String, int> _slotBooked = <String, int>{};


  Set<int> _offWeekdays = <int>{};
  Set<String> _offDatesYmd = <String>{};

  DateTime? _inactiveFrom;
  DateTime? _inactiveTo;

  // Reason (required only for accepted->amendment)
  final TextEditingController _reasonCtrl = TextEditingController();


  @override
  void initState() {
    super.initState();
//---------------------------------------
// get the booking from firebase
//---------------------------------------
    _bookingStream = FirebaseFirestore.instance
        .collection('Bookings')
        .doc(widget.bookingId)
        .snapshots();
//---------------------------------------
// after load working day and off day then create the next seven day from today
//---------------------------------------
    _loadWorkRules().then((_) {
      _buildNext6Days();
      if (mounted) setState(() {});
    });
    //---------------------------------------
// add listender for reason text box , max to 200 length
//---------------------------------------
    _reasonCtrl.addListener(() {
      setState(() => _reasonLen = _reasonCtrl.text.characters.length.clamp(0, 200));
    });
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

//---------------------------------------
// navigation bar page index
//---------------------------------------

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

//---------------------------------------
// format the date to day, date, month , year
//---------------------------------------
  String _formatFullDate(DateTime d) => DateFormat('EEE, d MMM yyyy').format(d);

  //---------------------------------------
// change to am pm
//---------------------------------------
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


  //---------------------------------------
// change (may not need this)
//---------------------------------------

  String _normalizeHHmm(String s) {
    String t = s.trim();
    final p = t.split(':');
    final hh = (p.isNotEmpty ? p[0] : '0').padLeft(2, '0');
    final mm = (p.length > 1 ? p[1] : '0').padLeft(2, '0');
    return '$hh:$mm';
  }

  //---------------------------------------
// parse hour to minute
//---------------------------------------

  int _minutesOf(String hhmm) {
    final p = hhmm.split(':');
    final h = int.tryParse(p[0]) ?? 0;
    final m = int.tryParse(p.length > 1 ? p[1] : '0') ?? 0;
    return h * 60 + m;
  }
//---------------------------------------
// change to slot key format
//---------------------------------------

  String _slotKey4FromHHmm(String s) => _normalizeHHmm(s).replaceAll(':', '');

  String _ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
//---------------------------------------
// change to date format
//---------------------------------------
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
//---------------------------------------
// get all the weeky day off
//---------------------------------------
  void _applyWeekdayOff(Map<String, dynamic> m) {
    void add(String k, int wd) {
      if (!m.containsKey(k)) return;
      final v = m[k];
      bool off = false;
      //---------------------------------------
// check if it is off or not off, then add to offweekday list
//---------------------------------------
      if (v is bool)
        off = !v;

      if (off)
        _offWeekdays.add(wd);
    }
    //---------------------------------------
// check by 1 by 1 using add
//---------------------------------------

    add('Monday', 1); add('Tuesday', 2); add('Wednesday', 3);
    add('Thursday', 4); add('Friday', 5); add('Saturday', 6); add('Sunday', 7);
  }

//---------------------------------------
// load not working day
//---------------------------------------

  Future<void> _loadWorkRules() async {
    _offWeekdays = <int>{};
    _offDatesYmd = <String>{};
    //---------------------------------------
// load week day off first
//---------------------------------------

    try {
      final ds = await FirebaseFirestore.instance.collection('SystemInformation').doc('Setting').get();
      if (ds.exists) {
        final m = ds.data();
        if (m != null) {
          _applyWeekdayOff(m);
        }
      }
    } catch (_) {}
    try {
//---------------------------------------
// then load off day
//---------------------------------------
      final off = await FirebaseFirestore.instance.collection('SystemInformation').doc('OffDays').get();
      if (off.exists) {
        final m = off.data();
        if (m != null && m['offDays'] is List) {
          for (final e in (m['offDays'] as List)) {
           _offDatesYmd.add(e);
          }
        }
      }
    } catch (_) {}
  }
//---------------------------------------
// check if it is pickable day or not
//---------------------------------------

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

//---------------------------------------
// get facility information
//---------------------------------------

  void _applyFacilityData(Map<String, dynamic> fac) {
    _facilityName = (fac['name'] ?? '').toString();
    _capacity = fac['availableSlots'] as int;
    _inactiveFrom = _dateOnly(fac['inactiveFrom']);
    _inactiveTo   = _dateOnly(fac['inactiveTo']);

    _timeChoices.clear();
    _startToEnd.clear();

    final dynamic arr = fac['customTimeSlots'];

    final List<Map<String, dynamic>> slots = <Map<String, dynamic>>[];
    int i = 0;
    while (i < arr.length) {
      final dynamic it = arr[i];
        slots.add(it);

      i = i + 1;
    }
    //---------------------------------------
// sort by start time
//---------------------------------------
    slots.sort((a, b) {
      final int sa = (a['startMin'] as int?) ?? 0;
      final int sb = (b['startMin'] as int?) ?? 0;
      return sa.compareTo(sb);
    });

//---------------------------------------
// add each time slot start and end into list
//---------------------------------------
    int j = 0;
    while (j < slots.length) {
      final Map<String, dynamic> it = slots[j];

      final String startHHmm = (it['start'] as String).trim(); // "09:00"
      final String endHHmm   = (it['end'] as String).trim();// "10:00"

      final String ns = _normalizeHHmm(startHHmm); // "09:00" -> "0900"
      final String ne = _normalizeHHmm(endHHmm); // "10:00" -> "1000"

      if (_startToEnd.containsKey(ns) == false) {
//---------------------------------------
// keep end time also in list
//---------------------------------------
        _timeChoices.add(ns);// add "0900"
        _startToEnd[ns] = ne;// map to "1000"
      }
      j = j + 1;
    }
  }

//---------------------------------------
// get the next six day from today
//---------------------------------------

  void _buildNext6Days() {
    _dateChoices.clear();
    //---------------------------------------
// add the date that can be pick into datechoices
//---------------------------------------

    final t = DateTime.now();
    for (int i = 0; i <= 6; i++) {
      _dateChoices.add(DateTime(t.year, t.month, t.day).add(Duration(days: i)));
    }
  }
//---------------------------------------
// check if selected day is today
//---------------------------------------

  bool _isSelectedDayToday() {
    if (_selectedDate == null) return false;
    final now = DateTime.now();
    final d = _selectedDate!;
    return now.year == d.year && now.month == d.month && now.day == d.day;
  }
//---------------------------------------
// check if the time already past for today
//---------------------------------------

  bool _isTimePastForSelectedDay(String hhmm) {
    if (!_isSelectedDayToday()) return false;
    final now = DateTime.now();
    return (now.hour * 60 + now.minute) >= _minutesOf(_normalizeHHmm(hhmm));
  }

  //---------------------------------------
// load the available slot for selected date
//---------------------------------------

  Future<void> _loadSlotForSelectedDate() async {
    _slotBooked.clear();
    if (_facilityId.isEmpty || _selectedDate == null) return;
    //---------------------------------------
// format slected date to yyyy-mm-dd
//---------------------------------------

    final ymd = _ymd(_selectedDate!);
    try {
      //---------------------------------------
// get the slot from facilities database
//---------------------------------------
      final q = await FirebaseFirestore.instance
          .collection('Facilities').doc(_facilityId)
          .collection('Days').doc(ymd)
          .collection('Slots')
          .get();
      for (final d in q.docs) {
        final key = d.id.trim();
        final m = d.data();
        int booked = 0;
        booked = m['booked'];
        _slotBooked[key] = booked;
      }
    } catch (_) {}
  }
//---------------------------------------
// check if same day
//---------------------------------------
  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  //---------------------------------------
// parse the seat from text to int
//---------------------------------------
  int _parseSeatText(String s) => int.tryParse(s) ?? -1;

  //---------------------------------------
// get the end time using start time in the list
//---------------------------------------
  String _lookupEndFromFacilityByStart(String start) {
    final s = _normalizeHHmm(start);
    final e = _startToEnd[s];
    return e == null ? '' : _normalizeHHmm(e);
  }

//---------------------------------------
// confirm cancel booking pop up
//---------------------------------------
  Future<bool> _confirmDeleteDialog() async {
    final bool? yes = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // cannot tap outside to close
      builder: (ctx) {
        return AlertDialog(
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
//---------------------------------------
// cancel button return false
//---------------------------------------
            TextButton(
              onPressed: () { Navigator.of(ctx).pop(false); },
              child: Text('Cancel', style: TextStyle(fontSize: 14.sp)),
            ),
//---------------------------------------
// true button return true
//---------------------------------------
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


//---------------------------------------
// delete proccess
//---------------------------------------

  Future<void> _onDelete() async {
//---------------------------------------
// pop up to ask user
//---------------------------------------
    final bool ok = await _confirmDeleteDialog();
    if (ok != true) return;

    try {
      //---------------------------------------
// get the booking id
//---------------------------------------
      final doc = await FirebaseFirestore.instance.collection('Bookings')
          .doc(widget.bookingId).get();
      if (!doc.exists || doc.data() == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Booking not found')));
        return;
      }

      final m = doc.data()!;
      String facilityId = (m['facilityId']).toString().trim();
      final String userId = (m['userId']).toString().trim();
      String managerId = (m['managerId']).toString().trim();
      final int seatIndex = m['seatIndex'] as int;
      final String start = m['start'];
      final String end   = m['end'];
      final String bookingDate = m['bookingDate'];

//---------------------------------------
// find current user
//---------------------------------------
      final String actor = FirebaseAuth.instance.currentUser?.uid ?? '';
//---------------------------------------
// cancel this booking using booking service
//---------------------------------------
      await BookingService.deleteAcceptedBookingByIdTx(bookingId: widget.bookingId);
//---------------------------------------
// send deleted mails
//---------------------------------------
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

//---------------------------------------
// delete button design
//---------------------------------------
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
 //---------------------------------------
// display cancel text
//---------------------------------------
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

//---------------------------------------
// find if there is overlap booking
//---------------------------------------
  Future<Map<String, String>?> _findOverlapWithMyOtherBookings({
    required String userId,
    required String dateYMD,
    required String newStart,
    required String newEnd,
    required String excludeBookingId,
  }) async {
    try {
//---------------------------------------
// get the booking date
//---------------------------------------
      final normalcheck = await FirebaseFirestore.instance
          .collection('Bookings')
          .where('userId', isEqualTo: userId)
          .where('bookingDate', isEqualTo: dateYMD)
          .get();
//---------------------------------------
// format them to minute format
//---------------------------------------
      final int newS = _minutesOf(_normalizeHHmm(newStart));
      final int newE = _minutesOf(_normalizeHHmm(newEnd));

      for (final d in normalcheck.docs) {
        if (d.id == excludeBookingId) continue;
        final m = d.data();
        if (m['deleted'] == true) continue;

        final ap = (m['approval'] ?? '').toString().toLowerCase().trim();
        if (!(ap == 'accepted' || ap == 'pending')) continue;

        String s = (m['start']).toString();
        String e = (m['end'] ).toString();

//---------------------------------------
// convert to minute
//---------------------------------------
        final int sM = _minutesOf(s);
        final int eM = _minutesOf(e);

        //---------------------------------------
// check both if overlap or not
//---------------------------------------
        if (newS < eM && newE > sM) {
          return {'start': s, 'end': e};
        }
      }

//---------------------------------------
// check for amendment request overlap
//---------------------------------------
      final apcheck = await FirebaseFirestore.instance
          .collection('Bookings')
          .where('userId', isEqualTo: userId)
          .where('hasPendingAmendment', isEqualTo: true)
          .where('amendmentPreview.bookingDate', isEqualTo: dateYMD)
          .get();

      for (final d in apcheck.docs) {
        if (d.id == excludeBookingId) continue;
        final m = d.data();
        final Map<String, dynamic>? p = (m['amendmentPreview'] as Map<String, dynamic>?);
        if (p == null) continue;

        String s = p['start'];
        String e = p['end'];

        final int sM = _minutesOf(s);
        final int eM = _minutesOf(e);

        if (newS < eM && newE > sM) return {'start': s, 'end': e};
      }
    } catch (_) {}
    return null; // no overlap found
  }
//---------------------------------------
// when confirm is press
//---------------------------------------

  Future<void> _onConfirm() async {
    //---------------------------------------
// make validation first
//---------------------------------------
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
//---------------------------------------
// check of seat is taken or no
//---------------------------------------
    final bool ok = await _validateSeatAvailable();
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Selected slot just got taken. Please pick another one.', style: TextStyle(fontSize: 13.sp))),
      );
      return;
    }
//---------------------------------------
// get start time and end time
//---------------------------------------
    final String newStart = _normalizeHHmm(_selectedTime);
    String newEnd = _startToEnd.containsKey(newStart) ? _startToEnd[newStart]! : '';
    final String newDateYMD = _ymd(_selectedDate!);
    final String newSlotKey = _slotKey4FromHHmm(newStart);
    final int newSeat = _selectedSeat;

    try {
      //---------------------------------------
// get the booking id
//---------------------------------------
      final doc = await FirebaseFirestore.instance.collection('Bookings').doc(widget.bookingId).get();
      if (!doc.exists || doc.data() == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Booking not found', style: TextStyle(fontSize: 13.sp))));
        return;
      }
      final Map<String, dynamic> b = doc.data()!;
      //---------------------------------------
// get the user id
//---------------------------------------

      String userId = (b['userId'] ?? '').toString();
      if (userId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not verify user on booking', style: TextStyle(fontSize: 13.sp))));
        return;
      }
      //---------------------------------------
// check the approal and status
//---------------------------------------

      final String approvalStr = (b['approval'] ?? '').toString().toLowerCase().trim();
      final String statusStr   = (b['status']   ?? '').toString().toLowerCase().trim();
      final bool isAcceptedUpcoming = (approvalStr == 'accepted' && statusStr == 'upcoming');

      //---------------------------------------
// get the manager id
//---------------------------------------
      String managerId = (b['managerId'] ?? '').toString().trim();
      if (managerId.isEmpty) {
        try {
          final facSnap = await FirebaseFirestore.instance.collection('Facilities').doc(_facilityId).get();
          final fac = facSnap.data();
          if (fac != null) {
            managerId = (fac['managerId'] ).toString().trim();
          }
        } catch (_) {}
      }
//---------------------------------------
// get the actor which is the one who make this booking or edit this booking
//---------------------------------------
      final String actorUid = FirebaseAuth.instance.currentUser?.uid ?? '';

//---------------------------------------
// check if there is overlap booking
//---------------------------------------
      final overlap = await _findOverlapWithMyOtherBookings(
        userId: userId,
        dateYMD: newDateYMD,
        newStart: newStart,
        newEnd: newEnd,
        excludeBookingId: widget.bookingId,
      );
      //---------------------------------------
// if there is overlap
//---------------------------------------

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
//---------------------------------------
// if is accepted and upcomig means its request amendment, so user need to enter reason, validate reason as well
//---------------------------------------
      if (isAcceptedUpcoming) {
        final String reason = _reasonCtrl.text.trim();
        if (reason.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:
          Text('Please enter your reason', style: TextStyle(fontSize: 13.sp))));
          return;
        }
//---------------------------------------
// store new amendment sub collection
//---------------------------------------
        final amendCol = FirebaseFirestore.instance
            .collection('Bookings').doc(widget.bookingId)
            .collection('Amendments');

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
//---------------------------------------
// also keep the original one
//---------------------------------------
          'original': b,
          'seen':false,
        };

        final ref = await amendCol.add(data);
//---------------------------------------
// get the amendment id
//---------------------------------------
        await ref.set({'amendmentId': ref.id}, SetOptions(merge: true));

//---------------------------------------
// also add some important field into booking id
//---------------------------------------
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

//---------------------------------------
// then set new seat in facility but taken is  = false
//---------------------------------------
        try {
          await FirebaseFirestore.instance
              .collection('Facilities').doc(_facilityId)
              .collection('Days').doc(newDateYMD)
              .collection('Slots').doc(newSlotKey)
              .collection('Seats').doc(newSeat.toString())
              .set({'taken': false, 'updatedAt': FieldValue.serverTimestamp()},
              SetOptions(merge: true));
        } catch (_) {}

//---------------------------------------
// then send amendment pending mails
//---------------------------------------
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

//---------------------------------------
// for pending booking after confrim edit set new value into the database
//---------------------------------------

      final WriteBatch batch = FirebaseFirestore.instance.batch();
      final bookingRef = FirebaseFirestore.instance.collection('Bookings').doc(widget.bookingId);

      final Map<String, dynamic> patch = <String, dynamic>{
        'facilityId': _facilityId,
        'bookingDate': newDateYMD,
        'slotKey': newSlotKey,
        'start': newStart,
        'end': newEnd,
        'seatIndex': newSeat,
        'approval': 'pending', // keep pending (all bookings require approval)
        'seen': false, // set the seen back to false
        'userSeen': false,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      batch.set(bookingRef, patch, SetOptions(merge: true));

//---------------------------------------
// also set taken = false in facilities seat
//---------------------------------------
      final seatRef = FirebaseFirestore.instance
          .collection('Facilities').doc(_facilityId)
          .collection('Days').doc(newDateYMD)
          .collection('Slots').doc(newSlotKey)
          .collection('Seats').doc(newSeat.toString());
      batch.set(seatRef, {'taken': false, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));

      await batch.commit();

//---------------------------------------
// send prending mails
//---------------------------------------
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

//---------------------------------------
// check wether the slot is available
//---------------------------------------

  Future<bool> _validateSeatAvailable() async {
    if (_selectedDate == null || _selectedTime.isEmpty || _selectedSeat <= 0)
      return false;
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
      if (m == null)
        return true;
      final v = m['taken'];
      if (v is bool)
        return v == false;

      return true;
    } catch (_) {
      return true;
    }
  }
  //---------------------------------------
// display seat slot for selected time
//---------------------------------------

  Widget _buildSeatPickerForSelectedTime() {
    //---------------------------------------
// makesure time is slected
//---------------------------------------

    if (_selectedTime.isEmpty || _selectedDate == null) {
      return const SizedBox.shrink();
    }

    final String ymd = _ymd(_selectedDate!);
    final String slotKey4 = _slotKey4FromHHmm(_selectedTime);
    final String timeLabel = _toAmPmDot(_selectedTime);

    // capacity (allow per-slot override if you keep that map; else just _capacity)
    final int cap =  _capacity;
//---------------------------------------
// use the stream to check the seats
//---------------------------------------

    final Stream<QuerySnapshot<Map<String, dynamic>>> seatsStream =
    FirebaseFirestore.instance
        .collection('Facilities').doc(_facilityId)
        .collection('Days').doc(ymd)
        .collection('Slots').doc(slotKey4)
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
      //---------------------------------------
// display time label above
//---------------------------------------

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(timeLabel, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700)),
          SizedBox(height: 10.h),

          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: seatsStream,
            builder: (context, snap) {
//---------------------------------------
// get the taken seat
//---------------------------------------

              final Set<int> taken = <int>{};
              if (snap.hasData) {
                for (final d in snap.data!.docs) {

                  final int idx = int.parse(d.id);
                  if (idx <= 0) continue;

                  final v = d.data()['taken'];
                  bool isTaken = false;
                  if (v is bool) isTaken = v;
                  if (isTaken)
                    taken.add(idx);
                }
              }

//---------------------------------------
// while using the stream to rebuild , if sudenly the seat was taken mmake user back to not slected any slot
//---------------------------------------
              if (_selectedSeat > 0 && taken.contains(_selectedSeat)) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _selectedSeat = -1);
                });
              }

//---------------------------------------
// start to build the chip
//--------------------------------------
              return LayoutBuilder(
                builder: (context, bc) {
                  final double gap = 8.w;
                  final double chipW = (bc.maxWidth - (gap * 2.0)) / 3.0;

                  final List<Widget> chips = <Widget>[];
                  for (int k = 1; k <= cap; k++) {
 //---------------------------------------
// of the seat taken list contain the k number
//---------------------------------------
                    final bool isTaken = taken.contains(k);
 //---------------------------------------
// if its selected
//---------------------------------------
                    final bool isChosen = _selectedSeat == k && !isTaken;
                    Color fill, border, text;
                    double bw = isChosen ? 2.0.w : 1.5.w;

                    if (isTaken) {
                      fill   = const Color(0xFFFFE7E9);
                      border = const Color(0xFFFF6B7A);
                      text   = const Color(0xFFB00020);
                    } else if (isChosen) {
                      fill   = const Color(0xFF9747FF);
                      border = const Color(0xFF4A00B8);
                      text   = Colors.white;
                    } else {
                      fill   = const Color(0xFFB779F1);
                      border = const Color(0xFF6E00D4);
                      text   = Colors.white;
                    }
//---------------------------------------
// if teh slot is tap, selected seat is tht chip, if tap again will will be k means is selected
//---------------------------------------

                    final VoidCallback? onTap = isTaken ? null : () {
                      setState(() => _selectedSeat = isChosen ? -1 : k);
                    };
//---------------------------------------
// add each chip
//---------------------------------------
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
                              child: Text('Slot $k',
                                  style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: text)),
                            ),
                          ),
                        ),
                      ),
                    );
                  }
//---------------------------------------
// return teh chip using wrap
//---------------------------------------
                  return Wrap(spacing: gap, runSpacing: gap, children: chips);
                },
              );
            },
          ),
        ],
      ),
    );
  }

//---------------------------------------
// main build
//---------------------------------------
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
//---------------------------------------
// stream builder of booking
//---------------------------------------
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

//---------------------------------------
// get the booking facility id
//---------------------------------------
          String fid = (bk['facilityId'] ).toString();
          if (_facilityId.isEmpty)
            _facilityId = fid;

//---------------------------------------
// get the facility id from facility database
//---------------------------------------
          if (_facilityStream == null || _facilityStreamForId != fid) {
            _facilityStream = FirebaseFirestore.instance
                .collection('Facilities')
                .doc(fid)
                .snapshots();
            _facilityStreamForId = fid;
          }

//---------------------------------------
// get the booking date
//---------------------------------------

          DateTime? bd;
          bd = _dateOnly(bk['bookingDate']);

//---------------------------------------
// get start adn end time
//---------------------------------------
          final String st = (bk['start'] ).toString();
          final String et = (bk['end'] ).toString();

//---------------------------------------
// get the seat index
//---------------------------------------
          String seatText = '-';
          seatText = bk['seatIndex'].toString();

//---------------------------------------
// apply it to original variable then get the amount of booked
//---------------------------------------
          if (!_initApplied) {
            _origDate = bd;
            _origStartStr = st;
            _origEndStr = et;
            _origSeatText = seatText;

            _selectedDate = bd ?? DateTime.now();
            _selectedTime = st.isNotEmpty ? _normalizeHHmm(st) : '';
            _selectedSeat = seatText != '-' ? (int.tryParse(seatText) ?? -1) : -1;

            _initApplied = true;
//---------------------------------------
// get how many booked it have
//---------------------------------------
            _loadSlotForSelectedDate();
          }
//---------------------------------------
// if no facility id
//---------------------------------------

          if (_facilityId.isEmpty) {
            return Center(child: Text('Missing facility info', style: TextStyle(fontSize: 14.sp)));
          }
//---------------------------------------
// get sattus and approval
//---------------------------------------
          final String approvalStr = (bk['approval'] ).toString().toLowerCase().trim();
          final String statusStr   = (bk['status'] ).toString().toLowerCase().trim();
//---------------------------------------
// check if it is amnedment or not
//---------------------------------------
          final bool isAcceptedUpcoming =
              (approvalStr == 'accepted' ) && statusStr == 'upcoming';


//---------------------------------------
// get teh facility data
//---------------------------------------
          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: _facilityStream,
            builder: (context, facSnap) {
              if (facSnap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!facSnap.hasData || !facSnap.data!.exists) {
                return Center(child: Text('Facility not found', style: TextStyle(fontSize: 14.sp)));
              }
//---------------------------------------
// get the facility information
//---------------------------------------
              final Map<String, dynamic> fac = facSnap.data!.data()!;
              _applyFacilityData(fac);
              _loadSlotForSelectedDate();

              return SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
//---------------------------------------
// have a cancel button at top
//---------------------------------------
                    Row(mainAxisAlignment: MainAxisAlignment.end, children: <Widget>[_buildDeleteButton()]),
                    SizedBox(height: 10.h),


                    Container(
                      width: sw * 0.95,
                      padding: EdgeInsets.all(14.w),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE9D7FF),
                        borderRadius: BorderRadius.circular(14.r),
                        boxShadow: <BoxShadow>[BoxShadow(color: const Color(0x22000000), blurRadius: 8.r, offset: Offset(0, 3.h))],
                      ),
//---------------------------------------
// use kv line to display facility , boking date, booking time and slot number
//---------------------------------------
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

//---------------------------------------
// date header and calender
//---------------------------------------
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Text(DateFormat('MMMM yyyy').format(_selectedDate ?? DateTime.now()),
                            style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600)),
                        SizedBox(width: 8.w),
//---------------------------------------
// show calender
//---------------------------------------
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
//---------------------------------------
// calender pickable day
//---------------------------------------
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: initial,
                                firstDate: first,
                                lastDate: last,
                                helpText: 'Select date',
//---------------------------------------
// slectable day
//---------------------------------------
                                selectableDayPredicate: (d) => !d.isBefore(first) && !d.isAfter(last) && _isPickableDay(d),
                              );
                              if (picked != null) {
                                setState(() {
                                  _selectedDate = DateTime(picked.year, picked.month, picked.day);
                                  _selectedTime = '';
                                  _selectedSeat = -1;
                                  _buildNext6Days();
                                });
                                _loadSlotForSelectedDate();
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

//---------------------------------------
// show next six day and check if it is pickable day
//---------------------------------------
                    Row(
                      children: List.generate(_dateChoices.length, (i) {
                        final d = _dateChoices[i];
                        final enabled = _isPickableDay(d);
                        final c = enabled ? Colors.black87 : Colors.black38;
                        return Expanded(child: Center
                          (child: Text(DateFormat('E').format(d)[0], style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600, color: c))));
                      }),
                    ),

                    SizedBox(height: 6.h),

//---------------------------------------
// the date of the six day and do the same as above
//---------------------------------------
                    Row(
                      children: List.generate(_dateChoices.length, (i) {
                        final d = _dateChoices[i];
                        final isSelected = _selectedDate != null && _sameDay(d, _selectedDate!);
                        final enabled = _isPickableDay(d);
                        final bg = isSelected ? const Color(0xFF9747FF) : Colors.transparent;
                        final fg = isSelected ? Colors.white : (enabled ? Colors.black87 : Colors.black38);

//---------------------------------------
// when press ,will change the date to selected date, and remove selected slot and seat
//---------------------------------------
                        return Expanded(
                          child: Center(
                            child: InkWell(
                              onTap: enabled ? () {
                                setState(() { _selectedDate = d; _selectedTime = ''; _selectedSeat = -1; });
                                _loadSlotForSelectedDate();
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
//---------------------------------------
// a devider
//---------------------------------------
                    SizedBox(height: 12.h),
                    Container(width: 1.0.sw, height: 1.h, color: Colors.black12),
                    SizedBox(height: 12.h),

//---------------------------------------
// show time slotips
//---------------------------------------

                    Align(alignment: Alignment.centerLeft, child: Text('Time Slot Available', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700))),
                    SizedBox(height: 6.h),

                    SizedBox(height: 12.h),
//---------------------------------------
// show each time chip
//---------------------------------------
                    LayoutBuilder(
                      builder: (context, bc) {
                        final double maxW = bc.maxWidth;
                        final double gap = 8.w;
                        final double itemW = (maxW - (gap * 2.0)) / 3.0;

                        final List<Widget> chips = <Widget>[];
                        for (final hhmm in _timeChoices) {
                          final key4 = _slotKey4FromHHmm(hhmm);
                          int capForThis = _capacity;
                          int booked = _slotBooked[key4] ?? 0;


//---------------------------------------
// check if time slot is full
//---------------------------------------
                          final bool isFull = booked >= capForThis;
//---------------------------------------
// check if the time already past for today
//---------------------------------------
                          final bool isPast = _isTimePastForSelectedDay(hhmm);
//---------------------------------------
// selected time
//---------------------------------------
                          final bool selected = _selectedTime == hhmm && !isPast;
//---------------------------------------
// allow tap chip must be not full and not pass
//---------------------------------------
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

//---------------------------------------
//  each of the button
//---------------------------------------
                          chips.add(
                            ConstrainedBox(
                              constraints: BoxConstraints.tightFor(width: itemW, height: 44.h),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
//---------------------------------------
// check if it is is allow tap only allow set state
//---------------------------------------
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
//---------------------------------------
// display time
//---------------------------------------
                                    child: Text(_toAmPmDot(hhmm), maxLines: 1, overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: textColor)),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }
//---------------------------------------
// return all teh chip and wrap it
//---------------------------------------
                        return Align(alignment: Alignment.centerLeft, child: Wrap(spacing: gap, runSpacing: gap, children: chips));
                      },
                    ),

                    SizedBox(height: 16.h),

//---------------------------------------
// display slot picker for selected time
//---------------------------------------
                    if (_selectedTime.isNotEmpty)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Align(alignment: Alignment.centerLeft, child: Text('Slot Available', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700))),
                          SizedBox(height: 8.h),
//---------------------------------------
// display the seat picker for each sit
//---------------------------------------
                          _buildSeatPickerForSelectedTime(),
                        ],
                      ),

                    SizedBox(height: 18.h),

//---------------------------------------
// reason for ammendment
//---------------------------------------
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
//---------------------------------------
// the counter
//---------------------------------------
                          Positioned(
                            right: 10.w,
                            bottom: 8.h,
                            child: Text('$_reasonLen/200', style: TextStyle(fontSize: 12.sp, color: Colors.black54)),
                          ),
                        ],
                      ),
                      SizedBox(height: 18.h),
                    ],
//---------------------------------------
// confirm button
//---------------------------------------
                    SizedBox(
                      width: sw * 0.95,
                      height: 48.h,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF9747FF),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28.r)),
                        ),
//---------------------------------------
// if it is amendment the user submit amendment, if normal edit, use confirm
//---------------------------------------
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
//---------------------------------------
// bottom navigation bar
//---------------------------------------
      bottomNavigationBar: BottomMenuBar(
        height: 0.07.sh,
        currentIndex: _currentIndex,
        onTabSelected: _onTabSelected,
      ),
    );
  }
}

//---------------------------------------
// kv line that display information
//---------------------------------------

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


