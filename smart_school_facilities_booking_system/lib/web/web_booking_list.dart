import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'web_top_bar.dart';
import 'web_booking_details.dart';
import 'package:smart_school_facilities_booking_system/notification_service.dart';


class BookingList extends StatefulWidget {
  const BookingList({Key? key}) : super(key: key);

  @override
  State<BookingList> createState() => _BookingListState();
}

class _BookingListState extends State<BookingList> {

  DateTime _selectedDate = DateTime.now();
  DateTime _visibleMonthFirst = DateTime(DateTime.now().year, DateTime.now().month, 1);
  String _role = 'unknown';
  bool _use24HourFormat = true;

  bool _filterByDate = false;

  bool _apPending = false;
  bool _apAccepted = false;
  bool _apRejected = false;
  bool _apAmendment = false;

  bool _stUpcoming = false;
  bool _stOngoing = false;
  bool _stEnded = false;

  bool _didRunHousekeeping = false;
  String? _currentUid;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _bookingsStream;


  final TextEditingController _searchCtrl = TextEditingController();

//---------------------------------------
// run this first before doing anything
//---------------------------------------
  @override
  void initState() {
    super.initState();
    _loadUserRole();

    _bookingsStream = FirebaseFirestore.instance
        .collection('Bookings')
        .snapshots();

    _runHousekeepingOnce();
  }

  String _sortKey = '';
  String _sortDir = 'asc';

//---------------------------------------
// sort the day
//---------------------------------------
  void _toggleSort(String key) {
    setState(() {
      if (_sortKey != key) {
        _sortKey = key;
        _sortDir = 'asc';
      } else {

        if (_sortDir == 'asc') {
          _sortDir = 'desc';
        } else if (_sortDir == 'desc') {
          _sortKey = '';
          _sortDir = 'asc';
        } else {
          _sortDir = 'asc';
        }
      }
    });
  }


//---------------------------------------
// load user role first
//---------------------------------------
  Future<void> _loadUserRole() async {
    try {
      final User? u = FirebaseAuth.instance.currentUser;
      if (u == null) {
        setState(() {
          _role = 'unknown';
          _currentUid = null;
          _bookingsStream = null;
        });
        return;
      }

      _currentUid = u.uid;
//---------------------------------------
// get the user information from database
//---------------------------------------

      final snap = await FirebaseFirestore.instance
          .collection('UserInformation')
          .doc(u.uid)
          .get();

      String newRole = 'unknown';
      if (snap.exists) {
        final data = snap.data();
        final r = data?['role'];
        if (r is String && r.trim().isNotEmpty) newRole = r.trim();
      }
//---------------------------------------
// set the state for role to change the ui accordingly to the role
//---------------------------------------
      setState(() => _role = newRole);
      _configureBookingsStream();
    } catch (e) {
      debugPrint('load role error: $e');
      setState(() {
        _role = 'unknown';
        _bookingsStream = null;
      });
    }
  }
//---------------------------------------
// get the bookings that belong to the role
//---------------------------------------
  void _configureBookingsStream() {
    final r = _role.toLowerCase();
    final uid = _currentUid;

    Stream<QuerySnapshot<Map<String, dynamic>>> s;
//---------------------------------------
// if manager get booking belongs to manager
//--------------------------------------
    if (r == 'manager' && uid != null) {
      s = FirebaseFirestore.instance
          .collection('Bookings')
          .where('managerId', isEqualTo: uid)
          .where('deleted', isEqualTo: false)
          .snapshots();
    } else {
      s = FirebaseFirestore.instance
          .collection('Bookings')
          .where('deleted', isEqualTo: false)
          .snapshots();
    }

    setState(() => _bookingsStream = s);
  }

  DateTime _readSortTime(Map<String, dynamic> m) {
    final v = m['createdAt'];
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return DateTime.fromMillisecondsSinceEpoch(0);
  }


//---------------------------------------
// look for the day in month
//---------------------------------------
  int _daysInMonth(DateTime firstOfMonth) {
    final firstNext = DateTime(firstOfMonth.year, firstOfMonth.month + 1, 1);
    final lastCurrent = firstNext.subtract(const Duration(days: 1));
    return lastCurrent.day;
  }
//---------------------------------------
//look how many day previous need to be empty
//---------------------------------------
  int _leadingEmptyCells(DateTime firstOfMonth) {
    final int wd = firstOfMonth.weekday % 7;
    return wd;
  }

//---------------------------------------
// check if picked date is same as filtered date then set default, if not same then set the date
//---------------------------------------
  void _onPickDate(DateTime d) {
    setState(() {
      if (_filterByDate && _isSameYMD(d, _selectedDate)) {
        // same date clicked again -> clear filter
        _filterByDate = false;
      } else {
        _selectedDate = d;
        _filterByDate = true;
      }
    });
  }

  void _prevMonth() {
    final f = _visibleMonthFirst;
    setState(() => _visibleMonthFirst = DateTime(f.year, f.month - 1, 1));
  }

  void _nextMonth() {
    final f = _visibleMonthFirst;
    setState(() => _visibleMonthFirst = DateTime(f.year, f.month + 1, 1));
  }

//---------------------------------------
// approval filter base on taped
//---------------------------------------
  void _tapApPending(bool? v) => setState(() {
    final on = v ?? false;
    _apPending = on;
    if (on) {
      _apAccepted = false;
      _apRejected = false;
      _apAmendment = false;
    }
  });

  void _tapApAccepted(bool? v) => setState(() {
    final on = v ?? false;
    _apAccepted = on;
    if (on) {
      _apPending = false;
      _apRejected = false;
      _apAmendment = false;
    }
  });

  void _tapApRejected(bool? v) => setState(() {
    final on = v ?? false;
    _apRejected = on;
    if (on) {
      _apPending = false;
      _apAccepted = false;
      _apAmendment = false;
    }
  });

  // toggle the "Amendment" approval filter
  void _tapApAmendment(bool? v) => setState(() {
    final on = v ?? false;
    _apAmendment = on;
    if (on) {
      _apPending = false;
      _apAccepted = false;
      _apRejected = false;
    }
  });

//---------------------------------------
// for status filter after check box
//---------------------------------------
  void _tapStUpcoming(bool? v) => setState(() {
    final on = v ?? false;
    _stUpcoming = on;
    if (on) {
      _stOngoing = false;
      _stEnded = false;
    }
  });

  void _tapStOngoing(bool? v) => setState(() {
    final on = v ?? false;
    _stOngoing = on;
    if (on) {
      _stUpcoming = false;
      _stEnded = false;
    }
  });

  void _tapStEnded(bool? v) => setState(() {
    final on = v ?? false;
    _stEnded = on;
    if (on) {
      _stUpcoming = false;
      _stOngoing = false;
    }
  });

//---------------------------------------
// run the house keeping to set everything to correct status
//---------------------------------------
  Future<void> _runHousekeepingOnce() async {
    if (_didRunHousekeeping) return;
    _didRunHousekeeping = true;

    try {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);

      final acceptedSnap = await FirebaseFirestore.instance
          .collection('Bookings')
          .where('approval', isEqualTo:  'accepted')
          .get();

      for (final doc in acceptedSnap.docs) {
        final m = doc.data();
        if (m == null) continue;
//---------------------------------------
// get the booking date
//---------------------------------------
        final bookDate = _readBookingDate(m);
        if (bookDate == null) continue;

        final bookDayStart =
        DateTime(bookDate.year, bookDate.month, bookDate.day);
        String newStatus = '';

        if (bookDayStart.isBefore(todayStart)) {
          newStatus = 'ended';
//---------------------------------------
// is same date with now
//---------------------------------------
        } else if (_isSameYMD(bookDate, now)) {
          final tStart = _readTime(m, ['start']);
          final tEnd = _readTime(m, ['end']);
          if (tStart != null && tEnd != null) {
            final startDT = DateTime(bookDate.year, bookDate.month, bookDate.day,
                tStart.hour, tStart.minute, tStart.second);
            final endDT = DateTime(bookDate.year, bookDate.month, bookDate.day,
                tEnd.hour, tEnd.minute, tEnd.second);

            if (endDT.isAfter(startDT)) {
              if (now.isBefore(startDT)) {
                // do nothing
              } else if (!now.isBefore(endDT)) {
                newStatus = 'ended';
              } else {
                newStatus = 'ongoing';
              }
            }
          }
        }
//---------------------------------------
// update the new status to database
//---------------------------------------
        if (newStatus.isNotEmpty) {
          final current = _readLowerStr(m, ['status']);
          if (current != newStatus) {
            await doc.reference.update({'status': newStatus});
          }
        }
      }

      // pending -> auto-reject if past start time/day
      final pendingSnap = await FirebaseFirestore.instance
          .collection('Bookings')
          .where('approval', whereIn: ['pending'])
          .get();

      for (final doc in pendingSnap.docs) {
        final m = doc.data();
        if (m == null) continue;

        final bookDate = _readBookingDate(m);
        if (bookDate == null) continue;

        final bookDayStart = DateTime(bookDate.year, bookDate.month, bookDate.day);
        bool shouldReject = false;
//---------------------------------------
// if booking is before today then reject
//---------------------------------------
        if (bookDayStart.isBefore(todayStart)) {
          shouldReject = true;
//---------------------------------------
// check is same day year month
//---------------------------------------
        } else if (_isSameYMD(bookDate, now)) {
          final tStart = _readTime(m, ['start']);
          if (tStart != null) {
            final startDT = DateTime(
              bookDate.year, bookDate.month, bookDate.day, tStart.hour, tStart.minute, tStart.second,
            );
//---------------------------------------
// if now is after the start date time, reject
//---------------------------------------
            if (!now.isBefore(startDT)) shouldReject = true;
          }
        }

        if (shouldReject) {
          final currAppr = _readLowerStr(m, ['approval']);
          if (currAppr != 'rejected') {
//---------------------------------------
// change approval to rejected
//---------------------------------------
            await doc.reference.update({
              'approval': 'rejected',
            });

//---------------------------------------
// get the nessecary information to send rejected maillbox
//---------------------------------------
            try {
              final String bookingId  = doc.id;
              final String userId     = _readFirstStr(m, ['userId']);
              final String bookedBy   = _readFirstStr(m, ['bookedBy']);
              final String facilityId = _readFirstStr(m, ['facilityId']);
              final String managerId  = _readFirstStr(m, ['managerId']);
              final String seatRaw = _readFirstStr(m, ['seatIndex']);
              final int seatIndex  = int.tryParse(seatRaw) ?? -1;
              String startStr = _readFirstStr(m, ['start']);
              String endStr   = _readFirstStr(m, ['end']);
              final DateTime? tStart = _readTime(m, ['start']);
              final DateTime? tEnd   = _readTime(m, ['end']);
              if (startStr.isEmpty && tStart != null) startStr = _formatOne(tStart, true);
              if (endStr.isEmpty   && tEnd   != null) endStr   = _formatOne(tEnd,   true);
              String bookingDate = _readFirstStr(m, ['bookingDate']);
              final DateTime? bd = _readBookingDate(m);
              if (bookingDate.trim().isEmpty && bd != null) bookingDate = _fmtYMD(bd); // "YYYY-MM-DD"

              await NotificationService.sendBookingApprovalMails(
                bookingId: bookingId,
                userId: userId,
                bookedBy: bookedBy.isNotEmpty ? bookedBy : userId, // actor; fallback to owner
                facilityId: facilityId,
                managerId: managerId,
                approval: 'rejected',
                seatIndex: seatIndex,
                start: startStr,
                end: endStr,
                bookingDate: bookingDate,
              );
            } catch (e) {
              debugPrint('notify auto-reject failed: $e');
            }
          }
        }
      }

    } catch (e) {
      debugPrint('housekeeping error: $e');
    }
  }

//---------------------------------------
// main UI build
//---------------------------------------
  @override
  Widget build(BuildContext context) {
    // final double sideMinW = 260.w;
    double sideW = 0.20.sw;
    // if (sideW < sideMinW)
    //   sideW = sideMinW;

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(70.h),
        child: WebCustomTopBar(use24HourFormat: _use24HourFormat),
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
//---------------------------------------
// left side for calender and filter bar design main design 1
//---------------------------------------
          SizedBox(
            width: sideW,
            height: 1.0.sh,
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('List of Bookings',
                      style: TextStyle(
                          fontSize: 18.sp, fontWeight: FontWeight.bold)),
                  SizedBox(height: 16.h),
                  _buildCalendarCard(),
                  SizedBox(height: 16.h),
                  _buildApprovalFilter(),
                  SizedBox(height: 12.h),
                  _buildStatusFilter(),
                  SizedBox(height: 16.h),
                ],
              ),
            ),
          ),

//---------------------------------------
// build for the right table main design 2
//---------------------------------------
          Expanded(
            child: Container(
              height: 1.0.sh,
              padding: EdgeInsets.all(16.w),
              color: Colors.white,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(12.r),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                padding: EdgeInsets.all(12.w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
//---------------------------------------
// earch header
//---------------------------------------
                    Align(
                      alignment: Alignment.centerRight,
                      child: ConstrainedBox(
                        constraints: BoxConstraints.tightFor(width: 320.w, height: 40.h), // fixed
                        child: TextField(
                          controller: _searchCtrl,
                          onChanged: (_) => setState(() {}),
                          style: TextStyle(fontSize: 12.sp),
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: 'Search',
                            hintStyle: TextStyle(fontSize: 18.sp, color: const Color(0xFF9CA3AF)),
                            contentPadding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 10.h),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8.r),
                              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                            ),
                            suffixIcon: _searchCtrl.text.trim().isEmpty
                                ? null
                                : IconButton(
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() {});
                              },
                              icon: const Icon(Icons.clear, size: 18),
                            ),
                          ),
                        ),
                      ),
                    ),

                    SizedBox(height: 10.h),

//---------------------------------------
// build the booking table
//---------------------------------------
                    Expanded(child: _buildBookingsTable()),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

//---------------------------------------
// build calendar design
//---------------------------------------
  Widget _buildCalendarCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(12.r),
      ),
      padding: EdgeInsets.all(12.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildCalendarHeader(),
          SizedBox(height: 8.h),
          _buildWeekdayRow(),
          SizedBox(height: 8.h),
          _buildCalendarGrid(),
        ],
      ),
    );
  }
//---------------------------------------
// head of the calender
//---------------------------------------
  Widget _buildCalendarHeader() {
    final m = _visibleMonthFirst;
    final monthName = _monthName(m.month);
    final label = '$monthName ${m.year}';

    return Row(
      children: <Widget>[
        Expanded(
            child: Text(label,
                style:
                TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600))),
        TextButton(
            onPressed: _prevMonth,
            child: Text('Prev', style: TextStyle(fontSize: 12.sp))),
        SizedBox(width: 4.w),
        TextButton(
            onPressed: _nextMonth,
            child: Text('Next', style: TextStyle(fontSize: 12.sp))),
      ],
    );
  }

//---------------------------------------
// week day row of calender
//---------------------------------------
  Widget _buildWeekdayRow() {
    const days = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];

    return LayoutBuilder(
      builder: (context, c) {
        final gap = 6.w;
        final totalGaps = gap * 6;
        double cellW = (c.maxWidth - totalGaps) / 7.0;
        if (cellW < 10.w) cellW = 10.w;

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(7, (i) {
            return SizedBox(
              width: cellW,
              child: Center(
                child: Text(
                  days[i],
                  style: TextStyle(
                      fontSize: 11.sp,
                      color: const Color(0xFF6B7280),
                      fontWeight: FontWeight.w600),
                ),
              ),
            );
          }),
        );
      },
    );
  }

//---------------------------------------
// build a day a day for calender
//---------------------------------------
  Widget _buildCalendarGrid() {
    final f = _visibleMonthFirst;
    final days = _daysInMonth(f);
    final lead = _leadingEmptyCells(f);
    final total = lead + days;

    int rows = (total / 7.0).ceil();
    if (rows < 6) rows = 6;

    return LayoutBuilder(
      builder: (context, c) {
        final gap = 6.w;
        final totalGapW = gap * 6;
        double cellW = (c.maxWidth - totalGapW) / 7.0;
        if (cellW < 10.w) cellW = 10.w;
        // get the overall height
        final gridH = (rows * cellW) + ((rows - 1) * gap);

        return SizedBox(
          height: gridH,
          child: Column(
//---------------------------------------
// 6 rows start from first row
//---------------------------------------
            children: List.generate(rows, (r) {
              return Padding(
                padding: EdgeInsets.only(bottom: r == rows - 1 ? 0 : gap),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
//---------------------------------------
// 7 comlumn start from first column means 2d array
//---------------------------------------
                  children: List.generate(7, (cIdx) {
                    final cellIndex = (r * 7) + cIdx;
                    final dayNum = cellIndex - lead + 1;

                    bool inMonth = (dayNum >= 1 && dayNum <= days);
                    DateTime? cellDate = inMonth ? DateTime(f.year, f.month, dayNum) : null;

                    final isSelected = cellDate != null && _isSameYMD(cellDate, _selectedDate) && _filterByDate;

                    return _buildDayCell(
                      width: cellW,
                      height: cellW,
//---------------------------------------
// if the date in month then display day number if no display ""
//---------------------------------------
                      label: inMonth ? '$dayNum' : '',
                      inMonth: inMonth,
                      isSelected: isSelected,
                      date: cellDate,
                    );
                  }),
                ),
              );
            }),
          ),
        );
      },
    );
  }
//---------------------------------------
// build each day each day for the calender
//---------------------------------------
  Widget _buildDayCell({
    required double width,
    required double height,
    required String label,
    required bool inMonth,
    required bool isSelected,
    required DateTime? date,
  }) {
    Color border = const Color(0xFFE5E7EB);
    Color bg = Colors.white;
    Color text = const Color(0xFF111827);

    if (!inMonth) text = const Color(0xFF9CA3AF);
    if (isSelected) {
      bg = const Color(0xFFEEF2FF);
      border = const Color(0xFF6366F1);
    }

    return SizedBox(
      width: width,
      height: height,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(8.r),
        child: InkWell(
          borderRadius: BorderRadius.circular(8.r),
          onTap: () {
            if (inMonth && date != null) _onPickDate(date);
          },
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8.r),
              border: Border.all(color: border),
            ),
            alignment: Alignment.center,
            child: Text(label,
                style: TextStyle(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w600,
                    color: text)),
          ),
        ),
      ),
    );
  }
//---------------------------------------
// A place that design build approval filter
//---------------------------------------
  Widget _buildApprovalFilter() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Approval',
              style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
          SizedBox(height: 6.h),
          CheckboxListTile(
            value: _apPending,
            onChanged: _tapApPending,
            title: Text('Pending', style: TextStyle(fontSize: 12.sp)),
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
          CheckboxListTile(
            value: _apAccepted,
            onChanged: _tapApAccepted,
            title: Text('Accepted', style: TextStyle(fontSize: 12.sp)),
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
          CheckboxListTile(
            value: _apRejected,
            onChanged: _tapApRejected,
            title: Text('Rejected', style: TextStyle(fontSize: 12.sp)),
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
          CheckboxListTile(
            value: _apAmendment,
            onChanged: _tapApAmendment,
            title: Text('Amendment', style: TextStyle(fontSize: 12.sp)),
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),

          SizedBox(height: 4.h),
          Text('Tip: If none is ticked, it means All.',
              style:
              TextStyle(fontSize: 11.sp, color: const Color(0xFF6B7280))),
        ],
      ),
    );
  }
//---------------------------------------
// A place that design status filter
//---------------------------------------
  Widget _buildStatusFilter() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Status',
              style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
          SizedBox(height: 6.h),
          CheckboxListTile(
            value: _stUpcoming,
            onChanged: _tapStUpcoming,
            title: Text('Upcoming', style: TextStyle(fontSize: 12.sp)),
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
          CheckboxListTile(
            value: _stOngoing,
            onChanged: _tapStOngoing,
            title: Text('Ongoing', style: TextStyle(fontSize: 12.sp)),
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
          CheckboxListTile(
            value: _stEnded,
            onChanged: _tapStEnded,
            title: Text('Ended', style: TextStyle(fontSize: 12.sp)),
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
          SizedBox(height: 4.h),
          Text('Tip: If none is ticked, it means All.',
              style:
              TextStyle(fontSize: 11.sp, color: const Color(0xFF6B7280))),
        ],
      ),
    );
  }

//---------------------------------------
// Design for the right table
//---------------------------------------
  Widget _buildBookingsTable() {
    if (_bookingsStream == null) {
      return Center(child: Text('Loading...', style: TextStyle(fontSize: 14.sp)));
    }

//---------------------------------------
// read the booking stream first check have data or not
//---------------------------------------
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _bookingsStream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Center(child: Text('Loading...', style: TextStyle(fontSize: 14.sp)));
        }
        if (snap.hasError) {
          return Center(child: Text('Failed to load bookings', style: TextStyle(fontSize: 14.sp)));
        }
        if (!snap.hasData) {
          return Center(child: Text('No data', style: TextStyle(fontSize: 14.sp)));
        }

//---------------------------------------
// sort the time base on created at
//---------------------------------------
        final all = <Map<String, dynamic>>[];
        for (final d in snap.data!.docs) {
          final m = d.data();
          if (m != null) { final c = Map<String, dynamic>.from(m)..['__id']=d.id; all.add(c); }
        }
        all.sort((a, b) => _readSortTime(b).compareTo(_readSortTime(a)));

//---------------------------------------
// get all the status filter
//---------------------------------------
        final byStatus = _applyAllFilters(all);

//---------------------------------------
// use the bystatus (list that already apply filter) then filter by search
//---------------------------------------
        final q = _searchCtrl.text.trim().toLowerCase();
        final Future<List<Map<String, dynamic>>> rowsFuture =
        q.isEmpty ? Future.value(byStatus)
            : _filterRowsByBookingIdFacilityNameUserName(byStatus, q);

//---------------------------------------
// build the table
//---------------------------------------
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: rowsFuture,
          builder: (context, fsnap) {
            if (fsnap.connectionState == ConnectionState.waiting) {
              return Align(alignment: Alignment.topLeft,
                child: Padding(
                  padding: EdgeInsets.all(8.w),
                  child: Text(q.isEmpty ? 'Loading...' : 'Searching...', style: TextStyle(fontSize: 14.sp)),
                ),
              );
            }
            if (fsnap.hasError) {
              return Align(alignment: Alignment.topLeft,
                child: Padding(
                  padding: EdgeInsets.all(8.w),
                  child: Text('Search failed', style: TextStyle(fontSize: 14.sp)),
                ),
              );
            }

            final rows = fsnap.data ?? <Map<String, dynamic>>[];
//---------------------------------------
// after the rowsfuture list which is the filter list is done then sort it by date asdc or descending order
//---------------------------------------
//---------------------------------------
// if no sort key means default skip this block
//---------------------------------------
            if (_sortKey == 'date') {
              rows.sort((a, b) {
                final minDate = DateTime.fromMillisecondsSinceEpoch(0);

                final ad = _readBookingDate(a) ?? minDate;
                final bd = _readBookingDate(b) ?? minDate;

//---------------------------------------
// if ascending order compare them
//---------------------------------------
                int dateCmp = ad.compareTo(bd);
                //---------------------------------------
// if is is desc, - dateCmp to turn them upside down
//---------------------------------------
                if (_sortDir == 'desc') dateCmp = -dateCmp;
                if (dateCmp != 0) return dateCmp;

//---------------------------------------
// if same date , sort them by time always in ascending otder
//---------------------------------------
                DateTime at = _composeStartDateTime(a) ??
                    DateTime(ad.year, ad.month, ad.day, 0, 0, 0);
                DateTime bt = _composeStartDateTime(b) ??
                    DateTime(bd.year, bd.month, bd.day, 0, 0, 0);
                return at.compareTo(bt);
              });
            }

//---------------------------------------
// a place that display the each data column
//---------------------------------------
            const gapCount = 8;
            final double wDate = 130.w;
            final double wFacility = 220.w;
            final double wTime = 160.w;
            final double wSlot = 100.w;
            final double wState = 120.w;
            final double wStatus = 120.w;
            final double wUser = 155.w;
            final double wRole = 120.w;
            final double wAction = 95.w;
            final double gapW = 16.w;

            final tableW = wDate + wFacility + wTime + wSlot + wState + wStatus + wUser + wRole + wAction + (gapW * gapCount);
            final shellW = tableW + (12.w * 2);
            double targetW = shellW;
            final viewportW = 1.0.sw;
            if (targetW < viewportW) targetW = viewportW;

            if (rows.isEmpty) {
              return Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: EdgeInsets.all(8.w),
                  child: Text(q.isEmpty ? 'No bookings found.' : 'No bookings found for the search.',
                      style: TextStyle(fontSize: 14.sp)),
                ),
              );
            }

//---------------------------------------
// render the table
//---------------------------------------
            return _renderTable(
              rows: rows,
              targetW: targetW,
              widths: (
              date: wDate,
              facility: wFacility,
              time: wTime,
              slot: wSlot,
              state: wState,
              status: wStatus,
              user: wUser,
              role: wRole,
              action: wAction,
              gap: gapW
              ),
            );
          },
        );
      },
    );
  }

//---------------------------------------
// apply filter for all booking
//---------------------------------------
  List<Map<String, dynamic>> _applyAllFilters(List<Map<String, dynamic>> all) {
//---------------------------------------
// check if there is filter date, if yes then add the boking date that is same to the selected date
//---------------------------------------
    final byDate = _filterByDate
        ? all.where((m) {
      final bd = _readBookingDate(m);
      return bd != null && _isSameYMD(bd, _selectedDate);
    }).toList()
        : List<Map<String, dynamic>>.from(all);

//---------------------------------------
// check if there is approval fileter
//---------------------------------------

    String? needApproval;
    var filterByAmendment = false;
    if (_apAmendment) {
      filterByAmendment = true;
    } else if (_apPending || _apAccepted || _apRejected) {
      if (_apPending) needApproval = 'pending';
      else if (_apAccepted) needApproval = 'accepted';
      else if (_apRejected) needApproval = 'rejected';
    }

    final byApproval = byDate.where((m) {
//---------------------------------------
// if filter by amendment then get the booking that has pending amendment = true
//---------------------------------------
      if (filterByAmendment) return m['hasPendingAmendment'] == true;
//---------------------------------------
// if no approval then return true
//---------------------------------------
      if (needApproval == null) return true;
//---------------------------------------
// if the booking have same approval then return true
//---------------------------------------
      final ap = _readLowerStr(m, ['approval']);
      return ap == needApproval;
    }).toList();

//---------------------------------------
// check if any status filter
//---------------------------------------

    String? needStatus;
    if (_stUpcoming) needStatus = 'upcoming';
    else if (_stOngoing) needStatus = 'ongoing';
    else if (_stEnded) needStatus = 'ended';

    final byStatus = byApproval.where((m) {
//---------------------------------------
// if no status filter then return true
//---------------------------------------
      if (needStatus == null) return true;
 //---------------------------------------
// if status equal to the status filter return true
//---------------------------------------
      final st = _readLowerStr(m, ['status']);
      return st == needStatus;
    }).toList();
//---------------------------------------
// return the bookings that meets the condition
//---------------------------------------
    return byStatus;
  }

//---------------------------------------
// table design
//---------------------------------------
  Widget _renderTable({
    required List<Map<String, dynamic>> rows,
    required double targetW,
    required ({
      double date,
      double facility,
      double time,
      double slot,
      double state,
      double status,
      double user,
      double role,
      double action,
      double gap
    }) widths,
  }) {
//---------------------------------------
// this to let slot cell at the center
//---------------------------------------
    Widget _headerCellCenter(String text, double width) => SizedBox(
      width: width,
      child: Center(
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700),
        ),
      ),
    );

    return Scrollbar(
      thumbVisibility: true,
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        padding: EdgeInsets.all(8.w),
          child: Column(
            children: [
              // unified header
              Container(
                width: targetW,
                padding: EdgeInsets.fromLTRB(16.w, 12.h, 12.w, 12.h),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3E8FF),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(10.r),
                    topRight: Radius.circular(10.r),
                  ),
                  border: Border(
                    bottom: BorderSide(color: const Color(0xFFE5E7EB), width: 1),
                  ),
                ),
//---------------------------------------
// The place where it build header for the table
//---------------------------------------
                child: Row(
                  children: [
                    _sortableHeaderCell('date', 'Booking Date', widths.date),
                    _gapW(widths.gap),
                    _headerCell('Facility', widths.facility),
                    _gapW(widths.gap),
                    _headerCell('Time', widths.time),
                    _gapW(widths.gap),
                    _headerCellCenter('Slot', widths.slot),
                    _gapW(widths.gap),
                    _headerCell('Status', widths.state),
                    _gapW(widths.gap),
                    _headerCell('Approval', widths.status),
                    _gapW(widths.gap),
                    _headerCell('Booked By', widths.user),
                    _gapW(widths.gap),
                    _headerCell('Role', widths.role),
                    _gapW(widths.gap),
                    _headerCell('', widths.action),
                  ],
                ),
              ),

              SizedBox(height: 6.h),

//---------------------------------------
// each row
//---------------------------------------
              Column(
                children: List.generate(rows.length, (i) {
                  final m = rows[i];

//---------------------------------------
//format date and time first
//---------------------------------------
                  final bd = _readBookingDate(m);
                  final dateStr = bd != null ? _fmtYMD(bd) : '-';

                  final st = _readTime(m, ['start']);
                  final en = _readTime(m, ['end']);
                  String timeStr = '-';
                  if (st != null) {
                    timeStr = (en != null)
                        ? _formatRange(st, en, _use24HourFormat)
                        : _formatOne(st, _use24HourFormat);
                  }

//---------------------------------------
// start displaying each row by each row data
//---------------------------------------
                  final slot = _readFirstStr(m, ['seatIndex']);
                  final state = _readFirstStr(m, ['status']);
                  final appr  = _readFirstStr(m, ['approval']);
                  final apprLc = appr.trim().toLowerCase();
                  final isAccepted = (apprLc == 'accepted');
                  final hasAmend = (m['hasPendingAmendment'] == true);

                  String bid = _readFirstStr(m, ['bookingId']);
                  if (bid.isEmpty) {
                    final alt = m['__id'];
                    if (alt != null) bid = alt.toString();
                  }

                  final facId = _readFirstStr(m, ['facilityId']);
                  final uid   = _readFirstStr(m, ['userId']);

//---------------------------------------
// see unread and read row and set by colour 1 row and second row
//---------------------------------------

                  final bool seen = (m['seen']);
                  final bool isEven = i % 2 == 0;
                  final rowBaseReadA   = const Color(0xFFFDFDFE);
                  final rowBaseReadB   = const Color(0xFFF3F2F2);

                  final rowBg = isEven ? rowBaseReadA : rowBaseReadB;


//---------------------------------------
// set all the colours for pill status and approval
//---------------------------------------
                  Widget statePill(String txt) {
                    Color bg = const Color(0xFFE5E7EB);
                    Color fg = const Color(0xFF111827);
                    final t = txt.trim().toLowerCase();
                    if (t == 'upcoming') { bg = const Color(0xFFD1FAE5); fg = const Color(0xFF065F46); }
                    if (t == 'ongoing')  { bg = const Color(0xFFFFF7D6); fg = const Color(0xFF92400E); }
                    if (t == 'ended')    { bg = const Color(0xFF9E9E9E); fg = const Color(0xFFFBFCFD); }
                    return Container(
                      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                      decoration: BoxDecoration(
                          color: bg, borderRadius: BorderRadius.circular(999.r)),
                      child: Text(txt.isEmpty ? '—' : txt,
                          style: TextStyle(fontSize: 11.sp, color: fg, fontWeight: FontWeight.w700)),
                    );
                  }

                  Widget approvalPill(String txt, bool isAmend) {
                    Color bg = const Color(0xFFE5E7EB);
                    Color fg = const Color(0xFF111827);
                    final t = txt.trim().toLowerCase();
                    if (isAmend) { bg = const Color(0xFFE0E7FF); fg = const Color(0xFF3730A3); txt = 'Amendment'; }
                    else if (t == 'pending'){ bg = const Color(0xFFFFF7D6); fg = const Color(0xFF92400E); }
                    else if (t == 'accepted') { bg = const Color(0xFFD1FAE5); fg = const Color(0xFF065F46); }
                    else if (t == 'rejected'){ bg = const Color(0xFFFEE2E2); fg = const Color(0xFF991B1B); }
                    return Container(
                      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                      decoration: BoxDecoration(
                          color: bg, borderRadius: BorderRadius.circular(999.r)),
                      child: Text(txt.isEmpty ? '—' : txt,
                          style: TextStyle(fontSize: 11.sp, color: fg, fontWeight: FontWeight.w700)),
                    );
                  }
//---------------------------------------
// when the details is open, set seen to true in database
//---------------------------------------
                  Future<void> _openDetails() async {
                    final String docId = (m['__id'] != null) ? m['__id'].toString() : '';
                    if (!seen && docId.isNotEmpty) {
                      try {
                        await FirebaseFirestore.instance
                            .collection('Bookings')
                            .doc(docId)
                            .set({'seen': true}, SetOptions(merge: true));
                        setState(() { m['seen'] = true; });
                      } catch (_) {}
                    }
                    final det = Map<String, dynamic>.from(m);
                    det['bookingId'] = det['bookingId'] ?? det['id'] ?? det['__id'];
//---------------------------------------
// show pop up
//---------------------------------------
                    showDialog(
                      context: context,
                      barrierDismissible: true,
                      builder: (_) => Dialog(
                        insetPadding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 24.h),
                        backgroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                        child: WebBookingDetails(booking: det, use24HourFormat: _use24HourFormat),
                      ),
                    );
                  }

//---------------------------------------
// main design for each row
//---------------------------------------
                  return MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _openDetails,
//---------------------------------------
// set hover colour
//---------------------------------------
                        hoverColor: Colors.black.withOpacity(0.03),
                        child: Container(
                          width: targetW,
                          margin: EdgeInsets.only(bottom: 4.h),
                          decoration: BoxDecoration(
                            color: rowBg,
                            borderRadius: BorderRadius.circular(10.r),
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                          ),
                          child: Row(
                            children: [
//---------------------------------------
// for unread contaider add red edge
//---------------------------------------
                              Container(
                                width: 4.w,
                                height: 44.h,
                                margin: EdgeInsets.only(left: 0.w),
                                decoration: BoxDecoration(
                                  color: seen ? Colors.transparent : const Color(0xFFE11D48),
                                  borderRadius: BorderRadius.only(
                                    topLeft: Radius.circular(10.r),
                                    bottomLeft: Radius.circular(10.r),
                                  ),
                                ),
                              ),
//---------------------------------------
// each of the date in the row design
//---------------------------------------
                              Expanded(
                                child: Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                                  child: Row(
                                    children: [
                                      _dataCell(dateStr, widths.date, false),
                                      _gapW(widths.gap),
                                      _dataCellW(
                                        _FacilityNameLive(
                                          facilityId: facId,
                                          style: TextStyle(fontSize: 12.sp, color: const Color(0xFF111827)),
                                        ),
                                        widths.facility, false,
                                      ),
                                      _gapW(widths.gap),
 //---------------------------------------
// time display
//---------------------------------------

                                      _dataCell(timeStr, widths.time, false),
                                      _gapW(widths.gap),
//---------------------------------------
// slot display
//---------------------------------------
                                      _dataCell(slot.isEmpty ? '—' : slot, widths.slot, true),
                                      _gapW(widths.gap),
//---------------------------------------
// status display
//---------------------------------------
                                      SizedBox(
                                        width: widths.state,
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: isAccepted ? statePill(state) : statePill('—'),
                                        ),
                                      ),
                                      _gapW(widths.gap),
//---------------------------------------
// approval display
//---------------------------------------
                                      SizedBox(
                                        width: widths.status,
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: approvalPill(appr, hasAmend),
                                        ),
                                      ),
                                      _gapW(widths.gap),
 //---------------------------------------
// username display
//---------------------------------------
                                      _dataCellW(
                                        _UserNameLive(
                                          uid: uid,
                                          style: TextStyle(fontSize: 12.sp),
                                        ),
                                        widths.user, false,
                                      ),
                                      _gapW(widths.gap),
//---------------------------------------
// user role display
//---------------------------------------
                                      _dataCellW(
                                        _UserRoleLive(
                                          uid: uid,
                                          style: TextStyle(fontSize: 12.sp),
                                        ),
                                        widths.role, false,
                                      ),
                                      _gapW(widths.gap),
//---------------------------------------
// details
//---------------------------------------
                                      SizedBox(
                                        width: widths.action,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            TextButton(
                                              onPressed: _openDetails,
                                              child: Text('Details >', style: TextStyle(fontSize: 12.sp)),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),

      ),
    );
  }

//---------------------------------------
// build header cell
//---------------------------------------
  Widget _headerCell(String text, double width) {
    return SizedBox(
      width: width,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700),
      ),
    );
  }
//---------------------------------------
// header that let u sort day and time
//---------------------------------------
  Widget _sortableHeaderCell(String key, String text, double width) {
    final active = _sortKey == key;
    String arrow;
//---------------------------------------
// when sort key = key
//---------------------------------------
    if (active) {
      arrow = _sortDir == 'asc' ? ' ▲' : ' ▼';
    } else {
//---------------------------------------
// when sort key = date
//---------------------------------------
      arrow = key == 'date' ? ' ↕' : '';
    }
    return GestureDetector(
      onTap: () => _toggleSort(key),
      child: _headerCell(text + arrow, width),
    );
  }

//---------------------------------------
// each column design in the row
//---------------------------------------
  Widget _dataCell(String text, double width, bool center) {
    Alignment align = center ? Alignment.center : Alignment.centerLeft;
    return SizedBox(
      width: width,
      child: Align(
        alignment: align,
        child: Text(
          text,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12.sp),
        ),
      ),
    );
  }

//---------------------------------------
// for live variable
//---------------------------------------
  Widget _dataCellW(Widget child, double width, bool center) {
    return SizedBox(
      width: width,
      child: Align(
        alignment: center ? Alignment.center : Alignment.centerLeft,
        child: DefaultTextStyle.merge(
          style: TextStyle(fontSize: 12.sp),
          child: child,
        ),
      ),
    );
  }

  // horizontal gap between columns
  Widget _gapW(double w) => SizedBox(width: w);

//---------------------------------------
// read the booking date
//---------------------------------------
  DateTime? _readBookingDate(Map<String, dynamic> m) {

      if (m.containsKey('bookingDate')) {
        final v = m['bookingDate'];
        if (v is Timestamp) return v.toDate();
        if (v is DateTime) return v;
        if (v is String) {
          final p1 = _tryParseYMD(v);
          if (p1 != null)
            return p1;
        }
      }
    return null;
  }
//---------------------------------------
// read the time
//---------------------------------------
  DateTime? _readTime(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      if (m.containsKey(k)) {
        final v = m[k];
        if (v is Timestamp) return v.toDate();
        if (v is DateTime) return v;
        if (v is String) {
          final t = _tryParseHM(v);
          if (t != null) return t;
        }
      }
    }
    return null;
  }
//---------------------------------------
// change the approval to string
//---------------------------------------
  String _readFirstStr(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      if (m.containsKey(k)) {
        final v = m[k];
        if (v is String) {
          if (v.trim().isNotEmpty) return v.trim();
        } else if (v != null) {
          return v.toString();
        }
      }
    }
    return '';
  }
//---------------------------------------
// change all to lower case
//---------------------------------------
  String _readLowerStr(Map<String, dynamic> m, List<String> keys) {
    final s = _readFirstStr(m, keys);
    return s.isEmpty ? '' : s.toLowerCase();
  }

//---------------------------------------
// check if they are same day year and month
//---------------------------------------
  bool _isSameYMD(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

//---------------------------------------
// month is base on number then - 1  to get actual month
//---------------------------------------
  String _monthName(int m) {
    const names = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    return names[m - 1];
  }

  String _fmtYMD(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final da = d.day.toString().padLeft(2, '0');
    return '$da-$m-$y';
  }

//---------------------------------------
// return time format
//---------------------------------------
  String _formatOne(DateTime d, bool use24) {
    if (use24) {
      final hh = d.hour.toString().padLeft(2, '0');
      final mm = d.minute.toString().padLeft(2, '0');
      return '$hh:$mm';
    } else {
      int h = d.hour;
      String ampm = 'am';
      if (h >= 12) ampm = 'pm';
      if (h == 0) {
        h = 12;
      } else if (h > 12) {
        h = h - 12;
      }
      final mm = d.minute.toString().padLeft(2, '0');
      return '$h.$mm $ampm';
    }
  }

  String _formatRange(DateTime st, DateTime en, bool use24) {
    final a = _formatOne(st, use24);
    final b = _formatOne(en, use24);
    return '$a - $b';
  }
//---------------------------------------
// parse date format
//---------------------------------------
  DateTime? _tryParseYMD(String s) {
    try {
      final p = s.split('-');
      if (p.length == 3) {
        return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
      }
      return null;
    } catch (_) {
      return null;
    }
  }
//---------------------------------------
// get the real date and time for compare
//---------------------------------------
  DateTime? _composeStartDateTime(Map<String, dynamic> m) {
    final d = _readBookingDate(m);
    final t = _readTime(m, ['start']);
    if (d == null || t == null) return null;
    return DateTime(d.year, d.month, d.day, t.hour, t.minute, t.second);
  }


//---------------------------------------
// parse the HM to hour and minute format
//---------------------------------------
  DateTime? _tryParseHM(String s) {
    try {
      final p = s.split(':');
      if (p.length == 2) {
        final now = DateTime.now();
        return DateTime(
            now.year, now.month, now.day, int.parse(p[0]), int.parse(p[1]));
      }
      return null;
    } catch (_) {
      return null;
    }
  }


//---------------------------------------
// search by the booking username, and facility name
//---------------------------------------
  Future<List<Map<String, dynamic>>> _filterRowsByBookingIdFacilityNameUserName(List<Map<String, dynamic>> items, String q,)
  async {
    final out = <Map<String, dynamic>>[];

    for (final m in items) {
      bool match = false;
      //---------------------------------------
// read bookig id if contain then metch = true
//---------------------------------------
      final bid = _readFirstStr(m, ['bookingId']).toLowerCase();
      if (bid.contains(q)) {
        match = true;
      }
//---------------------------------------
// read facility id then get the name
//---------------------------------------
      if (!match) {
        final facId = _readFirstStr(m, ['facilityId']);
        if (facId.isNotEmpty) {
          try {
            final facDoc = await FirebaseFirestore.instance
                .collection('Facilities')
                .doc(facId)
                .get();
            final data = facDoc.data();
            final facName = (data?['name'] as String?)?.trim().toLowerCase();
            if ((facName ?? '').contains(q)) {
              match = true;
            }
          } catch (e) {
            debugPrint('search facility error: $e');
          }
        }
      }

//---------------------------------------
// read user name if contain q then match = true
//---------------------------------------
      if (!match) {
        final uid = _readFirstStr(m, ['userId', 'bookedBy']);
        if (uid.isNotEmpty) {
          try {
            final userDoc = await FirebaseFirestore.instance
                .collection('UserInformation')
                .doc(uid)
                .get();
            final data = userDoc.data();
            final n = ((data?['username']) )
                ?.trim()
                .toLowerCase();
            if ((n ?? '').contains(q)) {
              match = true;
            }
          } catch (e) {
            debugPrint('search user error: $e');
          }
        }
      }
//---------------------------------------
// for all true which is match , the booking will added into the list
//---------------------------------------
      if (match) out.add(m);
    }

    return out;
  }

}

//---------------------------------------
// get facility name through id
//---------------------------------------
class _FacilityNameLive extends StatelessWidget {
  final String facilityId;
  final TextStyle style;
  final TextOverflow overflow;

  const _FacilityNameLive({
    Key? key,
    required this.facilityId,
    required this.style,
    this.overflow = TextOverflow.ellipsis,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (facilityId.isEmpty) {
      return Text('—', style: style, overflow: overflow);
    }
    final ref = FirebaseFirestore.instance.collection('Facilities').doc(facilityId);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ref.snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data();
        final name = (data?['name'] as String?)?.trim();
        return Text((name?.isNotEmpty ?? false) ? name! : '—',
            style: style, overflow: overflow);
      },
    );
  }
}
//---------------------------------------
// get user role  through id
//---------------------------------------

class _UserRoleLive extends StatelessWidget {
  final String uid;
  final TextStyle style;
  final TextOverflow overflow;

  const _UserRoleLive({
    Key? key,
    required this.uid,
    required this.style,
    this.overflow = TextOverflow.ellipsis,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (uid.isEmpty) {
      return Text('—', style: style, overflow: overflow);
    }

    final ref = FirebaseFirestore.instance.collection('UserInformation').doc(uid);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ref.snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data();
        final role = (data?['role'] as String?)?.trim();
        return Text((role?.isNotEmpty ?? false) ? role! : '—',
            style: style, overflow: overflow);
      },
    );
  }
}
//---------------------------------------
// get user name through id
//---------------------------------------

class _UserNameLive extends StatelessWidget {
  final String uid;
  final TextStyle style;
  final TextOverflow overflow;

  const _UserNameLive({
    Key? key,
    required this.uid,
    required this.style,
    this.overflow = TextOverflow.ellipsis,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (uid.isEmpty) {
      return Text('—', style: style, overflow: overflow);
    }
    final ref = FirebaseFirestore.instance.collection('UserInformation').doc(uid);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ref.snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data();
        final name = ((data?['username']) as String?)
            ?.trim();
        return Text((name?.isNotEmpty ?? false) ? name! : '—',
            style: style, overflow: overflow);
      },
    );
  }
}

