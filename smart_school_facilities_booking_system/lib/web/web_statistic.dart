import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'web_top_bar.dart';
import 'package:go_router/go_router.dart';
import 'web_view_rating.dart';

//---------------------------------------
// point for line chart
//---------------------------------------

class _Point {
  final int xIndex;
  final double yValue;
  const _Point({required this.xIndex, required this.yValue});
}

//---------------------------------------
// one point for data
//---------------------------------------

class _BarDatum {
  final String label; // shown on X axis
  final int count;    // bar height
  const _BarDatum(this.label, this.count);
}

//---------------------------------------
// one point for double data
//---------------------------------------

class _BarDoubleDatum {
  final String label; // shown on X axis
  final double value; // average rating
  const _BarDoubleDatum(this.label, this.value);
}

class WebStatistic extends StatefulWidget {
  const WebStatistic({Key? key}) : super(key: key);

  @override
  State<WebStatistic> createState() => _WebStatisticState();
}

class _WebStatisticState extends State<WebStatistic> {

  final bool _use24HourFormat = true;
  final String _bookingDateField = 'bookingDate';// STRING date
  final String _statusField = 'status';
  final String _endedValue = 'ended';
  final String _facilityIdField = 'facilityId';// used for bars
  final String _userIdField = 'userId';// used for pie #1
  final String _ratedField = 'rated';// used for pie #2

  final String _colBookings   = 'Bookings';
  final String _colFacilities = 'Facilities';
  final String _colCategories = 'FacilitiesCategory';
  final String _colUsers      = 'UserInformation';

  late DateTime _fromDate;// from
  late DateTime _toDate;// to
  bool _loading = true;

  String _groupBy = 'Day'; // 'Day' or 'Month'

  final List<_Point> _linePoints = <_Point>[];
  final List<String> _xLabels = <String>[];

//---------------------------------------
// data for bar chart
//---------------------------------------

  final List<_BarDatum> _topFacilityBars = <_BarDatum>[];
  final List<_BarDatum> _topCategoryBars = <_BarDatum>[];

//---------------------------------------
// data for pie chart
//---------------------------------------

  int _countStudent = 0;
  int _countLecturer = 0;
  int _countRated = 0;
  int _countNotRated = 0;
//---------------------------------------
// total user
//---------------------------------------
  int _totalAdmin = 0;
  int _totalManager = 0;
  int _totalLecturer = 0;
  int _totalStudent = 0;

//---------------------------------------
// data for rating bar
//---------------------------------------

  final List<_BarDoubleDatum> _topHighestAvg = <_BarDoubleDatum>[];
  final List<_BarDoubleDatum> _topLowestAvg  = <_BarDoubleDatum>[];

//---------------------------------------
// init state first before anything
//---------------------------------------

  @override
  void initState() {
    super.initState();
    final DateTime now = DateTime.now();
    //---------------------------------------
// get the first day of this month and last day of this month
//---------------------------------------
    _fromDate = DateTime(now.year, now.month, 1);
    _toDate   = DateTime(now.year, now.month + 1, 1);
    _reload();
  }

//---------------------------------------
// load data first
//---------------------------------------
  Future<void> _reload() async {
    setState(() => _loading = true);
    await Future.wait([
//---------------------------------------
// load all data belong within the date, all the top 5 top 5 data
//---------------------------------------
      _loadAllData(),
//---------------------------------------
// load amount of all user role
//---------------------------------------
      _loadRoleCounts(),
    ]);
    if (!mounted) return;
    setState(() => _loading = false);
  }


//---------------------------------------
// date range picker
//---------------------------------------

  Future<void> _pickDateRange() async {
//---------------------------------------
// show range picker for date
//---------------------------------------

    final DateTimeRange? range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2022, 1, 1),
      lastDate: DateTime(2100, 1, 1),
      initialDateRange: DateTimeRange(
        start: _fromDate,
        end: _toDate.subtract(const Duration(days: 1)),
      ),
      helpText: 'Select report date range',
    );
    if (range == null) return;

    final DateTime start = DateTime(range.start.year, range.start.month, range.start.day);
    final DateTime endExclusive = DateTime(range.end.year, range.end.month, range.end.day).add(const Duration(days: 1));
//---------------------------------------
// set state to rebuild Ui base on date
//---------------------------------------
    setState(() {
      _fromDate = start;
      _toDate   = endExclusive;
    });

    await _reload();
  }

//---------------------------------------
// load all ended booking
//---------------------------------------

  Future<void> _loadAllData() async {

    _linePoints.clear();
    _xLabels.clear();
    _topFacilityBars.clear();
    _topCategoryBars.clear();
    _countStudent = 0;
    _countLecturer = 0;
    _countRated = 0;
    _countNotRated = 0;
    _topHighestAvg.clear();
    _topLowestAvg.clear();

    final Map<String, int> bucketLine = <String, int>{};
    final List<DateTime> anchors = <DateTime>[];

//---------------------------------------
// default enter will be day
//---------------------------------------
    if (_groupBy == 'Day') {
      DateTime d = DateTime(_fromDate.year, _fromDate.month, _fromDate.day);
//---------------------------------------
// add 1 day by 1 day into bucket line and anchors list
//---------------------------------------
      while (d.isBefore(_toDate)) {
        bucketLine[_dayKey(d)] = 0;
        anchors.add(d);
        d = d.add(const Duration(days: 1));
      }
    } else {
//---------------------------------------
// if not group by day then it will get the month
//---------------------------------------
      DateTime m = DateTime(_fromDate.year, _fromDate.month, 1);
      while (m.isBefore(_toDate)) {
        bucketLine[_monthKey(m)] = 0;
        anchors.add(m);
        m = DateTime(m.year, m.month + 1, 1);
      }
    }

//---------------------------------------
// get the booking where the status is equal ended
//---------------------------------------
    final QuerySnapshot<Map<String, dynamic>> qs = await FirebaseFirestore.instance
        .collection(_colBookings)
        .where(_statusField, isEqualTo: _endedValue)
        .get();

//---------------------------------------
// for bar
//---------------------------------------
    final Map<String, int> facilityCount = <String, int>{};
    final Set<String> facilityIdsSeen = <String>{};

//---------------------------------------
// for pie
//---------------------------------------
    final List<String> userIdsForCount = <String>[]; // per booking
    final Set<String> userIdsUnique = <String>{};    // unique user fetch

 //---------------------------------------
// get the booking date
//---------------------------------------
    for (final doc in qs.docs) {
      final data = doc.data();
      final String? raw = data[_bookingDateField]?.toString();
      if (raw == null) continue;

//---------------------------------------
// if the date is before or after the choosen date then skip them
//---------------------------------------
      final DateTime? dt = _parseDateString(raw);
      if (dt == null) continue;
      if (dt.isBefore(_fromDate) || !dt.isBefore(_toDate)) continue;

//---------------------------------------
// for each booking on that day, add the key in bucketlince by 1 to get total booking on that day
//---------------------------------------
      final String lineKey = (_groupBy == 'Day') ? _dayKey(dt) : _monthKey(dt);
      if (bucketLine.containsKey(lineKey)) {
        bucketLine[lineKey] = (bucketLine[lineKey] ?? 0) + 1;
      }

//---------------------------------------
// add one facility in the key to get total book for that facility
//---------------------------------------
      final String? fid = data[_facilityIdField]?.toString();
      if (fid != null && fid.isNotEmpty) {
        facilityCount[fid] = (facilityCount[fid] ?? 0) + 1;
//---------------------------------------
// add the facility id to the list
//---------------------------------------
        facilityIdsSeen.add(fid);
      }

//---------------------------------------
// count how many rated for pie chart
//---------------------------------------
      final bool rated = (data[_ratedField] == true);
      if (rated) {
        _countRated++;
      } else {
        _countNotRated++;
      }

//---------------------------------------
// add user id to count list and unique list for pie chart
//---------------------------------------
      final String? uid = data[_userIdField]?.toString();
      if (uid != null && uid.isNotEmpty) {
        userIdsForCount.add(uid);
        userIdsUnique.add(uid);
      }
    }

//---------------------------------------
// base on the anchors length, get the count for each bucket line key then add to y value, then add x label
//---------------------------------------
    int x = 0;
    for (final DateTime a in anchors) {
      final String key = (_groupBy == 'Day') ? _dayKey(a) : _monthKey(a);
      final int count = bucketLine[key] ?? 0;
      _linePoints.add(_Point(xIndex: x, yValue: count.toDouble()));
      _xLabels.add((_groupBy == 'Day') ? _mmdd(a) : _mmmy(a));
      x = x + 1;
    }

//---------------------------------------
// declare list for facility id and category id for bar chart for bar chart
//---------------------------------------
    final Map<String, String> facilityNameById = <String, String>{};
    final Map<String, String> categoryIdByFid  = <String, String>{};
//---------------------------------------
// get the facility name and category id for each data in facilityIdSeen list
//---------------------------------------
    for (final String fid in facilityIdsSeen) {
      try {
        final fdoc = await FirebaseFirestore.instance.collection(_colFacilities).doc(fid).get();
        if (fdoc.exists) {
          final data = fdoc.data()!;
          facilityNameById[fid] = (data['name']).toString();
          categoryIdByFid[fid]  = (data['categoryId']).toString();
        }
      } catch (_) {
        facilityNameById[fid] = fid;
        categoryIdByFid[fid]  = 'unknown';
      }
    }

//---------------------------------------
// sort top 5 facilities
//---------------------------------------
    final List<MapEntry<String, int>> sortedFacilities = facilityCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final int takeF = math.min(5, sortedFacilities.length);
    for (int i = 0; i < takeF; i++) {
      final e = sortedFacilities[i];
      //---------------------------------------
// key is the facility id which helps to get facility name
//---------------------------------------
      final String label = facilityNameById[e.key] ?? e.key;
//---------------------------------------
// add each point to the bar chart, value means the value of the key so is amount of booking
//---------------------------------------
      _topFacilityBars.add(_BarDatum(_shorten(label, 14), e.value));
    }

//---------------------------------------
// sort top 5 catogory
//---------------------------------------
    final Map<String, int> categoryCount = <String, int>{};
    for (final MapEntry<String, int> e in facilityCount.entries) {
      final String fid = e.key;
      final int cnt = e.value;
      final String catId = categoryIdByFid[fid] ?? 'unknown';
      //---------------------------------------
// each of the catid will be added with the amount of facility
//---------------------------------------
      categoryCount[catId] = (categoryCount[catId] ?? 0) + cnt;
    }
//---------------------------------------
// sort each of the categories
//---------------------------------------
    final List<MapEntry<String, int>> sortedCats = categoryCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    //---------------------------------------
// take only the top 5
//---------------------------------------
    final int takeC = math.min(5, sortedCats.length);
    for (int i = 0; i < takeC; i++) {
      final e = sortedCats[i];
      String catName = e.key;
//---------------------------------------
// after sorting top 5 then get the category name
//---------------------------------------
      try {
        final cdoc = await FirebaseFirestore.instance.collection(_colCategories).doc(e.key).get();
        if (cdoc.exists) {
          catName = (cdoc.data()!['name'] ?? e.key).toString();
        }
      } catch (_) {}
      //---------------------------------------
// add it to bardatum which each the each of the bar in barchart
//---------------------------------------
      _topCategoryBars.add(_BarDatum(_shorten(catName, 14), e.value));
    }

//---------------------------------------
// get the role userIdsUnique list and get how many student and how many lecturer
//---------------------------------------
    final Map<String, String> roleByUserId = <String, String>{};
    for (final String uid in userIdsUnique) {
      try {
        final udoc = await FirebaseFirestore.instance.collection(_colUsers).doc(uid).get();
        if (udoc.exists) {
          final role = (udoc.data()!['role'] ?? '').toString();
          //---------------------------------------
// get the role for each uid
//---------------------------------------
          roleByUserId[uid] = role;
        }
      } catch (_) {}
    }
    int students = 0, lecturers = 0;
    for (final String uid in userIdsForCount) {
      final String role = (roleByUserId[uid] ?? '').toLowerCase().trim();
      if (role == 'student') {
        students++;
      } else if (role == 'lecturer') {
        lecturers++;
      }
    }
    //---------------------------------------
// got the student adn lecturer count
//---------------------------------------
    _countStudent = students;
    _countLecturer = lecturers;

//---------------------------------------
// get the rating from subcollection facility and get the date of rating
// first get all facility first
//---------------------------------------
    final QuerySnapshot<Map<String, dynamic>> allFacilities =
    await FirebaseFirestore.instance.collection(_colFacilities).get();

    final List<_BarDoubleDatum> averages = <_BarDoubleDatum>[];
    for (final doc in allFacilities.docs) {
      final String fid = doc.id;
      final String fname = (doc.data()['name'] ?? fid).toString();
//---------------------------------------
// get rating within the date range
//---------------------------------------
      try {
        final QuerySnapshot<Map<String, dynamic>> ratings = await FirebaseFirestore.instance
            .collection(_colFacilities)
            .doc(fid)
            .collection('Rating')
            .where('createdAt', isGreaterThanOrEqualTo: _fromDate)
            .where('createdAt', isLessThan: _toDate)
            .get();

        if (ratings.docs.isEmpty) continue;

        double sum = 0;
        int cnt = 0;
        for (final r in ratings.docs) {
          final dynamic v = r.data()['rating'];
          if (v is num) {
            sum += v.toDouble();
            cnt += 1;
          }
        }
//---------------------------------------
// get the avarage then add to rating barchart for each point
//---------------------------------------
        if (cnt > 0) {
          final double avg = sum / cnt;
          averages.add(_BarDoubleDatum(_shorten(fname, 14), avg));
        }
      } catch (_) {
      }
    }

//---------------------------------------
// then sort top highest adn top lowest rating
//---------------------------------------
    averages.sort((a, b) => b.value.compareTo(a.value)); // desc
    final int takeHi = math.min(5, averages.length);
    _topHighestAvg.addAll(averages.take(takeHi));

    final List<_BarDoubleDatum> asc = List<_BarDoubleDatum>.from(averages)..sort((a, b) => a.value.compareTo(b.value));
    final int takeLo = math.min(5, asc.length);
    _topLowestAvg.addAll(asc.take(takeLo));
  }

//---------------------------------------
// count the amount of different role
//---------------------------------------

  Future<void> _loadRoleCounts() async {
    Future<int> _countRole(String role) async {
      //---------------------------------------
// get the role, ingnore deleted role
//---------------------------------------
      try {
        final qs = await FirebaseFirestore.instance
            .collection(_colUsers) // 'UserInformation'
            .where('role', isEqualTo: role)
            .get();
        int c = 0;
        for (final d in qs.docs) {
          final m = d.data();
          if (m['deleted'] == true) continue; // ignore soft-deleted
          c++;
        }
        return c;
      } catch (_) {
        return 0;
      }
    }
//---------------------------------------
// get the required role
//---------------------------------------
    final a = await _countRole('Admin');
    final m = await _countRole('Manager');
    final l = await _countRole('Lecturer');
    final s = await _countRole('Student');

    _totalAdmin = a;
    _totalManager = m;
    _totalLecturer = l;
    _totalStudent = s;
  }

//---------------------------------------
// shorten the name to ...
//---------------------------------------

  String _shorten(String s, int maxChars) {
    final String t = s.trim();
    if (t.length <= maxChars) return t;
    return t.substring(0, math.max(0, maxChars - 1)) + '…';
  }

//---------------------------------------
// parse into date format
//---------------------------------------

  DateTime? _parseDateString(String s) {
    final String t = s.trim();
    final DateTime? iso = DateTime.tryParse(t);
    if (iso != null) return DateTime(iso.year, iso.month, iso.day);

  }

//---------------------------------------
// make it to year month day format
//---------------------------------------

  String _dayKey(DateTime d) {
    final String y = d.year.toString().padLeft(4, '0');
    final String m = d.month.toString().padLeft(2, '0');
    final String dd = d.day.toString().padLeft(2, '0');
    return '$y-$m-$dd';
  }
//---------------------------------------
// make it to year month format
//---------------------------------------
  String _monthKey(DateTime d) {
    final String y = d.year.toString().padLeft(4, '0');
    final String m = d.month.toString().padLeft(2, '0');
    return '$y-$m';
  }
//---------------------------------------
// convert to month day format
//---------------------------------------
  String _mmdd(DateTime d) {
    final String m = d.month.toString().padLeft(2, '0');
    final String dd = d.day.toString().padLeft(2, '0');
    return '$m/$dd';
  }
//---------------------------------------
// convert to month year format
//---------------------------------------
  String _mmmy(DateTime d) {
    const List<String> mm = <String>[
      'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    final String mon = mm[d.month - 1];
    final String yy = (d.year % 100).toString().padLeft(2, '0');
    return '$mon $yy';
  }

  //---------------------------------------
// get the chart width , count base on how many point we have
//---------------------------------------
  double _chartWidth() {
    final int n = _linePoints.length;
    if (n == 0) return 0.9.sw;
    final double per = (_groupBy == 'Day') ? 64.0.w : 88.0.w;
    return math.max(0.9.sw, per * n);
  }

//---------------------------------------
// main build
//---------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(70.h),
        child: WebCustomTopBar(use24HourFormat: _use24HourFormat),
      ),
        body: SingleChildScrollView(
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
 //---------------------------------------
// display date tools at top
//---------------------------------------
                children: <Widget>[
              _dateRow(),
              SizedBox(height: 12.h),

              if (_loading)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 24.h),
                  child: const Center(child: CircularProgressIndicator()),
                ),
//---------------------------------------
// show total role
//---------------------------------------
              if (!_loading) _rolesSummaryRow(),
              if (!_loading) SizedBox(height: 16.h),
//---------------------------------------
// show line graph
//---------------------------------------
              if (!_loading) _lineSection(),
              if (!_loading) SizedBox(height: 16.h),
//---------------------------------------
// show show bar chart
//---------------------------------------
              if (!_loading) _twoBarsRow(),
              if (!_loading) SizedBox(height: 16.h),
//---------------------------------------
// show two donut pie chart
//---------------------------------------
              if (!_loading) _twoPiesRow(),
              if (!_loading) SizedBox(height: 12.h),
//---------------------------------------
// show navigate to rating page
//---------------------------------------
              if (!_loading) _ratingRow(),
              if (!_loading) SizedBox(height: 12.h),
//---------------------------------------
// show rating bar chart
//---------------------------------------
              if (!_loading) _twoRatingBarsRow(),
            ],
          ),
        ),
      ),
        ),
    );
  }


//---------------------------------------
// row for header
//---------------------------------------

  Widget _dateRow() {
    final DateTime toIncl = _toDate.subtract(const Duration(days: 1));

    return SizedBox(
      width: 0.9.sw,
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
          child: Row(
            children: [
//---------------------------------------
// show date range
//---------------------------------------
              Expanded(
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F7FA),
                    borderRadius: BorderRadius.circular(10.r),
                    border: Border.all(color: const Color(0xFFE3E3EC)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.date_range, size: 18.sp),
                      SizedBox(width: 8.w),
                      Text(
                        '${_dayKey(_fromDate)}  —  ${_dayKey(toIncl)}',
                        style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
//---------------------------------------
// show the pick date
//---------------------------------------
                      OutlinedButton.icon(
                        onPressed: _pickDateRange,
                        icon: const Icon(Icons.edit_calendar, size: 16),
                        label: const Text('Change'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: Size(0, 36.h),
                          padding: EdgeInsets.symmetric(horizontal: 10.w),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(width: 12.w),

//---------------------------------------
// group by button
//---------------------------------------
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F7FA),
                  borderRadius: BorderRadius.circular(10.r),
                  border: Border.all(color: const Color(0xFFE3E3EC)),
                ),
                child: Row(
                  children: [
                    Text('Group by:', style: TextStyle(fontSize: 12.sp)),
                    SizedBox(width: 8.w),
                    _groupChip('Day'),
                    SizedBox(width: 6.w),
                    _groupChip('Month'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

//---------------------------------------
// show user tole design
//---------------------------------------
  Widget _rolesSummaryRow() {
    final double containerW = 0.9.sw;
    final double gap = 8.w;
    final double boxW = (containerW - gap * 3) / 4; // get width for each display

    return SizedBox(
      width: containerW,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
//---------------------------------------
// box for admin
//---------------------------------------
          _summaryBox(
            width: boxW,
            icon: Icons.admin_panel_settings,
            color: const Color(0xFF6D28D9),
            label: 'Admin',
            total: _totalAdmin,
          ),
//---------------------------------------
//  box for manager
//---------------------------------------
          SizedBox(width: gap),
          _summaryBox(
            width: boxW,
            icon: Icons.manage_accounts,
            color: const Color(0xFF0EA5E9),
            label: 'Manager',
            total: _totalManager,
          ),
//---------------------------------------
//  box for lecturer
//---------------------------------------
          SizedBox(width: gap),
          _summaryBox(
            width: boxW,
            icon: Icons.menu_book,
            color: const Color(0xFFF59E0B),
            label: 'Lecturer',
            total: _totalLecturer,
          ),
//---------------------------------------
// box for student
//---------------------------------------
          SizedBox(width: gap),
          _summaryBox(
            width: boxW,
            icon: Icons.school,
            color: const Color(0xFF22C55E),
            label: 'Student',
            total: _totalStudent,
          ),
        ],
      ),
    );
  }
//---------------------------------------
//  design for each role box
//---------------------------------------
  Widget _summaryBox({
    required double width,
    required IconData icon,
    required Color color,
    required String label,
    required int total,
  }) {
    return SizedBox(
      width: width,
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
          child: Row(
            children: [
//---------------------------------------
// outer circle for icon
//---------------------------------------
              Container(
                width: 44.w,
                height: 44.w,
                decoration: BoxDecoration(
                  color: color.withOpacity(.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 22.sp),
              ),
              SizedBox(width: 12.w),
//---------------------------------------
//  show total
//---------------------------------------
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600)),
                    SizedBox(height: 4.h),
                    Text('Total: $total', style: TextStyle(fontSize: 12.sp, color: Colors.black87)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

//---------------------------------------
// change the group by and run reload
//---------------------------------------

  Widget _groupChip(String label) {
    final bool selected = _groupBy == label;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 12.sp)),
      selected: selected,
      onSelected: (v) async {
        if (!v) return;
        setState(() => _groupBy = label);
        await _reload();
      },
      selectedColor: const Color(0xFF1E88E5).withOpacity(.12),
      labelStyle: TextStyle(
        color: selected ? const Color(0xFF1E88E5) : Colors.black87,
        fontWeight: FontWeight.w600,
      ),
      shape: StadiumBorder(side: BorderSide(color: selected ? const Color(0xFF1E88E5) : const Color(0xFFE3E3EC))),
    );
  }


//---------------------------------------
//  line graph design
//---------------------------------------
  Widget _lineSection() {
    final double chartWidth = _chartWidth();
    final double chartHeight = 450.h;
    final double yTitleWidth = 22.w;
    final double gapToYAxis  = 30.w;
    final double leftLabelW  = 30.w;
    final double bottomH     = 46.h;

//---------------------------------------
// get the highest point
//---------------------------------------
    int highest = 0;
    for (final _Point p in _linePoints) {
      if (p.yValue.round() > highest)
        highest = p.yValue.round();
    }
//---------------------------------------
// set the y axis bar, step which mean y axis point number, then we can get top line and get the max y
//---------------------------------------
    int step = ((highest + 3) ~/ 4);// get each y axis
    if (step < 1) step = 1;
    final int topLine = step * 4; // *4 to get highest point
    final double layoutMaxY = (topLine + step).toDouble();
    final double gridInterval = step.toDouble();

    return SizedBox(
      width: 0.9.sw,
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
        child: Padding(
          padding: EdgeInsets.all(12.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: double.infinity,
                child: Center(
                  child: Text(
                    'Total Bookings',
                    style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              SizedBox(height: 8.h),
              SizedBox(
                height: chartHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    SizedBox(
                      width: yTitleWidth,
//---------------------------------------
// rotate the box
//---------------------------------------
                      child: Center(
                        child: RotatedBox(
                          quarterTurns: 3,
                          child: Text('Total bookings', style: TextStyle(fontSize: 12.sp)),
                        ),
                      ),
                    ),
                    SizedBox(width: gapToYAxis),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, c) {
                          final double w = math.max(c.maxWidth, chartWidth);
                          return Column(
                            children: [
                              Expanded(
//---------------------------------------
// build the line chart
//---------------------------------------
                              child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: SizedBox(
                                    width: w,
                                    height: chartHeight,
                                    child: _buildLineChart(
                                      yMax: layoutMaxY,
                                      yInterval: gridInterval,
                                      topLine: topLine.toDouble(),
                                      bottomReserved: bottomH,
                                      leftLabelWidth: leftLabelW,
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(
                                height: 22.h,
                                child: const Center(child: Text('Date')),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

//---------------------------------------
// show the two bar chart
//---------------------------------------

  Widget _twoBarsRow() {
    final double containerW = 0.9.sw;
    final double gap = 6.w;
    final double half = (containerW - gap) / 2; // half half
    final double cardW = math.min(42.sw, half);

    return SizedBox(
      width: containerW,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: cardW,
            child: _barCard(
              title: 'Top 5 Facilities',
              xAxisTitle: 'Facility name',
              data: _topFacilityBars,
            ),
          ),
          SizedBox(width: gap),
          SizedBox(
            width: cardW,
            child: _barCard(
              title: 'Top 5 Categories',
              xAxisTitle: 'Category name',
              data: _topCategoryBars,
            ),
          ),
        ],
      ),
    );
  }

//---------------------------------------
// display the two pie chart
//---------------------------------------

  Widget _twoPiesRow() {
    final double containerW = 0.9.sw;
    final double gap = 6.w;
    final double half = (containerW - gap) / 2;
    final double cardW = math.min(42.sw, half);

    return SizedBox(
      width: containerW,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: cardW,
            child: _pieCard(
              title: 'Student vs Lecturer',
              aLabel: 'Student',
              aCount: _countStudent,
              aColor: Colors.red,
              bLabel: 'Lecturer',
              bCount: _countLecturer,
              bColor: Colors.blue,
            ),
          ),
          SizedBox(width: gap),
          SizedBox(
            width: cardW,
            child: _pieCard(
              title: 'Rating Participation after Booking',
              aLabel: 'Not rated',
              aCount: _countNotRated,
              aColor: Colors.red,
              bLabel: 'Rated',
              bCount: _countRated,
              bColor: Colors.blue,
            ),
          ),
        ],
      ),
    );
  }

//---------------------------------------
// rating row button
//---------------------------------------

  Widget _ratingRow() {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: Colors.transparent,
 //---------------------------------------
// show button on tap
//---------------------------------------

        child: InkWell(
          onTap: () => context.go('/webviewrating'), // or context.go(...) to replace
          hoverColor: Colors.black.withOpacity(.03),
          splashColor: Colors.black.withOpacity(.05),
          child: SizedBox(
            width: 0.9.sw,
            height: 48.h,
            child: Container(
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: Color(0xFFE0E0E0), width: 1),
                  bottom: BorderSide(color: Color(0xFFE0E0E0), width: 1),
                ),
              ),
              child: Stack(
                children: [
                  Center(
                    child: Text(
                      'Rating',
                      style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600),
                    ),
                  ),
//---------------------------------------
// right arrow
//---------------------------------------
                  Positioned(
                    right: 8,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: Icon(Icons.chevron_right, size: 18.sp, color: Colors.black87),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

//---------------------------------------
// show the two rating bar
//---------------------------------------

  Widget _twoRatingBarsRow() {
    final double containerW = 0.9.sw;
    final double gap = 6.w;
    final double half = (containerW - gap) / 2;
    final double cardW = math.min(42.sw, half);

    return SizedBox(
      width: containerW,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: cardW,
            child: _barCardDouble(
              title: 'Top 5 Highest Average Rating',
              xAxisTitle: 'Facility name',
              data: _topHighestAvg,
            ),
          ),
          SizedBox(width: gap),
          SizedBox(
            width: cardW,
            child: _barCardDouble(
              title: 'Top 5 Lowest Average Rating',
              xAxisTitle: 'Facility name',
              data: _topLowestAvg,
            ),
          ),
        ],
      ),
    );
  }

//---------------------------------------
// bar chart design
//---------------------------------------
  Widget _barCard({
    required String title,
    required String xAxisTitle,
    required List<_BarDatum> data,
  }) {
    //---------------------------------------
// get highest point first
//---------------------------------------

    int highest = 0;
    for (final _BarDatum d in data) {
      if (d.count > highest) highest = d.count;
    }
    //---------------------------------------
// find each of the y axis and maximum y axis
//---------------------------------------
    int step = ((highest + 3) ~/ 4);
    if (step < 1) step = 1;
    final int topLine = step * 4;
    final double layoutMaxY = (topLine + step).toDouble();
    final double gridInterval = step.toDouble();

    final double bottomReserved = 56.h;
    final double leftReserved   = 30.w;
    final double yTitleWidth    = 22.w;
    final double gapToYAxis     = 16.w;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
      child: Padding(
        padding: EdgeInsets.all(12.w),
        child: Column(
          children: [
            SizedBox(
              width: double.infinity,
//---------------------------------------
// place title
//---------------------------------------
              child: Center(
                child: Text(
                  title,
                  style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            SizedBox(height: 8.h),
            SizedBox(
              height: 320.h,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: yTitleWidth,
                    child: Center(
                      child: RotatedBox(
                        quarterTurns: 3,
                        child: Text('Total bookings', style: TextStyle(fontSize: 12.sp)),
                      ),
                    ),
                  ),
//---------------------------------------
// build the bar chart
//---------------------------------------
                  SizedBox(width: gapToYAxis),
                  Expanded(
                    child: _buildBarChart(
                      data: data,
                      yMax: layoutMaxY,
                      yInterval: gridInterval,
                      topLine: topLine.toDouble(),
                      leftReserved: leftReserved,
                      bottomReserved: bottomReserved,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 22.h, child: Center(child: Text(xAxisTitle))),
          ],
        ),
      ),
    );
  }
//---------------------------------------
// show bar chart but with double value
//---------------------------------------

  Widget _barCardDouble({
    required String title,
    required String xAxisTitle,
    required List<_BarDoubleDatum> data,
  }) {
//---------------------------------------
// maximum show to 5 star
//---------------------------------------

    const double layoutMaxY = 5.0;
    const double gridInterval = 1.0;
    const double topLine = 5.0;

    final double bottomReserved = 56.h;
    final double leftReserved   = 34.w;
    final double yTitleWidth    = 22.w;
    final double gapToYAxis     = 16.w;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
      child: Padding(
        padding: EdgeInsets.all(12.w),
        child: Column(
 //---------------------------------------
// display the title
//---------------------------------------

        children: [
            SizedBox(
              width: double.infinity,
              child: Center(
                child: Text(
                  title,
                  style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            SizedBox(height: 8.h),
            SizedBox(
//---------------------------------------
// display y title
//---------------------------------------
            height: 320.h,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: yTitleWidth,
                    child: Center(
                      child: RotatedBox(
                        quarterTurns: 3, // rotate 180
                        child: Text('Average rating', style: TextStyle(fontSize: 12.sp)),
                      ),
                    ),
                  ),
                  SizedBox(width: gapToYAxis),
                  Expanded(
                    child: _buildBarChartDouble(
                      data: data,
                      yMax: layoutMaxY,
                      yInterval: gridInterval,
                      topLine: topLine,
                      leftReserved: leftReserved,
                      bottomReserved: bottomReserved,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 22.h, child: Center(child: Text(xAxisTitle))),
          ],
        ),
      ),
    );
  }

//---------------------------------------
// pie chart design
//---------------------------------------

  Widget _pieCard({
    required String title,
    required String aLabel,
    required int aCount,
    required Color aColor,
    required String bLabel,
    required int bCount,
    required Color bColor,
  }) {
    final int total = aCount + bCount;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
      child: Padding(
        padding: EdgeInsets.all(12.w),
        child: Column(
          children: [
//---------------------------------------
// show titles
//---------------------------------------

            SizedBox(
              width: double.infinity,
              child: Center(
                child: Text(
                  title,
                  style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            SizedBox(height: 8.h),
            SizedBox(
              height: 300.h,
              child: (total == 0)
                  ? const Center(child: Text('No data'))
                  : PieChart(
                PieChartData(
                  sectionsSpace: 2.w, // alittle space betwen data
                  centerSpaceRadius: 44.w, // center space
                  startDegreeOffset: -90,// start from 90degree above
                  sections: [
//---------------------------------------
// tow selection data
//---------------------------------------
 //---------------------------------------
// this section show student and not rated
//---------------------------------------
                    PieChartSectionData(
                      color: aColor,
                      value: aCount.toDouble(),
                      title: aCount.toString(),
                      radius: 70.w,
                      titleStyle: TextStyle(
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
 //---------------------------------------
// tow selection data this section show lecturer and rated
//---------------------------------------
                    PieChartSectionData(
                      color: bColor,
                      value: bCount.toDouble(),
                      title: bCount.toString(),
                      radius: 70.w,
                      titleStyle: TextStyle(
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Row(
//---------------------------------------
// show legend
//---------------------------------------
            mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _legendDot(aColor),
                SizedBox(width: 6.w),
                Text(aLabel, style: TextStyle(fontSize: 12.sp)),
                SizedBox(width: 16.w),
                _legendDot(bColor),
                SizedBox(width: 6.w),
                Text(bLabel, style: TextStyle(fontSize: 12.sp)),
              ],
            ),
            SizedBox(height: 6.h),
          ],
        ),
      ),
    );
  }

  Widget _legendDot(Color c) => Container(
    width: 12.w,
    height: 12.w,
    decoration: BoxDecoration(color: c, shape: BoxShape.circle),
  );

//---------------------------------------
// fl graph line graph design
//---------------------------------------

  Widget _buildLineChart({
    required double yMax,
    required double yInterval,
    required double topLine,
    required double bottomReserved,
    required double leftLabelWidth,
  }) {
    if (_linePoints.isEmpty) return const Center(child: Text('No data'));
//---------------------------------------
// fl way to get the point
//---------------------------------------
    final List<FlSpot> spots = <FlSpot>[
      for (final _Point p in _linePoints) FlSpot(p.xIndex.toDouble(), p.yValue),
    ];
    final double lastX = _linePoints.last.xIndex.toDouble();

    return LineChart(
      LineChartData(
        minX: -0.5,
        maxX: lastX + 0.5,
        minY: 0,
        maxY: yMax,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false, // no vertical line
          drawHorizontalLine: true,
          horizontalInterval: yInterval,
          getDrawingHorizontalLine: (value) {
            const double eps = 1e-6;
            if (value <= eps) return const FlLine(strokeWidth: 0);
            final bool isMultiple =
                (value % yInterval).abs() < eps || (yInterval - (value % yInterval)).abs() < eps;
            if (!isMultiple || value - topLine > eps) return const FlLine(strokeWidth: 0);
            // grey line for yea y axis
            return FlLine(color: Colors.grey, strokeWidth: 1);
          },
        ),
        borderData: FlBorderData(
          show: true,
          border: Border(
            left: BorderSide(color: Colors.black, width: 1.2.w),
            right: const BorderSide(color: Colors.transparent, width: 0), // no border right
            top: const BorderSide(color: Colors.transparent, width: 0), // no border above
            bottom: BorderSide(color: Colors.black, width: 1.2.w),
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)), // no top title
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)), // no right title
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: leftLabelWidth,
              interval: yInterval,
              getTitlesWidget: (double value, TitleMeta meta) {
                const double eps = 1e-6;
                final bool isMultiple =
                    (value % yInterval).abs() < eps || (yInterval - (value % yInterval)).abs() < eps;
                if (!isMultiple || value - topLine > eps) return const SizedBox.shrink();
//---------------------------------------
// show y axis number
//---------------------------------------
                return Padding(
                  padding: EdgeInsets.only(right: 6.w),
                  child: Text(
                    value.toInt().toString(),
                    style: TextStyle(fontSize: 11.sp, color: Colors.black),
                  ),
                );
              },
            ),
          ),
//---------------------------------------
// for x axis
//---------------------------------------
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true, //show title which is the date by date
              reservedSize: bottomReserved,
              interval: 1,
              getTitlesWidget: (double x, TitleMeta meta) {
                if (x != x.floorToDouble()) return const SizedBox.shrink();
                final int i = x.toInt();
                if (i < 0 || i >= _xLabels.length) return const SizedBox.shrink();
                final bool rotate = _groupBy == 'Day';
                return Padding(
                  padding: EdgeInsets.only(top: 6.h),
                  child: Transform.rotate(
                    angle: rotate ? -0.8 : 0.0, // rotate the angle if its day
                    child: Text(_xLabels[i], style: TextStyle(fontSize: 11.sp)),
                  ),
                );
              },
            ),
          ),
        ),
//---------------------------------------
// when touch the line data show the value
//---------------------------------------
        lineTouchData: LineTouchData(
          handleBuiltInTouches: true,
          touchTooltipData: LineTouchTooltipData(
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            tooltipRoundedRadius: 6.r,
            tooltipPadding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 6.h),
          ),
        ),
//---------------------------------------
// line of the point design
//---------------------------------------
        lineBarsData: <LineChartBarData>[
          LineChartBarData(
            spots: spots,
            isCurved: false,
            color: Colors.black,
            barWidth: 3.w,
//---------------------------------------
// dot of the point design
//---------------------------------------
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                radius: 3.5.w,
                color: Colors.black,
                strokeWidth: 1.5.w,
                strokeColor: Colors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }

//---------------------------------------
// fl barchart design
//---------------------------------------
  Widget _buildBarChart({
    required List<_BarDatum> data,
    required double yMax,
    required double yInterval,
    required double topLine,
    required double leftReserved,
    required double bottomReserved,
  }) {
    if (data.isEmpty) return const Center(child: Text('No data'));
//---------------------------------------
// fl design way
//---------------------------------------
    final List<BarChartGroupData> groups = <BarChartGroupData>[];
    for (int i = 0; i < data.length; i++) {
      final _BarDatum d = data[i];
      groups.add(
        BarChartGroupData(
          x: i,
          barsSpace: 0,
          barRods: <BarChartRodData>[
//---------------------------------------
// barchart design colour and width
//---------------------------------------
            BarChartRodData(
              toY: d.count.toDouble(),
              color: Colors.black,
              width: 14.w,
              borderRadius: BorderRadius.circular(2.r),
            ),
          ],
        ),
      );
    }
    return BarChart(
      BarChartData(
        maxY: yMax,
        minY: 0,
        alignment: BarChartAlignment.spaceEvenly,
        barGroups: groups,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false, // no vertical line
          drawHorizontalLine: true, // only horizontal line
          horizontalInterval: yInterval,
          getDrawingHorizontalLine: (value) {
            const double eps = 1e-6;
            if (value <= eps) return const FlLine(strokeWidth: 0);
            final bool isMultiple =
                (value % yInterval).abs() < eps || (yInterval - (value % yInterval)).abs() < eps;
            if (!isMultiple || value - topLine > eps) return const FlLine(strokeWidth: 0);
            return FlLine(color: Colors.grey, strokeWidth: 1); // line colour grey
          },
        ),
        borderData: FlBorderData(
          show: true,
          border: Border(
            left: BorderSide(color: Colors.black, width: 1.2.w),
            right: const BorderSide(color: Colors.transparent, width: 0),// no right border line
            top: const BorderSide(color: Colors.transparent, width: 0), // no top border line
            bottom: BorderSide(color: Colors.black, width: 1.2.w),
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: leftReserved,
              interval: yInterval,
              getTitlesWidget: (double value, TitleMeta meta) {
                const double eps = 1e-6;
                final bool isMultiple =
                    (value % yInterval).abs() < eps || (yInterval - (value % yInterval)).abs() < eps;
                if (!isMultiple || value - topLine > eps) return const SizedBox.shrink();
                // show each y axis value
                return Padding(
                  padding: EdgeInsets.only(right: 6.w),
                  child: Text(value.toInt().toString(), style: TextStyle(fontSize: 11.sp)),
                );
              },
            ),
          ),
//---------------------------------------
// x axis show each facility or category name
//---------------------------------------
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: bottomReserved,
              interval: 1,
              getTitlesWidget: (double x, TitleMeta meta) {
                if (x != x.floorToDouble()) return const SizedBox.shrink();
                final int i = x.toInt();
                if (i < 0 || i >= data.length) return const SizedBox.shrink();
                return Padding(
                  padding: EdgeInsets.only(top: 6.h),
                  child: Transform.rotate(
                    angle: -0.6, // angle rounded
                    child: Text(data[i].label, style: TextStyle(fontSize: 11.sp)),
                  ),
                );
              },
            ),
          ),
        ),
//---------------------------------------
// bar chart when pointing text
//---------------------------------------
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            tooltipRoundedRadius: 6.r, // text that show total when point
            tooltipPadding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 6.h),
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final label = data[group.x].label;
              return BarTooltipItem(
                '$label\n${rod.toY.toInt()}',
                TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w500, color: Colors.black),
              );
            },
          ),
        ),
      ),
    );
  }

//---------------------------------------
// fl rating bar chart
//---------------------------------------

  Widget _buildBarChartDouble({
    required List<_BarDoubleDatum> data,
    required double yMax,
    required double yInterval,
    required double topLine,
    required double leftReserved,
    required double bottomReserved,
  }) {
    if (data.isEmpty) return const Center(child: Text('No data'));
//---------------------------------------
// fl chart way to gert data
//---------------------------------------
    final List<BarChartGroupData> groups = <BarChartGroupData>[];
    for (int i = 0; i < data.length; i++) {
      final _BarDoubleDatum d = data[i];
      groups.add(

//---------------------------------------
// barchart colour design and width
//---------------------------------------
      BarChartGroupData(
          x: i,
          barsSpace: 0,
          barRods: <BarChartRodData>[
            BarChartRodData(
              toY: d.value,
              color: Colors.black,
              width: 14.w,
              borderRadius: BorderRadius.circular(2.r),
            ),
          ],
        ),
      );
    }
//---------------------------------------
// bar chart y axis date
//---------------------------------------

    return BarChart(
      BarChartData(
        maxY: yMax,
        minY: 0,
        alignment: BarChartAlignment.spaceEvenly,
        barGroups: groups,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false, // no vertical line
          drawHorizontalLine: true,
          horizontalInterval: yInterval,
          getDrawingHorizontalLine: (value) {
            const double eps = 1e-6;
            if (value <= eps) return const FlLine(strokeWidth: 0);
            final bool isMultiple =
                (value % yInterval).abs() < eps || (yInterval - (value % yInterval)).abs() < eps;
            if (!isMultiple || value - topLine > eps) return const FlLine(strokeWidth: 0);
            return FlLine(color: Colors.grey, strokeWidth: 1); // color line
          },
        ),
        borderData: FlBorderData(
          show: true,
          border: Border(
            left: BorderSide(color: Colors.black, width: 1.2.w),
            right: const BorderSide(color: Colors.transparent, width: 0),// no right border line
            top: const BorderSide(color: Colors.transparent, width: 0), // no top border line
            bottom: BorderSide(color: Colors.black, width: 1.2.w),
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: leftReserved,
              interval: yInterval,
              getTitlesWidget: (double value, TitleMeta meta) {
                const double eps = 1e-6;
                final bool isMultiple =
                    (value % yInterval).abs() < eps || (yInterval - (value % yInterval)).abs() < eps;
                if (!isMultiple || value - topLine > eps) return const SizedBox.shrink();
                return Padding( // y axis value
                  padding: EdgeInsets.only(right: 6.w),
                  child: Text(value.toInt().toString(), style: TextStyle(fontSize: 11.sp)),
                );
              },
            ),
          ),

//---------------------------------------
// x axis design
//---------------------------------------

          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: bottomReserved,
              interval: 1,
              getTitlesWidget: (double x, TitleMeta meta) {
                if (x != x.floorToDouble()) return const SizedBox.shrink();
                final int i = x.toInt();
                if (i < 0 || i >= data.length) return const SizedBox.shrink();
                return Padding(
                  padding: EdgeInsets.only(top: 6.h),
                  child: Transform.rotate(
                    angle: -0.6, // rotate the word
                    child: Text(data[i].label, style: TextStyle(fontSize: 11.sp)),
                  ),
                );
              },
            ),
          ),
        ),
//---------------------------------------
// for touched bar
//---------------------------------------
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            tooltipRoundedRadius: 6.r,
            tooltipPadding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 6.h),
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final label = data[group.x].label;
              return BarTooltipItem( // touch bar show value
                '$label\n${rod.toY.toStringAsFixed(1)}',
                TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w500, color: Colors.black),
              );
            },
          ),
        ),
      ),
    );
  }
}


