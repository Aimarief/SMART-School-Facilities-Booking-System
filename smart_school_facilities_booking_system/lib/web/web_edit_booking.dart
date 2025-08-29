
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'web_booking_details.dart'; // for openWebBookingDetailsDialog()
import 'package:smart_school_facilities_booking_system/booking_service.dart';
// ---------- helper to open the EDIT popup (keep simple; styling lives inside the widget) ----------
Future<void> openWebEditBookingDialog({
  required BuildContext context,
  required Map<String, dynamic> booking, // raw booking map to show details again later
  required String bookingId,
  required String facilityId,
  required String bookedByUid,
  required String managerUid,
  required String dateYMD,
  required String timeStart,
  required String timeEnd,
  required String seatIndex,
  required String approval,
  required String status,
  bool use24HourFormat = false,
}) async {
  await showDialog(
    context: context,
    barrierDismissible: true,
    builder: (_) {
      return Dialog(
        insetPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
        child: WebEditBooking(
          rawBooking: booking,
          bookingId: bookingId,
          facilityId: facilityId,
          bookedByUid: bookedByUid,
          managerUid: managerUid,
          dateYMD: dateYMD,
          timeStart: timeStart,
          timeEnd: timeEnd,
          seatIndex: seatIndex,
          approval: approval,
          status: status,
          use24HourFormat: use24HourFormat,
        ),
      );
    },
  );
}

class WebEditBooking extends StatefulWidget {
  final Map<String, dynamic> rawBooking;

  final String bookingId;
  final String facilityId;
  final String bookedByUid;
  final String managerUid;
  final String dateYMD;   // current booked date (YYYY-MM-DD)
  final String timeStart; // current time label shown in details
  final String timeEnd;   // current time label shown in details
  final String seatIndex; // current seat index shown in details
  final String approval;
  final String status;
  final bool use24HourFormat;

  const WebEditBooking({
    Key? key,
    required this.rawBooking,
    required this.bookingId,
    required this.facilityId,
    required this.bookedByUid,
    required this.managerUid,
    required this.dateYMD,
    required this.timeStart,
    required this.timeEnd,
    required this.seatIndex,
    required this.approval,
    required this.status,
    this.use24HourFormat = false,
  }) : super(key: key);

  @override
  State<WebEditBooking> createState() => _WebEditBookingState();
}

class _WebEditBookingState extends State<WebEditBooking> {
  // -------- UI colors (kept inside State to match your pattern) --------
  final Color _cSelected = const Color(0xFFB779F1);   // purple when selected
  final Color _cFullRed  = Colors.red;                // full / taken
  final Color _cAvailBg  = Colors.white;              // default white
  final Color _cAvailBrd = const Color(0xFFE5E7EB);   // light border
  final Color _cAvailTxt = const Color(0xFF111827);   // dark text
  final Color _cPanelBg  = const Color(0xFFF9F4FF);   // whole popup background

  // -------- basic selection state --------
  DateTime? _selectedDate;
  String _selectedYMD = '';
  String _selectedSlotKey = '';
  int _selectedSeatIndex = -1;

  // -------- facility config --------
  int _facilitySeatCapacity = 0; // from Facilities/{facilityId}.facilityAvailableSlots (or similar)
  final List<Map<String, String>> _timeSlots = <Map<String, String>>[];
  // each slot map: {'start': 'HH:MM', 'end': 'HH:MM', 'key': 'HHmm'}

  // booked map for selected date: slotKey -> booked count
  final Map<String, int> _dayBooked = <String, int>{};

  // -------- rules for calendar --------
  List<bool> _weekdayOpen = <bool>[true, true, true, true, true, true, true]; // Monday..Sunday
  final Set<String> _offDateYMD = <String>{};

  // -------- seat state for chosen slot --------
  final List<bool> _seatTaken = <bool>[]; // length == _facilitySeatCapacity

  // -------- loading flags --------
  bool _loadingSettings = false;
  bool _loadingFacility = false;
  bool _loadingDayBooked = false;
  bool _loadingSeats = false;

  @override
  void initState() {
    super.initState();

    // 1) set initial date from booking
    if (widget.dateYMD.isNotEmpty) {
      final d = _parseYMD(widget.dateYMD);
      if (d != null) {
        _selectedDate = d;
        _selectedYMD = widget.dateYMD;
      }
    }

    // 2) load system rules + facility config
    _loadSettingsAndOffDays();
    _loadFacilityConfig().then((_) async {
      // after we know time slots and capacity, load the day booked map
      if (_selectedYMD.isNotEmpty) {
        await _loadDayBookedMap(_selectedYMD);
      }
    });
  }

  Future<void> _onConfirm() async {
    if (_selectedYMD.isEmpty) {
      _toast('Please pick a date.');
      return;
    }
    if (_selectedSlotKey.isEmpty) {
      _toast('Please pick a time slot.');
      return;
    }
    if (_selectedSeatIndex < 0) {
      _toast('Please pick a seat.');
      return;
    }

    // 1-based index for database
    final int seatIndex1Based = _selectedSeatIndex + 1;

    // get start/end labels from the UI slot you chose
    String selStart = '';
    String selEnd = '';
    final Map<String, String> ts = _timeSlots.firstWhere(
          (m) => (m.containsKey('key') && m['key'] == _selectedSlotKey),
      orElse: () => <String, String>{},
    );
    if (ts.isNotEmpty) {
      if (ts.containsKey('start')) {
        selStart = (ts['start'] ?? '').trim();
      }
      if (ts.containsKey('end')) {
        selEnd = (ts['end'] ?? '').trim();
      }
    }

    final ok = await _busy(() async {
      await BookingService.moveAcceptedBookingByIdTx(
        bookingId: widget.bookingId,
        newFacilityId: widget.facilityId,   // facility fixed in this UI
        newDateYMD: _selectedYMD,
        newSlotKey: _selectedSlotKey,
        newSeatIndex: seatIndex1Based,
        newStartStr: selStart,              // <= send start
        newEndStr: selEnd,                  // <= send end
      );
    });

    if (!ok) return;

    // Update local copy so Details popup shows new info immediately
    final updated = Map<String, dynamic>.from(widget.rawBooking);
    updated['bookingDate'] = _selectedYMD;
    updated['slotKey'] = _selectedSlotKey;
    updated['seatIndex'] = seatIndex1Based;
    if (selStart.isNotEmpty) updated['start'] = selStart;
    if (selEnd.isNotEmpty) updated['end'] = selEnd;

    if (!mounted) return;
    Navigator.of(context).pop(); // close edit
    await openWebBookingDetailsDialog(
      context: context,
      booking: updated,
      use24HourFormat: widget.use24HourFormat,
    );
  }


// simple busy overlay + friendly errors
  Future<bool> _busy(Future<void> Function() task) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      await task();
      return true;
    } catch (e) {
      _toast(_niceError(e));
      return false;
    } finally {
      if (mounted) Navigator.of(context).pop();
    }
  }

// map raw service/txn errors to user-friendly lines
  String _niceError(Object e) {
    final s = e.toString();

    if (s.contains('Slot is full')) return 'This time slot is full.';
    if (s.contains('Seat already taken')) return 'This seat is already taken.';
    if (s.contains('No free seat')) return 'No free seat in this slot.';
    if (s.contains('Seat index out of range')) return 'That seat number is not valid.';
    if (s.contains('Booking not found')) return 'Booking not found.';
    if (s.contains('Only accepted bookings')) return 'Only accepted, upcoming bookings can be edited.';

    // Firestore transaction contention / precondition failures
    if (s.contains('ABORTED') ||
        s.contains('FAILED_PRECONDITION') ||
        (s.contains('Transaction') && s.contains('conflict')) ||
        s.contains('document version') ||
        s.contains('has been modified') ||
        s.contains('requires all reads to be before writes')) {
      return 'This slot just changed — please try again.';
    }

    return 'Something went wrong. Please try again.';
  }


  @override
  Widget build(BuildContext context) {
    final double maxW = 960.w;

    // Rounded lilac panel with border and (optional) soft shadow
    return ClipRRect(
      borderRadius: BorderRadius.circular(16.r),
      child: Container(
        decoration: BoxDecoration(
          color: _cPanelBg,
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(color: _cAvailBrd),
          // Optional soft shadow (uncomment if you want)
          // boxShadow: [
          //   BoxShadow(
          //     color: Colors.black.withOpacity(0.06),
          //     blurRadius: 12.r,
          //     offset: Offset(0, 4.h),
          //   ),
          // ],
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW),
          child: SingleChildScrollView(
            padding: EdgeInsets.all(16.w),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ---------- header ----------
                Row(
                  children: [
                    Expanded(
                      child: Text('Edit Booking', style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700)),
                    ),
                    IconButton(
                      onPressed: () async {
                        Navigator.of(context).pop();
                        await openWebBookingDetailsDialog(
                          context: context,
                          booking: widget.rawBooking,
                          use24HourFormat: widget.use24HourFormat,
                        );
                      },
                      icon: const Icon(Icons.close),
                      tooltip: 'Close',
                    ),
                  ],
                ),
                SizedBox(height: 12.h),

                // ---------- current booking summary ----------
                _sectionTitle('Current Booking'),
                SizedBox(height: 8.h),
                _pillInfoRow('Date', widget.dateYMD),
                SizedBox(height: 6.h),
                _pillInfoRow('Time', _combineTime(widget.timeStart, widget.timeEnd)),
                SizedBox(height: 6.h),
                _pillInfoRow('Seat/Slot', widget.seatIndex),

                SizedBox(height: 16.h),
                const Divider(height: 1),
                SizedBox(height: 12.h),

                // ---------- Step 1: Date ----------
                _sectionTitle('1) Choose Date'),
                SizedBox(height: 8.h),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: () async {
                        await _openCalendarAndPick();
                      },
                      icon: const Icon(Icons.calendar_today, size: 18),
                      label: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 8.h),
                        child: Text('Pick Date', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700)),
                      ),
                    ),
                    SizedBox(width: 10.w),
                    Expanded(child: _pillInfoRow('Selected', _selectedYMD.isEmpty ? '-' : _selectedYMD)),
                  ],
                ),
                if (_loadingSettings) ...[
                  SizedBox(height: 10.h),
                  _loadingLine('Loading calendar rules...'),
                ],

                SizedBox(height: 16.h),
                const Divider(height: 1),
                SizedBox(height: 12.h),

                // ---------- Step 2: Time Slot (from facility customTimeSlots) ----------
                _sectionTitle('2) Choose Time Slot'),
                SizedBox(height: 8.h),
                if (_selectedYMD.isEmpty)
                  _helpText('Pick a date first.')
                else
                  _buildSlotsWrap(), // paints FULL red using booked >= facilitySeatCapacity

                if (_loadingFacility || _loadingDayBooked) ...[
                  SizedBox(height: 10.h),
                  _loadingLine('Loading time slots...'),
                ],

                SizedBox(height: 16.h),
                const Divider(height: 1),
                SizedBox(height: 12.h),

                // ---------- Step 3: Seat / Slot number ----------
                _sectionTitle('3) Choose Seat / Slot Number'),
                SizedBox(height: 8.h),
                if (_selectedSlotKey.isEmpty)
                  _helpText('Pick a time slot first.')
                else
                  _buildSeatsWrap(),

                if (_loadingSeats) ...[
                  SizedBox(height: 10.h),
                  _loadingLine('Loading seats...'),
                ],

                SizedBox(height: 18.h),
                _legendRow(),

                SizedBox(height: 16.h),
                const Divider(height: 1),
                SizedBox(height: 12.h),

                // ---------- actions ----------
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: () async {
                        Navigator.of(context).pop();
                        await openWebBookingDetailsDialog(
                          context: context,
                          booking: widget.rawBooking,
                          use24HourFormat: widget.use24HourFormat,
                        );
                      },
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
                        child: Text('Close', style: TextStyle(fontSize: 12.sp)),
                      ),
                    ),
                    SizedBox(width: 8.w),

                    ElevatedButton(
                      onPressed: _onConfirm,
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
                        child: Text('Confirm', style: TextStyle(fontSize: 12.sp)),
                      ),
                    )




                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ================================
  // UI helpers
  // ================================

  Widget _sectionTitle(String s) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(s, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700, color: const Color(0xFF111827))),
    );
  }

  Widget _pillInfoRow(String k, String v) {
    String value = v;
    if (value.isEmpty) {
      value = '-';
    }
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFBFF),
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: _cAvailBrd),
      ),
      child: Row(
        children: [
          Text('$k: ', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700)),
          Expanded(child: Text(value, style: TextStyle(fontSize: 12.sp), overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  Widget _helpText(String s) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(s, style: TextStyle(fontSize: 12.sp, color: const Color(0xFF6B7280))),
    );
  }

  Widget _loadingLine(String label) {
    return Row(
      children: [
        const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        SizedBox(width: 8.w),
        Expanded(child: Text(label, style: TextStyle(fontSize: 12.sp))),
      ],
    );
  }

  Widget _legendRow() {
    return Row(
      children: [
        _legendBox(_cFullRed, 'Full / Taken'),
        SizedBox(width: 10.w),
        _legendBox(_cAvailBg, 'Available'),
        SizedBox(width: 10.w),
        _legendBox(_cSelected, 'Selected'),
      ],
    );
  }

  Widget _legendBox(Color c, String label) {
    // add border when the swatch is white so it’s visible on lilac
    BoxDecoration deco;
    if (c == _cAvailBg) {
      deco = BoxDecoration(color: c, border: Border.all(color: _cAvailBrd), borderRadius: BorderRadius.circular(4.r));
    } else {
      deco = BoxDecoration(color: c, borderRadius: BorderRadius.circular(4.r));
    }

    return Row(
      children: [
        Container(width: 14.w, height: 14.w, decoration: deco),
        SizedBox(width: 6.w),
        Text(label, style: TextStyle(fontSize: 12.sp)),
      ],
    );
  }

  // ---------- Slots wrap (from facility customTimeSlots) ----------
  Widget _buildSlotsWrap() {
    if (_timeSlots.isEmpty && !_loadingFacility) {
      return _helpText('No time slots configured for this facility.');
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(8.w),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFBFF),
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: _cAvailBrd),
      ),
      child: Wrap(
        spacing: 8.w,
        runSpacing: 8.h,
        children: [
          for (int i = 0; i < _timeSlots.length; i++)
            _slotBox(_timeSlots[i]),
        ],
      ),
    );
  }

  // One slot box: white by default, purple when selected, red when FULL
  Widget _slotBox(Map<String, String> slot) {
    String start = '';
    String end = '';
    String key = '';

    if (slot.containsKey('start')) {
      start = slot['start']!;
    }
    if (slot.containsKey('end')) {
      end = slot['end']!;
    }
    if (slot.containsKey('key')) {
      key = slot['key']!;
    }

    String label;
    if (start.isNotEmpty) {
      if (end.isNotEmpty) {
        label = _fmtTimeLabel(start) + ' - ' + _fmtTimeLabel(end);
      } else {
        label = _fmtTimeLabel(start);
      }
    } else {
      label = key;
    }

    int booked = 0;
    if (_dayBooked.containsKey(key)) {
      booked = _dayBooked[key]!;
    }

    bool full = false;
    if (_facilitySeatCapacity > 0) {
      if (booked >= _facilitySeatCapacity) {
        full = true;
      } else {
        full = false;
      }
    } else {
      full = false;
    }

    bool selected = false;
    if (_selectedSlotKey == key) {
      selected = true;
    }

    // decide background and text color
    Color bg;
    Color fg;
    BoxDecoration deco;

    if (full) {
      bg = _cFullRed;
      fg = Colors.white;
      deco = BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10.r));
    } else {
      if (selected) {
        bg = _cSelected;
        fg = Colors.white;
        deco = BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10.r));
      } else {
        bg = _cAvailBg;
        fg = _cAvailTxt;
        deco = BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(color: _cAvailBrd),
        );
      }
    }

    return InkWell(
      onTap: () async {
        // block tap if full
        if (full) {
          _toast('This time slot is full.');
          return;
        }

        // set selected slot and clear seat selection
        setState(() {
          _selectedSlotKey = key;
          _selectedSeatIndex = -1;
          _seatTaken.clear();
        });

        // load seat taken flags for the chosen slot
        await _loadSeatsForSlot(_selectedYMD, key);
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
        decoration: deco,
        child: Text(
          label,
          style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700, color: fg),
        ),
      ),
    );
  }

  // ---------- Seats grid ----------
  Widget _buildSeatsWrap() {
    if (_facilitySeatCapacity <= 0 && !_loadingSeats) {
      return _helpText('No seat capacity set for this facility.');
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(8.w),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFBFF),
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: _cAvailBrd),
      ),
      child: Wrap(
        spacing: 8.w,
        runSpacing: 8.h,
        children: [
          for (int i = 0; i < _facilitySeatCapacity; i++)
            _seatBox(i),
        ],
      ),
    );
  }

  // One seat box: white default, purple when selected, red when taken
  Widget _seatBox(int index) {
    final String seatLabel = (index + 1).toString();

    bool taken = false;
    if (index < _seatTaken.length) {
      if (_seatTaken[index] == true) {
        taken = true;
      } else {
        taken = false;
      }
    }

    bool selected = false;
    if (_selectedSeatIndex == index) {
      selected = true;
    }

    Color bg;
    Color fg;
    BoxDecoration deco;

    if (taken) {
      bg = _cFullRed;
      fg = Colors.white;
      deco = BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10.r));
    } else {
      if (selected) {
        bg = _cSelected;
        fg = Colors.white;
        deco = BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10.r));
      } else {
        bg = _cAvailBg;
        fg = _cAvailTxt;
        deco = BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(color: _cAvailBrd),
        );
      }
    }

    return InkWell(
      onTap: () {
        // do not allow selecting taken seats
        if (taken) {
          _toast('This seat is already taken.');
          return;
        }

        // set chosen seat index
        setState(() {
          _selectedSeatIndex = index;
        });
      },
      child: Container(
        width: 56.w,
        height: 44.h,
        alignment: Alignment.center,
        decoration: deco,
        child: Text(
          seatLabel,
          style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700, color: fg),
        ),
      ),
    );
  }

  // ================================
  // Actions
  // ================================

  // open the calendar safely after rules are loaded
  Future<void> _openCalendarAndPick() async {
    if (_loadingSettings == true) {
      _toast('Loading calendar rules... please try again in a moment.');
      return;
    }
    if (_offDateYMD.isEmpty) {
      await _loadSettingsAndOffDays();
    }

    final DateTime today = DateTime.now();
    final DateTime minDate = DateTime(today.year, today.month, today.day);
    final DateTime maxDate = DateTime(today.year + 1, today.month, today.day);

    DateTime init;
    if (_selectedDate == null) {
      init = minDate;
    } else {
      init = _selectedDate!;
    }

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: init,
      firstDate: minDate,
      lastDate: maxDate,
      selectableDayPredicate: (DateTime d) {
        if (_isHoliday(d)) {
          return false;
        }
        if (!_isWorkingDay(d)) {
          return false;
        }
        return true;
      },
    );

    if (picked != null) {
      final String ymd = _toYMD(picked);
      setState(() {
        _selectedDate = picked;
        _selectedYMD = ymd;
        _selectedSlotKey = '';
        _selectedSeatIndex = -1;
        _seatTaken.clear();
        _dayBooked.clear();
      });
      await _loadDayBookedMap(ymd);
    }
  }

  // ================================
  // Firestore loaders
  // ================================

  // read weekday open flags AND OffDays array (SystemInformation/OffDays.offDays)
  Future<void> _loadSettingsAndOffDays() async {
    setState(() {
      _loadingSettings = true;
    });

    try {
      // ---- 1) Weekday settings (SystemInformation/Setting) ----
      final DocumentSnapshot<Map<String, dynamic>> setDoc = await FirebaseFirestore.instance
          .collection('SystemInformation')
          .doc('Setting')
          .get();

      final Map<String, dynamic>? m = setDoc.data();
      if (m != null) {
        final List<bool> tmp = <bool>[true, true, true, true, true, true, true];
        tmp[0] = _readBool(m, 'Monday', true);
        tmp[1] = _readBool(m, 'Tuesday', true);
        tmp[2] = _readBool(m, 'Wednesday', true);
        tmp[3] = _readBool(m, 'Thursday', true);
        tmp[4] = _readBool(m, 'Friday', true);
        tmp[5] = _readBool(m, 'Saturday', true);
        tmp[6] = _readBool(m, 'Sunday', true);
        setState(() {
          _weekdayOpen = tmp;
        });
      }

      // ---- 2) OffDays array (SystemInformation/OffDays.offDays) ----
      final DocumentSnapshot<Map<String, dynamic>> offDoc = await FirebaseFirestore.instance
          .collection('SystemInformation')
          .doc('OffDays')
          .get();

      final Set<String> tmpOff = <String>{};

      if (offDoc.exists) {
        final Map<String, dynamic>? om = offDoc.data();
        if (om != null) {
          if (om.containsKey('offDays')) {
            final dynamic arr = om['offDays'];

            if (arr is List) {
              for (final item in arr) {
                String ymd = '';

                if (item is String) {
                  ymd = item.trim();
                } else {
                  if (item is Timestamp) {
                    final DateTime dt = item.toDate();
                    ymd = _toYMD(dt);
                  } else {
                    if (item is Map<String, dynamic>) {
                      if (item.containsKey('date')) {
                        final v = item['date'];
                        if (v is String) {
                          ymd = v.trim();
                        } else {
                          if (v is Timestamp) {
                            ymd = _toYMD(v.toDate());
                          }
                        }
                      } else {
                        if (item.containsKey('dateYMD')) {
                          final v = item['dateYMD'];
                          if (v is String) {
                            ymd = v.trim();
                          }
                        }
                      }
                    }
                  }
                }

                if (ymd.isNotEmpty) {
                  tmpOff.add(ymd);
                }
              }
            }
          }
        }
      }

      // ---- 3) Optional fallback (old structure) ----
      if (tmpOff.isEmpty) {
        final QuerySnapshot<Map<String, dynamic>> old = await FirebaseFirestore.instance
            .collection('SystemInformation')
            .doc('OffDay')
            .collection('Dates')
            .get();

        for (final doc in old.docs) {
          final Map<String, dynamic> d = doc.data();
          String ymd = '';
          if (d.containsKey('dateYMD')) {
            final v = d['dateYMD'];
            if (v is String) {
              ymd = v.trim();
            }
          }
          if (ymd.isEmpty) {
            if (d.containsKey('date')) {
              final v = d['date'];
              if (v is String) {
                ymd = v.trim();
              } else {
                if (v is Timestamp) {
                  ymd = _toYMD(v.toDate());
                }
              }
            }
          }
          if (ymd.isNotEmpty) {
            tmpOff.add(ymd);
          }
        }
      }

      setState(() {
        _offDateYMD
          ..clear()
          ..addAll(tmpOff);
      });
    } catch (e) {
      _toast('Failed to load system settings.');
    } finally {
      setState(() {
        _loadingSettings = false;
      });
    }
  }

  // Load facilityAvailableSlots and customTimeSlots
  Future<void> _loadFacilityConfig() async {
    setState(() {
      _loadingFacility = true;
    });

    try {
      final DocumentSnapshot<Map<String, dynamic>> facDoc = await FirebaseFirestore.instance
          .collection('Facilities')
          .doc(widget.facilityId)
          .get();

      final Map<String, dynamic>? fd = facDoc.data();

      // seat capacity: try common keys
      int cap = 0;
      if (fd != null) {
        cap = _readInt(fd, 'facilityAvailableSlots', 0);
        if (cap <= 0) {
          final int a = _readInt(fd, 'availableSlots', 0);
          if (a > 0) {
            cap = a;
          } else {
            final int b = _readInt(fd, 'seatCapacity', 0);
            if (b > 0) {
              cap = b;
            } else {
              final int c = _readInt(fd, 'capacity', 0);
              if (c > 0) {
                cap = c;
              } else {
                final int d = _readInt(fd, 'availableSeats', 0);
                if (d > 0) {
                  cap = d;
                }
              }
            }
          }
        }
      }

      // time slots from subcollection "customTimeSlots"
      final List<Map<String, String>> tmpSlots = <Map<String, String>>[];
      final QuerySnapshot<Map<String, dynamic>> sub = await FirebaseFirestore.instance
          .collection('Facilities')
          .doc(widget.facilityId)
          .collection('customTimeSlots')
          .get();

      if (sub.docs.isNotEmpty) {
        for (final doc in sub.docs) {
          final Map<String, dynamic> m = doc.data();
          String s = '';
          String e = '';
          if (m.containsKey('start')) {
            final v = m['start'];
            if (v is String) {
              s = v.trim();
            } else {
              s = v.toString();
            }
          }
          if (m.containsKey('end')) {
            final v = m['end'];
            if (v is String) {
              e = v.trim();
            } else {
              e = v.toString();
            }
          }
          if (s.isNotEmpty || e.isNotEmpty) {
            final String key = _slotKeyFromStart(s);
            tmpSlots.add({'start': s, 'end': e, 'key': key});
          }
        }
      } else {
        // else: try array field on facility doc
        if (fd != null) {
          if (fd.containsKey('customTimeSlots')) {
            final v = fd['customTimeSlots'];
            if (v is List) {
              for (final item in v) {
                if (item is Map<String, dynamic>) {
                  String s = '';
                  String e = '';
                  if (item.containsKey('start')) {
                    final vs = item['start'];
                    if (vs is String) {
                      s = vs.trim();
                    } else {
                      s = vs.toString();
                    }
                  }
                  if (item.containsKey('end')) {
                    final ve = item['end'];
                    if (ve is String) {
                      e = ve.trim();
                    } else {
                      e = ve.toString();
                    }
                  }
                  if (s.isNotEmpty || e.isNotEmpty) {
                    final String key = _slotKeyFromStart(s);
                    tmpSlots.add({'start': s, 'end': e, 'key': key});
                  }
                }
              }
            }
          }
        }
      }

      setState(() {
        _facilitySeatCapacity = cap;
        _timeSlots
          ..clear()
          ..addAll(tmpSlots);
      });
    } catch (e) {
      _toast('Failed to load facility settings.');
    } finally {
      setState(() {
        _loadingFacility = false;
      });
    }
  }

  // Load booked numbers for the selected date (one read for all slots)
  Future<void> _loadDayBookedMap(String ymd) async {
    setState(() {
      _loadingDayBooked = true;
      _dayBooked.clear();
      _selectedSlotKey = '';
      _selectedSeatIndex = -1;
      _seatTaken.clear();
    });

    try {
      final QuerySnapshot<Map<String, dynamic>> snap = await FirebaseFirestore.instance
          .collection('Facilities')
          .doc(widget.facilityId)
          .collection('Days')
          .doc(ymd)
          .collection('Slots')
          .get();

      final Map<String, int> tmp = <String, int>{};
      for (final doc in snap.docs) {
        final Map<String, dynamic> m = doc.data();
        int booked = 0;
        if (m.containsKey('booked')) {
          final v = m['booked'];
          if (v is int) {
            booked = v;
          } else {
            if (v is double) {
              booked = v.toInt();
            }
          }
        } else {
          if (m.containsKey('reserve')) {
            final v = m['reserve'];
            if (v is int) {
              booked = v;
            } else {
              if (v is double) {
                booked = v.toInt();
              }
            }
          }
        }
        tmp[doc.id] = booked;
      }

      setState(() {
        _dayBooked
          ..clear()
          ..addAll(tmp);
      });
    } catch (e) {
      _toast('Failed to load day availability.');
    } finally {
      setState(() {
        _loadingDayBooked = false;
      });
    }
  }

  // Load seats taken flags for the chosen slot (handles 0-based or 1-based IDs)
  Future<void> _loadSeatsForSlot(String ymd, String slotKey) async {
    setState(() {
      _loadingSeats = true;
      _seatTaken.clear();
      _selectedSeatIndex = -1;
    });

    try {
      // default all false according to facility capacity
      if (_facilitySeatCapacity > 0) {
        for (int i = 0; i < _facilitySeatCapacity; i++) {
          _seatTaken.add(false);
        }
      }

      final QuerySnapshot<Map<String, dynamic>> seatsSnap = await FirebaseFirestore.instance
          .collection('Facilities')
          .doc(widget.facilityId)
          .collection('Days')
          .doc(ymd)
          .collection('Slots')
          .doc(slotKey)
          .collection('Seats')
          .get();

      // detect indexing scheme: 0-based vs 1-based
      bool hasZero = false;
      bool hasOne  = false;

      for (final d in seatsSnap.docs) {
        if (d.id == '0') hasZero = true;
        if (d.id == '1') hasOne  = true;
      }

// Default to 1-based (matches your writers). Fall back to 0-based only
// when there is '0' and there is NO '1'.
      int idOffset = 1;
      if (hasZero && !hasOne) {
        idOffset = 0;
      }

      // mark taken seats with correct index
      for (final doc in seatsSnap.docs) {
        final String idStr = doc.id;
        int rawIdx = -1;
        try {
          rawIdx = int.parse(idStr);
        } catch (_) {
          rawIdx = -1;
        }

        int idx = rawIdx;
        if (idOffset == 1) {
          idx = rawIdx - 1;
        }

        if (idx >= 0) {
          if (idx < _seatTaken.length) {
            final Map<String, dynamic> d = doc.data();
            bool taken = false;
            if (d.containsKey('taken')) {
              final v = d['taken'];
              if (v is bool) {
                taken = v;
              } else {
                taken = false;
              }
            } else {
              taken = false;
            }

            if (taken == true) {
              _seatTaken[idx] = true;
            }
          }
        }
      }

      setState(() {});
    } catch (e) {
      _toast('Failed to load seats.');
    } finally {
      setState(() {
        _loadingSeats = false;
      });
    }
  }

  // ================================
  // Small helpers
  // ================================

  // Make slotKey from start time "HH:MM" -> "HHmm"
  String _slotKeyFromStart(String start) {
    String s = start.trim();
    if (s.contains('.')) {
      s = s.replaceAll('.', ':');
    }
    final List<String> p = s.split(':');
    if (p.length >= 2) {
      final String hh = p[0].padLeft(2, '0');
      final String mm = p[1].padLeft(2, '0');
      return hh + mm;
    } else {
      final String only = s.replaceAll(RegExp(r'[^0-9]'), '');
      return only;
    }
  }

  bool _isHoliday(DateTime d) {
    final String ymd = _toYMD(d);
    if (_offDateYMD.contains(ymd)) {
      return true;
    } else {
      return false;
    }
  }

  bool _isWorkingDay(DateTime d) {
    final int idx = d.weekday - 1; // Mon=1 -> 0
    if (idx >= 0 && idx < _weekdayOpen.length) {
      if (_weekdayOpen[idx] == true) {
        return true;
      } else {
        return false;
      }
    } else {
      return true;
    }
  }

  String _toYMD(DateTime d) {
    final String y = d.year.toString().padLeft(4, '0');
    final String m = d.month.toString().padLeft(2, '0');
    final String da = d.day.toString().padLeft(2, '0');
    return y + '-' + m + '-' + da;
  }

  DateTime? _parseYMD(String s) {
    try {
      final List<String> p = s.split('-');
      if (p.length == 3) {
        final int y = int.parse(p[0]);
        final int m = int.parse(p[1]);
        final int d = int.parse(p[2]);
        return DateTime(y, m, d);
      }
    } catch (_) {}
    return null;
  }

  String _fmtTimeLabel(String v) {
    String s = v.trim();
    if (s.contains(':')) {
      final List<String> p = s.split(':');
      if (p.length >= 2) {
        final String hh = p[0].padLeft(2, '0');
        final String mm = p[1].padLeft(2, '0');
        return hh + '.' + mm;
      } else {
        return s;
      }
    } else {
      if (s.contains('.')) {
        return s;
      } else {
        return s;
      }
    }
  }

  String _combineTime(String a, String b) {
    if (a.isEmpty && b.isEmpty) {
      return '-';
    } else {
      if (a.isEmpty) {
        return b;
      } else {
        if (b.isEmpty) {
          return a;
        } else {
          return a + ' - ' + b;
        }
      }
    }
  }

  bool _readBool(Map<String, dynamic> m, String key, bool def) {
    if (m.containsKey(key)) {
      final v = m[key];
      if (v is bool) {
        return v;
      } else {
        if (v is String) {
          final String s = v.trim().toLowerCase();
          if (s == 'true') {
            return true;
          } else {
            if (s == 'false') {
              return false;
            } else {
              return def;
            }
          }
        } else {
          return def;
        }
      }
    } else {
      return def;
    }
  }

  int _readInt(Map<String, dynamic> m, String key, int def) {
    if (m.containsKey(key)) {
      final v = m[key];
      if (v is int) {
        return v;
      } else {
        if (v is double) {
          return v.toInt();
        } else {
          if (v is String) {
            final String s = v.trim();
            try {
              return int.parse(s);
            } catch (_) {
              return def;
            }
          } else {
            return def;
          }
        }
      }
    } else {
      return def;
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
