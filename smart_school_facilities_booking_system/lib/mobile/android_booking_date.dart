import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// bottom bar + other pages (unchanged)
import 'android_bottom_menu.dart';
import 'android_agenda.dart';
import 'android_view_booking.dart';
import 'android_notifications.dart';
import 'android_account.dart';
import 'android_list_of_facilities.dart';

// go to per-time slot picking page
import 'android_select_slot.dart';

import 'android_confirmation_booking.dart';

class Booking_Date extends StatefulWidget {
  // facility identity (must have)
  final String facilityId;     // e.g., "fac_123"
  final String facilityName;   // e.g., "Computer Lab 1"

  const Booking_Date({
    Key? key,
    required this.facilityId,
    required this.facilityName,
  }) : super(key: key);

  @override
  State<Booking_Date> createState() => _Booking_DateState();
}

class _Booking_DateState extends State<Booking_Date> {
  // ----- bottom bar -----
  int _currentIndex = 2;

  // ----- dates -----
  late DateTime _today;                  // today (00:00)
  late DateTime _selected;               // user selected date (00:00)
  late List<DateTime> _next7;            // today..today+6

  // ----- weekday rules (SystemInformation) -----
  bool _allowMon = true;
  bool _allowTue = true;
  bool _allowWed = true;
  bool _allowThu = true;
  bool _allowFri = true;
  bool _allowSat = false;
  bool _allowSun = false;

  // ----- facility static data (read ONCE) -----
  bool _loadingFacility = true;
  Map<String, dynamic> _facilityData = {};
  List<Map<String, dynamic>> _slotsTemplate = <Map<String, dynamic>>[];
  int _facilityCapacity = 1; // Facilities.availableSlots

  // ----- per-day slot data (live) -----
  bool _loadingSlots = true;
  final Map<String, int> _bookedByKey = <String, int>{};   // HHmm -> booked
  final Map<String, int> _capByKey    = <String, int>{};   // HHmm -> slot.capacity (only if present)
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _slotsSub;

  // ----- user picks -----
  final Set<String> _pickedStarts = <String>{}; // "08:00", "09:00"
  bool _autoAssign = true;

  // ----- debug panel flag -----
  bool _debugPanel = false;

  // ----- off-days cache -----
  final Set<String> _offDaysYMD = <String>{};

  @override
  void initState() {
    super.initState(); // call parent

    // set today's date + default selected + next 7 dates
    final DateTime now = DateTime.now();
    _today = DateTime(now.year, now.month, now.day);
    _selected = _today;
    _next7 = List<DateTime>.generate(7, (i) => _today.add(Duration(days: i)));

    // serialized bootstrap so first paint already knows capacity + rules
    _bootstrap();
  }

  // do first-time data loads in order (no logic change)
  Future<void> _bootstrap() async {
    await _loadWeekdayRules();   // working-day booleans
    await _loadOffDays();        // holidays
    await _loadFacilityOnce();   // capacity + template
    if (mounted) _startSlotsListenerForSelectedDay();
  }

  @override
  void dispose() {
    // stop the live slots listener
    _slotsSub?.cancel();
    super.dispose();
  }


  // make a 4-char key from "08:00"/"900" → "0800"/"0900" (used for map keys)
  String _slotKey4(String hhmmOrId) {
    String s = hhmmOrId.replaceAll(':', '');
    if (s.length < 4) s = s.padLeft(4, '0');
    return s;
  }

  // safe int parser for dynamic
  int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    final int? p = int.tryParse('$v');
    return p ?? 0;
  }

  // month + year text like "August 2025"
  String _monthYearText(DateTime d) {
    const List<String> months = <String>[
      'January','February','March','April','May','June',
      'July','August','September','October','November','December'
    ];
    return '${months[d.month - 1]} ${d.year}';
  }

  // "YYYY-MM-DD" for currently selected
  String get _ymdSelected {
    final String mo = _selected.month.toString().padLeft(2, '0');
    final String da = _selected.day.toString().padLeft(2, '0');
    return '${_selected.year}-$mo-$da';
  }

  // "YYYY-MM-DD" for any date
  String _ymd(DateTime d) {
    final String mo = d.month.toString().padLeft(2, '0');
    final String da = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mo-$da';
  }

  // convert "HH:MM" to minutes since midnight
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

  // is the selected day equal to today?
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

  // "08:00" -> "8.00 am"
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

  // one-letter weekday for header row
  String _letterFor(DateTime d) {
    if (d.weekday == DateTime.sunday) return 'S';
    if (d.weekday == DateTime.monday) return 'M';
    if (d.weekday == DateTime.tuesday) return 'T';
    if (d.weekday == DateTime.wednesday) return 'W';
    if (d.weekday == DateTime.thursday) return 'T';
    if (d.weekday == DateTime.friday) return 'F';
    return 'S'; // Saturday
  }

  // is this date in the OffDays set?
  bool _isOffDay(DateTime d) => _offDaysYMD.contains(_ymd(d));

  // is this date allowed to book (weekday rule + not OffDay)?
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
    return true;
  }

  // read weekday booleans from SystemInformation/Setting
  Future<void> _loadWeekdayRules() async {
    try {
      final DocumentSnapshot<Map<String, dynamic>> snap = await FirebaseFirestore.instance
          .collection('SystemInformation')
          .doc('Setting')
          .get();

      if (snap.exists) {
        final Map<String, dynamic> m = snap.data() ?? <String, dynamic>{};

        // convert any type to bool
        bool toBool(dynamic v) {
          if (v is bool) return v;
          if (v is num) return v != 0;
          if (v is String) return v.trim().toLowerCase() == 'true';
          return false;
        }

        // read with fallback to lowercase key (short with ??)
        bool read(String key) {
          final dynamic raw = m[key] ?? m[key.toLowerCase()];
          return toBool(raw);
        }

        _allowSun = read('Sunday');
        _allowMon = read('Monday');
        _allowTue = read('Tuesday');
        _allowWed = read('Wednesday');
        _allowThu = read('Thursday');
        _allowFri = read('Friday');
        _allowSat = read('Saturday');
      }
    } catch (_) {
      // keep defaults on error
    }

    if (mounted) setState(() {});
  }

  // read facility doc ONCE (capacity + slots template)
  Future<void> _loadFacilityOnce() async {
    setState(() => _loadingFacility = true);

    try {
      final DocumentSnapshot<Map<String, dynamic>> snap = await FirebaseFirestore.instance
          .collection('Facilities')
          .doc(widget.facilityId)
          .get();

      _facilityData = snap.data() ?? <String, dynamic>{};

      // customTimeSlots (list of maps with 'start', 'end', etc.)
      _slotsTemplate = <Map<String, dynamic>>[];
      final dynamic raw = _facilityData['customTimeSlots'];
      if (raw is List) {
        for (final dynamic item in raw) {
          if (item is Map<String, dynamic>) {
            _slotsTemplate.add(item);
          }
        }
      }

      // availableSlots -> base capacity
      int cap = _asInt(_facilityData['availableSlots']);
      if (cap <= 0) cap = 1;
      _facilityCapacity = cap;
    } catch (_) {
      _facilityData = <String, dynamic>{};
      _slotsTemplate = <Map<String, dynamic>>[];
      _facilityCapacity = 1;
    }

    if (mounted) setState(() => _loadingFacility = false);
  }

  // read OffDays (array of "YYYY-MM-DD")
  Future<void> _loadOffDays() async {
    try {
      final DocumentSnapshot<Map<String, dynamic>> doc = await FirebaseFirestore.instance
          .collection('SystemInformation')
          .doc('OffDays')
          .get();

      final Set<String> next = <String>{};
      final Map<String, dynamic>? data = doc.data();
      if (doc.exists && data != null && data['offDays'] is List) {
        for (final dynamic v in (data['offDays'] as List)) {
          final String? s = v?.toString().trim();
          if (s != null && s.isNotEmpty) next.add(s);
        }
      }

      if (mounted) {
        setState(() {
          _offDaysYMD
            ..clear()
            ..addAll(next);
        });
      }
    } catch (_) {
      // keep empty set on failure
    }
  }

  void _startSlotsListenerForSelectedDay() {
    // stop previous
    _slotsSub?.cancel();

    // reset loading + maps
    setState(() {
      _loadingSlots = true;
      _bookedByKey.clear();
      _capByKey.clear();
    });

    // subscribe to Slots collection for this day
    _slotsSub = FirebaseFirestore.instance
        .collection('Facilities')
        .doc(widget.facilityId)
        .collection('Days')
        .doc(_ymdSelected)
        .collection('Slots')
        .snapshots()
        .listen((QuerySnapshot<Map<String, dynamic>> qs) {
      // build new maps from snapshot
      final Map<String, int> nextBooked = <String, int>{};
      final Map<String, int> nextCap = <String, int>{};

      for (final QueryDocumentSnapshot<Map<String, dynamic>> d in qs.docs) {
        final Map<String, dynamic> data = d.data();

        // 4-char slot key based on doc id
        final String key4 = _slotKey4(d.id);

        // booked can be in several legacy fields → pick the first non-null
        int booked = _asInt(data['booked'] ?? data['reserved'] ?? data['reserve'] ?? 0);
        if (booked < 0) booked = 0;
        nextBooked[key4] = booked;

        // slot-level capacity overrides facility capacity only if present and > 0
        final int slotCap = _asInt(data['capacity'] ?? 0);
        if (slotCap > 0) {
          nextCap[key4] = slotCap;
        }

        if (_debugPanel) {
          // ignore: avoid_print
          print('[SLOTS] $_ymdSelected $key4 => booked=$booked cap=${nextCap[key4] ?? _facilityCapacity}');
        }
      }

      if (mounted) {
        setState(() {
          _bookedByKey
            ..clear()
            ..addAll(nextBooked);
          _capByKey
            ..clear()
            ..addAll(nextCap);
          _loadingSlots = false;
        });
      }
    }, onError: (e) {
      if (_debugPanel) {
        // ignore: avoid_print
        print('Slots listener error: $e');
      }
      if (mounted) {
        setState(() {
          _bookedByKey.clear();
          _capByKey.clear();
          _loadingSlots = false;
        });
      }
    });
  }

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

  Future<void> _pickDateWithCalendar() async {
    final DateTime first = _today;
    final DateTime last  = _today.add(const Duration(days: 6));

    // open calendar
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selected,
      firstDate: first,
      lastDate: last,
      helpText: 'Select date',
      selectableDayPredicate: (DateTime day) {
        final bool inRange = !day.isBefore(first) && !day.isAfter(last);
        return inRange && _isWeekdayAllowed(day);
      },
    );

    // apply picked date and refresh slots
    if (picked != null) {
      setState(() {
        _selected = DateTime(picked.year, picked.month, picked.day);
        _next7 = List<DateTime>.generate(7, (i) => _today.add(Duration(days: i)));
        _pickedStarts.clear();
      });
      _startSlotsListenerForSelectedDay(); // switch listener to new day
    }
  }

  @override
  Widget build(BuildContext context) {
    // bottom bar height scaled from screen
    final double barHeight = MediaQuery.of(context).size.height * 0.07;

    return Scaffold(
      // ----- Top AppBar -----
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(60.h),
        child: AppBar(
          backgroundColor: const Color(0xFF9747FF),
          centerTitle: true,
          elevation: 0,
          automaticallyImplyLeading: false,
          // back button
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
          // close button
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

      // ----- Body -----
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            // scrollable content
            SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h).copyWith(bottom: 120.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  // -- Month + Year + Calendar icon --
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text(
                        _monthYearText(_selected),
                        style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600),
                      ),
                      SizedBox(width: 8.w),
                      SizedBox(
                        width: 28.w,
                        height: 28.w,
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

                  // -- Weekday letters (grey if closed) --
                  Row(
                    children: List<Widget>.generate(_next7.length, (int i) {
                      final DateTime d = _next7[i];
                      final bool enabled = _isWeekdayAllowed(d);
                      final Color c = enabled ? Colors.black87 : Colors.black38;

                      return Expanded(
                        child: Center(
                          child: Text(
                            _letterFor(d),
                            style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600, color: c),
                          ),
                        ),
                      );
                    }),
                  ),

                  SizedBox(height: 6.h),

                  // -- Day numbers (selectable) --
                  Row(
                    children: List<Widget>.generate(_next7.length, (int i) {
                      final DateTime d = _next7[i];

                      final bool isSelected =
                          d.year == _selected.year &&
                              d.month == _selected.month &&
                              d.day == _selected.day;

                      final bool enabled = _isWeekdayAllowed(d);

                      final Color bg = isSelected ? const Color(0xFF9747FF) : Colors.transparent;
                      final Color fg = isSelected ? Colors.white : (enabled ? Colors.black87 : Colors.black38);

                      return Expanded(
                        child: Center(
                          child: InkWell(
                            onTap: enabled
                                ? () {
                              setState(() {
                                _selected = d;
                                _pickedStarts.clear();
                              });
                              _startSlotsListenerForSelectedDay(); // switch listener to this date
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

                  // -- Header: Slots Available --
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          'Slots Available',
                          style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (_debugPanel) ...<Widget>[
                        SizedBox(width: 8.w),
                        Chip(
                          label: Text('cap = $_facilityCapacity'),
                          backgroundColor: Colors.black12,
                        ),
                        SizedBox(width: 8.w),
                        Chip(
                          label: Text(_ymdSelected),
                          backgroundColor: Colors.black12,
                        ),
                      ],
                    ],
                  ),

                  SizedBox(height: 6.h),

                  // -- Info row --
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

                  // -- Loading/Warnings/Slots grid --
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
                  else if (_loadingFacility || _loadingSlots)
                    SizedBox(
                      width: 28.w,
                      height: 28.w,
                      child: const CircularProgressIndicator(),
                    )
                  else if (_slotsTemplate.isEmpty)
                      Text(
                        'No time slots set by admin.',
                        style: TextStyle(fontSize: 13.sp, color: Colors.black54, fontWeight: FontWeight.w500),
                      )
                    else
                      Builder(
                        builder: (BuildContext _) {
                          // responsive chip layout (3 per row)
                          final double fullW = 1.0.sw - 32.w;
                          final double gap = 8.w;
                          final double itemW = (fullW - (gap * 2.0)) / 3.0;

                          final List<Widget> chips = <Widget>[];
                          int i = 0;
                          while (i < _slotsTemplate.length) {
                            final Map<String, dynamic> m = _slotsTemplate[i];
                            final String s = (m['start'] ?? '').toString(); // "08:00"

                            if (s.isNotEmpty) {
                              final String key = _slotKey4(s);          // "0800"
                              final int booked = _bookedByKey[key] ?? 0; // booked count (default 0)
                              final int capForThis = _capByKey[key] ?? _facilityCapacity; // capacity override or facility cap

                              final bool isPast = _isSlotPastNow(s);
                              final bool isFull = booked >= capForThis;
                              final bool isPicked = _pickedStarts.contains(s);

                              // decide colors/styles
                              Color fillColor;
                              Color borderColor;
                              Color textColor;
                              double borderWidth = 1.5;
                              double opacity = 1.0;

                              if (isPast) {
                                fillColor = Colors.grey.shade300;
                                borderColor = Colors.grey.shade500;
                                textColor = Colors.black54;
                                opacity = 0.6;
                              } else if (isFull) {
                                fillColor = const Color(0xFFFFCDD2);
                                borderColor = const Color(0xFFFF0707);
                                textColor = const Color(0xFFB00020);
                              } else if (isPicked) {
                                fillColor = const Color(0xFF9747FF);
                                borderColor = const Color(0xFF4A00B8);
                                textColor = Colors.white;
                                borderWidth = 2.0;
                              } else {
                                fillColor = const Color(0xFFB779F1);
                                borderColor = const Color(0xFF6E00D4);
                                textColor = Colors.white;
                              }

                              final bool disabled = isPast || isFull;

                              // one slot chip (tap to toggle pick)
                              chips.add(
                                IgnorePointer(
                                  ignoring: disabled,
                                  child: Opacity(
                                    opacity: disabled ? 0.85 : 1.0,
                                    child: InkWell(
                                      onLongPress: _debugPanel
                                          ? () {
                                        showDialog(
                                          context: context,
                                          builder: (_) => AlertDialog(
                                            title: Text('Slot $key'),
                                            content: Text(
                                              'booked = $booked\n'
                                                  'capacity (slot/fallback) = $capForThis\n'
                                                  'facilityCap = $_facilityCapacity\n'
                                                  'past = $isPast\n'
                                                  'full = $isFull',
                                            ),
                                            actions: <Widget>[
                                              TextButton(
                                                onPressed: () => Navigator.pop(context),
                                                child: const Text('Close'),
                                              ),
                                            ],
                                          ),
                                        );
                                      }
                                          : null,
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
                                          if (_debugPanel)
                                            Positioned(
                                              bottom: 3.h,
                                              child: Text(
                                                '$booked/$capForThis',
                                                style: TextStyle(
                                                  fontSize: 10.sp,
                                                  color: Colors.black87,
                                                  fontWeight: FontWeight.w600,
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

                          // chips + auto-assign switch
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Wrap(spacing: gap, runSpacing: gap, children: chips),
                              ),
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
                              if (_debugPanel) ...<Widget>[
                                SizedBox(height: 8.h),
                                Text(
                                  'Debug: facilityId=${widget.facilityId}, date=$_ymdSelected, slots=${_bookedByKey.length}',
                                  style: TextStyle(fontSize: 12.sp, color: Colors.black54),
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                ],
              ),
            ),

            // -- Bottom Confirm Button --
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
                  // disable if no picks
                  onPressed: _pickedStarts.isEmpty
                      ? null
                      : () async {
                    // 1) sort selected times
                    final List<String> times = _pickedStarts.toList()..sort();

                    // 2) if today, reject past times
                    if (_isTodaySelected()) {
                      final DateTime now = DateTime.now();
                      final int nowMin = (now.hour * 60) + now.minute;
                      final List<String> bad = <String>[];
                      for (final String t in times) {
                        if (nowMin >= _timeToMinutes(t)) {
                          bad.add(_toAmPmDotStart(t));
                        }
                      }
                      if (bad.isNotEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('These times already passed: ${bad.join(', ')}')),
                        );
                        return;
                      }
                    }

                    // 3) go next by auto-assign or manual seat selection
                    if (_autoAssign) {
                      // directly to confirm
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
                      // open seat selection page first
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

                      // if user picked seats, go to confirm with seat map
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

      // ----- Bottom Navigation Bar -----
      bottomNavigationBar: BottomMenuBar(
        height: barHeight,
        currentIndex: _currentIndex,
        onTabSelected: _onTabSelected,
      ),
    );
  }
}
