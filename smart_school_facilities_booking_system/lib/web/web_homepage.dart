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

//---------------------------------------
// decide the legend colour and size
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
                    DateTime? cellDate = inMonth ? DateTime(f.year, f.month, dayNum) : null;
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

    final List<Map<String, dynamic>> sorted =
    List<Map<String, dynamic>>.from(items);

//---------------------------------------
// sort the time in the list
//---------------------------------------
    sorted.sort((a, b) {
      final DateTime? sa = _readTime(a, const ['start']); // start of a
      final DateTime? sb = _readTime(b, const ['start']); // start of b
      if (sa == null && sb == null) return 0;  // both no start -> equal
      if (sa == null) return 1;// a has no start -> after b
      if (sb == null) return -1;// b has no start -> after a
      return sa.compareTo(sb);// normal ascending compare
    });


    return Container(
      padding: EdgeInsets.all(8.w),
      constraints: BoxConstraints(minHeight: 64.h),

      //---------------------------------------
// if no booking on that day, show noting
//---------------------------------------
      child: sorted.isEmpty
          ? const SizedBox.shrink()
          : Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,

        //---------------------------------------
// if there is
//---------------------------------------
        children: List.generate(sorted.length, (i) {
          final m = sorted[i];
          final uid = _readFirstStr(
              m, const ['userId']);
          final st = _readTime(m, const ['start']);
          final en = _readTime(m, const ['end']);
          final bd = _readBookingDate(m) ?? st;
//---------------------------------------
// compute the status again
//---------------------------------------
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
          //---------------------------------------
// get category from database which is not deleted
//---------------------------------------
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
 //---------------------------------------
// display each of the category check box
//---------------------------------------
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
                    controlAffinity: ListTileControlAffinity.leading, // the check box placement
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
          //---------------------------------------
// wen into database get the manager id that belongs to facilities
//---------------------------------------

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
//---------------------------------------
// generate list base on facility the manager manage
//---------------------------------------
                return Column(
                  children: List.generate(visible.length, (i) {
                    final m = visible[i].data();
                    final id = visible[i].id;

                    String name = '';
                    final v = m['name'];
                    if (v is String && v.trim().isNotEmpty) name = v.trim();
                    if (name.isEmpty) name = '(no name)';

                    final checked = _selectedFacilityIds.contains(id);
//---------------------------------------
// check box for manager facility
//---------------------------------------
                    return CheckboxListTile(
                      value: checked,
                      onChanged: (val) => _toggleFacility(id, val),
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
    //---------------------------------------
// if not filter by date , date is start from today
//---------------------------------------
    final DateTime base = _filterByDate ? _selectedDate : DateTime.now();
    final DateTime startDay = DateTime(base.year, base.month, base.day);

    //---------------------------------------
// add next 6 days from start day
//---------------------------------------
    final List<DateTime> days = <DateTime>[];
    for (int i = 0; i < 7; i++) {
      days.add(DateTime(startDay.year, startDay.month, startDay.day + i));
    }

//---------------------------------------
// choose facility base on manager and admin
//---------------------------------------
    final Stream<QuerySnapshot<Map<String, dynamic>>> facilitiesQuery =
    (_role.toLowerCase() == 'manager' && _currentUid != null)
//---------------------------------------
// facility for that manager manager
//---------------------------------------
        ? FirebaseFirestore.instance
        .collection('Facilities')
        .where('managerId', isEqualTo: _currentUid)
        .where ('deleted', isEqualTo: false)
        .snapshots()
    //---------------------------------------
// facility snapshot for admin
//---------------------------------------
        : FirebaseFirestore.instance
        .collection('Facilities')
        .where ('deleted', isEqualTo: false)
        .snapshots();

//---------------------------------------
// get all booking taht is not deleted and approval is accepted
//---------------------------------------
    final Stream<QuerySnapshot<Map<String, dynamic>>> bookingsQuery =
    FirebaseFirestore.instance
        .collection('Bookings')
        .where('deleted', isEqualTo: false)
        .where('approval', isEqualTo: 'accepted')
        .snapshots();

//---------------------------------------
//  column width
//---------------------------------------
    final double wFacilityCol = 260.w;
    final double wSlotCol     = 120.w;
    final double wDayCol      = 180.w;

//---------------------------------------
// colour for header and facility
//---------------------------------------
    const Color headerBg  = Color(0xFFE9D5FF);
    const Color gridColor = Color(0xFFB18CE3);

//---------------------------------------
// whole width for the table
//---------------------------------------
    final double totalWidth = wFacilityCol + wSlotCol + (7 * wDayCol);

//---------------------------------------
// main build 3 for the time table
//---------------------------------------
    return Container(
      color: Colors.white,
      padding: EdgeInsets.all(16.w),
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        //---------------------------------------
// facility stream
//---------------------------------------
      stream: facilitiesQuery,
        builder: (context, facSnap) {

          if (facSnap.connectionState == ConnectionState.waiting) {
            return Center(child: Text('Loading timetable...', style: TextStyle(fontSize: 14.sp)));
          }
          if (facSnap.hasError || !facSnap.hasData) {
            return Center(child: Text('Failed to load facilities', style: TextStyle(fontSize: 14.sp)));
          }

//---------------------------------------
// get all not deleted facility
//---------------------------------------
          final List<QueryDocumentSnapshot<Map<String, dynamic>>> allFacDocs =
              facSnap.data!.docs;
          final List<QueryDocumentSnapshot<Map<String, dynamic>>> visibleFacs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
          for (int i = 0; i < allFacDocs.length; i++) {
            final Map<String, dynamic> m = allFacDocs[i].data();
            final dynamic del = m['deleted'];
            bool keep = true;
            if (del is bool) keep = del == false;
            if (keep) visibleFacs.add(allFacDocs[i]);
          }
          if (visibleFacs.isEmpty) {
            return Center(child: Text('No facilities', style: TextStyle(fontSize: 14.sp)));
          }

//---------------------------------------
// for admin when filter category , display the facility that belong to the category
//---------------------------------------
          List<QueryDocumentSnapshot<Map<String, dynamic>>> facDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
          if (_role.toLowerCase() != 'manager' && _selectedCategoryIds.isNotEmpty) {
            for (int i = 0; i < visibleFacs.length; i++) {
              final Map<String, dynamic> m = visibleFacs[i].data();
              final String catId = _readFacilityCategoryId(m);
              if (catId.isNotEmpty && _selectedCategoryIds.contains(catId)) {
                facDocs.add(visibleFacs[i]);
              }
            }
          } else {
//---------------------------------------
// if no filter by category
//---------------------------------------
            facDocs = visibleFacs;
          }
//---------------------------------------
// for manager if there is filter by selected facility
//---------------------------------------
          if (_selectedFacilityIds.isNotEmpty) {
            final List<QueryDocumentSnapshot<Map<String, dynamic>>> tmp = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
            for (int i = 0; i < facDocs.length; i++) {
              if (_selectedFacilityIds.contains(facDocs[i].id)) {
                tmp.add(facDocs[i]);
              }
            }
            //---------------------------------------
// if no filter by facility for manager
//---------------------------------------
            facDocs = tmp;
          }

//---------------------------------------
// sort all of the facility by name
//---------------------------------------
          facDocs.sort((a, b) {
            final String na = (a.data()['name'] ?? '').toString().toLowerCase();
            final String nb = (b.data()['name'] ?? '').toString().toLowerCase();
            return na.compareTo(nb);
          });

//---------------------------------------
// get the slot of the facility and store in like id = slot available
//---------------------------------------
          final Map<String, int> slotsByFid = <String, int>{};
          for (int i = 0; i < facDocs.length; i++) {
            final String fid = facDocs[i].id;
            final int slots = _readSlots(facDocs[i].data());
            slotsByFid[fid] = slots;
          }

//---------------------------------------
// booking stream
//---------------------------------------
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: bookingsQuery,
            builder: (context, bookSnap) {
              if (bookSnap.connectionState == ConnectionState.waiting) {
                return Center(child: Text('Loading bookings...', style: TextStyle(fontSize: 14.sp)));
              }
              if (bookSnap.hasError || !bookSnap.hasData) {
                return Center(child: Text('Failed to load bookings', style: TextStyle(fontSize: 14.sp)));
              }

              //---------------------------------------
// get year month and date and store in list (date month year = i)
//---------------------------------------
              final Map<String, int> dayIndexByYMD = <String, int>{};
              for (int i = 0; i < days.length; i++) {
                final DateTime d = days[i];
                dayIndexByYMD['${d.year}-${d.month}-${d.day}'] = i;
              }

//---------------------------------------
// add each of facility id into facIDs list
//---------------------------------------
              final Set<String> facIds = <String>{};
              for (int i = 0; i < facDocs.length; i++) {
                facIds.add(facDocs[i].id);
              }

//---------------------------------------
//   for each facility , get the available slot from that fac id
//---------------------------------------
              final Map<_RowKey, Map<int, List<Map<String, dynamic>>>> grid = <_RowKey, Map<int, List<Map<String, dynamic>>>>{};
              for (int i = 0; i < facDocs.length; i++) {
                final String fid = facDocs[i].id;
                final int slots = slotsByFid[fid] ?? 1;
                final int sCount = (slots <= 0) ? 1 : slots;
//---------------------------------------
// for each slot
//---------------------------------------
                for (int s = 1; s <= sCount; s++) {
//---------------------------------------
// store the facility and slot together as a key
//---------------------------------------
                  final _RowKey rk = _RowKey(fid: fid, seatIndex: s);
                  final Map<int, List<Map<String, dynamic>>> dayBuckets = <int, List<Map<String, dynamic>>>{};
                  for (int di = 0; di < 7; di++) {
                    dayBuckets[di] = <Map<String, dynamic>>[];
                  }
//---------------------------------------
// for each rk store 7 empty list
//---------------------------------------
                  grid[rk] = dayBuckets;
                }
              }

//---------------------------------------
//  for each booking
//---------------------------------------
              final DateTime nowDT = DateTime.now();
              for (int i = 0; i < bookSnap.data!.docs.length; i++) {
                final Map<String, dynamic> m = bookSnap.data!.docs[i].data();

//---------------------------------------
// get the facility id, if facids list did not have facility id , continue
//---------------------------------------
                final String fid = _readFirstStr(m, const ['facilityId']);
                if (!facIds.contains(fid)) continue;

//---------------------------------------
// get the booking date
//---------------------------------------
                final DateTime? bd = _readBookingDate(m);
                if (bd == null) continue;
//---------------------------------------
// get the date in date format then get the first day and the last day
//---------------------------------------
                final DateTime dayOnly = DateTime(bd.year, bd.month, bd.day);
                final DateTime startInclusive = days.first;
                final DateTime endInclusive = days.last;
//---------------------------------------
// if not in the day range list, continue
//---------------------------------------
                if (dayOnly.isBefore(startInclusive) || dayOnly.isAfter(endInclusive)) continue;

//---------------------------------------
// get the start adn end time
//---------------------------------------
                final DateTime? st = _readTime(m, const ['start']);
                final DateTime? en = _readTime(m, const ['end']);

//---------------------------------------
// get the status of this booking, upcoming, ongoing or ended
//---------------------------------------
                final String status = _computeStatus(nowDT, DateTime(dayOnly.year, dayOnly.month, dayOnly.day), st, en,);
 //---------------------------------------
// filter the status base on picked status
//---------------------------------------
                if (!_isStatusAllowed(status)) continue;

//---------------------------------------
// get the seatindex
//---------------------------------------
                final String seatStr = _readFirstStr(m, const ['seatIndex']);
                final int seatIndex = int.tryParse(seatStr) ?? -1;

//---------------------------------------
// find which booking day this column belongs to, must have because already make sure its in 7 days
//---------------------------------------
                final int? di = dayIndexByYMD['${bd.year}-${bd.month}-${bd.day}'];
                if (di == null) continue;

//---------------------------------------
// store the row key as facid:seat index, then check, if previous rk have it or not, if not have it, create new grid
// normally will have the key arleady
//---------------------------------------
                final _RowKey rk = _RowKey(fid: fid, seatIndex: seatIndex);
                if (!grid.containsKey(rk)) {
                  final Map<int, List<Map<String, dynamic>>> dayBuckets = <int, List<Map<String, dynamic>>>{};
                  for (int j = 0; j < 7; j++) {
                    dayBuckets[j] = <Map<String, dynamic>>[];
                  }
                  grid[rk] = dayBuckets;
                }
                //---------------------------------------
// for the rk that key and the date, add m (booking information)
//---------------------------------------
                grid[rk]![di]!.add(m);
              }
//---------------------------------------
// build header
//---------------------------------------
              final Widget header = _buildHeaderTable(
                days: days,
                totalWidth: totalWidth,
                wFacilityCol: wFacilityCol,
                wSlotCol: wSlotCol,
                wDayCol: wDayCol,
                headerBg: headerBg,
                gridColor: gridColor,
              );

//---------------------------------------
// build each of the row, base on the facDoc that already filter by category, by name
//---------------------------------------
              final List<Widget> blocks = <Widget>[];
              for (int idx = 0; idx < facDocs.length; idx++) {
                final String fid = facDocs[idx].id;
//---------------------------------------
// get facility name
//---------------------------------------
                final String facilityName = (facDocs[idx].data()['name'] ?? '').toString();
//---------------------------------------
// get the available slot from that fid
//---------------------------------------
                final int slots = slotsByFid[fid] ?? 1;
//---------------------------------------
// for each facility add this table to display at main design later
//---------------------------------------
                blocks.add(
                  _facilityBlock(
                    fid: fid,
                    facilityName: facilityName,
                    slots: slots,
                    wFacilityCol: wFacilityCol,
                    wSlotCol: wSlotCol,
                    wDayCol: wDayCol,
                    gridColor: gridColor,
                    daysCount: 7,
                    grid: grid,
                    topBorder: idx != 0, // keep original rule: first block no top border
                  ),
                );
              }

 //---------------------------------------
// allows h and v scroll
//---------------------------------------
              return
                SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                    child: SingleChildScrollView(
                      controller: _hCtrl,
                      scrollDirection: Axis.horizontal,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          header,       // header table
                          ...blocks,    // all facility blocks
                        ],
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
// build the header table (Facility | Slot | Day1..Day7)
//---------------------------------------
  Widget _buildHeaderTable({
    required List<DateTime> days,
    required double totalWidth,
    required double wFacilityCol,
    required double wSlotCol,
    required double wDayCol,
    required Color headerBg,
    required Color gridColor,
  }) {
    // build cells for the header row by FOR LOOP
    final List<Widget> headerCells = <Widget>[];

    // first two fixed cells
    headerCells.add(
      _hdrCell('Facility',
          align: Alignment.centerLeft,
          pad: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h)),
    );
    headerCells.add(_hdrCell('Slot'));

//---------------------------------------
// get the day for each day
//---------------------------------------
    for (int i = 0; i < days.length; i++) {
      headerCells.add(_hdrCell(_fmtDayHeader(days[i])));
    }

//---------------------------------------
// header display width
//---------------------------------------
    final Map<int, TableColumnWidth> widths = <int, TableColumnWidth>{};
    widths[0] = FixedColumnWidth(wFacilityCol);
    widths[1] = FixedColumnWidth(wSlotCol);
    for (int i = 2; i <= 8; i++) {
      widths[i] = FixedColumnWidth(wDayCol);
    }
//---------------------------------------
// display a table base on above set width and total column
//---------------------------------------
    return SizedBox(
      width: totalWidth,
      child: Table(
        columnWidths: widths,
        border: TableBorder.all(color: gridColor, width: 1),
        children: <TableRow>[
          TableRow(
            decoration: BoxDecoration(color: headerBg),
            children: headerCells,
          ),
        ],
      ),
    );
  }

//---------------------------------------
// part where it displays one facility block (left name + slot rows table)
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

    final int sCount = (slots <= 0) ? 1 : slots;

//---------------------------------------
// set the border colour ( top column )
//---------------------------------------
    final Border leftBorder = Border(
      top: topBorder ? BorderSide(color: gridColor, width: 1) : BorderSide.none,
      left: BorderSide(color: gridColor, width: 1),
      right: BorderSide(color: gridColor, width: 1),
      bottom: BorderSide(color: gridColor, width: 1),
    );
//---------------------------------------
// set the border colour ( whole border)
//---------------------------------------
    final TableBorder tableBorder = TableBorder(
      top: topBorder ? BorderSide(color: gridColor, width: 1) : BorderSide.none,
      left: BorderSide(color: gridColor, width: 1),
      right: BorderSide(color: gridColor, width: 1),
      bottom: BorderSide(color: gridColor, width: 1),
      horizontalInside: BorderSide(color: gridColor, width: 1),
      verticalInside: BorderSide(color: gridColor, width: 1),
    );

//---------------------------------------
// for each slot
//---------------------------------------
    final List<TableRow> rows = <TableRow>[];
    for (int i = 0; i < sCount; i++) {
      final int s = i + 1;// seat index
 //---------------------------------------
// pick the row key like id:seatindex
//---------------------------------------
      final _RowKey rk = _RowKey(fid: fid, seatIndex: s);
//---------------------------------------
// start to add the table cell
//---------------------------------------
      final List<Widget> rowCells = <Widget>[];
      rowCells.add(_cell(
        Text('Slot $s', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600)),
      ));
//---------------------------------------
// for each day, the item for that item will be the id:seatindex, date and the booking information
//---------------------------------------
      for (int di = 0; di < daysCount; di++) {
        final List<Map<String, dynamic>> items = grid[rk]?[di] ?? const <Map<String, dynamic>>[];
        rowCells.add(_cell(_dayCellSimple(items)));
      }
//---------------------------------------
// add all this cell into row
//---------------------------------------
      rows.add(TableRow(children: rowCells));
    }

//---------------------------------------
// design the cell
//---------------------------------------
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // left facility name column
          Container(
            width: wFacilityCol,
            alignment: Alignment.centerLeft,
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F5FF),
              border: leftBorder,
            ),
            child: Text(
              facilityName,
              style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700),
            ),
          ),
//---------------------------------------
// right side with slot and day
//---------------------------------------
          SizedBox(
            width: wSlotCol + daysCount * wDayCol,
            child: Table(
              columnWidths: <int, TableColumnWidth>{
                0: FixedColumnWidth(wSlotCol),
                for (int i = 1; i <= daysCount; i++) i: FixedColumnWidth(wDayCol),
              },
              border: tableBorder,
//---------------------------------------
// display row based on above
//---------------------------------------
              children: rows,
            ),
          ),
        ],
      ),
    );
  }


//---------------------------------------
// chck and return filter base on status
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

//---------------------------------------
// each cell will be a container with padding and edither 1 childe widget
//---------------------------------------
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
// compute the status
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
//---------------------------------------
// format date to am pm
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
// ---------------------------------------
// get manager name
// ---------------------------------------
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
    //---------------------------------------
// if no manager show -
//---------------------------------------
    if (managerId.isEmpty) {
      return Text('—', style: style, overflow: overflow);
    }

//---------------------------------------
// get the name throuhg id
//---------------------------------------
    final ref = FirebaseFirestore.instance
        .collection('UserInformation')
        .doc(managerId);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ref.snapshots(),
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Text('—', style: style, overflow: overflow);
        }

        if (!snap.hasData || !(snap.data?.exists ?? false)) {
          return Text('—', style: style, overflow: overflow);
        }

        final map = snap.data!.data();
        final raw = map?['username'];
        final name = (raw is String) ? raw.trim() : (raw?.toString() ?? '');

        return Text(
          name.isEmpty ? '—' : 'Manager: $name',
          style: style,
          overflow: overflow,
        );
      },
    );
  }
}

// ---------------------------------------
// get the username
// ---------------------------------------
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
    //---------------------------------------
// id no id show -
//---------------------------------------
    if (uid.isEmpty) {
      return Text('—', style: style, overflow: overflow);
    }

//---------------------------------------
// get the userinformation using id
//---------------------------------------
    final ref = FirebaseFirestore.instance
        .collection('UserInformation')
        .doc(uid);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ref.snapshots(),
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Text('—', style: style, overflow: overflow);
        }

        if (!snap.hasData || !(snap.data?.exists ?? false)) {
          return Text('—', style: style, overflow: overflow);
        }

        final map = snap.data!.data();
        final raw = map?['username'];
        final name = (raw is String) ? raw.trim() : (raw?.toString() ?? '');

        return Text(
          name.isEmpty ? '—' : name,
          style: style,
          overflow: overflow,
        );
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
