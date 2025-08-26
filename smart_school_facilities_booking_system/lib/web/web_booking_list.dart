import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'web_top_bar.dart';
import 'web_booking_details.dart';

class BookingList extends StatefulWidget {
  const BookingList({Key? key}) : super(key: key);

  @override
  State<BookingList> createState() => _BookingListState();
}

class _BookingListState extends State<BookingList> {
  // ====== BASIC STATES ======
  DateTime _selectedDate = DateTime.now();
  DateTime _visibleMonthFirst =
  DateTime(DateTime.now().year, DateTime.now().month, 1);
  String _role = 'unknown';
  bool _use24HourFormat = false;

  // when false => show ALL dates; when true => filter by _selectedDate
  bool _filterByDate = false;

  // ====== FILTER STATES (one-at-a-time) ======
  bool _apPending = false; // approval
  bool _apAccepted = false;
  bool _apRejected = false;

  bool _stUpcoming = false; // status/state
  bool _stOngoing = false;
  bool _stEnded = false;

  bool _didRunHousekeeping = false;
  String? _currentUid;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _bookingsStream;

  // ====== SEARCH BAR ======
  final TextEditingController _searchCtrl =
  TextEditingController(); // search by ids + booking id

  // ====== LIFECYCLE ======
  @override
  void initState() {
    super.initState();
    _loadUserRole();
    _bookingsStream =
        FirebaseFirestore.instance.collection('Bookings').snapshots();
    _runHousekeepingOnce();
  }

  // ====== FIRESTORE: READ ROLE ======
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

  void _configureBookingsStream() {
    final r = _role.toLowerCase();
    final uid = _currentUid;

    Stream<QuerySnapshot<Map<String, dynamic>>> s;
    if (r == 'manager' && uid != null) {
      s = FirebaseFirestore.instance
          .collection('Bookings')
          .where('managerId', isEqualTo: uid)
          .snapshots();
    } else {
      s = FirebaseFirestore.instance.collection('Bookings').snapshots();
    }
    setState(() => _bookingsStream = s);
  }

  // ====== CALENDAR HELPERS ======
  int _daysInMonth(DateTime firstOfMonth) {
    final firstNext = DateTime(firstOfMonth.year, firstOfMonth.month + 1, 1);
    final lastCurrent = firstNext.subtract(const Duration(days: 1));
    return lastCurrent.day;
  }

  int _leadingEmptyCells(DateTime firstOfMonth) {
    final int wd = firstOfMonth.weekday % 7; // Sun=0
    return wd;
  }

  void _onPickDate(DateTime d) {
    setState(() {
      _selectedDate = d;
      _filterByDate = true;
    });
  }

  void _clearDateFilter() => setState(() => _filterByDate = false);

  void _prevMonth() {
    final f = _visibleMonthFirst;
    setState(() => _visibleMonthFirst = DateTime(f.year, f.month - 1, 1));
  }

  void _nextMonth() {
    final f = _visibleMonthFirst;
    setState(() => _visibleMonthFirst = DateTime(f.year, f.month + 1, 1));
  }

  // ====== APPROVAL FILTER TOGGLERS ======
  void _tapApPending(bool? v) =>
      setState(() => _apPending = (v ?? false) ? true : false..toString());

  void _tapApAccepted(bool? v) => setState(() {
    final on = v ?? false;
    _apAccepted = on;
    if (on) {
      _apPending = false;
      _apRejected = false;
    }
  });

  void _tapApRejected(bool? v) => setState(() {
    final on = v ?? false;
    _apRejected = on;
    if (on) {
      _apPending = false;
      _apAccepted = false;
    }
  });

  // ====== STATUS FILTER TOGGLERS ======
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

  // ====== ONE-TIME HOUSEKEEPING ======
  Future<void> _runHousekeepingOnce() async {
    if (_didRunHousekeeping) return;
    _didRunHousekeeping = true;

    try {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);

      // accepted -> set ongoing/ended by time
      final acceptedValues = <String>[
        'accepted',
        'Accepted',
        'ACCEPTED',
        'approved',
        'Approved',
        'APPROVED',
      ];

      final acceptedSnap = await FirebaseFirestore.instance
          .collection('Bookings')
          .where('approval', whereIn: acceptedValues)
          .get();

      for (final doc in acceptedSnap.docs) {
        final m = doc.data();
        if (m == null) continue;

        final bookDate = _readBookingDate(m);
        if (bookDate == null) continue;

        final bookDayStart =
        DateTime(bookDate.year, bookDate.month, bookDate.day);
        String newStatus = '';

        if (bookDayStart.isBefore(todayStart)) {
          newStatus = 'ended';
        } else if (_isSameYMD(bookDate, now)) {
          final tStart = _readTime(m, ['start', 'startTime', 'timeStart']);
          final tEnd = _readTime(m, ['end', 'endTime', 'timeEnd']);
          if (tStart != null && tEnd != null) {
            final startDT = DateTime(bookDate.year, bookDate.month, bookDate.day,
                tStart.hour, tStart.minute, tStart.second);
            final endDT = DateTime(bookDate.year, bookDate.month, bookDate.day,
                tEnd.hour, tEnd.minute, tEnd.second);

            if (endDT.isAfter(startDT)) {
              if (now.isBefore(startDT)) {
                // keep
              } else if (!now.isBefore(endDT)) {
                newStatus = 'ended';
              } else {
                newStatus = 'ongoing';
              }
            }
          }
        }

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
          .where('approval', whereIn: ['pending', 'Pending', 'PENDING'])
          .get();

      for (final doc in pendingSnap.docs) {
        final m = doc.data();
        if (m == null) continue;

        final bookDate = _readBookingDate(m);
        if (bookDate == null) continue;

        final bookDayStart =
        DateTime(bookDate.year, bookDate.month, bookDate.day);
        bool shouldReject = false;

        if (bookDayStart.isBefore(todayStart)) {
          shouldReject = true;
        } else if (_isSameYMD(bookDate, now)) {
          final tStart = _readTime(m, ['start', 'startTime', 'timeStart']);
          if (tStart != null) {
            final startDT = DateTime(bookDate.year, bookDate.month, bookDate.day,
                tStart.hour, tStart.minute, tStart.second);
            if (!now.isBefore(startDT)) shouldReject = true;
          }
        }

        if (shouldReject) {
          final currAppr = _readLowerStr(m, ['approval', 'approve', 'approvalStatus']);
          if (currAppr != 'rejected') {
            await doc.reference.update({
              'approval': 'rejected',
              'approvalStatus': 'rejected',
            });
          }
        }
      }
    } catch (e) {
      debugPrint('housekeeping error: $e');
    }
  }

  // ====== UI BUILD ======
  @override
  Widget build(BuildContext context) {
    final double sideMinW = 260.w;
    double sideW = 0.20.sw;
    if (sideW < sideMinW) sideW = sideMinW;

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(70.h),
        child: WebCustomTopBar(use24HourFormat: _use24HourFormat),
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // ---------- LEFT: Calendar + Filters ----------
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
                  SizedBox(height: 8.h),
                  if (_filterByDate)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: _clearDateFilter,
                        child: Text('Clear date filter',
                            style: TextStyle(fontSize: 12.sp)),
                      ),
                    ),

                  SizedBox(height: 16.h),
                  _buildApprovalFilter(),
                  SizedBox(height: 12.h),
                  _buildStatusFilter(),
                  SizedBox(height: 16.h),
                  _buildRoleInfo(),
                ],
              ),
            ),
          ),

          // ---------- RIGHT: Table ----------
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
                    // top row with search bar aligned to right
                    Row(
                      children: <Widget>[
                        const Spacer(),
                        SizedBox(
                          width: 320.w,
                          child: TextField(
                            controller: _searchCtrl,
                            onChanged: (s) => setState(() {}),
                            style: TextStyle(fontSize: 12.sp),
                            decoration: InputDecoration(
                              isDense: true,
                              hintText:
                              'Search by booking ID, user ID, facility ID',
                              hintStyle: TextStyle(
                                  fontSize: 12.sp,
                                  color: const Color(0xFF9CA3AF)),
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 10.w, vertical: 10.h),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8.r),
                                borderSide: const BorderSide(
                                    color: Color(0xFFE5E7EB)),
                              ),
                              suffixIcon: (_searchCtrl.text.trim().isEmpty)
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
                      ],
                    ),
                    SizedBox(height: 10.h),

                    // the table itself
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

  // ====== Small UI pieces ======
  Widget _buildRoleInfo() {
    String label = 'Role: $_role';
    Color bg = const Color(0xFFE5E7EB);
    Color fg = const Color(0xFF111827);

    if (_role == 'admin') {
      bg = const Color(0xFFD1FAE5);
      fg = const Color(0xFF065F46);
    } else if (_role == 'manager') {
      bg = const Color(0xFFDBEAFE);
      fg = const Color(0xFF1E3A8A);
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration:
      BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8.r)),
      child: Text(label, style: TextStyle(fontSize: 12.sp, color: fg)),
    );
  }

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
        final gridH = (rows * cellW) + ((rows - 1) * gap);

        return SizedBox(
          height: gridH,
          child: Column(
            children: List.generate(rows, (r) {
              return Padding(
                padding: EdgeInsets.only(bottom: r == rows - 1 ? 0 : gap),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(7, (cIdx) {
                    final cellIndex = (r * 7) + cIdx;
                    final dayNum = cellIndex - lead + 1;

                    bool inMonth = (dayNum >= 1 && dayNum <= days);
                    DateTime? cellDate =
                    inMonth ? DateTime(f.year, f.month, dayNum) : null;

                    final isSelected = cellDate != null &&
                        _isSameYMD(cellDate, _selectedDate) &&
                        _filterByDate;

                    return _buildDayCell(
                      width: cellW,
                      height: cellW,
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
          SizedBox(height: 4.h),
          Text('Tip: If none is ticked, it means All.',
              style:
              TextStyle(fontSize: 11.sp, color: const Color(0xFF6B7280))),
        ],
      ),
    );
  }

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

  // ====== TABLE (RIGHT) ======
  Widget _buildBookingsTable() {
    if (_bookingsStream == null) {
      return Center(child: Text('Loading...', style: TextStyle(fontSize: 14.sp)));
    }
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

        // collect docs
        final all = <Map<String, dynamic>>[];
        for (final d in snap.data!.docs) {
          final m = d.data();
          if (m != null) {
            final c = Map<String, dynamic>.from(m);
            c['__id'] = d.id; // doc id fallback
            all.add(c);
          }
        }

        // optional: date filter
        final byDate = <Map<String, dynamic>>[];
        if (_filterByDate) {
          for (final m in all) {
            final bd = _readBookingDate(m);
            if (bd != null && _isSameYMD(bd, _selectedDate)) byDate.add(m);
          }
        } else {
          byDate.addAll(all);
        }

        // approval filter
        String? needApproval;
        if (_apPending || _apAccepted || _apRejected) {
          if (_apPending) {
            needApproval = 'pending';
          } else if (_apAccepted) {
            needApproval = 'accepted';
          } else if (_apRejected) {
            needApproval = 'rejected';
          }
        }
        final byApproval = <Map<String, dynamic>>[];
        for (final m in byDate) {
          if (needApproval == null) {
            byApproval.add(m);
          } else {
            final ap = _readLowerStr(m, ['approval', 'approve', 'approvalStatus']);
            if (ap == needApproval) byApproval.add(m);
          }
        }

        // status filter
        String? needStatus;
        if (_stUpcoming || _stOngoing || _stEnded) {
          if (_stUpcoming) {
            needStatus = 'upcoming';
          } else if (_stOngoing) {
            needStatus = 'ongoing';
          } else if (_stEnded) {
            needStatus = 'ended';
          }
        }
        final byStatus = <Map<String, dynamic>>[];
        for (final m in byApproval) {
          if (needStatus == null) {
            byStatus.add(m);
          } else {
            final st = _readLowerStr(m, ['status', 'bookingStatus', 'state']);
            if (st == needStatus) byStatus.add(m);
          }
        }

        // search: bookingId OR userId OR facilityId
        final q = _searchCtrl.text.trim().toLowerCase();
        final rows = <Map<String, dynamic>>[];
        for (final m in byStatus) {
          if (q.isEmpty) {
            rows.add(m);
          } else {
            final userId = _readFirstStr(m, ['uid', 'userId', 'bookedByUid', 'bookedById', 'bookedBy']).toLowerCase();
            final facilityId = _readFirstStr(m, ['facilityId', 'facilityID', 'facilityDocId', 'facility_id']).toLowerCase();
            String bid = _readFirstStr(m, ['bookingId', 'booking_id', 'id', '__id']).toLowerCase();

            if (userId.contains(q) || facilityId.contains(q) || bid.contains(q)) {
              rows.add(m);
            }
          }
        }

        if (rows.isEmpty) {
          return Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: EdgeInsets.all(8.w),
              child: Text('No bookings found for the current filters/search.',
                  style: TextStyle(fontSize: 14.sp)),
            ),
          );
        }

        // widths
        final double wDate = 130.w;
        final double wFacility = 220.w;
        final double wTime = 180.w;
        final double wSlot = 80.w;
        final double wState = 120.w;
        final double wStatus = 120.w;
        final double wUser = 155.w;
        final double wId = 200.w;
        final double wAction = 95.w;
        final double gapW = 16.w;

        final tableW = wDate +
            wFacility +
            wTime +
            wSlot +
            wState +
            wStatus +
            wUser +
            wId +
            wAction +
            (gapW * 8);
        final shellW = tableW + (12.w * 2);
        double targetW = shellW;
        final viewportW = 1.0.sw;
        if (targetW < viewportW) targetW = viewportW;

        return Scrollbar(
          thumbVisibility: true,
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            padding: EdgeInsets.all(8.w),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Column(
                children: <Widget>[
                  // Header
                  Container(
                    width: targetW,
                    padding:
                    EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
                    decoration: const BoxDecoration(
                      color: Color(0xFFE2CCFF),
                    ),
                    child: Row(
                      children: <Widget>[
                        _headerCell('Booking Date', wDate),
                        _gapW(gapW),
                        _headerCell('Facility', wFacility),
                        _gapW(gapW),
                        _headerCell('Time', wTime),
                        _gapW(gapW),
                        _headerCell('Slot', wSlot),
                        _gapW(gapW),
                        _headerCell('State', wState),
                        _gapW(gapW),
                        _headerCell('Status', wStatus),
                        _gapW(gapW),
                        _headerCell('Booked By', wUser),
                        _gapW(gapW),
                        _headerCell('Booking ID', wId),
                        _gapW(gapW),
                        _headerCell('', wAction),
                      ],
                    ),
                  ),

                  SizedBox(height: 6.h),

                  // Rows
                  Column(
                    children: List.generate(rows.length, (i) {
                      final m = rows[i];

                      final bd = _readBookingDate(m);
                      final dateStr = bd != null ? _fmtYMD(bd) : '-';

                      final st =
                      _readTime(m, ['start', 'startTime', 'timeStart']);
                      final en = _readTime(m, ['end', 'endTime', 'timeEnd']);
                      String timeStr = '-';
                      if (st != null) {
                        timeStr = (en != null)
                            ? _formatRange(st, en, _use24HourFormat)
                            : _formatOne(st, _use24HourFormat);
                      }

                      final slot = _readFirstStr(m, [
                        'seatIndex',
                        'slotNumber',
                        'slot',
                        'seatNumber',
                        'seat'
                      ]);
                      final state =
                      _readFirstStr(m, ['status', 'bookingStatus', 'state']);
                      final appr = _readFirstStr(
                          m, ['approval', 'approve', 'approvalStatus']);
                      final apprLc = appr.trim().toLowerCase();
                      final isAccepted =
                      (apprLc == 'accepted' || apprLc == 'approved');
                      final stateDisplay =
                      isAccepted ? (state.isEmpty ? '—' : state) : '-';

                      String bid =
                      _readFirstStr(m, ['bookingId', 'booking_id', 'id']);
                      if (bid.isEmpty) {
                        final alt = m['__id'];
                        if (alt != null) bid = alt.toString();
                      }

                      // ids (for live lookups)
                      final facId = _readFirstStr(
                          m, ['facilityId', 'facilityID', 'facilityDocId', 'facility_id']);
                      final uid = _readFirstStr(
                          m, ['uid', 'userId', 'bookedByUid', 'bookedById', 'bookedBy']);

                      return Container(
                        width: targetW,
                        margin: EdgeInsets.only(bottom: 3.h),
                        padding: EdgeInsets.symmetric(
                            horizontal: 12.w, vertical: 10.h),
                        decoration: const BoxDecoration(
                          color: Color(0xFFF9F4FF),
                        ),
                        child: Row(
                          children: <Widget>[
                            _dataCell('' + (dateStr), wDate, false),
                            _gapW(gapW),

                            // Facility name (LIVE from Facilities/{facilityId})
                            _dataCellW(
                              _FacilityNameLive(
                                facilityId: facId,
                                style: TextStyle(
                                  fontSize: 12.sp,
                                  color: const Color(0xFF111827),
                                ),
                              ),
                              wFacility,
                              false,
                            ),
                            _gapW(gapW),

                            _dataCell(timeStr, wTime, false),
                            _gapW(gapW),
                            _dataCell(slot.isEmpty ? '—' : slot, wSlot, true),
                            _gapW(gapW),
                            _dataCell(stateDisplay, wState, false),
                            _gapW(gapW),
                            _dataCell(appr.isEmpty ? '—' : appr, wStatus, false),
                            _gapW(gapW),

                            // User name (LIVE from UserInformation/{uid})
                            _dataCellW(
                              _UserNameLive(
                                uid: uid,
                                style: TextStyle(
                                  fontSize: 12.sp,
                                  color: const Color(0xFF111827),
                                ),
                              ),
                              wUser,
                              false,
                            ),
                            _gapW(gapW),

                            _dataCell(bid.isEmpty ? '—' : bid, wId, false),
                            _gapW(gapW),

                            SizedBox(
                              width: wAction,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton(
                                  onPressed: () {
                                    // ensure bookingId is present for details/actions
                                    final det =
                                    Map<String, dynamic>.from(m);
                                    det['bookingId'] = det['bookingId'] ??
                                        det['id'] ??
                                        det['__id'];
                                    showDialog(
                                      context: context,
                                      barrierDismissible: true,
                                      builder: (_) => Dialog(
                                        insetPadding: EdgeInsets.symmetric(
                                            horizontal: 24.w, vertical: 24.h),
                                        backgroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                            BorderRadius.circular(12.r)),
                                        child: WebBookingDetails(
                                          booking: det,
                                          use24HourFormat: _use24HourFormat,
                                        ),
                                      ),
                                    );
                                  },
                                  child: Text('Details >',
                                      style: TextStyle(fontSize: 12.sp)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // build a header cell with fixed width
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

  // build a data cell with fixed width (center = true centers it)
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

  // same as _dataCell but accepts a widget (for live StreamBuilders)
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

  // ====== FIELD READER HELPERS ======
  DateTime? _readBookingDate(Map<String, dynamic> m) {
    for (final k in ['bookingDate', 'date', 'bookDate', 'day']) {
      if (m.containsKey(k)) {
        final v = m[k];
        if (v is Timestamp) return v.toDate();
        if (v is DateTime) return v;
        if (v is String) {
          final p1 = _tryParseYMD(v);
          if (p1 != null) return p1;
          final p2 = _tryParseDMY(v);
          if (p2 != null) return p2;
        }
      }
    }
    return null;
  }

  DateTime? _readTime(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      if (m.containsKey(k)) {
        final v = m[k];
        if (v is Timestamp) return v.toDate();
        if (v is DateTime) return v;
        if (v is String) {
          final t1 = _tryParseHMS(v);
          if (t1 != null) return t1;
          final t2 = _tryParseHM(v);
          if (t2 != null) return t2;
        }
      }
    }
    return null;
  }

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

  String _readLowerStr(Map<String, dynamic> m, List<String> keys) {
    final s = _readFirstStr(m, keys);
    return s.isEmpty ? '' : s.toLowerCase();
  }

  // ====== DATE/TIME FORMAT + PARSE ======
  bool _isSameYMD(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

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
    return '$y-$m-$da';
  }

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

  DateTime? _tryParseDMY(String s) {
    try {
      final p = s.split('/');
      if (p.length == 3) {
        return DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0]));
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  DateTime? _tryParseHMS(String s) {
    try {
      final p = s.split(':');
      if (p.length == 3) {
        final now = DateTime.now();
        return DateTime(
            now.year, now.month, now.day, int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  DateTime? _tryParseHM(String s) {
    try {
      final p = s.split(':');
      if (p.length == 2) {
        final now = DateTime.now();
        return DateTime(now.year, now.month, now.day, int.parse(p[0]), int.parse(p[1]));
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}

// ===========================
// Live-resolved names
// ===========================
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
    final ref =
    FirebaseFirestore.instance.collection('Facilities').doc(facilityId);
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

/// Live user name from UserInformation/{uid}
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
    final ref =
    FirebaseFirestore.instance.collection('UserInformation').doc(uid);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ref.snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data();
        final name =
        (data?['name'] ?? data?['userName'] ?? data?['username']) as String?;
        return Text((name != null && name.trim().isNotEmpty) ? name.trim() : '—',
            style: style, overflow: overflow);
      },
    );
  }
}
