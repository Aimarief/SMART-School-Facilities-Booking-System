import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'web_top_bar.dart';

class Homepage extends StatefulWidget {
  const Homepage({Key? key}) : super(key: key);

  @override
  State<Homepage> createState() => _HomepageState();
}

class _HomepageState extends State<Homepage> {
  // -------- BASIC STATES --------
  late DateTime _selectedDate;
  late DateTime _visibleMonthFirst;
  bool _filterByDate = false;
  bool _use24HourFormat = false;

  // -------- STATUS FILTER (one at a time) --------
  bool _stUpcoming = false;
  bool _stOngoing = false;
  bool _stEnded = false;

  // -------- CATEGORY FILTER (Admin) --------
  final Set<String> _selectedCategoryIds = <String>{};

  // -------- FACILITY FILTER (Manager) --------
  final Set<String> _selectedFacilityIds = <String>{};

  // -------- ROLE + USER INFO --------
  String _role = 'unknown'; // 'Admin' | 'Manager' | 'unknown'
  String? _currentUid;
  String _managerName = '';

  // -------- scroll controllers (for visible scrollbars) --------
  final ScrollController _hCtrl = ScrollController();
  final ScrollController _vCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
    _visibleMonthFirst = DateTime(now.year, now.month, 1);
    _loadUserRole();
  }

  // read UserInformation/{uid}
  Future<void> _loadUserRole() async {
    try {
      final u = FirebaseAuth.instance.currentUser;
      if (u == null) {
        setState(() {
          _role = 'unknown';
          _currentUid = null;
          _managerName = '';
        });
        return;
      }
      _currentUid = u.uid;

      final snap = await FirebaseFirestore.instance
          .collection('UserInformation')
          .doc(u.uid)
          .get();

      String newRole = 'unknown';
      String newName = '';

      if (snap.exists) {
        final data = snap.data();
        if (data != null) {
          final r = data['role'];
          if (r is String && r.trim().isNotEmpty) newRole = r.trim();

          if (data['name'] is String && (data['name'] as String).trim().isNotEmpty) {
            newName = (data['name'] as String).trim();
          } else if (data['userName'] is String && (data['userName'] as String).trim().isNotEmpty) {
            newName = (data['userName'] as String).trim();
          } else if (data['username'] is String && (data['username'] as String).trim().isNotEmpty) {
            newName = (data['username'] as String).trim();
          }
        }
      }

      setState(() {
        _role = newRole;
        _managerName = newName;
      });
    } catch (e) {
      debugPrint('load role error: $e');
      setState(() {
        _role = 'unknown';
        _managerName = '';
      });
    }
  }

  // -------- CALENDAR HELPERS --------
  int _daysInMonth(DateTime firstOfMonth) {
    final firstNext = DateTime(firstOfMonth.year, firstOfMonth.month + 1, 1);
    final lastCurrent = firstNext.subtract(const Duration(days: 1));
    return lastCurrent.day;
  }

  int _leadingEmptyCells(DateTime firstOfMonth) {
    final wd = firstOfMonth.weekday % 7; // Sun=0
    return wd;
  }

  bool _isSameYMD(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _monthName(int m) {
    const names = <String>[
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



  void _onPickDate(DateTime d) {
    setState(() {
      if (_filterByDate) {
        _filterByDate = !_isSameYMD(d, _selectedDate);
        _selectedDate = d;
      } else {
        _selectedDate = d;
        _filterByDate = true;
      }
    });
  }

  void _prevMonth() {
    final f = _visibleMonthFirst;
    setState(() {
      _visibleMonthFirst = DateTime(f.year, f.month - 1, 1);
    });
  }

  void _nextMonth() {
    final f = _visibleMonthFirst;
    setState(() {
      _visibleMonthFirst = DateTime(f.year, f.month + 1, 1);
    });
  }

  void _clearDateFilter() {
    setState(() {
      _filterByDate = false;
    });
  }

  // -------- STATUS TOGGLERS --------
  void _tapStUpcoming(bool? v) {
    final on = v == true;
    setState(() {
      _stUpcoming = on;
      if (on) {
        _stOngoing = false;
        _stEnded = false;
      }
    });
  }

  void _tapStOngoing(bool? v) {
    final on = v == true;
    setState(() {
      _stOngoing = on;
      if (on) {
        _stUpcoming = false;
        _stEnded = false;
      }
    });
  }

  void _tapStEnded(bool? v) {
    final on = v == true;
    setState(() {
      _stEnded = on;
      if (on) {
        _stUpcoming = false;
        _stOngoing = false;
      }
    });
  }

  // -------- CATEGORY SELECT --------
  void _toggleCategory(String id, bool? v) {
    final on = v == true;
    setState(() {
      if (on) {
        _selectedCategoryIds.add(id);
      } else {
        _selectedCategoryIds.remove(id);
      }
    });
  }

  void _clearAllCategories() {
    setState(() {
      _selectedCategoryIds.clear();
    });
  }

  // -------- FACILITY SELECT --------
  void _toggleFacility(String id, bool? v) {
    final on = v == true;
    setState(() {
      if (on) {
        _selectedFacilityIds.add(id);
      } else {
        _selectedFacilityIds.remove(id);
      }
    });
  }

  void _clearAllFacilities() {
    setState(() {
      _selectedFacilityIds.clear();
    });
  }

  // -------- UI BUILD --------
  @override
  Widget build(BuildContext context) {
    final sideMinW = 260.w;
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
          // LEFT (unchanged)
          SizedBox(
            width: sideW,
            height: 1.0.sh,
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('List of Bookings',
                      style:
                      TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),
                  SizedBox(height: 16.h),
                  _buildCalendarCard(),
                  SizedBox(height: 16.h),
                  _buildStatusFilter(),
                  SizedBox(height: 12.h),
                  _buildCategoryOrFacilityFilter(),
                  SizedBox(height: 16.h),
                  _buildRoleInfo(),
                ],
              ),
            ),
          ),

          // RIGHT — 7-day timetable
          Expanded(child: _buildTimetablePanel()),
        ],
      ),
    );
  }

  // -------- Small UI pieces --------
  Widget _buildRoleInfo() {
    String label = 'Role: ' + _role;
    Color bg = const Color(0xFFE5E7EB);
    Color fg = const Color(0xFF111827);

    switch (_role.toLowerCase()) {
      case 'admin':
        bg = const Color(0xFFD1FAE5);
        fg = const Color(0xFF065F46);
        break;
      case 'manager':
        bg = const Color(0xFFDBEAFE);
        fg = const Color(0xFF1E3A8A);
        break;
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
          SizedBox(height: 8.h),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _clearDateFilter,
              child:
              Text('Clear Date Filter', style: TextStyle(fontSize: 12.sp)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarHeader() {
    final m = _visibleMonthFirst;
    final label = '${_monthName(m.month)} ${m.year}';
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
    const days = <String>['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];
    return LayoutBuilder(
      builder: (_, c) {
        final gap = 6.w;
        final totalGaps = gap * 6.0;
        double cellW = (c.maxWidth - totalGaps) / 7.0;
        if (cellW < 10.w) cellW = 10.w;

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(7, (i) {
            return SizedBox(
              width: cellW,
              child: Center(
                child: Text(days[i],
                    style: TextStyle(
                        fontSize: 11.sp,
                        color: const Color(0xFF6B7280),
                        fontWeight: FontWeight.w600)),
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
      builder: (_, c) {
        final gap = 6.w;
        final totalGapW = gap * 6.0;
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

                    final inMonth = dayNum >= 1 && dayNum <= days;
                    DateTime? cellDate =
                    inMonth ? DateTime(f.year, f.month, dayNum) : null;
                    final isSelected = (cellDate != null && _filterByDate)
                        ? _isSameYMD(cellDate, _selectedDate)
                        : false;

                    return _buildDayCell(
                      width: cellW,
                      height: cellW,
                      label: inMonth ? dayNum.toString() : '',
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

  // ====== small generic grid helpers ======
  Widget _gridCell({
    required Border border,
    Widget? child,
    Alignment align = Alignment.centerLeft,
    EdgeInsets? pad,
    Color? bg,
  }) {
    return Container(
      alignment: align,
      padding: pad ?? EdgeInsets.all(8.w),
      decoration: BoxDecoration(color: bg, border: border),
      child: child ?? const SizedBox.shrink(),
    );
  }

  // header cell (legacy – not used by the new table, kept to avoid breaking anything else)
  Widget _ttHeaderCell(String text,
      {Alignment align = Alignment.center, double padH = 8.0, double padV = 10.0}) {
    return Container(
      alignment: align,
      padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
      child: Text(
        text,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700),
      ),
    );
  }

  // booking chips inside a cell (legacy style with explicit border – unused by the new table)
  Widget _bookingCell({
    required List<Map<String, dynamic>> items,
    required Border border,
  }) {
    const greenBg = Color(0xFFD1FAE5);
    const greenBd = Color(0xFF10B981);
    const yellowBg = Color(0xFFFEF3C7);
    const yellowBd = Color(0xFFF59E0B);
    const greyBg = Color(0xFFE5E7EB);
    const greyBd = Color(0xFF9CA3AF);

    final nowDT = DateTime.now();

    return Container(
      decoration: BoxDecoration(border: border),
      padding: EdgeInsets.all(8.w),
      constraints: BoxConstraints(minHeight: 74.h),
      child: (items.isEmpty)
          ? const SizedBox.shrink()
          : Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: List.generate(items.length, (i) {
          final m = items[i];
          final uid = _readFirstStr(
              m, const ['uid', 'userId', 'bookedByUid', 'bookedById', 'bookedBy']);
          final st = _readTime(m, const ['start', 'startTime', 'timeStart']);
          final en = _readTime(m, const ['end', 'endTime', 'timeEnd']);
          final bd = _readBookingDate(m) ?? st;

          final status = _computeStatus(
            nowDT,
            bd != null ? DateTime(bd.year, bd.month, bd.day) : null,
            st,
            en,
          );

          Color bg = greyBg, bdColor = greyBd;
          if (status == 'upcoming') {
            bg = greenBg;
            bdColor = greenBd;
          } else if (status == 'ongoing') {
            bg = yellowBg;
            bdColor = yellowBd;
          }

          String timeLabel = '-';
          if (st != null) {
            timeLabel = (en != null)
                ? _formatRange(st, en, _use24HourFormat)
                : _formatOne(st, _use24HourFormat);
          }

          return Container(
            width: double.infinity,
            margin: EdgeInsets.only(bottom: i == items.length - 1 ? 0 : 6.h),
            padding: EdgeInsets.all(8.w),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(8.r),
              border: Border.all(color: bdColor, width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _UserNameLive(
                  uid: uid,
                  style: TextStyle(
                      fontSize: 12.sp, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 2.h),
                Text(timeLabel,
                    style: TextStyle(
                        fontSize: 11.sp, color: const Color(0xFF374151))),
              ],
            ),
          );
        }),
      ),
    );
  }

  // ===========================================================
  // RIGHT PANEL — 7-day timetable (today + next 6) as SIMPLE TABLE
  // ===========================================================
  // Small header cell for the simple table
  Widget _hdrCell(String text,
      {Alignment align = Alignment.center, EdgeInsets? pad}) {
    return Container(
      alignment: align,
      padding: pad ?? EdgeInsets.symmetric(horizontal: 8.w, vertical: 10.h),
      child: Text(
        text,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700),
      ),
    );
  }

  // Day cell for the simple table (no per-cell borders; table draws them)
  Widget _dayCellSimple(List<Map<String, dynamic>> items) {
    const greenBg = Color(0xFFD1FAE5);
    const greenBd = Color(0xFF10B981);
    const yellowBg = Color(0xFFFEF3C7);
    const yellowBd = Color(0xFFF59E0B);
    const greyBg = Color(0xFFE5E7EB);
    const greyBd = Color(0xFF9CA3AF);

    final nowDT = DateTime.now();




    return Container(
      padding: EdgeInsets.all(8.w),
      constraints: BoxConstraints(minHeight: 64.h),
      child: items.isEmpty
          ? const SizedBox.shrink()
          : Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: List.generate(items.length, (i) {
          final m = items[i];
          final uid = _readFirstStr(
              m, const ['uid','userId','bookedByUid','bookedById','bookedBy']);
          final st = _readTime(m, const ['start','startTime','timeStart']);
          final en = _readTime(m, const ['end','endTime','timeEnd']);
          final bd = _readBookingDate(m) ?? st;

          final status = _computeStatus(
            nowDT,
            bd != null ? DateTime(bd.year, bd.month, bd.day) : null,
            st, en,
          );

          Color bg = const Color(0xFFE5E7EB), bdColor = const Color(0xFF9CA3AF);
          if (status == 'upcoming') { bg = const Color(0xFFD1FAE5); bdColor = const Color(0xFF10B981); }
          else if (status == 'ongoing') { bg = const Color(0xFFFEF3C7); bdColor = const Color(0xFFF59E0B); }

          String timeLabel = '-';
          if (st != null) {
            timeLabel = (en != null) ? _formatRange(st, en, _use24HourFormat)
                : _formatOne(st, _use24HourFormat);
          }

          final double chipMinH = 52.h; // min chip height (tweak 48–56.h as you like)

          return Container(
            width: double.infinity,
            margin: EdgeInsets.only(bottom: i == items.length - 1 ? 0 : 6.h),
            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 6.h), // use .h vertically
            constraints: BoxConstraints(minHeight: chipMinH),              // no fixed height
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(8.r),
              border: Border.all(color: bdColor, width: 1),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,                               // shrink to content
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _UserNameLive(
                  uid: uid,
                  style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, height: 1.1),
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 2.h),
                Text(
                  timeLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textHeightBehavior: const TextHeightBehavior(
                    applyHeightToFirstAscent: false,
                    applyHeightToLastDescent: false,
                  ),
                  style: TextStyle(fontSize: 11.sp, height: 1.1, color: const Color(0xFF374151)),
                ),
              ],
            ),
          );

        }),
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
          Text('Status', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
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
              style: TextStyle(fontSize: 11.sp, color: const Color(0xFF6B7280))),
        ],
      ),
    );
  }

  Widget _buildCategoryOrFacilityFilter() {
    return (_role.toLowerCase() == 'manager')
        ? _buildFacilityFilter()
        : _buildCategoryFilter();
  }

  // CATEGORY (Admin)
  Widget _buildCategoryFilter() {
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
          Text('Category', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
          SizedBox(height: 6.h),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('FacilitiesCategory')
                .where('available', isEqualTo: true)
                .where('deleted', isEqualTo: false)
                .snapshots(),
            builder: (_, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return Padding(
                    padding: EdgeInsets.symmetric(vertical: 6.h),
                    child: Text('Loading categories...', style: TextStyle(fontSize: 12.sp)));
              }
              if (snap.hasError || !snap.hasData || snap.data!.docs.isEmpty) {
                return Padding(
                    padding: EdgeInsets.symmetric(vertical: 6.h),
                    child: Text('No categories', style: TextStyle(fontSize: 12.sp)));
              }
              final docs = snap.data!.docs;
              return Column(
                children: List.generate(docs.length, (i) {
                  final m = docs[i].data();
                  final id = docs[i].id;
                  String name = '';
                  final v = m['name'];
                  if (v is String && v.trim().isNotEmpty) name = v.trim();
                  if (name.isEmpty) name = '(no name)';
                  final checked = _selectedCategoryIds.contains(id);
                  return CheckboxListTile(
                    value: checked,
                    onChanged: (val) => _toggleCategory(id, val),
                    title: Text(name, style: TextStyle(fontSize: 12.sp)),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                  );
                }),
              );
            },
          ),
          SizedBox(height: 4.h),
          Text('Tip: You can pick more than one category.',
              style: TextStyle(fontSize: 11.sp, color: const Color(0xFF6B7280))),
          SizedBox(height: 4.h),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
                onPressed: _clearAllCategories,
                child: Text('Clear Categories', style: TextStyle(fontSize: 12.sp))),
          ),
        ],
      ),
    );
  }

  // FACILITY (Manager) — show manager’s facilities, hide deleted==true
  Widget _buildFacilityFilter() {
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
          Text('Facility', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
          SizedBox(height: 6.h),
          if (_currentUid == null)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 6.h),
              child: Text('Not signed in', style: TextStyle(fontSize: 12.sp)),
            )
          else
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('Facilities')
                  .where('managerId', isEqualTo: _currentUid)
                  .snapshots(),
              builder: (_, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return Padding(
                    padding: EdgeInsets.symmetric(vertical: 6.h),
                    child: Text('Loading facilities...',
                        style: TextStyle(fontSize: 12.sp)),
                  );
                }
                if (snap.hasError || !snap.hasData) {
                  return Padding(
                    padding: EdgeInsets.symmetric(vertical: 6.h),
                    child:
                    Text('No facilities', style: TextStyle(fontSize: 12.sp)),
                  );
                }

                final all = snap.data!.docs;
                final visible = all.where((d) {
                  final m = d.data();
                  final del = m['deleted'];
                  if (del is bool) return del == false;
                  if (del is String) return del.toLowerCase() != 'true';
                  return true; // missing => keep
                }).toList();

                if (visible.isEmpty) {
                  return Padding(
                    padding: EdgeInsets.symmetric(vertical: 6.h),
                    child:
                    Text('No facilities', style: TextStyle(fontSize: 12.sp)),
                  );
                }

                return Column(
                  children: List.generate(visible.length, (i) {
                    final m = visible[i].data();
                    final id = visible[i].id;

                    String name = '';
                    final v = m['name'];
                    if (v is String && v.trim().isNotEmpty) name = v.trim();
                    if (name.isEmpty) name = '(no name)';

                    String managerId = '';
                    final vm = m['managerId'];
                    if (vm is String && vm.trim().isNotEmpty) {
                      managerId = vm.trim();
                    } else if (vm != null) {
                      managerId = vm.toString();
                    }

                    final checked = _selectedFacilityIds.contains(id);

                    return CheckboxListTile(
                      value: checked,
                      onChanged: (val) => _toggleFacility(id, val),
                      title: Text(name, style: TextStyle(fontSize: 12.sp)),
                      subtitle: _ManagerNameLive(
                        managerId: managerId,
                        style: TextStyle(
                            fontSize: 11.sp, color: const Color(0xFF6B7280)),
                      ),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                    );
                  }),
                );
              },
            ),
          SizedBox(height: 4.h),
          Text('Tip: You can pick more than one facility.',
              style: TextStyle(fontSize: 11.sp, color: const Color(0xFF6B7280))),
          SizedBox(height: 4.h),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
                onPressed: _clearAllFacilities,
                child: Text('Clear Facilities', style: TextStyle(fontSize: 12.sp))),
          ),
        ],
      ),
    );
  }

  Widget _buildTimetablePanel() {
    // days: selected day (if any) + next 6
    final base = _filterByDate ? _selectedDate : DateTime.now();
    final startDay = DateTime(base.year, base.month, base.day);
    final days = List<DateTime>.generate(7, (i) =>
        DateTime(startDay.year, startDay.month, startDay.day + i));

    // Streams
    final facilitiesQuery = (_role.toLowerCase() == 'manager' && _currentUid != null)
        ? FirebaseFirestore.instance.collection('Facilities')
        .where('managerId', isEqualTo: _currentUid).snapshots()
        : FirebaseFirestore.instance.collection('Facilities').snapshots();

    final bookingsQuery = FirebaseFirestore.instance
        .collection('Bookings')
        .where('deleted', isEqualTo: false)
        .where('approval', isEqualTo: 'accepted')
        .snapshots();


    // layout
    final wFacilityCol = 260.w; // BIG first column
    final wSlotCol = 120.w;
    final wDayCol = 180.w;

    const headerBg = Color(0xFFE9D5FF);
    const gridColor = Color(0xFFB18CE3);

    final totalWidth = wFacilityCol + wSlotCol + (7 * wDayCol);

    return Container(
      color: Colors.white,
      padding: EdgeInsets.all(16.w),
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: facilitiesQuery,
        builder: (_, facSnap) {
          if (facSnap.connectionState == ConnectionState.waiting) {
            return Center(child: Text('Loading timetable...',
                style: TextStyle(fontSize: 14.sp)));
          }
          if (facSnap.hasError || !facSnap.hasData) {
            return Center(child: Text('Failed to load facilities',
                style: TextStyle(fontSize: 14.sp)));
          }

          // facilities filtered + sorted
          final allFacDocs = facSnap.data!.docs.where((d) {
            final m = d.data();
            final del = m['deleted'];
            if (del is bool) return del == false;
            if (del is String) return del.toLowerCase() != 'true';
            return true;
          }).toList();

          // Admin: filter by selected category ids
          List<QueryDocumentSnapshot<Map<String, dynamic>>> facDocs = allFacDocs;
          if (_role.toLowerCase() != 'manager' && _selectedCategoryIds.isNotEmpty) {
            facDocs = facDocs.where((d) {
              final catId = _readFacilityCategoryId(d.data());
              return catId.isNotEmpty && _selectedCategoryIds.contains(catId);
            }).toList();
          }

          // Manager: optional facility pick filter
          if (_selectedFacilityIds.isNotEmpty) {
            facDocs = facDocs.where((d) => _selectedFacilityIds.contains(d.id)).toList();
          }

          facDocs.sort((a, b) {
            final na = (a.data()['name'] ?? '').toString().toLowerCase();
            final nb = (b.data()['name'] ?? '').toString().toLowerCase();
            return na.compareTo(nb);
          });

          final slotsByFid = <String, int>{
            for (final d in facDocs) d.id: _readSlots(d.data())
          };

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: bookingsQuery,
            builder: (_, bookSnap) {
              if (bookSnap.connectionState == ConnectionState.waiting) {
                return Center(child: Text('Loading bookings...',
                    style: TextStyle(fontSize: 14.sp)));
              }
              if (bookSnap.hasError || !bookSnap.hasData) {
                return Center(child: Text('Failed to load bookings',
                    style: TextStyle(fontSize: 14.sp)));
              }

              // grid map: (facility, slot) -> dayIdx -> bookings[]
              final startInclusive = startDay;
              final endInclusive = days.last;
              final dayIndexByYMD = {
                for (int i = 0; i < days.length; i++)
                  '${days[i].year}-${days[i].month}-${days[i].day}': i
              };

              final facIds = facDocs.map((d) => d.id).toSet();
              final grid = <_RowKey, Map<int, List<Map<String, dynamic>>>>{};

              for (final d in facDocs) {
                final slots = slotsByFid[d.id] ?? 1;
                for (int s = 1; s <= slots; s++) {
                  grid[_RowKey(fid: d.id, seatIndex: s)] =
                  {for (int i = 0; i < 7; i++) i: <Map<String, dynamic>>[]};
                }
              }

              // fill grid (with STATUS filter applied)
              final nowDT = DateTime.now();
              for (final doc in bookSnap.data!.docs) {
                final m = doc.data();

                // facility scope
                final fid = _readFirstStr(m, const [
                  'facilityId','facilityID','facilityDocId','facility_id'
                ]);
                if (!facIds.contains(fid)) continue;

                // day range scope
                final bd = _readBookingDate(m);
                if (bd == null) continue;
                final dayOnly = DateTime(bd.year, bd.month, bd.day);
                if (dayOnly.isBefore(startInclusive) || dayOnly.isAfter(endInclusive)) continue;

                // status scope
                final st = _readTime(m, const ['start','startTime','timeStart']);
                final en = _readTime(m, const ['end','endTime','timeEnd']);
                final status = _computeStatus(
                  nowDT,
                  DateTime(dayOnly.year, dayOnly.month, dayOnly.day),
                  st, en,
                );
                if (!_isStatusAllowed(status)) continue;

                // seat mapping
                final seatStr = _readFirstStr(
                    m, const ['seatIndex','slotNumber','seatNumber','slot','seat']);
                final seatIndex = int.tryParse(seatStr) ?? -1;

                final di = dayIndexByYMD['${bd.year}-${bd.month}-${bd.day}'];
                if (di == null) continue;

                final key = _RowKey(fid: fid, seatIndex: seatIndex);
                grid.putIfAbsent(key,
                        () => {for (int i = 0; i < 7; i++) i: <Map<String, dynamic>>[]});
                grid[key]![di]!.add(m);
              }

              // Header (no gap below)
              final header = SizedBox(
                width: totalWidth,
                child: Table(
                  columnWidths: {
                    0: FixedColumnWidth(wFacilityCol),
                    1: FixedColumnWidth(wSlotCol),
                    for (int i = 2; i <= 8; i++) i: FixedColumnWidth(wDayCol),
                  },
                  border: TableBorder.all(color: gridColor, width: 1),
                  children: [
                    TableRow(
                      decoration: const BoxDecoration(color: headerBg),
                      children: [
                        _hdrCell('Facility', align: Alignment.centerLeft,
                            pad: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h)),
                        _hdrCell('Slot'),
                        for (final d in days) _hdrCell(_fmtDayHeader(d)),
                      ],
                    ),
                  ],
                ),
              );

              // Body blocks (merged facility column). First block: remove top border to avoid a visible gap
              return Scrollbar(
                controller: _vCtrl,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _vCtrl,
                  child: Scrollbar(
                    controller: _hCtrl,
                    thumbVisibility: true,
                    notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
                    child: SingleChildScrollView(
                      controller: _hCtrl,
                      scrollDirection: Axis.horizontal,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          header,
                          for (int idx = 0; idx < facDocs.length; idx++)
                            _facilityBlock(
                              fid: facDocs[idx].id,
                              facilityName: (facDocs[idx].data()['name'] ?? '').toString(),
                              slots: slotsByFid[facDocs[idx].id] ?? 1,
                              wFacilityCol: wFacilityCol,
                              wSlotCol: wSlotCol,
                              wDayCol: wDayCol,
                              gridColor: gridColor,
                              daysCount: 7,
                              grid: grid,
                              topBorder: idx != 0, // <- no top border on the first block
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _facilityBlock({
    required String fid,
    required String facilityName,
    required int slots,
    required double wFacilityCol,
    required double wSlotCol,
    required double wDayCol,
    required Color gridColor,
    required int daysCount,
    required Map<_RowKey, Map<int, List<Map<String, dynamic>>>> grid,
    required bool topBorder,
  }) {
    final sCount = slots <= 0 ? 1 : slots;

    final leftBorder = Border(
      top: topBorder ? BorderSide(color: gridColor, width: 1) : BorderSide.none,
      left: BorderSide(color: gridColor, width: 1),
      right: BorderSide(color: gridColor, width: 1),
      bottom: BorderSide(color: gridColor, width: 1),
    );

    final tableBorder = TableBorder(
      top: topBorder ? BorderSide(color: gridColor, width: 1) : BorderSide.none,
      left: BorderSide(color: gridColor, width: 1),
      right: BorderSide(color: gridColor, width: 1),
      bottom: BorderSide(color: gridColor, width: 1),
      horizontalInside: BorderSide(color: gridColor, width: 1),
      verticalInside: BorderSide(color: gridColor, width: 1),
    );

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // FACILITY (single tall cell)
          Container(
            width: wFacilityCol,
            alignment: Alignment.centerLeft,
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
            decoration: BoxDecoration(color: const Color(0xFFF8F5FF), border: leftBorder),
            child: Text(facilityName, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
          ),
          // SLOTS + 7 DAYS
          SizedBox(
            width: wSlotCol + daysCount * wDayCol,
            child: Table(
              columnWidths: {
                0: FixedColumnWidth(wSlotCol),
                for (int i = 1; i <= daysCount; i++) i: FixedColumnWidth(wDayCol),
              },
              border: tableBorder,
              children: List<TableRow>.generate(sCount, (i) {
                final s = i + 1;
                final rk = _RowKey(fid: fid, seatIndex: s);
                return TableRow(children: [
                  _cell(Text('Slot $s', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600))),
                  for (int di = 0; di < daysCount; di++)
                    _cell(_dayCellSimple(grid[rk]?[di] ?? const <Map<String, dynamic>>[])),
                ]);
              }),
            ),
          ),
        ],
      ),
    );
  }

  bool _isStatusAllowed(String status) {
    final anyOn = _stUpcoming || _stOngoing || _stEnded;
    if (!anyOn) return true;
    if (_stUpcoming && status == 'upcoming') return true;
    if (_stOngoing && status == 'ongoing') return true;
    if (_stEnded && status == 'ended') return true;
    return false;
  }

  String _readFacilityCategoryId(Map<String, dynamic> m) {
    for (final k in const ['categoryId','categoryID','category','catId']) {
      final v = m[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
      if (v != null) return v.toString();
    }
    return '';
  }


  Widget _cell(Widget child) => Container(padding: EdgeInsets.all(8.w), child: child);


  String _fmtDayHeader(DateTime d) {
    const wd = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];
    final w = wd[d.weekday % 7];
    final dm = '${d.day}/${d.month}'; // e.g., 31/5
    return '$w\n$dm';
  }

  // ------- parsing / formatting helpers -------
  int _readSlots(Map<String, dynamic> m) {
    final keys = ['availableSlots', 'slotCount', 'slots'];
    for (final k in keys) {
      if (m.containsKey(k)) {
        final v = m[k];
        if (v is int) return v > 0 ? v : 1;
        if (v is String) {
          final n = int.tryParse(v.trim());
          if (n != null && n > 0) return n;
        }
      }
    }
    return 1;
  }

  DateTime? _readBookingDate(Map<String, dynamic> m) {
    const keys = ['bookingDate', 'date', 'bookDate', 'day'];
    for (final k in keys) {
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
        if (v is String && v.trim().isNotEmpty) return v.trim();
        if (v != null) return v.toString();
      }
    }
    return '';
  }

  String _computeStatus(
      DateTime nowDT, DateTime? bookDay, DateTime? st, DateTime? en) {
    if (bookDay == null) return 'upcoming';
    final today = DateTime(nowDT.year, nowDT.month, nowDT.day);
    if (bookDay.isAfter(today)) return 'upcoming';
    if (bookDay.isBefore(today)) return 'ended';

    if (st == null || en == null) return 'upcoming';
    final stDT = DateTime(
        bookDay.year, bookDay.month, bookDay.day, st.hour, st.minute, st.second);
    final enDT = DateTime(
        bookDay.year, bookDay.month, bookDay.day, en.hour, en.minute, en.second);
    if (nowDT.isBefore(stDT)) return 'upcoming';
    if (!nowDT.isBefore(enDT)) return 'ended';
    return 'ongoing';
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
        h -= 12;
      }
      final mm = d.minute.toString().padLeft(2, '0');
      return '$h.$mm $ampm';
    }
  }

  String _formatRange(DateTime st, DateTime en, bool use24) =>
      '${_formatOne(st, use24)} - ${_formatOne(en, use24)}';

  DateTime? _tryParseYMD(String s) {
    try {
      final p = s.split('-');
      if (p.length == 3) {
        return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
      }
    } catch (_) {}
    return null;
  }

  DateTime? _tryParseDMY(String s) {
    try {
      final p = s.split('/');
      if (p.length == 3) {
        return DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0]));
      }
    } catch (_) {}
    return null;
  }

  DateTime? _tryParseHMS(String s) {
    try {
      final p = s.split(':');
      if (p.length == 3) {
        final n = DateTime.now();
        return DateTime(n.year, n.month, n.day, int.parse(p[0]),
            int.parse(p[1]), int.parse(p[2]));
      }
    } catch (_) {}
    return null;
  }

  DateTime? _tryParseHM(String s) {
    try {
      final p = s.split(':');
      if (p.length == 2) {
        final n = DateTime.now();
        return DateTime(
            n.year, n.month, n.day, int.parse(p[0]), int.parse(p[1]));
      }
    } catch (_) {}
    return null;
  }
}

// ============== Small live helpers ==============
class _ManagerNameLive extends StatelessWidget {
  final String managerId;
  final TextStyle style;
  final TextOverflow overflow;

  const _ManagerNameLive({
    Key? key,
    required this.managerId,
    required this.style,
    this.overflow = TextOverflow.ellipsis,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (managerId.isEmpty) {
      return Text('—', style: style, overflow: overflow);
    }
    final ref =
    FirebaseFirestore.instance.collection('UserInformation').doc(managerId);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ref.snapshots(),
      builder: (_, snap) {
        String name = '—';
        final data = snap.data?.data();
        if (data != null) {
          if (data['name'] is String &&
              (data['name'] as String).trim().isNotEmpty) {
            name = (data['name'] as String).trim();
          } else if (data['userName'] is String &&
              (data['userName'] as String).trim().isNotEmpty) {
            name = (data['userName'] as String).trim();
          } else if (data['username'] is String &&
              (data['username'] as String).trim().isNotEmpty) {
            name = (data['username'] as String).trim();
          }
        }
        return (name != '—')
            ? Text('Manager: $name', style: style, overflow: overflow)
            : Text('—', style: style, overflow: overflow);
      },
    );
  }
}

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
    if (facilityId.isEmpty) return Text('—', style: style, overflow: overflow);
    final ref =
    FirebaseFirestore.instance.collection('Facilities').doc(facilityId);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ref.snapshots(),
      builder: (_, snap) {
        final data = snap.data?.data();
        final name = (data?['name'] is String &&
            (data?['name'] as String).trim().isNotEmpty)
            ? (data!['name'] as String).trim()
            : '—';
        return Text(name, style: style, overflow: overflow);
      },
    );
  }
}

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
    if (uid.isEmpty) return Text('—', style: style, overflow: overflow);
    final ref = FirebaseFirestore.instance.collection('UserInformation').doc(uid);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ref.snapshots(),
      builder: (_, snap) {
        final data = snap.data?.data();
        String name = '—';
        if (data != null) {
          if (data['name'] is String &&
              (data['name'] as String).trim().isNotEmpty) {
            name = (data['name'] as String).trim();
          } else if (data['userName'] is String &&
              (data['userName'] as String).trim().isNotEmpty) {
            name = (data['userName'] as String).trim();
          } else if (data['username'] is String &&
              (data['username'] as String).trim().isNotEmpty) {
            name = (data['username'] as String).trim();
          }
        }
        return Text(name, style: style, overflow: overflow);
      },
    );
  }
}

// key for a row (facility + slot)
class _RowKey {
  final String fid;
  final int seatIndex;
  const _RowKey({required this.fid, required this.seatIndex});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          (other is _RowKey && fid == other.fid && seatIndex == other.seatIndex);

  @override
  int get hashCode => Object.hash(fid, seatIndex);
}
