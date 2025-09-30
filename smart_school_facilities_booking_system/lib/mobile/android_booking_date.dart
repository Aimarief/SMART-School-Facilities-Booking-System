import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'android_bottom_menu.dart';
import 'android_agenda.dart';
import 'android_view_booking.dart';
import 'android_notifications.dart';
import 'android_account.dart';
import 'android_list_of_facilities.dart';

import 'android_select_slot.dart';

import 'android_confirmation_booking.dart';

class Booking_Date extends StatefulWidget {

  final String facilityId;
  final String facilityName;

  const Booking_Date({
    Key? key,
    required this.facilityId,
    required this.facilityName,
  }) : super(key: key);

  @override
  State<Booking_Date> createState() => _Booking_DateState();
}

class _Booking_DateState extends State<Booking_Date> {
//---------------------------------------
// current page
//---------------------------------------

  int _currentIndex = 2;

  late DateTime _today;
  late DateTime _selected;
  late List<DateTime> _next7;

  bool _allowMon = true;
  bool _allowTue = true;
  bool _allowWed = true;
  bool _allowThu = true;
  bool _allowFri = true;
  bool _allowSat = false;
  bool _allowSun = false;


  bool _loadingFacility = true;
  Map<String, dynamic> _facilityData = {};
  List<Map<String, dynamic>> _slotsTemplate = <Map<String, dynamic>>[];
  int _facilityCapacity = 1;

  bool _loadingSlots = true;
  final Map<String, int> _bookedByKey = <String, int>{};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _slotsSub;

  final Set<String> _pickedStarts = <String>{};
  bool _autoAssign = true;

  bool _debugPanel = false;

  final Set<String> _offDaysYMD = <String>{};
//---------------------------------------
// run init state first
//---------------------------------------
  @override
  void initState() {
    super.initState();

    //---------------------------------------
// set today date, selected date is today and next 7 days
//---------------------------------------

    final DateTime now = DateTime.now();
    _today = DateTime(now.year, now.month, now.day);
    _selected = _today;
    _next7 = List<DateTime>.generate(7, (i) => _today.add(Duration(days: i)));

//---------------------------------------
// get all the slot belongs to this facility
//---------------------------------------
    _bootstrap();
  }

//---------------------------------------
// loads data
//---------------------------------------

  Future<void> _bootstrap() async {
    await _loadWeekdayRules();
    await _loadOffDays();
    await _loadFacilityOnce();
    if (mounted) _startSlotsListenerForSelectedDay();
  }

  @override
  void dispose() {
    _slotsSub?.cancel();
    super.dispose();
  }


//---------------------------------------
// convert time to slot key
//---------------------------------------
  String _slotKey4(String hhmmOrId) {
    String s = hhmmOrId.replaceAll(':', '');
    if (s.length < 4) s = s.padLeft(4, '0');
    return s;
  }

//---------------------------------------
// parse to int
//---------------------------------------
  int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    final int? p = int.tryParse('$v');
    return p ?? 0;
  }

//---------------------------------------
// get the month and set to month year
//---------------------------------------
  String _monthYearText(DateTime d) {
    const List<String> months = <String>[
      'January','February','March','April','May','June',
      'July','August','September','October','November','December'
    ];
    return '${months[d.month - 1]} ${d.year}';
  }

//---------------------------------------
// get the ymd that is selected and turn into string
//---------------------------------------

  String get _ymdSelected {
    final String mo = _selected.month.toString().padLeft(2, '0');
    final String da = _selected.day.toString().padLeft(2, '0');
    return '${_selected.year}-$mo-$da';
  }

//---------------------------------------
// conver to ymd format
//---------------------------------------

  String _ymd(DateTime d) {
    final String mo = d.month.toString().padLeft(2, '0');
    final String da = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mo-$da';
  }

//---------------------------------------
// convert hhmm to minute
//---------------------------------------

  int _timeToMinutes(String hhmm) {
    final List<String> p = hhmm.split(':');
    int h = 0;
    int m = 0;
    if (p.isNotEmpty) {
      final int? hh = int.tryParse(p[0]);
      if (hh != null) h = hh;
    }
    if (p.length > 1) {
      final int? mm = int.tryParse(p[1]);
      if (mm != null) m = mm;
    }
    return (h * 60) + m;
  }

//---------------------------------------
//  check if its the same day
//---------------------------------------

  bool _isTodaySelected() {
    return _selected.year == _today.year &&
        _selected.month == _today.month &&
        _selected.day == _today.day;
  }

  // check if a slot is already past (for today only)
  bool _isSlotPastNow(String startHHMM) {
    if (_isTodaySelected()) {
      final DateTime now = DateTime.now();
      final int nowMin = (now.hour * 60) + now.minute;
      final int startMin = _timeToMinutes(startHHMM);
      return nowMin >= startMin;
    }
    return false;
  }

//---------------------------------------
// add am pm
//---------------------------------------

  String _toAmPmDotStart(String hhmm) {
    final List<String> parts = hhmm.split(':');
    int hour = 0;
    int minute = 0;

    if (parts.isNotEmpty) {
      final int? h = int.tryParse(parts[0]);
      if (h != null) hour = h;
    }
    if (parts.length > 1) {
      final int? m = int.tryParse(parts[1]);
      if (m != null) minute = m;
    }

    String suffix = 'am';
    if (hour >= 12) suffix = 'pm';

    int h12 = hour % 12;
    if (h12 == 0) h12 = 12;

    final String m = minute.toString().padLeft(2, '0');
    return '$h12.$m $suffix';
  }

  //---------------------------------------
// get the letter of date
//---------------------------------------

  String _letterFor(DateTime d) {
    if (d.weekday == DateTime.sunday) return 'S';
    if (d.weekday == DateTime.monday) return 'M';
    if (d.weekday == DateTime.tuesday) return 'T';
    if (d.weekday == DateTime.wednesday) return 'W';
    if (d.weekday == DateTime.thursday) return 'T';
    if (d.weekday == DateTime.friday) return 'F';
    return 'S'; // Saturday
  }

//---------------------------------------
// check it is is offday
//---------------------------------------

  bool _isOffDay(DateTime d) => _offDaysYMD.contains(_ymd(d));

//---------------------------------------
// check which day can be book
//---------------------------------------
  bool _isWeekdayAllowed(DateTime d) {
    final int wd = d.weekday;
    final bool byWeekday =
        (wd == DateTime.monday    && _allowMon) ||
            (wd == DateTime.tuesday   && _allowTue) ||
            (wd == DateTime.wednesday && _allowWed) ||
            (wd == DateTime.thursday  && _allowThu) ||
            (wd == DateTime.friday    && _allowFri) ||
            (wd == DateTime.saturday  && _allowSat) ||
            (wd == DateTime.sunday    && _allowSun);

    if (!byWeekday) return false;
    if (_isOffDay(d)) return false;

//---------------------------------------
// block inactive day also
//---------------------------------------
    if (_inactiveFrom != null && _inactiveTo != null) {
      final DateTime dOnly = DateTime(d.year, d.month, d.day);
      if (!dOnly.isBefore(_inactiveFrom!) && !dOnly.isAfter(_inactiveTo!)) {
        return false;
      }
    }

    return true;
  }

//---------------------------------------
// 3 hour before only can book
//---------------------------------------

  final int _leadDisableMinutes = 180; // 3 hours

  DateTime? _inactiveFrom;
  DateTime? _inactiveTo;

//---------------------------------------
// parse to date format
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

// Disable if (today) and we are within lead time of start
  bool _isSlotTooSoon(String startHHMM) {
    if (!_isTodaySelected()) return false;
    final now = DateTime.now();
    final int nowMin = (now.hour * 60) + now.minute;
    final int startMin = _timeToMinutes(startHHMM);
    return nowMin >= (startMin - _leadDisableMinutes);
  }


//---------------------------------------
// read the week day which day is on and off
//---------------------------------------

  Future<void> _loadWeekdayRules() async {
    try {
      final DocumentSnapshot<Map<String, dynamic>> snap = await FirebaseFirestore.instance
          .collection('SystemInformation')
          .doc('Setting')
          .get();

      if (snap.exists) {
        final Map<String, dynamic> m = snap.data() ?? <String, dynamic>{};

        _allowSun = m['Sunday'];
        _allowMon = m['Monday'];
        _allowTue = m['Tuesday'];
        _allowWed = m['Wednesday'];
        _allowThu = m['Thursday'];
        _allowFri = m['Friday'];
        _allowSat = m['Saturday'];
      }
    } catch (_) {
    }

    if (mounted) setState(() {});
  }

//---------------------------------------
// load all facility important thing liks available slot, time slot, inactive time
//---------------------------------------

  Future<void> _loadFacilityOnce() async {
    setState(() => _loadingFacility = true);

    try {
      final DocumentSnapshot<Map<String, dynamic>> snap = await FirebaseFirestore.instance
          .collection('Facilities')
          .doc(widget.facilityId)
          .get();

      _facilityData = snap.data() ?? <String, dynamic>{};

      //---------------------------------------
// add each time slot to list
//---------------------------------------
      _slotsTemplate = <Map<String, dynamic>>[];
      final dynamic raw = _facilityData['customTimeSlots'];
      if (raw is List) {
        for (final dynamic item in raw) {
          if (item is Map<String, dynamic>) {
            _slotsTemplate.add(item);
          }
        }
      }

      _facilityCapacity = _facilityData['availableSlots'];

      _inactiveFrom = _dateOnly(_facilityData['inactiveFrom']);
      _inactiveTo   = _dateOnly(_facilityData['inactiveTo']);
    } catch (_) {
      _facilityData = <String, dynamic>{};
      _slotsTemplate = <Map<String, dynamic>>[];
      _facilityCapacity = 1;

    }
    //---------------------------------------
// set loading facility to flase
//---------------------------------------

    if (mounted) setState(() => _loadingFacility = false);
  }

//---------------------------------------
// load the off days or holidays
//---------------------------------------
  Future<void> _loadOffDays() async {
    try {
      final DocumentSnapshot<Map<String, dynamic>> doc = await FirebaseFirestore.instance
          .collection('SystemInformation')
          .doc('OffDays')
          .get();
//---------------------------------------
// add each day into list
//---------------------------------------
      final Set<String> next = <String>{};
      final Map<String, dynamic>? data = doc.data();
      if (doc.exists && data != null && data['offDays'] is List) {
        for (final dynamic v in (data['offDays'] as List)) {
          final String? s = v?.toString().trim();
          if (s != null && s.isNotEmpty) next.add(s);
        }
      }

//---------------------------------------
// set the UI
//---------------------------------------
      if (mounted) {
        setState(() {
          _offDaysYMD
            ..clear()
            ..addAll(next);
        });
      }
    } catch (_) {
    }
  }

  void _startSlotsListenerForSelectedDay() {

    _slotsSub?.cancel();

    setState(() {
      _loadingSlots = true;
      _bookedByKey.clear();
    });

//---------------------------------------
// get the time slot
//---------------------------------------

    _slotsSub = FirebaseFirestore.instance
        .collection('Facilities')
        .doc(widget.facilityId)
        .collection('Days')
        .doc(_ymdSelected)
        .collection('Slots')
        .snapshots()
        .listen((QuerySnapshot<Map<String, dynamic>> qs) {

      final Map<String, int> nextBooked = <String, int>{};

      for (final QueryDocumentSnapshot<Map<String, dynamic>> d in qs.docs) {
        final Map<String, dynamic> data = d.data();

//---------------------------------------
// get the slot key
//---------------------------------------
        final String key4 = _slotKey4(d.id);
        //---------------------------------------
// get the booked total
//---------------------------------------

        int booked = _asInt(data['booked']);
        if (booked < 0) booked = 0;
        nextBooked[key4] = booked;

      }

      if (mounted) {
        setState(() {
          _bookedByKey
            ..clear()
            ..addAll(nextBooked);
          _loadingSlots = false;
        });
      }
    }, onError: (e) {
      if (_debugPanel) {
        print('Slots listener error: $e');
      }
      if (mounted) {
        setState(() {
          _bookedByKey.clear();
          _loadingSlots = false;
        });
      }
    });
  }
//---------------------------------------
// navigation page
//---------------------------------------

  void _onTabSelected(int i) {
    if (i == 2) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidListOfFacilities()));
    } else if (i == 0) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidAgenda()));
    } else if (i == 1) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidViewBooking()));
    } else if (i == 3) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidNotifications()));
    } else if (i == 4) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidAccount()));
    }
  }

  //---------------------------------------
// pick date calender
//---------------------------------------

  Future<void> _pickDateWithCalendar() async {
    //---------------------------------------
// set only allow today and next 6 days
//---------------------------------------
    final DateTime first = _today;
    final DateTime last  = _today.add(const Duration(days: 6));

    //---------------------------------------
// open calender
//---------------------------------------

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selected,
      firstDate: first,
      lastDate: last,
      helpText: 'Select date',
      //---------------------------------------
// make sure the allowable day is weekday allow and not before and after first adn last
//---------------------------------------
      selectableDayPredicate: (DateTime day) {
        final bool inRange = !day.isBefore(first) && !day.isAfter(last);
        return inRange && _isWeekdayAllowed(day);
      },
    );

    //---------------------------------------
// after its picked
//---------------------------------------
    if (picked != null) {
      setState(() {
        _selected = DateTime(picked.year, picked.month, picked.day);
        _next7 = List<DateTime>.generate(7, (i) => _today.add(Duration(days: i)));
        _pickedStarts.clear();
      });
      _startSlotsListenerForSelectedDay(); // switch listener to new day
    }
  }

  //---------------------------------------
// main build
//---------------------------------------

  @override
  Widget build(BuildContext context) {
    final double barHeight = MediaQuery.of(context).size.height * 0.07;

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(60.h),
        child: AppBar(
          backgroundColor: const Color(0xFF9747FF),
          centerTitle: true,
          elevation: 0,
          automaticallyImplyLeading: false,
          leading: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            tooltip: 'Back',
          ),
          // title
          title: Text(
            'Date and time',
            style: TextStyle(color: Colors.white, fontSize: 18.sp, fontWeight: FontWeight.w600),
          ),
          actions: <Widget>[
            IconButton(
              onPressed: () {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => AndroidListOfFacilities()),
                      (route) => false,
                );
              },
              icon: const Icon(Icons.close, color: Colors.white),
              tooltip: 'Close',
            ),
          ],
        ),
      ),

//---------------------------------------
// body
//---------------------------------------
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h).copyWith(bottom: 120.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
//---------------------------------------
// display the month year for selected day
//---------------------------------------
                      Text(
                        _monthYearText(_selected),
                        style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600),
                      ),
                      SizedBox(width: 8.w),
                      SizedBox(
                        width: 28.w,
                        height: 28.w,
//---------------------------------------
// allow to pick date
//---------------------------------------
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          onPressed: _pickDateWithCalendar,
                          icon: const Icon(Icons.calendar_month),
                          iconSize: 20.sp,
                          tooltip: 'Pick date',
                        ),
                      ),
                    ],
                  ),

                  SizedBox(height: 10.h),

//---------------------------------------
// list the next seven days
//---------------------------------------
                  Row(
                    children: List<Widget>.generate(_next7.length, (int i) {
                      final DateTime d = _next7[i];
                      final bool enabled = _isWeekdayAllowed(d);
                      final Color c = enabled ? Colors.black87 : Colors.black38;

                      return Expanded(
                        child: Center(
//---------------------------------------
// list the day
//---------------------------------------
                        child: Text(
                            _letterFor(d),
                            style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600, color: c),
                          ),
                        ),
                      );
                    }),
                  ),

                  SizedBox(height: 6.h),

//---------------------------------------
// for selectable day
//---------------------------------------
                  Row(
                    children: List<Widget>.generate(_next7.length, (int i) {
                      final DateTime d = _next7[i];

                      final bool isSelected = d.year == _selected.year && d.month == _selected.month && d.day == _selected.day;

                      final bool enabled = _isWeekdayAllowed(d);

                      final Color bg = isSelected ? const Color(0xFF9747FF) : Colors.transparent;
                      final Color fg = isSelected ? Colors.white : (enabled ? Colors.black87 : Colors.black38);

                      return Expanded(
                        child: Center(
                          child: InkWell(
//---------------------------------------
// if it is enable date will turn colour to selected , if not do nothing
//---------------------------------------

                          onTap: enabled
                                ? () {
                              setState(() {
                                _selected = d;
                                _pickedStarts.clear();
                              });
                              _startSlotsListenerForSelectedDay();
                            }
                                : null,
                            borderRadius: BorderRadius.circular(20.r),
                            child: Container(
                              width: 36.w,
                              height: 36.w,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: bg,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
//---------------------------------------
// show day oonly whcih is the first of the date
//---------------------------------------
                              '${d.day}',
                                style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600, color: fg),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),

                  SizedBox(height: 12.h),
                  Container(width: 1.0.sw, height: 1.h, color: Colors.black12),
                  SizedBox(height: 12.h),

//---------------------------------------
// display slot available
//---------------------------------------
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          'Slots Available',
                          style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),

                  SizedBox(height: 6.h),
//---------------------------------------
// row info
//---------------------------------------
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(Icons.info_outline, size: 16.sp, color: Colors.black54),
                      SizedBox(width: 6.w),
                      Expanded(
                        child: Text(
                          'Choose more than 1 start time is allowed',
                          style: TextStyle(fontSize: 12.5.sp, color: Colors.black54, fontWeight: FontWeight.w600),
                          softWrap: true,
                        ),
                      ),
                    ],
                  ),

                  SizedBox(height: 12.h),

//---------------------------------------
// if the picked day is not allowed day( normally wont happend )
//---------------------------------------
                  if (!_isWeekdayAllowed(_selected))
                    Container(
                      width: 1.0.sw,
                      padding: EdgeInsets.all(12.w),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF1F1),
                        borderRadius: BorderRadius.circular(12.r),
                        border: Border.all(color: const Color(0xFFFF7070)),
                      ),
                      child: Text(
                        'Booking is closed on this day.',
                        style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: const Color(0xFFFF0707)),
                      ),
                    )
//---------------------------------------
// show loading if not done loading
//---------------------------------------
                  else if (_loadingFacility || _loadingSlots)
                    SizedBox(
                      width: 28.w,
                      height: 28.w,
                      child: const CircularProgressIndicator(),
                    )
//---------------------------------------
// if no time slot
//---------------------------------------
                  else if (_slotsTemplate.isEmpty)
                      Text(
                        'No time slots set by admin.',
                        style: TextStyle(fontSize: 13.sp, color: Colors.black54, fontWeight: FontWeight.w500),
                      )
                    else
                      Builder(
                        builder: (BuildContext _) {
                          final double fullW = 1.0.sw - 32.w;
                          final double gap = 8.w;
//---------------------------------------
// size to allow 3 chip to be display in a row
//---------------------------------------
                          final double itemW = (fullW - (gap * 2.0)) / 3.0;

                          final List<Widget> chips = <Widget>[];
                          int i = 0;
//---------------------------------------
// slot time plate is the time slot list
//---------------------------------------
                          while (i < _slotsTemplate.length) {
                            final Map<String, dynamic> m = _slotsTemplate[i];
                            final String s = (m['start']).toString(); // "08:00"

                            if (s.isNotEmpty) {
                              final String key = _slotKey4(s);          // "0800"
                              final int booked = _bookedByKey[key] ?? 0; // booked count (default 0)
                              final int capForThis = _facilityCapacity; // capacity override or facility cap

                              final bool isTooSoon = _isSlotTooSoon(s); // 3h lock
                              final bool isFull = booked >= capForThis;
                              final bool isPicked = _pickedStarts.contains(s);

                              // decide colors/styles
                              Color fillColor;
                              Color borderColor;
                              Color textColor;
                              double borderWidth = 1.5;
                              double opacity = 1.0;
//---------------------------------------
// already within 3 hour
//---------------------------------------
                              if (isTooSoon) {
                                fillColor = Colors.grey.shade300;
                                borderColor = Colors.grey.shade500;
                                textColor = Colors.black54;
                                opacity = 0.6;
//---------------------------------------
// slot already full
//---------------------------------------
                              } else if (isFull) {
                                fillColor = const Color(0xFFFFCDD2);
                                borderColor = const Color(0xFFFF0707);
                                textColor = const Color(0xFFB00020);
//---------------------------------------
// picked slot
//---------------------------------------
                              } else if (isPicked) {
                                fillColor = const Color(0xFF9747FF);
                                borderColor = const Color(0xFF4A00B8);
                                textColor = Colors.white;
                                borderWidth = 2.0;
//---------------------------------------
// default slot
//---------------------------------------
                              } else {
                                fillColor = const Color(0xFFB779F1);
                                borderColor = const Color(0xFF6E00D4);
                                textColor = Colors.white;
                              }

                              final bool disabled = isTooSoon || isFull;

//---------------------------------------
// start chip build
//---------------------------------------
                              chips.add(
//---------------------------------------
// ingnore pointer to ingnore disable time
//---------------------------------------
                              IgnorePointer(
                                  ignoring: disabled,
                                  child: Opacity(
                                    opacity: disabled ? 0.85 : 1.0,
                                    child: InkWell(
                                      onTap: () {
                                        setState(() {
                                          if (isPicked) {
                                            _pickedStarts.remove(s);
                                          } else {
                                            _pickedStarts.add(s);
                                          }
                                        });
                                      },
                                      borderRadius: BorderRadius.circular(20.r),
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: <Widget>[
                                          Container(
                                            width: itemW,
                                            height: 44.h,
                                            alignment: Alignment.center,
                                            decoration: BoxDecoration(
                                              color: fillColor,
                                              borderRadius: BorderRadius.circular(20.r),
                                              border: Border.all(color: borderColor, width: borderWidth),
                                            ),
//---------------------------------------
// display time
//---------------------------------------
                                            child: Text(
                                              _toAmPmDotStart(s),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 13.sp,
                                                fontWeight: FontWeight.w700,
                                                color: textColor,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }

                            i = i + 1;
                          }

//---------------------------------------
// column to display chip
//---------------------------------------

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Wrap(spacing: gap, runSpacing: gap, children: chips),
                              ),
//---------------------------------------
// check box for auto asign
//---------------------------------------
                              SizedBox(height: 16.h),
                              CheckboxListTile(
                                value: _autoAssign,
                                onChanged: (bool? v) {
                                  setState(() => _autoAssign = (v ?? true));
                                },
                                controlAffinity: ListTileControlAffinity.leading,
                                title: const Text('Auto-assign facility (slot number)'),
                                contentPadding: EdgeInsets.zero,
                              ),
                            ],
                          );
                        },
                      ),
                ],
              ),
            ),
//---------------------------------------
// confirm button
//---------------------------------------
            Positioned(
              left: 16.w,
              right: 16.w,
              bottom: 16.h,
              child: SizedBox(
                height: 48.h,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF9747FF),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28.r)),
                  ),
//---------------------------------------
// if no date is pick
//---------------------------------------
                  onPressed: _pickedStarts.isEmpty
                      ? null
                      : () async {
//---------------------------------------
// sort the picked selected time
//---------------------------------------
                    final List<String> times = _pickedStarts.toList()..sort();
//---------------------------------------
// if auto assign in true go to confirm booking page
//---------------------------------------

                    if (_autoAssign) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ConfirmBooking(
                            facilityId: widget.facilityId,
                            facilityName: widget.facilityName,
                            dateYMD: _ymdSelected,
                            startTimes: times,
                            autoAssign: true,
                          ),
                        ),
                      );
                    } else {
//---------------------------------------
// or else go select slot page
//---------------------------------------

                      final Map<String, int>? picks = await Navigator.push<Map<String, int>>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SelectSlot(
                            facilityId: widget.facilityId,
                            facilityName: widget.facilityName,
                            dateYMD: _ymdSelected,
                            startTimes: times,
                          ),
                        ),
                      );

//---------------------------------------
// await after slot is picked directly send to confirmation booking
//---------------------------------------

                      if (picks != null && picks.isNotEmpty) {
                        final List<String> sortedKeys = picks.keys.toList()..sort();
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ConfirmBooking(
                              facilityId: widget.facilityId,
                              facilityName: widget.facilityName,
                              dateYMD: _ymdSelected,
                              startTimes: sortedKeys,
                              autoAssign: false,
                              seatPicks: Map<String, int>.unmodifiable(picks),
                            ),
                          ),
                        );
                      }
                    }
                  },
                  child: Text(
                    'Confirm',
                    style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),

//---------------------------------------
// bottom navigation bar
//---------------------------------------

      bottomNavigationBar: BottomMenuBar(
        height: barHeight,
        currentIndex: _currentIndex,
        onTabSelected: _onTabSelected,
      ),
    );
  }
}
