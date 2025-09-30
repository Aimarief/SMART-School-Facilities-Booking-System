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

  late DateTime _selectedDate;
  late DateTime _visibleMonthFirst;
  bool _filterByDate = false;
  bool _use24HourFormat = true;
  bool _stUpcoming = false;
  bool _stOngoing = false;
  bool _stEnded = false;


  final Set<String> _selectedCategoryIds = <String>{};

  final Set<String> _selectedFacilityIds = <String>{};

  String _role = 'unknown'; // 'Admin' | 'Manager' |
  String? _currentUid;
  String _managerName = '';


  final ScrollController _hCtrl = ScrollController();
  final ScrollController _vCtrl = ScrollController();

  //---------------------------------------
// do init state first before anything
//---------------------------------------

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    //---------------------------------------
// set today as selected and the month taht show in calender is this month then load user role first
//---------------------------------------

    _selectedDate = DateTime(now.year, now.month, now.day);
    _visibleMonthFirst = DateTime(now.year, now.month, 1);
    _loadUserRole();
  }

//---------------------------------------
// load user role
//---------------------------------------
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

         if (data['username'] is String && (data['username'] as String).trim().isNotEmpty) {
            newName = (data['username'] as String).trim();
          }
        }
      }
//---------------------------------------
// get the role and set state
//---------------------------------------

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

//---------------------------------------
// get the start of first day in the month (get next month first day, then minuz 1 get total day
//---------------------------------------
  int _daysInMonth(DateTime firstOfMonth) {
    final firstNext = DateTime(firstOfMonth.year, firstOfMonth.month + 1, 1);
    final lastCurrent = firstNext.subtract(const Duration(days: 1));
    return lastCurrent.day;
  }
//---------------------------------------
// modulus to get empty cell at the back of the first day
//---------------------------------------

  int _leadingEmptyCells(DateTime firstOfMonth) {
    final wd = firstOfMonth.weekday % 7; // Sun=0
    return wd;
  }

//---------------------------------------
// check if same day
//---------------------------------------

  bool _isSameYMD(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

//---------------------------------------
//get the month name
//---------------------------------------
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

//---------------------------------------
// check if the same date as pick previously
//---------------------------------------

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
//---------------------------------------
// go to previous month
//---------------------------------------

  void _prevMonth() {
    final f = _visibleMonthFirst;
    setState(() {
      _visibleMonthFirst = DateTime(f.year, f.month - 1, 1);
    });
  }
//---------------------------------------
// go to next month
//---------------------------------------

  void _nextMonth() {
    final f = _visibleMonthFirst;
    setState(() {
      _visibleMonthFirst = DateTime(f.year, f.month + 1, 1);
    });
  }

//---------------------------------------
// when the status is toggle
//---------------------------------------

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

//---------------------------------------
// when category is selected
//---------------------------------------

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


//---------------------------------------
// when facility is press
//---------------------------------------

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

//---------------------------------------
// decide the legend colour
//---------------------------------------

  Widget _legendSwatch(Color fill, Color border) {
    return Container(
      width: 16.w,
      height: 16.w,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(4.r),
        border: Border.all(color: border, width: 1),
      ),
    );
  }

//---------------------------------------
// main build
//---------------------------------------
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
//---------------------------------------
// left box
//---------------------------------------
          SizedBox(
            width: sideW,
            height: 1.0.sh,
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
//---------------------------------------
// list the widget that have in left bar
//---------------------------------------
                  Text('List of Bookings',
                      style:
                      TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),
                  SizedBox(height: 16.h),
                  _buildCalendarCard(),
                  SizedBox(height: 16.h),
                  _buildStatusFilter(),
                  SizedBox(height: 12.h),
                  _buildCategoryOrFacilityFilter(),

                ],
              ),
            ),
          ),
//---------------------------------------
// the right part
//---------------------------------------
          Expanded(
              child:
          _buildTimetablePanel()
          ),
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
//---------------------------------------
// build calender main design
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
          SizedBox(height: 8.h),
        ],
      ),
    );
  }
//---------------------------------------
// header of calendar design
//---------------------------------------

  Widget _buildCalendarHeader() {
    final m = _visibleMonthFirst;
    final label = '${_monthName(m.month)} ${m.year}';
    return Row(
      children: <Widget>[
        Expanded(
            child: Text(label,
                style:
                TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600))
        ),
        TextButton(
            onPressed: _prevMonth,
            child: Text('Prev', style: TextStyle(fontSize: 12.sp))
        ),
        SizedBox(width: 4.w),
        TextButton(
            onPressed: _nextMonth,
            child: Text('Next', style: TextStyle(fontSize: 12.sp))),
      ],
    );
  }

//---------------------------------------
// build calendar week that row
//---------------------------------------
  Widget _buildWeekdayRow() {
    const days = <String>['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];
    return LayoutBuilder(
      builder: (context, c) {
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
                    style: TextStyle(fontSize: 11.sp, color: const Color(0xFF6B7280), fontWeight: FontWeight.w600)
                ),
              ),
            );
          }),
        );
      },
    );
  }

//---------------------------------------
// display the calender to pick date
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
//---------------------------------------
// calculate the day date
//---------------------------------------
                  children: List.generate(7, (cIdx) {
                    final cellIndex = (r * 7) + cIdx;
                    final dayNum = cellIndex - lead + 1;

                    final inMonth = dayNum >= 1 && dayNum <= days;
                    DateTime? cellDate =
                    inMonth ? DateTime(f.year, f.month, dayNum) : null;
                    final isSelected = (cellDate != null && _filterByDate)
                        ? _isSameYMD(cellDate, _selectedDate)
                        : false;
//---------------------------------------
// builde the cell day each day each day
//---------------------------------------
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
//---------------------------------------
// design for each day cell
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
                style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: text)
            ),
          ),
        ),
      ),
    );
  }

//---------------------------------------
// cell for header
//---------------------------------------

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

//---------------------------------------
// each design for the cell in the table
//---------------------------------------

  Widget _dayCellSimple(List<Map<String, dynamic>> items) {


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
              m, const ['userId']);
          final st = _readTime(m, const ['start']);
          final en = _readTime(m, const ['end']);
          final bd = _readBookingDate(m) ?? st;

          final status = _computeStatus(
            nowDT,
            bd != null ? DateTime(bd.year, bd.month, bd.day) : null,
            st, en,
          );
//---------------------------------------
// set colour for each cell
//---------------------------------------

          Color bg = const Color(0xFFE5E7EB), bdColor = const Color(0xFF9CA3AF);
          if (status == 'upcoming') { bg = const Color(0xFFD1FAE5); bdColor = const Color(0xFF10B981); }
          else if (status == 'ongoing') { bg = const Color(0xFFFEF3C7); bdColor = const Color(0xFFF59E0B); }

//---------------------------------------
// label time
//---------------------------------------

          String timeLabel = '-';
          if (st != null) {
            timeLabel = (en != null) ? _formatRange(st, en, _use24HourFormat)
                : _formatOne(st, _use24HourFormat);
          }

          final double chipMinH = 52.h;
//---------------------------------------
// display
//---------------------------------------

          return Container(
            width: double.infinity,
            margin: EdgeInsets.only(bottom: i == items.length - 1 ? 0 : 6.h),
            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 6.h),
            constraints: BoxConstraints(minHeight: chipMinH),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(8.r),
              border: Border.all(color: bdColor, width: 1),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,                               // shrink to content
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
//---------------------------------------
// get the username
//---------------------------------------
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

//---------------------------------------
// status filter design
//---------------------------------------

  Widget _buildStatusFilter() {

    const upcomingFill  = Color(0xFFD1FAE5);
    const upcomingBd    = Color(0xFF10B981);
    const ongoingFill   = Color(0xFFFEF3C7);
    const ongoingBd     = Color(0xFFF59E0B);
    const endedFill     = Color(0xFFE5E7EB);
    const endedBd       = Color(0xFF9CA3AF);

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
//---------------------------------------
// each of the check box
//---------------------------------------
          CheckboxListTile(
            value: _stUpcoming,
            onChanged: _tapStUpcoming,
            title: Text('Upcoming', style: TextStyle(fontSize: 12.sp)),
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            secondary: _legendSwatch(upcomingFill, upcomingBd),
          ),

          CheckboxListTile(
            value: _stOngoing,
            onChanged: _tapStOngoing,
            title: Text('Ongoing', style: TextStyle(fontSize: 12.sp)),
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            secondary: _legendSwatch(ongoingFill, ongoingBd),
          ),

          CheckboxListTile(
            value: _stEnded,
            onChanged: _tapStEnded,
            title: Text('Ended', style: TextStyle(fontSize: 12.sp)),
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            secondary: _legendSwatch(endedFill, endedBd),
          ),

          SizedBox(height: 4.h),
          Text(
            'Tip: If none is ticked, it means All.',
            style: TextStyle(fontSize: 11.sp, color: const Color(0xFF6B7280)),
          ),
        ],
      ),
    );
  }

//---------------------------------------
// decide category or facility filter
//---------------------------------------

  Widget _buildCategoryOrFacilityFilter() {
//---------------------------------------
// if role is manager then build for manager, if admin then build for admin
//---------------------------------------
    return (_role.toLowerCase() == 'manager')
        ? _buildFacilityFilter()
        : _buildCategoryFilter();
  }

  //---------------------------------------
//  category filter design
//---------------------------------------

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

        ],
      ),
    );
  }

//---------------------------------------
// facility filter for manager
//---------------------------------------

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
              builder: (context, snap) {
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
//---------------------------------------
// get only the not deleted facility
//---------------------------------------
                final all = snap.data!.docs;
                final visible = all.where((d) {
                  final m = d.data();
                  final del = m['deleted'];
                  if (del is bool) return del == false;
                  if (del is String) return del.toLowerCase() != 'true';
                  return true;
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

        ],
      ),
    );
  }
//---------------------------------------
// build the time table right side
//---------------------------------------
  Widget _buildTimetablePanel() {

    final base = _filterByDate ? _selectedDate : DateTime.now();
    final startDay = DateTime(base.year, base.month, base.day);
    final days = List<DateTime>.generate(7, (i) =>
        DateTime(startDay.year, startDay.month, startDay.day + i));

//---------------------------------------
// for manager
//---------------------------------------
    final facilitiesQuery = (_role.toLowerCase() == 'manager' && _currentUid != null)
        ? FirebaseFirestore.instance.collection('Facilities')
        .where('managerId', isEqualTo: _currentUid).snapshots()
        : FirebaseFirestore.instance.collection('Facilities').snapshots();
//---------------------------------------
// get the bookings taht is accepted
//---------------------------------------
    final bookingsQuery = FirebaseFirestore.instance
        .collection('Bookings')
        .where('deleted', isEqualTo: false)
        .where('approval', isEqualTo: 'accepted')
        .snapshots();

    final wFacilityCol = 260.w;
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
        builder: (context, facSnap) {
          if (facSnap.connectionState == ConnectionState.waiting) {
            return Center(child: Text('Loading timetable...',
                style: TextStyle(fontSize: 14.sp)));
          }
          if (facSnap.hasError || !facSnap.hasData) {
            return Center(child: Text('Failed to load facilities',
                style: TextStyle(fontSize: 14.sp)));
          }

//---------------------------------------
// only take no deleted facility
//---------------------------------------
          final allFacDocs = facSnap.data!.docs.where((d) {
            final m = d.data();
            final del = m['deleted'];
            if (del is bool) return del == false;
            if (del is String) return del.toLowerCase() != 'true';
            return true;
          }).toList();

//---------------------------------------
// for admin get the booking with the category id
//---------------------------------------
          List<QueryDocumentSnapshot<Map<String, dynamic>>> facDocs = allFacDocs;
          if (_role.toLowerCase() != 'manager' && _selectedCategoryIds.isNotEmpty) {
            facDocs = facDocs.where((d) {
              final catId = _readFacilityCategoryId(d.data());
              return catId.isNotEmpty && _selectedCategoryIds.contains(catId);
            }).toList();
          }
//---------------------------------------
// if have the facility id is picked , search it in booking
//---------------------------------------
          if (_selectedFacilityIds.isNotEmpty) {
            facDocs = facDocs.where((d) => _selectedFacilityIds.contains(d.id)).toList();
          }

//---------------------------------------
// sort by name
//---------------------------------------
          facDocs.sort((a, b) {
            final na = (a.data()['name'] ?? '').toString().toLowerCase();
            final nb = (b.data()['name'] ?? '').toString().toLowerCase();
            return na.compareTo(nb);
          });
//---------------------------------------
// find the available slot for the facility
//---------------------------------------
          final slotsByFid = <String, int>{
            for (final d in facDocs) d.id: _readSlots(d.data())
          };

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: bookingsQuery,
            builder: (context, bookSnap) {
              if (bookSnap.connectionState == ConnectionState.waiting) {
                return Center(child: Text('Loading bookings...',
                    style: TextStyle(fontSize: 14.sp)));
              }
              if (bookSnap.hasError || !bookSnap.hasData) {
                return Center(child: Text('Failed to load bookings',
                    style: TextStyle(fontSize: 14.sp)));
              }
//---------------------------------------
// 7 slot for day
//---------------------------------------

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
//---------------------------------------
// get bookind id from database
//---------------------------------------

              final nowDT = DateTime.now();
              for (final doc in bookSnap.data!.docs) {
                final m = doc.data();
//---------------------------------------
// get facility id belong to the booking id
//---------------------------------------

                final fid = _readFirstStr(m, const ['facilityId']);
                if (!facIds.contains(fid)) continue;

//---------------------------------------
// get and read the booking date
//---------------------------------------

                final bd = _readBookingDate(m);
                if (bd == null) continue;
                final dayOnly = DateTime(bd.year, bd.month, bd.day);
                if (dayOnly.isBefore(startInclusive) || dayOnly.isAfter(endInclusive)) continue;

//---------------------------------------
// get and read the time
//---------------------------------------
                final st = _readTime(m, const ['start']);
                final en = _readTime(m, const ['end']);

//---------------------------------------
// get the sattus and check whether the status is in the filter list
//---------------------------------------

                final status = _computeStatus(nowDT, DateTime(dayOnly.year, dayOnly.month, dayOnly.day), st, en,);
                if (!_isStatusAllowed(status)) continue;

//---------------------------------------
// decide which slot
//---------------------------------------

                final seatStr = _readFirstStr(
                    m, const ['seatIndex']);
                final seatIndex = int.tryParse(seatStr) ?? -1;

                final di = dayIndexByYMD['${bd.year}-${bd.month}-${bd.day}'];
                if (di == null) continue;
//---------------------------------------
// get the facility and seat index
//---------------------------------------
                final key = _RowKey(fid: fid, seatIndex: seatIndex);
                grid.putIfAbsent(key,
                        () => {for (int i = 0; i < 7; i++) i: <Map<String, dynamic>>[]});
                grid[key]![di]!.add(m);
              }

//---------------------------------------
// header for the table
//---------------------------------------
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
//---------------------------------------
// the place the design the whole table
//---------------------------------------

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
//---------------------------------------
// function displaying each row by each row
//---------------------------------------

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
//---------------------------------------
// part where id display the design of the table
//---------------------------------------

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
//---------------------------------------
// display facility column
//---------------------------------------
          Container(
            width: wFacilityCol,
            alignment: Alignment.centerLeft,
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
            decoration: BoxDecoration(color: const Color(0xFFF8F5FF), border: leftBorder),
            child: Text(facilityName, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
          ),
//---------------------------------------
// display each slot for next 7 days
//---------------------------------------
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

//---------------------------------------
// filter base on status
//---------------------------------------

  bool _isStatusAllowed(String status) {
    final anyOn = _stUpcoming || _stOngoing || _stEnded;
    if (!anyOn) return true;
    if (_stUpcoming && status == 'upcoming') return true;
    if (_stOngoing && status == 'ongoing') return true;
    if (_stEnded && status == 'ended') return true;
    return false;
  }

//---------------------------------------
// get the booking with the categoryid
//---------------------------------------

  String _readFacilityCategoryId(Map<String, dynamic> m) {
    for (final k in const ['categoryId']) {
      final v = m[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
      if (v != null) return v.toString();
    }
    return '';
  }


  Widget _cell(Widget child) => Container(padding: EdgeInsets.all(8.w), child: child);

//---------------------------------------
// header cell for day
//---------------------------------------
  String _fmtDayHeader(DateTime d) {
    const wd = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];
    final w = wd[d.weekday % 7];
    final dm = '${d.day}/${d.month}'; // e.g., 31/5
    return '$w\n$dm';
  }

//---------------------------------------
// get the available slot
//---------------------------------------

  int _readSlots(Map<String, dynamic> m) {
    final keys = ['availableSlots'];
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
//---------------------------------------
//  get the bookingdate
//---------------------------------------

  DateTime? _readBookingDate(Map<String, dynamic> m) {
    const keys = ['bookingDate'];
    for (final k in keys) {
      if (m.containsKey(k)) {
        final v = m[k];
        if (v is Timestamp) return v.toDate();
        if (v is DateTime) return v;
        if (v is String) {
          final p = _tryParseYMD(v);
          if (p != null) return p;
        }
      }
    }
    return null;
  }
//---------------------------------------
// get the time
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
//---------------------------------------
// get the status
//---------------------------------------

  String _computeStatus(DateTime nowDT, DateTime? bookDay, DateTime? st, DateTime? en) {
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

  //---------------------------------------
// parse and get the year month and day
//---------------------------------------

  DateTime? _tryParseYMD(String s) {
    try {
      final p = s.split('-');
      if (p.length == 3) {
        return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
      }
    } catch (_) {}
    return null;
  }

//---------------------------------------
// parse the time
//---------------------------------------
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


//---------------------------------------
// get the username
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
    if (uid.isEmpty) return Text('—', style: style, overflow: overflow);
    final ref = FirebaseFirestore.instance.collection('UserInformation').doc(uid);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ref.snapshots(),
      builder: (_, snap) {
        final data = snap.data?.data();
        String name = '—';
        if (data != null) {
        if (data['username'] is String &&
              (data['username'] as String).trim().isNotEmpty) {
            name = (data['username'] as String).trim();
          }
        }
        return Text(name, style: style, overflow: overflow);
      },
    );
  }
}

//---------------------------------------
// store the facility and slot together
//---------------------------------------

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
