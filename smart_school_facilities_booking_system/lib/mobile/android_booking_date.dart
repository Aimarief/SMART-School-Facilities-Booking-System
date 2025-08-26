// android_booking_date.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// bottom bar + other pages (unchanged)
import 'android_bottom_menu.dart';
import 'android_calendar.dart';
import 'android_view_booking.dart';
import 'android_notifications.dart';
import 'android_account.dart';
import 'android_list_of_facilities.dart';

// go to per-time slot picking page
import 'android_select_slot.dart';

// confirmation page (writes to DB there)
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
  // ---------------- basic state ----------------
  int _currentIndex = 2;

  late DateTime _today;
  late DateTime _selected;
  late List<DateTime> _next7;

  // ---------------- weekday rules (SystemInformation) ----------------
  bool _allowMon = true;
  bool _allowTue = true;
  bool _allowWed = true;
  bool _allowThu = true;
  bool _allowFri = true;
  bool _allowSat = false;
  bool _allowSun = false;

  // ---------------- facility static data (read ONCE) ----------------
  bool _loadingFacility = true;
  Map<String, dynamic> _facilityData = {};
  List<Map<String, dynamic>> _slotsTemplate = <Map<String, dynamic>>[];
  int _facilityCapacity = 1; // Facilities.availableSlots

  // ---------------- per-day slot data (live) ----------------
  bool _loadingSlots = true;
  final Map<String, int> _bookedByKey = <String, int>{};   // HHmm -> booked
  final Map<String, int> _capByKey    = <String, int>{};   // HHmm -> slot.capacity (only if present)
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _slotsSub;

  // ---------------- user picks ----------------
  final Set<String> _pickedStarts = <String>{}; // "08:00", "09:00"
  bool _autoAssign = true;

  // ------------- debug -------------
  bool _debugPanel = false; // set true to show counters & long-press slot info

  @override
  void initState() {
    super.initState();

    final now = DateTime.now();
    _today = DateTime(now.year, now.month, now.day);
    _selected = _today;
    _next7 = List<DateTime>.generate(7, (i) => _today.add(Duration(days: i)));

    // Serialized bootstrap so the first paint already knows capacity + date
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _loadWeekdayRules();   // May change _selected to first open day
    await _loadFacilityOnce();   // Reads availableSlots + customTimeSlots
    if (mounted) _startSlotsListenerForSelectedDay(); // Start live listener AFTER both above
  }

  @override
  void dispose() {
    _slotsSub?.cancel();
    super.dispose();
  }

  // ---------- helpers ----------
  // "08:00" / "8:00" / "900" -> "0800" / "0900"
  String _slotKey4(String hhmmOrId) {
    String s = hhmmOrId.replaceAll(':', '');
    if (s.length < 4) s = s.padLeft(4, '0');
    return s;
  }

  int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    final int? p = int.tryParse('$v');
    return p ?? 0;
  }

  // ------------------------------------------------------
  // Read weekday booleans from SystemInformation (once)
  // ------------------------------------------------------
  Future<void> _loadWeekdayRules() async {
    try {
      final qs = await FirebaseFirestore.instance
          .collection('SystemInformation')
          .limit(1)
          .get();

      if (qs.docs.isNotEmpty) {
        final m = qs.docs.first.data();

        bool toBool(dynamic v) {
          if (v is bool) return v;
          if (v is num) return v != 0;
          if (v is String) return v.trim().toLowerCase() == 'true';
          return false;
        }

        bool? read(Map<String, dynamic> map, String titleCase) {
          final lower = titleCase.toLowerCase();
          if (map.containsKey(titleCase)) return toBool(map[titleCase]);
          if (map.containsKey(lower)) return toBool(map[lower]);
          return null;
        }

        final s  = read(m, 'Sunday');    if (s  != null) _allowSun = s;
        final mo = read(m, 'Monday');    if (mo != null) _allowMon = mo;
        final tu = read(m, 'Tuesday');   if (tu != null) _allowTue = tu;
        final we = read(m, 'Wednesday'); if (we != null) _allowWed = we;
        final th = read(m, 'Thursday');  if (th != null) _allowThu = th;
        final fr = read(m, 'Friday');    if (fr != null) _allowFri = fr;
        final sa = read(m, 'Saturday');  if (sa != null) _allowSat = sa;

        // If selected day is closed, jump to first open in the 7-day window
        if (!_isWeekdayAllowed(_selected)) {
          for (final d in _next7) {
            if (_isWeekdayAllowed(d)) {
              _selected = d;
              break;
            }
          }
        }
      }
    } catch (_) {}

    if (mounted) setState(() {});
  }

  // ------------------------------------------------------
  // Read facility doc ONCE (capacity + template)
  // ------------------------------------------------------
  Future<void> _loadFacilityOnce() async {
    setState(() => _loadingFacility = true);

    try {
      final snap = await FirebaseFirestore.instance
          .collection('Facilities')
          .doc(widget.facilityId)
          .get();

      _facilityData = snap.data() ?? <String, dynamic>{};

      // customTimeSlots (list of maps with 'start', 'end', etc.)
      _slotsTemplate = <Map<String, dynamic>>[];
      final dynamic raw = _facilityData['customTimeSlots'];
      if (raw is List) {
        for (final item in raw) {
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

  // ------------------------------------------------------
  // Realtime SLOTS for the selected day
  // Facilities/{facility}/Days/{YYYY-MM-DD}/Slots/{HHmm}
  // Fields we care about:
  //  - booked (int)
  //  - capacity (int)  <-- overrides facility capacity for that slot if present
  // ------------------------------------------------------
  void _startSlotsListenerForSelectedDay() {
    _slotsSub?.cancel();
    setState(() {
      _loadingSlots = true;
      _bookedByKey.clear();
      _capByKey.clear();
    });

    _slotsSub = FirebaseFirestore.instance
        .collection('Facilities')
        .doc(widget.facilityId)
        .collection('Days')
        .doc(_ymdSelected)
        .collection('Slots')
        .snapshots()
        .listen((qs) {
      // Rebuild the maps from the snapshot
      final Map<String, int> nextBooked = {};
      final Map<String, int> nextCap = {};

      for (final d in qs.docs) {
        final data = d.data();
        final String key4 = _slotKey4(d.id);

        int booked = 0;
        if (data.containsKey('booked')) {
          booked = _asInt(data['booked']);
        } else if (data.containsKey('reserved')) {
          booked = _asInt(data['reserved']); // legacy
        } else if (data.containsKey('reserve')) {
          booked = _asInt(data['reserve']);  // legacy
        }
        if (booked < 0) booked = 0;
        nextBooked[key4] = booked;

        // Only store slot-level capacity if explicitly present; otherwise UI falls back to facility cap
        if (data.containsKey('capacity')) {
          final int c = _asInt(data['capacity']);
          if (c > 0) {
            nextCap[key4] = c;
          }
        }

        if (_debugPanel) {
          // ignore: avoid_print
          print('[SLOTS] $_ymdSelected $key4 => booked=$booked '
              'cap=${nextCap[key4] ?? _facilityCapacity} '
              '(slotCap? ${data.containsKey('capacity')}) facCap=$_facilityCapacity');
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

  // ------------------------------------------------------
  // Bottom bar navigation
  // ------------------------------------------------------
  void _onTabSelected(int i) {
    if (i == 2) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidListOfFacilities()));
    } else if (i == 0) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidCalendar()));
    } else if (i == 1) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidViewBooking()));
    } else if (i == 3) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidNotifications()));
    } else if (i == 4) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidAccount()));
    }
  }

  // ------------------------------------------------------
  // Month + Year text (e.g., "August 2025")
  // ------------------------------------------------------
  String _monthYearText(DateTime d) {
    const months = [
      'January','February','March','April','May','June',
      'July','August','September','October','November','December'
    ];
    return '${months[d.month - 1]} ${d.year}';
  }

  // Selected date as "YYYY-MM-DD"
  String get _ymdSelected {
    final mo = _selected.month.toString().padLeft(2, '0');
    final da = _selected.day.toString().padLeft(2, '0');
    return '${_selected.year}-$mo-$da';
  }

  // Is this date allowed to book?
  bool _isWeekdayAllowed(DateTime d) {
    if (d.weekday == DateTime.monday) return _allowMon;
    if (d.weekday == DateTime.tuesday) return _allowTue;
    if (d.weekday == DateTime.wednesday) return _allowWed;
    if (d.weekday == DateTime.thursday) return _allowThu;
    if (d.weekday == DateTime.friday) return _allowFri;
    if (d.weekday == DateTime.saturday) return _allowSat;
    return _allowSun; // Sunday
  }

  // Open calendar dialog (block closed days and out-of-range)
  Future<void> _pickDateWithCalendar() async {
    final DateTime first = _today;
    final DateTime last  = _today.add(const Duration(days: 6));

    final picked = await showDatePicker(
      context: context,
      initialDate: _selected,
      firstDate: first,
      lastDate: last,
      helpText: 'Select date',
      selectableDayPredicate: (day) {
        final bool inRange = !day.isBefore(first) && !day.isAfter(last);
        return inRange && _isWeekdayAllowed(day);
      },
    );

    if (picked != null) {
      setState(() {
        _selected = DateTime(picked.year, picked.month, picked.day);
        _next7 = List<DateTime>.generate(7, (i) => _today.add(Duration(days: i)));
        _pickedStarts.clear();
      });
      _startSlotsListenerForSelectedDay(); // switch listener to new day
    }
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

  bool _isTodaySelected() {
    return _selected.year == _today.year &&
        _selected.month == _today.month &&
        _selected.day == _today.day;
  }

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
    final parts = hhmm.split(':');
    int hour = 0;
    int minute = 0;

    if (parts.isNotEmpty) {
      final h = int.tryParse(parts[0]);
      if (h != null) hour = h;
    }
    if (parts.length > 1) {
      final m = int.tryParse(parts[1]);
      if (m != null) minute = m;
    }

    String suffix = 'am';
    if (hour >= 12) suffix = 'pm';

    int h12 = hour % 12;
    if (h12 == 0) h12 = 12;

    final m = minute.toString().padLeft(2, '0');
    return '$h12.$m $suffix';
  }

  String _letterFor(DateTime d) {
    if (d.weekday == DateTime.sunday) return 'S';
    if (d.weekday == DateTime.monday) return 'M';
    if (d.weekday == DateTime.tuesday) return 'T';
    if (d.weekday == DateTime.wednesday) return 'W';
    if (d.weekday == DateTime.thursday) return 'T';
    if (d.weekday == DateTime.friday) return 'F';
    return 'S'; // Saturday
  }

  String? _endForStart(String start) {
    for (final m in _slotsTemplate) {
      final String s = (m['start'] ?? '').toString();
      if (s == start) {
        return (m['end'] ?? '').toString();
      }
    }
    return null;
  }

  // ------------------------------------------------------
  // UI
  // ------------------------------------------------------
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
          title: Text(
            'Date and time',
            style: TextStyle(color: Colors.white, fontSize: 18.sp, fontWeight: FontWeight.w600),
          ),
          actions: [
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

      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h).copyWith(bottom: 120.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Month + year + calendar icon
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
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

                  // weekday letters (grey if closed)
                  Row(
                    children: List.generate(_next7.length, (i) {
                      final d = _next7[i];
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

                  // day numbers selectable (grey + disabled when closed)
                  Row(
                    children: List.generate(_next7.length, (i) {
                      final d = _next7[i];

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

                  // Header
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Slots Available',
                          style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (_debugPanel) ...[
                        const SizedBox(width: 8),
                        Chip(
                          label: Text('cap = $_facilityCapacity'),
                          backgroundColor: Colors.black12,
                        ),
                        const SizedBox(width: 8),
                        Chip(
                          label: Text(_ymdSelected),
                          backgroundColor: Colors.black12,
                        ),
                      ],
                    ],
                  ),

                  SizedBox(height: 6.h),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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

                  // Loading states and warnings
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
                        builder: (_) {
                          final double fullW = 1.0.sw - 32.w;
                          final double gap = 8.w;
                          final double itemW = (fullW - (gap * 2.0)) / 3.0;

                          final List<Widget> chips = <Widget>[];
                          int i = 0;
                          while (i < _slotsTemplate.length) {
                            final Map<String, dynamic> m = _slotsTemplate[i];
                            final String s = (m['start'] ?? '').toString(); // e.g. "08:00"

                            if (s.isNotEmpty) {
                              final String key = _slotKey4(s); // "0800"
                              final int booked = _bookedByKey[key] ?? 0;
                              final int capForThis = _capByKey[key] ?? _facilityCapacity;

                              final bool isPast = _isSlotPastNow(s);
                              final bool isFull = booked >= capForThis;
                              final bool isPicked = _pickedStarts.contains(s);

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
                                // FULL → red + disabled
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
                                            actions: [
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
                                        children: [
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
                                              bottom: 3,
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

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Wrap(spacing: gap, runSpacing: gap, children: chips),
                              ),
                              SizedBox(height: 16.h),
                              CheckboxListTile(
                                value: _autoAssign,
                                onChanged: (v) {
                                  setState(() => _autoAssign = (v ?? true));
                                },
                                controlAffinity: ListTileControlAffinity.leading,
                                title: const Text('Auto-assign facility (slot number)'),
                                contentPadding: EdgeInsets.zero,
                              ),
                              if (_debugPanel) ...[
                                const SizedBox(height: 8),
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

            // Bottom confirm button
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
                  onPressed: _pickedStarts.isEmpty
                      ? null
                      : () async {
                    // sort once
                    final List<String> times = _pickedStarts.toList()..sort();

                    // guard against past times for today
                    if (_isTodaySelected()) {
                      final DateTime now = DateTime.now();
                      final int nowMin = (now.hour * 60) + now.minute;
                      final List<String> bad = [];
                      for (final t in times) {
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

      bottomNavigationBar: BottomMenuBar(
        height: barHeight,
        currentIndex: _currentIndex,
        onTabSelected: _onTabSelected,
      ),
    );
  }
}
