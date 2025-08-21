// android_booking_date.dart
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// bottom bar + other pages (unchanged)
import 'android_bottom_menu.dart';
import 'android_calendar.dart';
import 'android_view_booking.dart';
import 'android_notifications.dart';
import 'android_account.dart';
import 'android_list_of_facilities.dart';

// go to per-time slot picking page
import 'android_select_slot.dart';

// Auto-assign service (adjust path if your file is elsewhere)
import 'package:smart_school_facilities_booking_system/booking_service.dart';

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
  int _currentIndex = 2;

  late DateTime _today;
  late DateTime _selected;
  late List<DateTime> _next7;

  // weekday rule flags (from SystemInformation)
  bool _allowMon = true;
  bool _allowTue = true;
  bool _allowWed = true;
  bool _allowThu = true;
  bool _allowFri = true;
  bool _allowSat = false;
  bool _allowSun = false;

  // selected start times (store as "08:00")
  final Set<String> _pickedStarts = <String>{};

  // auto-assign toggle (default ON)
  bool _autoAssign = true;

  // cache the day's slot template from Facilities.customTimeSlots
  // each item has {start:"HH:MM", end:"HH:MM", startMin:int, endMin:int}
  List<Map<String, dynamic>> _slotsTemplate = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _today = DateTime(now.year, now.month, now.day);
    _selected = _today;
    _next7 = List<DateTime>.generate(7, (i) => _today.add(Duration(days: i)));
    _loadWeekdayRules();
  }

  // ---------- helpers ----------
  Future<void> _loadWeekdayRules() async {
    try {
      final qs = await FirebaseFirestore.instance
          .collection('SystemInformation')
          .limit(1)
          .get();

      if (qs.docs.isNotEmpty) {
        final m = qs.docs.first.data();
        bool _toBool(dynamic v) {
          if (v is bool) return v;
          if (v is num) return v != 0;
          if (v is String) return v.toLowerCase().trim() == 'true';
          return false;
        }

        _allowMon = m.containsKey('monday') ? _toBool(m['monday']) : _allowMon;
        _allowTue = m.containsKey('tuesday') ? _toBool(m['tuesday']) : _allowTue;
        _allowWed = m.containsKey('wednesday') ? _toBool(m['wednesday']) : _allowWed;
        _allowThu = m.containsKey('thursday') ? _toBool(m['thursday']) : _allowThu;
        _allowFri = m.containsKey('friday') ? _toBool(m['friday']) : _allowFri;
        _allowSat = m.containsKey('saturday') ? _toBool(m['saturday']) : _allowSat;
        _allowSun = m.containsKey('sunday') ? _toBool(m['sunday']) : _allowSun;
      }
      if (mounted) setState(() {});
    } catch (_) {/* keep defaults */}
  }

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

  String _monthYearText(DateTime d) {
    const months = [
      'January','February','March','April','May','June',
      'July','August','September','October','November','December'
    ];
    return '${months[d.month - 1]} ${d.year}';
  }

  // "YYYY-MM-DD" for currently selected date
  String get _ymdSelected {
    final mo = _selected.month.toString().padLeft(2, '0');
    final da = _selected.day.toString().padLeft(2, '0');
    return '${_selected.year}-$mo-$da';
  }

  bool _isWeekdayAllowed(DateTime d) {
    switch (d.weekday) {
      case DateTime.monday: return _allowMon;
      case DateTime.tuesday: return _allowTue;
      case DateTime.wednesday: return _allowWed;
      case DateTime.thursday: return _allowThu;
      case DateTime.friday: return _allowFri;
      case DateTime.saturday: return _allowSat;
      default: return _allowSun;
    }
  }

  Future<void> _pickDateWithCalendar() async {
    final DateTime first = _today;
    final DateTime last  = _today.add(const Duration(days: 6));

    final picked = await showDatePicker(
      context: context,
      initialDate: _selected,
      firstDate: first,
      lastDate: last,
      helpText: 'Select date',
      selectableDayPredicate: (day) =>
      !day.isBefore(first) && !day.isAfter(last) && _isWeekdayAllowed(day),
    );

    if (picked != null) {
      setState(() {
        _selected = DateTime(picked.year, picked.month, picked.day);
        _next7 = List<DateTime>.generate(7, (i) => _today.add(Duration(days: i)));
        _pickedStarts.clear(); // clear selections when date changes
      });
    }
  }

  String _toAmPmDotStart(String hhmm) {
    final parts = hhmm.split(':');
    int hour = int.tryParse(parts.isNotEmpty ? parts[0] : '0') ?? 0;
    int minute = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
    final suffix = hour >= 12 ? 'pm' : 'am';
    final h12 = hour % 12 == 0 ? 12 : hour % 12;
    final m = minute.toString().padLeft(2, '0');
    return '$h12.$m $suffix';
  }

  String _letterFor(DateTime d) {
    switch (d.weekday) {
      case DateTime.sunday: return 'S';
      case DateTime.monday: return 'M';
      case DateTime.tuesday: return 'T';
      case DateTime.wednesday: return 'W';
      case DateTime.thursday: return 'T';
      case DateTime.friday: return 'F';
      default: return 'S';
    }
  }

  // get end time for a given start (from _slotsTemplate)
  String? _endForStart(String start) {
    for (final m in _slotsTemplate) {
      if ((m['start'] ?? '').toString() == start) {
        return (m['end'] ?? '').toString();
      }
    }
    return null;
  }

  // ---------- Confirm handlers ----------
  Future<void> _confirmAutoAssign({
    required List<String> starts, // ["08:00", ...]
  }) async {
    try {
      // read facility once (manager etc.)
      final facDoc = await FirebaseFirestore.instance
          .collection('Facilities')
          .doc(widget.facilityId)
          .get();
      final fac = facDoc.data() ?? {};
      final managerId = (fac['managerId'] ?? '').toString();
      final managerName = (fac['managerName'] ?? '').toString();

      // current user
      final u = FirebaseAuth.instance.currentUser;
      final userId = u?.uid ?? 'unknown';
      final userName = u?.displayName ?? u?.email ?? 'User';

      // create a booking per time (each in a transaction to auto-assign seat)
      for (final start in starts) {
        final key = start.replaceAll(':', ''); // "0800"
        final end = _endForStart(start) ?? ''; // can be '', service doesn't require it

        final bookingBase = <String, dynamic>{
          'userId': userId,
          'userName': userName,
          'facilityId': widget.facilityId,
          'facilityName': widget.facilityName,
          'managerId': managerId,
          'managerName': managerName,
          'bookingDate': _ymdSelected,
          'slotKey': key,       // "0800"
          'start': start,       // "08:00"
          'end': end,           // "09:00" (if template has it)
          'status': 'upcoming',
          'createdAt': FieldValue.serverTimestamp(),
          // 'approval' will be set by service based on facility.requireApproval
        };

        await BookingService.createBookingAutoAssignTx(
          facilityId: widget.facilityId,
          dateYMD: _ymdSelected,
          slotKey: key,
          bookingBase: bookingBase,
        );
      }

      if (!mounted) return;
      _pickedStarts.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Booking(s) created')),
      );
      // send user to "My Bookings"
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidViewBooking()));
    } catch (e) {
      if (!mounted) return;
      final isFull = '$e'.contains('FULL');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isFull
            ? 'One or more selected times are full.'
            : 'Failed to create booking: $e')),
      );
    }
  }

  void _confirm() {
    if (_pickedStarts.isEmpty) return;
    final times = _pickedStarts.toList()..sort();
    if (_autoAssign) {
      _confirmAutoAssign(starts: times);
    } else {
      // Go to SelectSlot page to choose seat numbers
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SelectSlot(
            facilityId: widget.facilityId,
            facilityName: widget.facilityName,
            dateYMD: _ymdSelected,
            startTimes: times, // ["08:00","09:00",...]
          ),
        ),
      );
    }
  }

  // ---------- build ----------
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
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h)
                  .copyWith(bottom: 120.h), // leave room for bottom controls
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

                  // weekday letters
                  Row(
                    children: List.generate(_next7.length, (i) {
                      return Expanded(
                        child: Center(
                          child: Text(
                            _letterFor(_next7[i]),
                            style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
                          ),
                        ),
                      );
                    }),
                  ),

                  SizedBox(height: 6.h),

                  // day numbers selectable
                  Row(
                    children: List.generate(_next7.length, (i) {
                      final d = _next7[i];
                      final isSelected =
                          d.year == _selected.year &&
                              d.month == _selected.month &&
                              d.day == _selected.day;
                      final enabled = _isWeekdayAllowed(d);

                      final bg = isSelected ? const Color(0xFF9747FF) : Colors.transparent;
                      final fg = isSelected
                          ? Colors.white
                          : (enabled ? Colors.black87 : Colors.black38);

                      return Expanded(
                        child: Center(
                          child: InkWell(
                            onTap: enabled
                                ? () {
                              setState(() {
                                _selected = d;
                                _pickedStarts.clear();
                              });
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

                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Slots Available',
                        style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
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

                  // times for this facility
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
                  else
                    StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('Facilities')
                          .doc(widget.facilityId)
                          .snapshots(),
                      builder: (context, facSnap) {
                        if (facSnap.connectionState == ConnectionState.waiting) {
                          return SizedBox(width: 24.w, height: 24.w, child: const CircularProgressIndicator());
                        }

                        final facData = facSnap.data?.data() ?? {};
                        // template: customTimeSlots
                        final List<Map<String, dynamic>> slots = <Map<String, dynamic>>[];
                        final raw = facData['customTimeSlots'];
                        if (raw is List) {
                          for (final item in raw) {
                            if (item is Map<String, dynamic>) slots.add(item);
                          }
                        }
                        _slotsTemplate = slots;

                        if (slots.isEmpty) {
                          return Text('No time slots set by admin.',
                              style: TextStyle(fontSize: 13.sp, color: Colors.black54, fontWeight: FontWeight.w500));
                        }

                        final int capacity = (facData['availableSlots'] ?? 1) is int
                            ? facData['availableSlots'] as int
                            : int.tryParse('${facData['availableSlots']}') ?? 1;

                        // live reserved counts for this date
                        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: FirebaseFirestore.instance
                              .collection('Facilities').doc(widget.facilityId)
                              .collection('Days').doc(_ymdSelected)
                              .collection('Slots').snapshots(),
                          builder: (context, resSnap) {
                            final Map<String, int> reservedByKey = {};
                            if (resSnap.hasData) {
                              for (final d in resSnap.data!.docs) {
                                reservedByKey[d.id] = (d.data()['reserved'] ?? 0) as int;
                              }
                            }

                            final double fullW = 1.0.sw - 32.w;
                            final double gap = 8.w;
                            final double itemW = (fullW - (gap * 2.0)) / 3.0;

                            final List<Widget> chips = <Widget>[];
                            for (final m in slots) {
                              final s = (m['start'] ?? '').toString(); // "08:00"
                              if (s.isEmpty) continue;

                              final key = s.replaceAll(':', ''); // "0800"
                              final reserved = reservedByKey[key] ?? 0;
                              final isFull = reserved >= capacity;
                              final isPicked = _pickedStarts.contains(s);

                              Color fillColor;
                              Color borderColor;
                              Color textColor;

                              if (isFull) {
                                fillColor = const Color(0xFFFFCDD2);   // full: red-ish
                                borderColor = const Color(0xFFFF0707);
                                textColor = const Color(0xFFB00020);
                              } else if (isPicked) {
                                fillColor = const Color(0xFF9747FF);   // selected purple
                                borderColor = const Color(0xFF4A00B8);
                                textColor = Colors.white;
                              } else {
                                fillColor = const Color(0xFFB779F1);   // normal purple
                                borderColor = const Color(0xFF6E00D4);
                                textColor = Colors.white;
                              }

                              chips.add(
                                InkWell(
                                  onTap: () {
                                    if (isFull) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('That time is full')),
                                      );
                                    } else {
                                      setState(() {
                                        if (isPicked) {
                                          _pickedStarts.remove(s);
                                        } else {
                                          _pickedStarts.add(s); // multi-select allowed
                                        }
                                      });
                                    }
                                  },
                                  borderRadius: BorderRadius.circular(20.r),
                                  child: Container(
                                    width: itemW,
                                    height: 44.h,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: fillColor,
                                      borderRadius: BorderRadius.circular(20.r),
                                      border: Border.all(color: borderColor, width: isPicked ? 2.0 : 1.5),
                                    ),
                                    child: Text(
                                      _toAmPmDotStart(s), // "8.00 am"
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: textColor),
                                    ),
                                  ),
                                ),
                              );
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
                                  onChanged: (v) => setState(() => _autoAssign = v ?? true),
                                  controlAffinity: ListTileControlAffinity.leading,
                                  title: const Text('Auto-assign facility (slot number)'),
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ],
                            );
                          },
                        );
                      },
                    ),
                ],
              ),
            ),

            // Bottom confirm button (appears only when at least one time is picked)
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
                  onPressed: _pickedStarts.isEmpty ? null : _confirm,
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
