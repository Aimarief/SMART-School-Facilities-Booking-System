import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:smart_school_facilities_booking_system/notification_service.dart';
import 'web_booking_details.dart';
import 'package:smart_school_facilities_booking_system/booking_service.dart';


Future<void> openWebEditBookingDialog({
  required BuildContext context,
  required Map<String, dynamic> booking,
  required String bookingId,
  required String facilityId,
  required String bookedByUid,
  required String managerUid,
  required String userUid,
  required String dateYMD,
  required String timeStart,
  required String timeEnd,
  required String seatIndex,
  required String approval,
  required String status,
  bool use24HourFormat = false,
}) async {
  await showDialog(
    context: context,
    barrierDismissible: true,
    builder: (_) {
      return Dialog(
        insetPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
        child: WebEditBooking(
          rawBooking: booking,
          bookingId: bookingId,
          facilityId: facilityId,
          bookedByUid: bookedByUid,
          managerUid: managerUid,
          userUid: userUid,
          dateYMD: dateYMD,
          timeStart: timeStart,
          timeEnd: timeEnd,
          seatIndex: seatIndex,
          approval: approval,
          status: status,
          use24HourFormat: use24HourFormat,
        ),
      );
    },
  );
}

class WebEditBooking extends StatefulWidget {
  final Map<String, dynamic> rawBooking;

  final String bookingId;
  final String facilityId;
  final String bookedByUid;
  final String managerUid;
  final String userUid;
  final String dateYMD;
  final String timeStart;
  final String timeEnd;
  final String seatIndex;
  final String approval;
  final String status;
  final bool use24HourFormat;

  const WebEditBooking({
    Key? key,
    required this.rawBooking,
    required this.bookingId,
    required this.facilityId,
    required this.bookedByUid,
    required this.managerUid,
    required this.userUid,
    required this.dateYMD,
    required this.timeStart,
    required this.timeEnd,
    required this.seatIndex,
    required this.approval,
    required this.status,
    this.use24HourFormat = false,
  }) : super(key: key);

  @override
  State<WebEditBooking> createState() => _WebEditBookingState();
}

class _WebEditBookingState extends State<WebEditBooking> {
//---------------------------------------
// colour that will be used
//---------------------------------------

  final Color _cSelected = const Color(0xFFB779F1);
  final Color _cFullRed  = Colors.red;
  final Color _cAvailBg  = Colors.white;
  final Color _cAvailBrd = const Color(0xFFE5E7EB);
  final Color _cAvailTxt = const Color(0xFF111827);
  final Color _cPanelBg  = const Color(0xFFF9F4FF);
  final Color _cPastBg  = const Color(0xFFE5E7EB);
  final Color _cPastTxt = const Color(0xFF9CA3AF);


  DateTime? _selectedDate;
  String _selectedYMD = '';
  String _selectedSlotKey = '';
  int _selectedSeatIndex = -1;


  int _facilitySeatCapacity = 0;
  final List<Map<String, String>> _timeSlots = <Map<String, String>>[];

  // booked map for selected date: slotKey -> booked count
  final Map<String, int> _dayBooked = <String, int>{};

  List<bool> _weekdayOpen = <bool>[true, true, true, true, true, true, true]; // Monday..Sunday
  final Set<String> _offDateYMD = <String>{};

  final List<bool> _seatTaken = <bool>[]; // length == _facilitySeatCapacity

  bool _loadingSettings = false;
  bool _loadingFacility = false;
  bool _loadingDayBooked = false;
  bool _loadingSeats = false;

//---------------------------------------
// run init state first
//---------------------------------------

  @override
  void initState() {
    super.initState();

//---------------------------------------
// set the date first
//---------------------------------------
    if (widget.dateYMD.isNotEmpty) {
      final d = _parseYMD(widget.dateYMD);
      if (d != null) {
        _selectedDate = d;
        _selectedYMD = widget.dateYMD;
      }
    }
//---------------------------------------
// load off day and facility configuration
//---------------------------------------
    _loadSettingsAndOffDays();
    _loadFacilityConfig().then((_) async {
      // after we know time slots and capacity, load the day booked map
      if (_selectedYMD.isNotEmpty) {
        await _loadDayBookedMap(_selectedYMD);
      }
    });
  }

  DateTime? _inactiveFrom;
  DateTime? _inactiveTo;

//---------------------------------------
// change to date format to real date
//---------------------------------------

  DateTime? _dateOnly(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) {
      final dt = v.toDate();
      return DateTime(dt.year, dt.month, dt.day);
    }
    if (v is DateTime) return DateTime(v.year, v.month, v.day);
    if (v is String) {
      final p = DateTime.tryParse(v);
      if (p != null) return DateTime(p.year, p.month, p.day);
    }
    return null;
  }

//---------------------------------------
// cehck if it is within inactive range
//---------------------------------------
  bool _isWithinInactiveRange(DateTime d) {
    if (_inactiveFrom == null || _inactiveTo == null) return false;
    final dd = DateTime(d.year, d.month, d.day);
    return !dd.isBefore(_inactiveFrom!) && !dd.isAfter(_inactiveTo!);
  }

//---------------------------------------
// check if taht date is selectable
//---------------------------------------

  bool _isSelectable(DateTime d) {
    if (_isHoliday(d)) return false;
    if (!_isWorkingDay(d)) return false;
    if (_isWithinInactiveRange(d)) return false;
    return true;
  }

//---------------------------------------
// proccess teh selected date
//---------------------------------------

  DateTime? _firstSelectable(DateTime first, DateTime last, DateTime preferred) {
    if (_isSelectable(preferred)) return preferred;

    var cur = preferred;
    while (!cur.isAfter(last)) {
      if (_isSelectable(cur)) return cur;
      cur = cur.add(const Duration(days: 1));
    }
    cur = preferred;
    while (!cur.isBefore(first)) {
      if (_isSelectable(cur)) return cur;
      cur = cur.subtract(const Duration(days: 1));
    }
    return null;
  }

//---------------------------------------
// check if there is booking conflict with their own time
//---------------------------------------
  Future<String> _checkUserConflictForInterval({
    required String userId,
    required String dateYMD,
    required String newStartHHmm,
    required String newEndHHmm,
  }) async {
    try {

      final String nS = _normalizeHHmm(newStartHHmm);
      String nE = _normalizeHHmm(newEndHHmm);
      if (nE.isEmpty) nE = _endForStartForConflict(nS);
      final int newS = _hmToMinutes(nS);
      final int newE = _hmToMinutes(nE);

//---------------------------------------
// get from database for this user all booking time that belongs to the booking date
//---------------------------------------
      final qs = await FirebaseFirestore.instance
          .collection('Bookings')
          .where('userId', isEqualTo: userId)
          .where('bookingDate', isEqualTo: dateYMD)
          .where('deleted', isEqualTo: false)
          .get();

      for (final d in qs.docs) {
//---------------------------------------
// ignore it self booking id
//---------------------------------------
        if (d.id == widget.bookingId) continue;
        final m = d.data();

        if ((m['deleted'] ?? false) == true) continue;

        // keep only accepted/approved/pending
        final ap = (m['approval'] ?? '').toString().toLowerCase().trim();
        final keep = ap == 'accepted' || ap == 'pending';
        if (!keep) continue;

        // existing start
        String s = (m['start'] ).toString();
        s = _normalizeHHmm(s);
        if (s.isEmpty) continue;

        // existing end (doc -> facility map -> +60)
        String e = (m['end']).toString();
        e = _normalizeHHmm(e);
        if (e.isEmpty) e = _endForStartForConflict(s);

        final int exS = _hmToMinutes(s);
        final int exE = _hmToMinutes(e);
//---------------------------------------
// cehck if they overlap
//---------------------------------------
        if (_rangesOverlapStrict(newS, newE, exS, exE)) {
          return 'Overlap with other booking ${_rangeText(s, e)}. '
              'New time ${_rangeText(nS, nE)} is not allowed.';
        }
      }
      return '';
    } catch (_) {
      return 'Could not verify other bookings. Please try again.';
    }
  }


//---------------------------------------
// chagne minute back to  HH:MM
//---------------------------------------
  String _minutesToHHmm(int mins) {
    int h = mins ~/ 60;
    int m = mins % 60;
    if (h < 0) { h = 0; } else { if (h > 23) { h = 23; } }
    if (m < 0) { m = 0; } else { if (m > 59) { m = 59; } }
    final String hh = h.toString().padLeft(2, '0');
    final String mm = m.toString().padLeft(2, '0');
    return hh + ':' + mm;
  }

//---------------------------------------
// check the time end, if not time end then assume end after 1 hour
//---------------------------------------
  String _endForStartForConflict(String startHHmm) {
    String end = '';
    final String sNorm = _normalizeHHmm(startHHmm);

    // build start->end map from _timeSlots
    final Map<String, String> map = <String, String>{};
    int i = 0;
    while (i < _timeSlots.length) {
      final Map<String, String> it = _timeSlots[i];
      String st = '';
      String en = '';
      if (it.containsKey('start')) { st = (it['start'] ?? '').trim(); }
      if (it.containsKey('end'))   { en = (it['end'] ?? '').trim(); }
      if (st.isNotEmpty == true && en.isNotEmpty == true) {
        map[_normalizeHHmm(st)] = _normalizeHHmm(en);
      }
      i = i + 1;
    }

    if (map.containsKey(sNorm) == true) {
      end = map[sNorm]!;
    }

    if (end.isEmpty == true) {
      final int sM = _hmToMinutes(sNorm);
      end = _minutesToHHmm(sM + 60);
    }

    return _normalizeHHmm(end);
  }

//---------------------------------------
// check if they overlap
//---------------------------------------
  bool _rangesOverlapStrict(int aStart, int aEnd, int bStart, int bEnd) {
    if (aStart < bEnd) {
      if (aEnd > bStart) {
        return true;
      } else {
        return false;
      }
    } else {
      return false;
    }
  }

//---------------------------------------
// label range for the time
//---------------------------------------

  String _rangeText(String s, String e) {
    return _fmtHHmm(s) + ' - ' + _fmtHHmm(e);
  }


//---------------------------------------
// when confirm is pressed, the proccess
//---------------------------------------

  Future<void> _onConfirm() async {

//---------------------------------------
// make sure everthing is here
//---------------------------------------

    if (_selectedYMD.isEmpty) {
      _toast('Please pick a date.');
      return;
    }
    if (_selectedSlotKey.isEmpty) {
      _toast('Please pick a time slot.');
      return;
    }
    if (_selectedSeatIndex < 0) {
      _toast('Please pick a seat.');
      return;
    }

    final int seatIndex1Based = _selectedSeatIndex + 1;

    // get start/end labels from the UI slot you chose
    String selStart = '';
    String selEnd = '';
    final Map<String, String> ts = _timeSlots.firstWhere(
          (m) => (m.containsKey('key') && m['key'] == _selectedSlotKey),
      orElse: () => <String, String>{},
    );
    if (ts.isNotEmpty) {
      if (ts.containsKey('start')) {
        selStart = (ts['start'] ?? '').trim();
      }
      if (ts.containsKey('end')) {
        selEnd = (ts['end'] ?? '').trim();
      }
    }

    if (selStart.isEmpty) {
      _toast('Please pick a time slot.');
      return;
    }

    String selEndForCheck = selEnd;
    if (selEndForCheck.isEmpty) {
      selEndForCheck = _endForStartForConflict(selStart);
    }
    selEndForCheck = _normalizeHHmm(selEndForCheck); // normalize

//---------------------------------------
// turn them to hhmm make sure end time > start time
//---------------------------------------
    final int sM = _hmToMinutes(_normalizeHHmm(selStart));
    final int eM = _hmToMinutes(selEndForCheck);
    if (!(sM < eM)) {
      _toast('End time must be after start time.');
      return;
    }
//---------------------------------------
// check for booking conflict
//---------------------------------------
    final String reason = await _checkUserConflictForInterval(
      userId: widget.bookedByUid,
      dateYMD: _selectedYMD,
      newStartHHmm: selStart,
      newEndHHmm: selEndForCheck,
    );
    if (reason.isNotEmpty) {
      _toast(reason);
      return;
    }

    final ok = await _busy(() async {
      await BookingService.moveAcceptedBookingByIdTx(
        bookingId: widget.bookingId,
        newFacilityId: widget.facilityId,
        newDateYMD: _selectedYMD,
        newSlotKey: _selectedSlotKey,
        newSeatIndex: seatIndex1Based,
        newStartStr: _normalizeHHmm(selStart),
        newEndStr: selEndForCheck,
      );
    });

    if (!ok) return;
//---------------------------------------
// after booking is made then make notification
//---------------------------------------

    final String bookedBy = FirebaseAuth.instance.currentUser?.uid ?? '-';
    final String userId   = widget.userUid;
    final String facility = widget.facilityId;
    String managerId = widget.managerUid.trim().isEmpty ? '-' : widget.managerUid.trim();

    await NotificationService.sendBookingUpdatedMails(
      bookingId: widget.bookingId,
      userId: userId,                     // owner (booker)
      bookedBy: bookedBy,                 // actor who edited
      facilityId: facility,
      managerId: managerId,
      approval: widget.approval,
      seatIndex: seatIndex1Based,         // 1-based
      bookingDate: _selectedYMD,          // "YYYY-MM-DD"
      start: _normalizeHHmm(selStart),    // "HH:MM"
      end: selEndForCheck,                // "HH:MM"
    );

//---------------------------------------
// after update successfully, will close pop up at bring the new information back to boking details immediately
//---------------------------------------

    final updated = Map<String, dynamic>.from(widget.rawBooking);
    updated['bookingDate'] = _selectedYMD;
    updated['slotKey'] = _selectedSlotKey;
    updated['seatIndex'] = seatIndex1Based;
    updated['start'] = _normalizeHHmm(selStart);
    updated['end'] = selEndForCheck; // always a normalized, non-empty end

    if (!mounted) return;
    Navigator.of(context).pop();
    await openWebBookingDetailsDialog(
      context: context,
      booking: updated,
      use24HourFormat: widget.use24HourFormat,
    );
  }

//---------------------------------------
// change hour to hh:mm format
//---------------------------------------

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
//---------------------------------------
// change hour and minute to minute
//---------------------------------------

  int _hmToMinutes(String s) {
    final String n = _normalizeHHmm(s);
    final List<String> p = n.split(':');
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
//---------------------------------------
//change time to something like 8.30
//---------------------------------------

  String _fmtHHmm(String s) {
    // label like "08.30"
    final String n = _normalizeHHmm(s);
    final List<String> p = n.split(':');
    if (p.length >= 2) {
      return p[0].padLeft(2, '0') + '.' + p[1].padLeft(2, '0');
    } else {
      return n;
    }
  }


//---------------------------------------
// when waiting show loading
//---------------------------------------

  Future<bool> _busy(Future<void> Function() task) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      await task();
      return true;
    } catch (e) {
      _toast(_niceError(e));
      return false;
    } finally {
      if (mounted) Navigator.of(context).pop();
    }
  }

//---------------------------------------
// show error
//---------------------------------------

  String _niceError(Object e) {
    final s = e.toString();

    if (s.contains('Slot is full')) return 'This time slot is full.';
    if (s.contains('Seat already taken')) return 'This seat is already taken.';
    if (s.contains('No free seat')) return 'No free seat in this slot.';
    if (s.contains('Seat index out of range')) return 'That seat number is not valid.';
    if (s.contains('Booking not found')) return 'Booking not found.';
    if (s.contains('Only accepted bookings')) return 'Only accepted, upcoming bookings can be edited.';

    // Firestore transaction contention / precondition failures
    if (s.contains('ABORTED') ||
        s.contains('FAILED_PRECONDITION') ||
        (s.contains('Transaction') && s.contains('conflict')) ||
        s.contains('document version') ||
        s.contains('has been modified') ||
        s.contains('requires all reads to be before writes')) {
      return 'This slot just changed — please try again.';
    }

    return 'Something went wrong. Please try again.';
  }

//---------------------------------------
// check if the selected is the same day
//---------------------------------------

  bool _isSelectedDateToday() {
    if (_selectedDate == null) return false;
    final now = DateTime.now();
    final d = _selectedDate!;
    return now.year == d.year && now.month == d.month && now.day == d.day;
  }

  /// key = "HHmm" (e.g., "0930"). Returns true if now >= slot start.
  bool _isSlotPastForSelectedDate(String key) {
    if (!_isSelectedDateToday()) return false;
    if (key.length < 4) return false;

    final now = DateTime.now();
    final hh = int.tryParse(key.substring(0, 2)) ?? 0;
    final mm = int.tryParse(key.substring(2, 4)) ?? 0;
    final slotStart = DateTime(now.year, now.month, now.day, hh, mm);

    // Treat "now == slot start" as past/unavailable:
    return !now.isBefore(slotStart);
  }


//---------------------------------------
// main build
//---------------------------------------

  @override
  Widget build(BuildContext context) {
    final double maxW = 960.w;

//---------------------------------------
// return a panel design
//---------------------------------------
    return ClipRRect(
      borderRadius: BorderRadius.circular(16.r),
      child: Container(
        decoration: BoxDecoration(
          color: _cPanelBg,
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(color: _cAvailBrd),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW),
          child: SingleChildScrollView(
            padding: EdgeInsets.all(16.w),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
//---------------------------------------
// header
//---------------------------------------
                Row(
                  children: [
                    Expanded(
                      child: Text('Edit Booking', style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700)),
                    ),
                    IconButton(
                      onPressed: () async {
                        Navigator.of(context).pop();
                        await openWebBookingDetailsDialog(
                          context: context,
                          booking: widget.rawBooking,
                          use24HourFormat: widget.use24HourFormat,
                        );
                      },
                      icon: const Icon(Icons.close),
                      tooltip: 'Close',
                    ),
                  ],
                ),
                SizedBox(height: 12.h),
//---------------------------------------
// show current booking details
//---------------------------------------

                _sectionTitle('Current Booking'),
                SizedBox(height: 8.h),
                _pillInfoRow('Date', widget.dateYMD),
                SizedBox(height: 6.h),
                _pillInfoRow('Time', _combineTime(widget.timeStart, widget.timeEnd)),
                SizedBox(height: 6.h),
                _pillInfoRow('Seat/Slot', widget.seatIndex),

                SizedBox(height: 16.h),
                const Divider(height: 1),
                SizedBox(height: 12.h),

//---------------------------------------
// allow user to choose date
//---------------------------------------
                _sectionTitle('1) Choose Date'),
                SizedBox(height: 8.h),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: () async {
                        await _openCalendarAndPick();
                      },
                      icon: const Icon(Icons.calendar_today, size: 18),
                      label: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 8.h),
                        child: Text('Pick Date', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700)),
                      ),
                    ),
                    SizedBox(width: 10.w),
                    Expanded(child: _pillInfoRow('Selected', _selectedYMD.isEmpty ? '-' : _selectedYMD)),
                  ],
                ),
                if (_loadingSettings) ...[
                  SizedBox(height: 10.h),
                  _loadingLine('Loading calendar rules...'),
                ],

                SizedBox(height: 16.h),
                const Divider(height: 1),
                SizedBox(height: 12.h),

//---------------------------------------
// select the time slot for the picked date
//---------------------------------------

                _sectionTitle('2) Choose Time Slot'),
                SizedBox(height: 8.h),
                if (_selectedYMD.isEmpty)
                  _helpText('Pick a date first.')
                else
                  _buildSlotsWrap(),

                if (_loadingFacility || _loadingDayBooked) ...[
                  SizedBox(height: 10.h),
                  _loadingLine('Loading time slots...'),
                ],

                SizedBox(height: 16.h),
                const Divider(height: 1),
                SizedBox(height: 12.h),

//---------------------------------------
// pick slot number
//---------------------------------------

                _sectionTitle('3) Choose Seat / Slot Number'),
                SizedBox(height: 8.h),
                if (_selectedSlotKey.isEmpty)
                  _helpText('Pick a time slot first.')
                else
                  _buildSeatsWrap(),

                if (_loadingSeats) ...[
                  SizedBox(height: 10.h),
                  _loadingLine('Loading seats...'),
                ],
//---------------------------------------
// show legend
//---------------------------------------

                SizedBox(height: 18.h),
                _legendRow(),

                SizedBox(height: 16.h),
                const Divider(height: 1),
                SizedBox(height: 12.h),

//---------------------------------------
// show button
//---------------------------------------
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: () async {
                        Navigator.of(context).pop();
                        await openWebBookingDetailsDialog(
                          context: context,
                          booking: widget.rawBooking,
                          use24HourFormat: widget.use24HourFormat,
                        );
                      },
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
                        child: Text('Close', style: TextStyle(fontSize: 12.sp)),
                      ),
                    ),
                    SizedBox(width: 8.w),

                    ElevatedButton(
                      onPressed: _onConfirm,
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
                        child: Text('Confirm', style: TextStyle(fontSize: 12.sp)),
                      ),
                    )
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

//---------------------------------------
// design for each title
//---------------------------------------

  Widget _sectionTitle(String s) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(s, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700, color: const Color(0xFF111827))),
    );
  }

//---------------------------------------
// design that shows each info
//---------------------------------------

  Widget _pillInfoRow(String k, String v) {
    String value = v;
    if (value.isEmpty) {
      value = '-';
    }
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFBFF),
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: _cAvailBrd),
      ),
      child: Row(
        children: [
          Text('$k: ', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700)),
          Expanded(child: Text(value, style: TextStyle(fontSize: 12.sp), overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  Widget _helpText(String s) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(s, style: TextStyle(fontSize: 12.sp, color: const Color(0xFF6B7280))),
    );
  }

  Widget _loadingLine(String label) {
    return Row(
      children: [
        const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        SizedBox(width: 8.w),
        Expanded(child: Text(label, style: TextStyle(fontSize: 12.sp))),
      ],
    );
  }
//---------------------------------------
// show each legend
//---------------------------------------

  Widget _legendRow() {
    return Row(
      children: [
        _legendBox(_cFullRed, 'Full / Taken'),
        SizedBox(width: 10.w),
        _legendBox(_cAvailBg, 'Available'),
        SizedBox(width: 10.w),
        _legendBox(_cSelected, 'Selected'),
      ],
    );
  }
//---------------------------------------
// design for legend
//---------------------------------------

  Widget _legendBox(Color c, String label) {
    // add border when the swatch is white so it’s visible on lilac
    BoxDecoration deco;
    if (c == _cAvailBg) {
      deco = BoxDecoration(color: c, border: Border.all(color: _cAvailBrd), borderRadius: BorderRadius.circular(4.r));
    } else {
      deco = BoxDecoration(color: c, borderRadius: BorderRadius.circular(4.r));
    }

    return Row(
      children: [
        Container(width: 14.w, height: 14.w, decoration: deco),
        SizedBox(width: 6.w),
        Text(label, style: TextStyle(fontSize: 12.sp)),
      ],
    );
  }

//---------------------------------------
// design for the time slot
//---------------------------------------

  Widget _buildSlotsWrap() {
    if (_timeSlots.isEmpty && !_loadingFacility) {
      return _helpText('No time slots configured for this facility.');
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(8.w),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFBFF),
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: _cAvailBrd),
      ),

      child: Wrap(
        spacing: 8.w,
        runSpacing: 8.h,
        children: [
          for (int i = 0; i < _timeSlots.length; i++)
            _slotBox(_timeSlots[i]),
        ],
      ),
    );
  }

//---------------------------------------
// each time slot design
//---------------------------------------

  Widget _slotBox(Map<String, String> slot) {
    String start = '';
    String end = '';
    String key = '';

    if (slot.containsKey('start')) start = slot['start']!;
    if (slot.containsKey('end'))   end   = slot['end']!;
    if (slot.containsKey('key'))   key   = slot['key']!;

    final bool past = _isSlotPastForSelectedDate(key);

    String label;
    if (start.isNotEmpty) {
      label = end.isNotEmpty
          ? _fmtTimeLabel(start) + ' - ' + _fmtTimeLabel(end)
          : _fmtTimeLabel(start);
    } else {
      label = key;
    }

    int booked = _dayBooked[key] ?? 0;
    bool full = _facilitySeatCapacity > 0 && booked >= _facilitySeatCapacity;
    bool selected = _selectedSlotKey == key;

    Color bg;
    Color fg;
    BoxDecoration deco;
//---------------------------------------
// if the time already past
//---------------------------------------

    if (past) {
      bg = _cPastBg;
      fg = _cPastTxt;
      deco = BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: _cAvailBrd),
      );
//---------------------------------------
// if already full
//---------------------------------------

    } else if (full) {
      bg = _cFullRed;
      fg = Colors.white;
      deco = BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10.r));
//---------------------------------------
// for selected
//---------------------------------------
    } else if (selected) {
      bg = _cSelected;
      fg = Colors.white;
      deco = BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10.r));
    } else {
//---------------------------------------
// default white
//---------------------------------------
      bg = _cAvailBg;
      fg = _cAvailTxt;
      deco = BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: _cAvailBrd),
      );
    }

    return InkWell(
      onTap: () async {
        if (past) {
          _toast('This time slot has already passed.');
          return;
        }
        if (full) {
          _toast('This time slot is full.');
          return;
        }
        setState(() {
          _selectedSlotKey = key;
          _selectedSeatIndex = -1;
          _seatTaken.clear();
        });
//---------------------------------------
// once its selected, it will set state and start to laod available slot
//---------------------------------------

        await _loadSeatsForSlot(_selectedYMD, key);
      },
//---------------------------------------
// place time label into each time slot
//---------------------------------------

      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
        decoration: deco,
        child: Text(
          label,
          style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700, color: fg),
        ),
      ),
    );
  }

//---------------------------------------
// design for the slot
//---------------------------------------

  Widget _buildSeatsWrap() {
    if (_facilitySeatCapacity <= 0 && !_loadingSeats) {
      return _helpText('No seat capacity set for this facility.');
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(8.w),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFBFF),
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: _cAvailBrd),
      ),
      child: Wrap(
        spacing: 8.w,
        runSpacing: 8.h,
        children: [
          for (int i = 0; i < _facilitySeatCapacity; i++)
            _seatBox(i),
        ],
      ),
    );
  }

//---------------------------------------
// design for each slot in slot
//---------------------------------------

  Widget _seatBox(int index) {
    final String seatLabel = (index + 1).toString();

    bool taken = false;
//---------------------------------------
// if taken = true it is taken
//---------------------------------------

    if (index < _seatTaken.length) {
      if (_seatTaken[index] == true) {
        taken = true;
      } else {
        taken = false;
      }
    }

//---------------------------------------
// check which is selected
//---------------------------------------

    bool selected = false;
    if (_selectedSeatIndex == index) {
      selected = true;
    }

    Color bg;
    Color fg;
    BoxDecoration deco;

//---------------------------------------
// if it is taken
//---------------------------------------

    if (taken) {
      bg = _cFullRed;
      fg = Colors.white;
      deco = BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10.r));
    } else {
//---------------------------------------
// if is it selected
//---------------------------------------
      if (selected) {
        bg = _cSelected;
        fg = Colors.white;
        deco = BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10.r));
      } else {
//---------------------------------------
// default
//---------------------------------------

        bg = _cAvailBg;
        fg = _cAvailTxt;
        deco = BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(color: _cAvailBrd),
        );
      }
    }

    return InkWell(
      onTap: () {

        if (taken) {
          _toast('This seat is already taken.');
          return;
        }

        setState(() {
          _selectedSeatIndex = index;
        });
      },
//---------------------------------------
// display the slot number for each slot
//---------------------------------------

      child: Container(
        width: 56.w,
        height: 44.h,
        alignment: Alignment.center,
        decoration: deco,
        child: Text(
          seatLabel,
          style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700, color: fg),
        ),
      ),
    );
  }


//---------------------------------------
// open the calendar
//---------------------------------------

  Future<void> _openCalendarAndPick() async {
    if (_loadingSettings == true) {
      _toast('Loading calendar rules... please try again in a moment.');
      return;
    }
//---------------------------------------
// load all the off day
//---------------------------------------

    if (_offDateYMD.isEmpty) {
      await _loadSettingsAndOffDays();
    }

    final DateTime today = DateTime.now();
    final DateTime minDate = DateTime(today.year, today.month, today.day);
    final DateTime maxDate = DateTime(today.year + 1, today.month, today.day);

//---------------------------------------
// get the selected day
//---------------------------------------

    final DateTime preferred = _selectedDate ?? minDate;

    final DateTime? safeInit = _firstSelectable(minDate, maxDate, preferred);
    if (safeInit == null) {
      _toast('No selectable dates available in the allowed range.');
      return;
    }
//---------------------------------------
// show the date picker with content
//---------------------------------------

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: safeInit,
      firstDate: minDate,
      lastDate: maxDate,
      selectableDayPredicate: _isSelectable,
    );

    if (picked != null) {
      final String ymd = _toYMD(picked);
      setState(() {
        _selectedDate = picked;
        _selectedYMD = ymd;
        _selectedSlotKey = '';
        _selectedSeatIndex = -1;
        _seatTaken.clear();
        _dayBooked.clear();
      });
      await _loadDayBookedMap(ymd);
    }
  }


//---------------------------------------
// load off day first
//---------------------------------------

  Future<void> _loadSettingsAndOffDays() async {
    setState(() {
      _loadingSettings = true;
    });

    try {
//---------------------------------------
// get weekday from setting
//---------------------------------------

      final DocumentSnapshot<Map<String, dynamic>> setDoc = await FirebaseFirestore.instance
          .collection('SystemInformation')
          .doc('Setting')
          .get();

      final Map<String, dynamic>? m = setDoc.data();
      if (m != null) {
        final List<bool> tmp = <bool>[true, true, true, true, true, true, true];
        tmp[0] = _readBool(m, 'Monday', true);
        tmp[1] = _readBool(m, 'Tuesday', true);
        tmp[2] = _readBool(m, 'Wednesday', true);
        tmp[3] = _readBool(m, 'Thursday', true);
        tmp[4] = _readBool(m, 'Friday', true);
        tmp[5] = _readBool(m, 'Saturday', true);
        tmp[6] = _readBool(m, 'Sunday', true);
        setState(() {
          _weekdayOpen = tmp;
        });
      }

//---------------------------------------
// get the off day
//---------------------------------------
      final DocumentSnapshot<Map<String, dynamic>> offDoc = await FirebaseFirestore.instance
          .collection('SystemInformation')
          .doc('OffDays')
          .get();

      final Set<String> tmpOff = <String>{};

      if (offDoc.exists) {
        final Map<String, dynamic>? om = offDoc.data();
        if (om != null) {
          if (om.containsKey('offDays')) {
            final dynamic arr = om['offDays'];

            if (arr is List) {
              for (final item in arr) {
                String ymd = '';

                if (item is String) {
                  ymd = item.trim();
                } else {
                  if (item is Timestamp) {
                    final DateTime dt = item.toDate();
                    ymd = _toYMD(dt);
                  } else {
                    if (item is Map<String, dynamic>) {
                      if (item.containsKey('date')) {
                        final v = item['date'];
                        if (v is String) {
                          ymd = v.trim();
                        } else {
                          if (v is Timestamp) {
                            ymd = _toYMD(v.toDate());
                          }
                        }
                      } else {
                        if (item.containsKey('dateYMD')) {
                          final v = item['dateYMD'];
                          if (v is String) {
                            ymd = v.trim();
                          }
                        }
                      }
                    }
                  }
                }

                if (ymd.isNotEmpty) {
                  tmpOff.add(ymd);
                }
              }
            }
          }
        }
      }

      if (tmpOff.isEmpty) {
        final QuerySnapshot<Map<String, dynamic>> old = await FirebaseFirestore.instance
            .collection('SystemInformation')
            .doc('OffDay')
            .collection('Dates')
            .get();

        for (final doc in old.docs) {
          final Map<String, dynamic> d = doc.data();
          String ymd = '';
          if (d.containsKey('dateYMD')) {
            final v = d['dateYMD'];
            if (v is String) {
              ymd = v.trim();
            }
          }
          if (ymd.isEmpty) {
            if (d.containsKey('date')) {
              final v = d['date'];
              if (v is String) {
                ymd = v.trim();
              } else {
                if (v is Timestamp) {
                  ymd = _toYMD(v.toDate());
                }
              }
            }
          }
          if (ymd.isNotEmpty) {
            tmpOff.add(ymd);
          }
        }
      }

      setState(() {
        _offDateYMD
          ..clear()
          ..addAll(tmpOff);
      });
    } catch (e) {
      _toast('Failed to load system settings.');
    } finally {
      setState(() {
        _loadingSettings = false;
      });
    }
  }

//---------------------------------------
// load the facility available slot and custom slot
//---------------------------------------

  Future<void> _loadFacilityConfig() async {
    setState(() {
      _loadingFacility = true;
    });

    try {
      final DocumentSnapshot<Map<String, dynamic>> facDoc = await FirebaseFirestore.instance
          .collection('Facilities')
          .doc(widget.facilityId)
          .get();

      final Map<String, dynamic>? fd = facDoc.data();

      int cap = 0;
      if (fd != null) {
        cap = _readInt(fd, 'availableSlots', 0);       // read 'availableSlots'
      }

      final List<Map<String, String>> tmpSlots = [];

      if (fd != null) {
        // get the field that stores your slots
        final dynamic v = fd['customTimeSlots'];

        // make sure it's a list
        if (v is List) {
          // loop one by one
          for (final item in v) {
            // each item must be a map with 'start' and 'end'
            if (item is Map<String, dynamic>) {
              // read start time as string (trim spaces)
              String s = '';
              final dynamic vs = item['start'];
              if (vs is String) {
                s = vs.trim();
              } else if (vs != null) {
                s = vs.toString().trim();
              }

              // read end time as string (trim spaces)
              String e = '';
              final dynamic ve = item['end'];
              if (ve is String) {
                e = ve.trim();
              } else if (ve != null) {
                e = ve.toString().trim();
              }

              // only add if there is at least a start or end
              if (s.isNotEmpty || e.isNotEmpty) {
                // build a sortable key from start (e.g. "0930")
                final String key = _slotKeyFromStart(s);

                // add to list
                tmpSlots.add({'start': s, 'end': e, 'key': key});
              }
            }
          }
        }
      }

      setState(() {
        _facilitySeatCapacity = cap;
        _timeSlots
          ..clear()
          ..addAll(tmpSlots);

        _inactiveFrom = _dateOnly(fd?['inactiveFrom']);
        _inactiveTo   = _dateOnly(fd?['inactiveTo']);

        if (_selectedDate != null && !_isSelectable(_selectedDate!)) {
          setState(() {
            _selectedDate = null;
            _selectedYMD = '';
            _selectedSlotKey = '';
            _selectedSeatIndex = -1;
            _seatTaken.clear();
            _dayBooked.clear();
          });
        }
      });
    } catch (e) {
      _toast('Failed to load facility settings.');
    } finally {
      setState(() {
        _loadingFacility = false;
      });
    }
  }

//---------------------------------------
// start to load the booked for the facilites time slot
//---------------------------------------

  Future<void> _loadDayBookedMap(String ymd) async {
    setState(() {
      _loadingDayBooked = true;
      _dayBooked.clear();
      _selectedSlotKey = '';
      _selectedSeatIndex = -1;
      _seatTaken.clear();
    });

    try {
      final QuerySnapshot<Map<String, dynamic>> snap = await FirebaseFirestore.instance
          .collection('Facilities')
          .doc(widget.facilityId)
          .collection('Days')
          .doc(ymd)
          .collection('Slots')
          .get();

      final Map<String, int> tmp = <String, int>{};
      for (final doc in snap.docs) {
        final Map<String, dynamic> m = doc.data();
        int booked = 0;
        if (m.containsKey('booked')) {
          final v = m['booked'];
          if (v is int) {
            booked = v;
          } else {
            if (v is double) {
              booked = v.toInt();
            }
          }
        }
        tmp[doc.id] = booked;
      }

      setState(() {
        _dayBooked
          ..clear()
          ..addAll(tmp);
      });
    } catch (e) {
      _toast('Failed to load day availability.');
    } finally {
      setState(() {
        _loadingDayBooked = false;
      });
    }
  }

//---------------------------------------
// load the slot for the time slot
//---------------------------------------

  Future<void> _loadSeatsForSlot(String ymd, String slotKey) async {
    setState(() {
      _loadingSeats = true;
      _seatTaken.clear();
      _selectedSeatIndex = -1;
    });

    try {

      if (_facilitySeatCapacity > 0) {
        for (int i = 0; i < _facilitySeatCapacity; i++) {
          _seatTaken.add(false);
        }
      }
//---------------------------------------
// wnt into database and check if it is taken or not
//---------------------------------------

      final QuerySnapshot<Map<String, dynamic>> seatsSnap = await FirebaseFirestore.instance
          .collection('Facilities')
          .doc(widget.facilityId)
          .collection('Days')
          .doc(ymd)
          .collection('Slots')
          .doc(slotKey)
          .collection('Seats')
          .get();

      // detect indexing scheme: 0-based vs 1-based
      bool hasZero = false;
      bool hasOne  = false;

      for (final d in seatsSnap.docs) {
        if (d.id == '0') hasZero = true;
        if (d.id == '1') hasOne  = true;
      }


      int idOffset = 1;
      if (hasZero && !hasOne) {
        idOffset = 0;
      }

      // mark taken seats with correct index
      for (final doc in seatsSnap.docs) {
        final String idStr = doc.id;
        int rawIdx = -1;
        try {
          rawIdx = int.parse(idStr);
        } catch (_) {
          rawIdx = -1;
        }

        int idx = rawIdx;
        if (idOffset == 1) {
          idx = rawIdx - 1;
        }
//---------------------------------------
// check if the slot is taken or not add into seattaken list
//---------------------------------------

        if (idx >= 0) {
          if (idx < _seatTaken.length) {
            final Map<String, dynamic> d = doc.data();
            bool taken = false;
            if (d.containsKey('taken')) {
              final v = d['taken'];
              if (v is bool) {
                taken = v;
              } else {
                taken = false;
              }
            } else {
              taken = false;
            }

            if (taken == true) {
              _seatTaken[idx] = true;
            }
          }
        }
      }

      setState(() {});
    } catch (e) {
      _toast('Failed to load seats.');
    } finally {
      setState(() {
        _loadingSeats = false;
      });
    }
  }

//---------------------------------------
// make it become a slotkey
//---------------------------------------

  String _slotKeyFromStart(String start) {
    String s = start.trim();
    if (s.contains('.')) {
      s = s.replaceAll('.', ':');
    }
    final List<String> p = s.split(':');
    if (p.length >= 2) {
      final String hh = p[0].padLeft(2, '0');
      final String mm = p[1].padLeft(2, '0');
      return hh + mm;
    } else {
      final String only = s.replaceAll(RegExp(r'[^0-9]'), '');
      return only;
    }
  }

  //---------------------------------------
// check if it is holiday
//---------------------------------------

  bool _isHoliday(DateTime d) {
    final String ymd = _toYMD(d);
    if (_offDateYMD.contains(ymd)) {
      return true;
    } else {
      return false;
    }
  }
//---------------------------------------
// check if it is working day
//---------------------------------------

  bool _isWorkingDay(DateTime d) {
    final int idx = d.weekday - 1; // Mon=1 -> 0
    if (idx >= 0 && idx < _weekdayOpen.length) {
      if (_weekdayOpen[idx] == true) {
        return true;
      } else {
        return false;
      }
    } else {
      return true;
    }
  }

  //---------------------------------------
// convert to y - m - d format
//---------------------------------------

  String _toYMD(DateTime d) {
    final String y = d.year.toString().padLeft(4, '0');
    final String m = d.month.toString().padLeft(2, '0');
    final String da = d.day.toString().padLeft(2, '0');
    return y + '-' + m + '-' + da;
  }

//---------------------------------------
// parse the YMD to int for each for dateformat purpose
//---------------------------------------

  DateTime? _parseYMD(String s) {
    try {
      final List<String> p = s.split('-');
      if (p.length == 3) {
        final int y = int.parse(p[0]);
        final int m = int.parse(p[1]);
        final int d = int.parse(p[2]);
        return DateTime(y, m, d);
      }
    } catch (_) {}
    return null;
  }
//---------------------------------------
// change tiem format to hh.mm
//---------------------------------------

  String _fmtTimeLabel(String v) {
    String s = v.trim();
    if (s.contains(':')) {
      final List<String> p = s.split(':');
      if (p.length >= 2) {
        final String hh = p[0].padLeft(2, '0');
        final String mm = p[1].padLeft(2, '0');
        return hh + '.' + mm;
      } else {
        return s;
      }
    } else {
      if (s.contains('.')) {
        return s;
      } else {
        return s;
      }
    }
  }
//---------------------------------------
// combine time to a - b
//---------------------------------------

  String _combineTime(String a, String b) {
    if (a.isEmpty && b.isEmpty) {
      return '-';
    } else {
      if (a.isEmpty) {
        return b;
      } else {
        if (b.isEmpty) {
          return a;
        } else {
          return a + ' - ' + b;
        }
      }
    }
  }
//---------------------------------------
// if its string but actually boolean , turn them into bollean
//---------------------------------------
  bool _readBool(Map<String, dynamic> m, String key, bool def) {
    if (m.containsKey(key)) {
      final v = m[key];
      if (v is bool) {
        return v;
      } else {
        if (v is String) {
          final String s = v.trim().toLowerCase();
          if (s == 'true') {
            return true;
          } else {
            if (s == 'false') {
              return false;
            } else {
              return def;
            }
          }
        } else {
          return def;
        }
      }
    } else {
      return def;
    }
  }
//---------------------------------------
// parse string to int
//---------------------------------------

  int _readInt(Map<String, dynamic> m, String key, int def) {
    if (m.containsKey(key)) {
      final v = m[key];
      if (v is int) {
        return v;
      } else {
        if (v is double) {
          return v.toInt();
        } else {
          if (v is String) {
            final String s = v.trim();
            try {
              return int.parse(s);
            } catch (_) {
              return def;
            }
          } else {
            return def;
          }
        }
      }
    } else {
      return def;
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
