import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'web_top_bar.dart';
import 'package:smart_school_facilities_booking_system/booking_service.dart';

// ==============================
// WebBooking (restyled like WebEditBooking)
// ==============================
class WebBooking extends StatefulWidget {
  const WebBooking({Key? key}) : super(key: key);

  @override
  State<WebBooking> createState() => _WebBookingState();
}

class _WebBookingState extends State<WebBooking> {
  final bool _use24HourFormat = true;
  final TextEditingController _facSearch = TextEditingController();

  String? _userId;
  String _role = 'unknown';

  String? _selectedFacId;
  Map<String, dynamic>? _selectedFacData;

  @override
  void initState() {
    super.initState();
    _readUserAndRole();
  }

  @override
  void dispose() {
    _facSearch.dispose();
    super.dispose();
  }

  Future<void> _readUserAndRole() async {
    final User? u = FirebaseAuth.instance.currentUser;

    if (u == null) {
      setState(() {
        _userId = null;
        _role = 'unknown';
      });
      return;
    }

    final String uid = u.uid;
    String roleFromDb = 'unknown';

    try {
      final doc =
      await FirebaseFirestore.instance.collection('UserInformation').doc(uid).get();
      if (doc.exists) {
        final m = doc.data();
        if (m != null) {
          roleFromDb = (m['role'] ?? 'unknown').toString();
        }
      }
    } catch (_) {
      roleFromDb = 'unknown';
    }

    setState(() {
      _userId = uid;
      _role = roleFromDb;
    });
  }

  void _selectFacility(String id, Map<String, dynamic> data) {
    setState(() {
      _selectedFacId = id;
      _selectedFacData = data;
    });
  }

  void _closeRight() {
    setState(() {
      _selectedFacId = null;
      _selectedFacData = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(70.h),
        child: WebCustomTopBar(use24HourFormat: _use24HourFormat),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                padding: EdgeInsets.all(16.w),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: 460.w + 24.w + 1200.w),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _BookingLeftList(
                            width: 460.w,
                            height: 965.h,
                            search: _facSearch,
                            userId: _userId,
                            role: _role,
                            onSelect: _selectFacility,
                          ),
                          SizedBox(width: 24.w),
                          _BookingRightPanel(
                            width: 1200.w,
                            height: 965.h,
                            selectedFacilityId: _selectedFacId,
                            selectedFacilityData: _selectedFacData,
                            onClose: _closeRight,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ==============================
// Simple list panel (unchanged behavior)
// ==============================
class _BoxPanel extends StatelessWidget {
  const _BoxPanel({
    Key? key,
    required this.width,
    required this.height,
    required this.title,
    required this.child,
    this.header,
  }) : super(key: key);

  final double width;
  final double height;
  final String title;
  final Widget child;
  final Widget? header;

  static const Color _fill = Color(0xFFEDDFFF);
  static const Color _outline = Color(0xFF8620E2);

  @override
  Widget build(BuildContext context) {
    final kids = <Widget>[
      Text(title, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600)),
      SizedBox(height: 8.h),
    ];

    if (header != null) {
      kids.add(header!);
      kids.add(SizedBox(height: 8.h));
    }

    kids.add(
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Scrollbar(thumbVisibility: true, child: child),
        ),
      ),
    );

    return Container(
      width: width,
      height: height,
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: _fill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _outline, width: 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: kids),
    );
  }
}

class _SearchHeaderNoAdd extends StatelessWidget {
  const _SearchHeaderNoAdd({
    Key? key,
    required this.controller,
    required this.onChanged,
  }) : super(key: key);

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 48.h,
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search',
                prefixIcon: const Icon(Icons.search, size: 18),
                contentPadding: EdgeInsets.symmetric(vertical: 12.h),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ListTileCard extends StatelessWidget {
  const _ListTileCard({Key? key, required this.label, required this.onTap})
      : super(key: key);

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(.9),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
          child: Row(
            children: [
              Expanded(
                child: Text(label,
                    style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis),
              ),
              const Icon(Icons.chevron_right, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _BookingLeftList extends StatefulWidget {
  const _BookingLeftList({
    Key? key,
    required this.width,
    required this.height,
    required this.search,
    required this.userId,
    required this.role,
    required this.onSelect,
  }) : super(key: key);

  final double width;
  final double height;
  final TextEditingController search;
  final String? userId;
  final String role;
  final void Function(String id, Map<String, dynamic> data) onSelect;

  @override
  State<_BookingLeftList> createState() => _BookingLeftListState();
}

class _BookingLeftListState extends State<_BookingLeftList> {
  Stream<QuerySnapshot<Map<String, dynamic>>> _facilitiesStream() {
    return FirebaseFirestore.instance.collection('Facilities').orderBy('name').snapshots();
  }

  String _clean(String s) => s.trim();

  @override
  Widget build(BuildContext context) {
    return _BoxPanel(
      width: widget.width,
      height: widget.height,
      title: 'Facility',
      header: _SearchHeaderNoAdd(
        controller: widget.search,
        onChanged: (_) => setState(() {}),
      ),
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _facilitiesStream(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(child: Text('Loading...', style: TextStyle(fontSize: 14.sp)));
          }
          if (snap.hasError) {
            return Center(child: Text('Failed to load', style: TextStyle(fontSize: 14.sp)));
          }

          var docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
          if (snap.hasData) docs = snap.data!.docs;

          final String q = _clean(widget.search.text).toLowerCase();
          final filtered = <QueryDocumentSnapshot<Map<String, dynamic>>>[];

          for (final d in docs) {
            final m = d.data();
            final del = (m['deleted'] == true);
            final name = (m['name'] ?? '').toString();

            bool allowed;
            if (widget.role == 'Manager') {
              final managerId = (m['managerId'] ?? '').toString();
              allowed = (widget.userId != null && managerId == widget.userId);
            } else {
              allowed = widget.role != 'unknown';
            }

            final matches = q.isEmpty ? true : name.toLowerCase().contains(q);

            if (!del && allowed && matches) filtered.add(d);
          }

          if (filtered.isEmpty) {
            return Center(child: Text('empty', style: TextStyle(fontSize: 14.sp)));
          }

          return ListView.separated(
            itemCount: filtered.length,
            separatorBuilder: (_, __) => SizedBox(height: 8.h),
            itemBuilder: (context, i) {
              final doc = filtered[i];
              final data = doc.data();
              final name = (data['name'] ?? '').toString();
              return _ListTileCard(label: name, onTap: () => widget.onSelect(doc.id, data));
            },
          );
        },
      ),
    );
  }
}

// ==============================
// RIGHT: Details + Make Booking (restyled like WebEditBooking)
// ==============================
class _BookingRightPanel extends StatelessWidget {
  const _BookingRightPanel({
    Key? key,
    required this.width,
    required this.height,
    required this.selectedFacilityData,
    required this.onClose,
    this.selectedFacilityId,
  }) : super(key: key);

  final double width;
  final double height;
  final Map<String, dynamic>? selectedFacilityData;
  final VoidCallback onClose;
  final String? selectedFacilityId;

  String _readStr(Map<String, dynamic>? m, String key) {
    if (m == null) return '-';
    final v = m[key];
    return (v == null) ? '-' : v.toString();
  }

  Map<String, String> _readAvailableTime(Map<String, dynamic>? m) {
    String start = '-';
    String end = '-';
    if (m != null && m['availableTime'] is Map) {
      final at = m['availableTime'] as Map;
      start = (at['start'] ?? '-').toString();
      end = (at['end'] ?? '-').toString();
    }
    return {'start': start, 'end': end};
  }

  String _toHHmm(String raw) {
    String s = raw.toString().trim();
    if (s.isEmpty || s == '-') return '-';
    s = s.replaceAll('.', ':');
    if (s.contains(':')) {
      final parts = s.split(':');
      if (parts.length >= 2) {
        var hhStr = parts[0];
        var mmStr = parts[1];
        if (hhStr.length == 1) hhStr = '0$hhStr';
        if (mmStr.length == 1) {
          mmStr = '0$mmStr';
        } else if (mmStr.length > 2) {
          mmStr = mmStr.substring(0, 2);
        }
        return '$hhStr:$mmStr';
      }
      return '-';
    } else {
      final digits = s.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.length < 3) return '-';
      if (digits.length == 3) {
        final h = digits.substring(0, 1);
        final m = digits.substring(1, 3);
        final hh = h.length == 1 ? '0$h' : h;
        return '$hh:$m';
      } else {
        final h = digits.substring(0, 2);
        String m = '00';
        if (digits.length >= 4) m = digits.substring(2, 4);
        return '$h:$m';
      }
    }
  }

  String _toAmPm(String hhmm) {
    if (hhmm == '-' || !hhmm.contains(':')) return '-';
    final parts = hhmm.split(':');
    if (parts.length < 2) return '-';
    int hh = int.tryParse(parts[0]) ?? 0;
    int mm = int.tryParse(parts[1]) ?? 0;

    String ap = 'am';
    int displayHour = hh;
    if (hh == 0) {
      displayHour = 12;
      ap = 'am';
    } else if (hh == 12) {
      displayHour = 12;
      ap = 'pm';
    } else if (hh > 12) {
      displayHour = hh - 12;
      ap = 'pm';
    } else {
      ap = 'am';
    }
    final mmStr = mm.toString().padLeft(2, '0');
    return '$displayHour:$mmStr $ap';
  }

  Widget _imagePlaceholder() {
    return Container(
      width: double.infinity,
      height: 260.h,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.7),
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(color: Colors.black12, width: 1.w),
      ),
      child: Text('No Image',
          style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildFacilityImage(String imageName) {
    if (imageName == '-' || imageName.trim().isEmpty) return _imagePlaceholder();
    final hasDot = imageName.contains('.');
    String firstPath, secondPath;
    if (hasDot) {
      firstPath = 'asset/image/$imageName';
      if (imageName.toLowerCase().endsWith('.jpg')) {
        secondPath = 'asset/image/${imageName.substring(0, imageName.length - 4)}.png';
      } else if (imageName.toLowerCase().endsWith('.png')) {
        secondPath = 'asset/image/${imageName.substring(0, imageName.length - 4)}.jpg';
      } else {
        secondPath = '';
      }
    } else {
      firstPath = 'asset/image/$imageName.jpg';
      secondPath = 'asset/image/$imageName.png';
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8.r),
      child: SizedBox(
        width: 300.w,
        height: 260.h,
        child: Image.asset(
          firstPath,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stack) {
            if (secondPath.isNotEmpty) {
              return Image.asset(
                secondPath,
                fit: BoxFit.cover,
                errorBuilder: (context2, error2, stack2) => _imagePlaceholder(),
              );
            } else {
              return _imagePlaceholder();
            }
          },
        ),
      ),
    );
  }

  Widget _labelValue(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600)),
          SizedBox(height: 4.h),
          Text(value, style: TextStyle(fontSize: 13.sp), softWrap: true),
        ],
      ),
    );
  }

  Widget _emptyPlaceholder() {
    return SizedBox(
      height: 820.h,
      child: Center(
          child: Text('Please pick an option',
              style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600))),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _BoxPanel(
      width: width,
      height: height,
      title: 'Details',
      child: SingleChildScrollView(
        padding: EdgeInsets.only(right: 8.w, bottom: 8.h),
        child: _buildInner(context),
      ),
    );
  }

  Widget _buildInner(BuildContext context) {
    if (selectedFacilityData == null) return _emptyPlaceholder();

    final String name = _readStr(selectedFacilityData, 'name');
    final String imageName = _readStr(selectedFacilityData, 'imageName');
    final at = _readAvailableTime(selectedFacilityData);
    final String loc = _readStr(selectedFacilityData, 'location');
    final String det = _readStr(selectedFacilityData, 'details');
    final String dur = _readStr(selectedFacilityData, 'bookingDurationHours');

    String facId = '';
    if (selectedFacilityId != null && selectedFacilityId!.trim().isNotEmpty) {
      facId = selectedFacilityId!;
    } else {
      final String mId = _readStr(selectedFacilityData, 'id');
      final String mFacId = _readStr(selectedFacilityData, 'facilityId');
      if (mId != '-' && mId.trim().isNotEmpty) {
        facId = mId;
      } else if (mFacId != '-' && mFacId.trim().isNotEmpty) {
        facId = mFacId;
      } else {
        facId = '-';
      }
    }

    final String start24 = _toHHmm(at['start'] ?? '-');
    final String end24 = _toHHmm(at['end'] ?? '-');
    final String startAmPm = _toAmPm(start24);
    final String endAmPm = _toAmPm(end24);

    String timeLine = '-';
    if (start24 != '-' && end24 != '-') {
      timeLine = '$start24 – $end24 ($startAmPm – $endAmPm)';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name,
            style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700),
            softWrap: true),
        SizedBox(height: 12.h),
        _buildFacilityImage(imageName),
        SizedBox(height: 16.h),
        _labelValue('Available Time', timeLine),
        _labelValue('Location', loc),
        _labelValue('Description', det),
        _labelValue('Duration per slot (hours)', dur),
        SizedBox(height: 16.h),

        if (facId != '-' && facId.trim().isNotEmpty)
          _MakeBookingSectionRestyled(
            key: ValueKey('make-booking-$facId'),
            facilityId: facId,
            durationHoursText: dur,
            use24HourFormat: false,
            onClose: onClose,
          ),

        
      ],
    );
  }
}

// ============================================================
// Make Booking (restyled exactly like WebEditBooking)
// Steps: Booked by (email) → Date → Time Slot → Seat → Confirm
// with same-day conflict checks for the chosen user
// ============================================================
class _MakeBookingSectionRestyled extends StatefulWidget {
  const _MakeBookingSectionRestyled({
    Key? key,
    required this.facilityId,
    required this.durationHoursText,
    required this.onClose,
    this.use24HourFormat = false,
  }) : super(key: key);

  final String facilityId;
  final String durationHoursText;
  final bool use24HourFormat;
  final VoidCallback onClose;

  @override
  State<_MakeBookingSectionRestyled> createState() =>
      _MakeBookingSectionRestyledState();
}

class _MakeBookingSectionRestyledState
    extends State<_MakeBookingSectionRestyled> {
  // ---------- palette to match WebEditBooking ----------
  final Color _cSelected = const Color(0xFFB779F1);
  final Color _cFullRed = Colors.red;
  final Color _cAvailBg = Colors.white;
  final Color _cAvailBrd = const Color(0xFFE5E7EB);
  final Color _cAvailTxt = const Color(0xFF111827);
  final Color _cPanelBg = const Color(0xFFF9F4FF);
  final Color _cPastBg = const Color(0xFFE5E7EB);
  final Color _cPastTxt = const Color(0xFF9CA3AF);

  // ---------- Booked by email ----------
  final TextEditingController _bookedByEmail = TextEditingController();
  final RegExp _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  // ---------- selection state ----------
  DateTime? _selectedDate;
  String _selectedYMD = '';
  String _selectedSlotKey = '';
  int _selectedSeatIndex = -1; // 0-based for UI; send 1-based

  // ---------- facility config ----------
  int _facilitySeatCapacity = 0;
  String? _managerId;
  final List<Map<String, String>> _timeSlots = <Map<String, String>>[]; // {start,end,key}
  final Map<String, int> _dayBooked = <String, int>{}; // slotKey -> booked

  // ---------- seats for chosen slot ----------
  final List<bool> _seatTaken = <bool>[]; // len == capacity

  // ---------- system rules ----------
  List<bool> _weekdayOpen = <bool>[true, true, true, true, true, true, true];
  final Set<String> _offDateYMD = <String>{};

  // ---------- loading flags ----------
  bool _loadingSettings = false;
  bool _loadingFacility = false;
  bool _loadingDayBooked = false;
  bool _loadingSeats = false;

  @override
  void initState() {
    super.initState();
    _loadSettingsAndOffDays();
    _loadFacilityConfig();
  }

  @override
  void dispose() {
    _bookedByEmail.dispose();
    super.dispose();
  }

  // minutes -> "HH:mm"
  String _minutesToHHmm(int mins) {
    int h = mins ~/ 60;
    int m = mins % 60;
    if (h < 0) { h = 0; } else { if (h > 23) { h = 23; } }
    if (m < 0) { m = 0; } else { if (m > 59) { m = 59; } }
    final hh = h.toString().padLeft(2, '0');
    final mm = m.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

// Get end for a given start from _timeSlots; fallback +60 min
  String _endForStartForConflict(String startHHmm) {
    final sNorm = _normalizeHHmm(startHHmm);
    String end = '';

    final Map<String, String> startToEnd = <String, String>{};
    int i = 0;
    while (i < _timeSlots.length) {
      final m = _timeSlots[i];
      String s = (m['start'] ?? '').trim();
      String e = (m['end'] ?? '').trim();
      if (s.isNotEmpty && e.isNotEmpty) {
        startToEnd[_normalizeHHmm(s)] = _normalizeHHmm(e);
      }
      i = i + 1;
    }

    if (startToEnd.containsKey(sNorm) == true) {
      end = startToEnd[sNorm]!;
    }
    if (end.isEmpty == true) {
      end = _minutesToHHmm(_hmToMinutes(sNorm) + 60);
    }
    return _normalizeHHmm(end);
  }

// Half-open overlap check: [aS,aE) vs [bS,bE) — edge-touch OK
  bool _rangesOverlapStrict(int aStart, int aEnd, int bStart, int bEnd) {
    if (aStart < bEnd) {
      if (aEnd > bStart) {
        return true;
      } else {
        return false;
      }
    } else {
      return false;
    }
  }

  String _rangeText(String s, String e) {
    return _fmtHHmm(s) + ' - ' + _fmtHHmm(e);
  }


  // ================================
  // Confirm (create booking)
  // ================================
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

    final uidCurrent = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uidCurrent.isEmpty) {
      _toast('Please sign in.');
      return;
    }

    // Resolve effective userId to book for
    String effectiveUserId = uidCurrent;
    final emailInput = _bookedByEmail.text.trim();
    if (emailInput.isNotEmpty) {
      if (!_emailRe.hasMatch(emailInput)) {
        _toast('Please enter a valid email address.');
        return;
      }
      final found = await _findUserIdByEmail(emailInput);
      if (found == null || found.isEmpty) {
        _toast('No user found for that email.');
        return;
      }
      effectiveUserId = found;
    }

    // get start/end from selected slot
    final ts = _timeSlots.firstWhere(
          (m) => m['key'] == _selectedSlotKey,
      orElse: () => <String, String>{},
    );

    String selStart = _normalizeHHmm((ts['start'] ?? '').trim());
    String selEnd = _normalizeHHmm((ts['end'] ?? '').trim());

    // compute an end if missing, and normalize
    String selEndForCheck = selEnd.isEmpty ? _endForStartForConflict(selStart) : selEnd;
    selEndForCheck = _normalizeHHmm(selEndForCheck);

    // sanity: start < end
    final int sM = _hmToMinutes(selStart);
    final int eM = _hmToMinutes(selEndForCheck);
    if (!(sM < eM)) {
      _toast('End time must be after start time.');
      return;
    }

    // interval conflict check (half-open; edge-touch OK)
    final reason = await _conflictReasonForInterval(
      userId: effectiveUserId,
      dateYMD: _selectedYMD,
      newStartHHmm: selStart,
      newEndHHmm: selEndForCheck,
    );
    if (reason.isNotEmpty) {
      _toast(reason);
      return;
    }

    // create (use normalized start/end that we validated)
    final int seatIndex1Based = _selectedSeatIndex + 1;

    try {
      final Map<String, dynamic> bookingBase = <String, dynamic>{
        'userId': effectiveUserId,
        'facilityId': widget.facilityId,
        'managerId': _managerId ?? '',
        'bookingDate': _selectedYMD,
        'start': selStart,            // ✅ normalized
        'end': selEndForCheck,        // ✅ normalized & validated
        'slotKey': _selectedSlotKey,
        'seatIndex': seatIndex1Based,
        'status': 'upcoming',
        'approval': 'accepted',
        'seen': false,
        'userSeen': false,
        'rated': false,
        'rejectedAt': null,
        'createdAt': FieldValue.serverTimestamp(),
        if (emailInput.isNotEmpty) 'bookedByEmail': emailInput,
      };

      await BookingService.createBookingPickSeatTx(
        facilityId: widget.facilityId,
        dateYMD: _selectedYMD,
        slotKey: _selectedSlotKey,
        seatIndex: seatIndex1Based,
        bookingBase: bookingBase,
      );

      _toast('Booking created.');
      if (mounted) widget.onClose();
    } catch (e) {
      _toast('Slot is taken');
    }
  }


  // ================================
  // User lookup + conflicts
  // ================================
  Future<String?> _findUserIdByEmail(String email) async {
    try {
      final qs = await FirebaseFirestore.instance
          .collection('UserInformation')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      if (qs.docs.isNotEmpty) return qs.docs.first.id;
    } catch (_) {}

    try {
      final alt = await FirebaseFirestore.instance
          .collection('SystemInformation')
          .doc('Users')
          .collection('List')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      if (alt.docs.isNotEmpty) {
        final m = alt.docs.first.data();
        final uid = (m['userId'] ?? m['uid'] ?? '').toString();
        if (uid.isNotEmpty) return uid;
      }
    } catch (_) {}

    return null;
  }



  // ================================
  // Firestore loaders
  // ================================
  Future<void> _loadSettingsAndOffDays() async {
    setState(() => _loadingSettings = true);
    try {
      // 1) Weekday flags
      final setDoc = await FirebaseFirestore.instance
          .collection('SystemInformation')
          .doc('Setting')
          .get();

      final m = setDoc.data();
      if (m != null) {
        final tmp = <bool>[
          _readBool(m, 'Monday', true),
          _readBool(m, 'Tuesday', true),
          _readBool(m, 'Wednesday', true),
          _readBool(m, 'Thursday', true),
          _readBool(m, 'Friday', true),
          _readBool(m, 'Saturday', true),
          _readBool(m, 'Sunday', true),
        ];
        _weekdayOpen = tmp;
      }

      // 2) OffDays
      final offDoc = await FirebaseFirestore.instance
          .collection('SystemInformation')
          .doc('OffDays')
          .get();

      final tmpOff = <String>{};
      if (offDoc.exists) {
        final om = offDoc.data();
        if (om != null && om['offDays'] is List) {
          for (final item in (om['offDays'] as List)) {
            String ymd = '';
            if (item is String) {
              ymd = item.trim();
            } else if (item is Timestamp) {
              ymd = _toYMD(item.toDate());
            } else if (item is Map<String, dynamic>) {
              final v = item['date'] ?? item['dateYMD'];
              if (v is String) ymd = v.trim();
              if (v is Timestamp) ymd = _toYMD(v.toDate());
            }
            if (ymd.isNotEmpty) tmpOff.add(ymd);
          }
        }
      }

      if (tmpOff.isEmpty) {
        final old = await FirebaseFirestore.instance
            .collection('SystemInformation')
            .doc('OffDay')
            .collection('Dates')
            .get();
        for (final doc in old.docs) {
          String ymd = (doc.data()['dateYMD'] ?? '').toString().trim();
          if (ymd.isEmpty) {
            final v = doc.data()['date'];
            if (v is String) ymd = v.trim();
            if (v is Timestamp) ymd = _toYMD(v.toDate());
          }
          if (ymd.isNotEmpty) tmpOff.add(ymd);
        }
      }

      setState(() {
        _offDateYMD
          ..clear()
          ..addAll(tmpOff);
      });
    } catch (_) {
      _toast('Failed to load system settings.');
    } finally {
      setState(() => _loadingSettings = false);
    }
  }

  Future<void> _loadFacilityConfig() async {
    setState(() => _loadingFacility = true);
    try {
      final facDoc = await FirebaseFirestore.instance
          .collection('Facilities')
          .doc(widget.facilityId)
          .get();
      final fd = facDoc.data();

      // manager
      _managerId = (fd?['managerId'] ?? '').toString();

      // capacity
      int cap = _readInt(fd, 'facilityAvailableSlots', 0);
      if (cap <= 0) cap = _readInt(fd, 'availableSlots', cap);
      if (cap <= 0) cap = _readInt(fd, 'seatCapacity', cap);
      if (cap <= 0) cap = _readInt(fd, 'capacity', cap);
      if (cap <= 0) cap = _readInt(fd, 'availableSeats', cap);

      // slots: subcollection first
      final tmpSlots = <Map<String, String>>[];
      final sub = await FirebaseFirestore.instance
          .collection('Facilities')
          .doc(widget.facilityId)
          .collection('customTimeSlots')
          .get();

      if (sub.docs.isNotEmpty) {
        for (final doc in sub.docs) {
          final m = doc.data();
          final s = (m['start'] ?? '').toString().trim();
          final e = (m['end'] ?? '').toString().trim();
          if (s.isNotEmpty || e.isNotEmpty) {
            tmpSlots.add({'start': s, 'end': e, 'key': _slotKeyFromStart(s)});
          }
        }
      } else if (fd != null && fd['customTimeSlots'] is List) {
        for (final item in (fd['customTimeSlots'] as List)) {
          if (item is Map<String, dynamic>) {
            final s = (item['start'] ?? '').toString().trim();
            final e = (item['end'] ?? '').toString().trim();
            if (s.isNotEmpty || e.isNotEmpty) {
              tmpSlots.add({'start': s, 'end': e, 'key': _slotKeyFromStart(s)});
            }
          }
        }
      }

      tmpSlots.sort((a, b) => (a['key'] ?? '').compareTo(b['key'] ?? ''));

      setState(() {
        _facilitySeatCapacity = cap;
        _timeSlots
          ..clear()
          ..addAll(tmpSlots);
      });
    } catch (_) {
      _toast('Failed to load facility settings.');
    } finally {
      setState(() => _loadingFacility = false);
    }
  }

  Future<void> _loadDayBookedMap(String ymd) async {
    setState(() {
      _loadingDayBooked = true;
      _dayBooked.clear();
      _selectedSlotKey = '';
      _selectedSeatIndex = -1;
      _seatTaken.clear();
    });

    try {
      final snap = await FirebaseFirestore.instance
          .collection('Facilities')
          .doc(widget.facilityId)
          .collection('Days')
          .doc(ymd)
          .collection('Slots')
          .get();

      final tmp = <String, int>{};
      for (final doc in snap.docs) {
        final m = doc.data();
        int booked = 0;
        final v = m['booked'] ?? m['reserve'];
        if (v is int) booked = v;
        if (v is double) booked = v.toInt();
        tmp[doc.id] = booked;
      }

      setState(() {
        _dayBooked
          ..clear()
          ..addAll(tmp);
      });
    } catch (_) {
      _toast('Failed to load day availability.');
    } finally {
      setState(() => _loadingDayBooked = false);
    }
  }

  Future<void> _loadSeatsForSlot(String ymd, String slotKey) async {
    setState(() {
      _loadingSeats = true;
      _seatTaken.clear();
      _selectedSeatIndex = -1;
    });

    try {
      for (int i = 0; i < _facilitySeatCapacity; i++) {
        _seatTaken.add(false);
      }

      final seatsSnap = await FirebaseFirestore.instance
          .collection('Facilities')
          .doc(widget.facilityId)
          .collection('Days')
          .doc(ymd)
          .collection('Slots')
          .doc(slotKey)
          .collection('Seats')
          .get();

      bool hasZero = false, hasOne = false;
      for (final d in seatsSnap.docs) {
        if (d.id == '0') hasZero = true;
        if (d.id == '1') hasOne = true;
      }
      int idOffset = (hasZero && !hasOne) ? 0 : 1;

      for (final doc in seatsSnap.docs) {
        final idStr = doc.id;
        int rawIdx = int.tryParse(idStr) ?? -999;
        int idx = (idOffset == 1) ? rawIdx - 1 : rawIdx;

        if (idx >= 0 && idx < _seatTaken.length) {
          final taken = (doc.data()['taken'] == true);
          if (taken) _seatTaken[idx] = true;
        }
      }

      setState(() {});
    } catch (_) {
      _toast('Failed to load seats.');
    } finally {
      setState(() => _loadingSeats = false);
    }
  }

  Future<String> _conflictReasonForInterval({
    required String userId,
    required String dateYMD,
    required String newStartHHmm,
    required String newEndHHmm, // can be empty; handled below
  }) async {
    try {
      final String nS = _normalizeHHmm(newStartHHmm);
      String nE = _normalizeHHmm(newEndHHmm);
      if (nE.isEmpty) {
        nE = _endForStartForConflict(nS); // +60 min fallback when slot has no stored end
      }
      final int newS = _hmToMinutes(nS);
      final int newE = _hmToMinutes(nE);

      final qs = await FirebaseFirestore.instance
          .collection('Bookings')
          .where('userId', isEqualTo: userId)
          .where('bookingDate', isEqualTo: dateYMD)
          .get();

      for (final d in qs.docs) {
        final m = d.data();
        final ap = (m['approval'] ?? '').toString().toLowerCase().trim();
        final keep = (ap == 'accepted' || ap == 'approved' || ap == 'pending');
        if (!keep) continue;

        String s = (m['start'] ?? m['startTime'] ?? '').toString();
        s = _normalizeHHmm(s);
        if (s.isEmpty) continue;

        String e = (m['end'] ?? m['endTime'] ?? '').toString();
        e = _normalizeHHmm(e);
        if (e.isEmpty) e = _endForStartForConflict(s);

        final int exS = _hmToMinutes(s);
        final int exE = _hmToMinutes(e);

        // half-open overlap: [newS,newE) vs [exS,exE), edge-touch OK
        if (newS < exE && newE > exS) {
          return 'Overlap with other booking ${_fmtHHmm(s)} - ${_fmtHHmm(e)}.';
        }
      }
      return '';
    } catch (_) {
      return 'Could not verify the other bookings. Please try again.';
    }
  }


  // ================================
  // UI
  // ================================
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16.r),
      child: Container(
        decoration: BoxDecoration(
          color: _cPanelBg,
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(color: _cAvailBrd),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(16.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // header
              Row(
                children: [
                  Expanded(
                    child: Text('Make a Booking',
                        style:
                        TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              SizedBox(height: 12.h),

              // Booked by
              _sectionTitle('Booked by'),
              SizedBox(height: 8.h),
              SizedBox(
                width: 320.w,
                child: TextField(
                  controller: _bookedByEmail,
                  keyboardType: TextInputType.emailAddress,
                  inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'email',
                    contentPadding:
                    EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10.r)),
                  ),
                  style: TextStyle(fontSize: 12.sp),
                ),
              ),

              SizedBox(height: 16.h),
              const Divider(height: 1),
              SizedBox(height: 12.h),

              // Step 1: Date
              _sectionTitle('1) Choose Date'),
              SizedBox(height: 8.h),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _openCalendarAndPick,
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 8.h),
                      child: Text('Pick Date',
                          style:
                          TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: _pillInfoRow('Selected',
                        _selectedYMD.isEmpty ? '-' : _selectedYMD),
                  ),
                ],
              ),
              if (_loadingSettings) ...[
                SizedBox(height: 10.h),
                _loadingLine('Loading calendar rules...'),
              ],

              SizedBox(height: 16.h),
              const Divider(height: 1),
              SizedBox(height: 12.h),

              // Step 2: Time slots
              _sectionTitle('2) Choose Time Slot'),
              SizedBox(height: 8.h),
              if (_selectedYMD.isEmpty)
                _helpText('Pick a date first.')
              else
                _buildSlotsWrap(),
              if (_loadingFacility || _loadingDayBooked) ...[
                SizedBox(height: 10.h),
                _loadingLine('Loading time slots...'),
              ],

              SizedBox(height: 16.h),
              const Divider(height: 1),
              SizedBox(height: 12.h),

              // Step 3: Seat
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

              // actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: widget.onClose,
                    child: Padding(
                      padding:
                      EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
                      child: Text('Close', style: TextStyle(fontSize: 12.sp)),
                    ),
                  ),
                  SizedBox(width: 8.w),
                  ElevatedButton(
                    onPressed: _onConfirm,
                    child: Padding(
                      padding:
                      EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
                      child: Text('Confirm', style: TextStyle(fontSize: 12.sp)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- UI helpers (mirroring WebEditBooking) ----------
  Widget _sectionTitle(String s) => Align(
    alignment: Alignment.centerLeft,
    child: Text(s,
        style: TextStyle(
            fontSize: 14.sp, fontWeight: FontWeight.w700, color: _cAvailTxt)),
  );

  Widget _pillInfoRow(String k, String v) {
    final value = v.isEmpty ? '-' : v;
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
          Expanded(
              child: Text(value,
                  style: TextStyle(fontSize: 12.sp), overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  Widget _helpText(String s) => Align(
    alignment: Alignment.centerLeft,
    child: Text(s, style: TextStyle(fontSize: 12.sp, color: const Color(0xFF6B7280))),
  );

  Widget _loadingLine(String label) => Row(
    children: [
      const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
      SizedBox(width: 8.w),
      Expanded(child: Text(label, style: TextStyle(fontSize: 12.sp))),
    ],
  );

  Widget _legendRow() => Row(
    children: [
      _legendBox(_cFullRed, 'Full / Taken'),
      SizedBox(width: 10.w),
      _legendBox(_cAvailBg, 'Available'),
      SizedBox(width: 10.w),
      _legendBox(_cSelected, 'Selected'),
    ],
  );

  Widget _legendBox(Color c, String label) {
    final BoxDecoration deco = (c == _cAvailBg)
        ? BoxDecoration(color: c, border: Border.all(color: _cAvailBrd), borderRadius: BorderRadius.circular(4.r))
        : BoxDecoration(color: c, borderRadius: BorderRadius.circular(4.r));
    return Row(
      children: [
        Container(width: 14.w, height: 14.w, decoration: deco),
        SizedBox(width: 6.w),
        Text(label, style: TextStyle(fontSize: 12.sp)),
      ],
    );
  }

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
        children: [for (final m in _timeSlots) _slotBox(m)],
      ),
    );
  }

  Widget _slotBox(Map<String, String> slot) {
    final start = (slot['start'] ?? '');
    final end = (slot['end'] ?? '');
    final key = (slot['key'] ?? '');

    final past = _isSlotPastForSelectedDate(key);

    final label = start.isNotEmpty
        ? (end.isNotEmpty ? '${_fmtTimeLabel(start)} - ${_fmtTimeLabel(end)}' : _fmtTimeLabel(start))
        : key;

    final booked = _dayBooked[key] ?? 0;
    final full = _facilitySeatCapacity > 0 && booked >= _facilitySeatCapacity;
    final selected = _selectedSlotKey == key;

    Color bg;
    Color fg;
    BoxDecoration deco;

    if (past) {
      bg = _cPastBg;
      fg = _cPastTxt;
      deco = BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10.r), border: Border.all(color: _cAvailBrd));
    } else if (full) {
      bg = _cFullRed;
      fg = Colors.white;
      deco = BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10.r));
    } else if (selected) {
      bg = _cSelected;
      fg = Colors.white;
      deco = BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10.r));
    } else {
      bg = _cAvailBg;
      fg = _cAvailTxt;
      deco = BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10.r), border: Border.all(color: _cAvailBrd));
    }

    return InkWell(
      onTap: () async {
        if (past) {
          _toast('This time slot has already passed.');
          return;
        }
        if (full) {
          _toast('This time slot is full.');
          return;
        }
        setState(() {
          _selectedSlotKey = key;
          _selectedSeatIndex = -1;
          _seatTaken.clear();
        });
        await _loadSeatsForSlot(_selectedYMD, key);
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
        decoration: deco,
        child: Text(label,
            style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700, color: fg)),
      ),
    );
  }

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
        children: [for (int i = 0; i < _facilitySeatCapacity; i++) _seatBox(i)],
      ),
    );
  }

  Widget _seatBox(int index) {
    final seatLabel = (index + 1).toString();
    final taken = (index < _seatTaken.length) ? (_seatTaken[index] == true) : false;
    final selected = (_selectedSeatIndex == index);

    Color bg;
    Color fg;
    BoxDecoration deco;

    if (taken) {
      bg = _cFullRed;
      fg = Colors.white;
      deco = BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10.r));
    } else if (selected) {
      bg = _cSelected;
      fg = Colors.white;
      deco = BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10.r));
    } else {
      bg = _cAvailBg;
      fg = _cAvailTxt;
      deco = BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(10.r), border: Border.all(color: _cAvailBrd));
    }

    return InkWell(
      onTap: () {
        if (taken) {
          _toast('This seat is already taken.');
          return;
        }
        setState(() => _selectedSeatIndex = index);
      },
      child: Container(
        width: 56.w,
        height: 44.h,
        alignment: Alignment.center,
        decoration: deco,
        child: Text(seatLabel,
            style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700, color: fg)),
      ),
    );
  }

  // ================================
  // Calendar
  // ================================
  Future<void> _openCalendarAndPick() async {
    if (_loadingSettings) {
      _toast('Loading calendar rules... please try again in a moment.');
      return;
    }
    if (_offDateYMD.isEmpty) await _loadSettingsAndOffDays();

    final today = DateTime.now();
    final minDate = DateTime(today.year, today.month, today.day);
    final maxDate = DateTime(today.year + 1, today.month, today.day);

    final init = _selectedDate ?? minDate;

    final picked = await showDatePicker(
      context: context,
      initialDate: init,
      firstDate: minDate,
      lastDate: maxDate,
      selectableDayPredicate: (d) {
        if (_isHoliday(d)) return false;
        if (!_isWorkingDay(d)) return false;
        return true;
      },
    );

    if (picked != null) {
      final ymd = _toYMD(picked);
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

  bool _isSelectedDateToday() {
    if (_selectedDate == null) return false;
    final now = DateTime.now();
    final d = _selectedDate!;
    return now.year == d.year && now.month == d.month && now.day == d.day;
  }

  bool _isSlotPastForSelectedDate(String key) {
    if (!_isSelectedDateToday()) return false;
    if (key.length < 4) return false;

    final now = DateTime.now();
    final hh = int.tryParse(key.substring(0, 2)) ?? 0;
    final mm = int.tryParse(key.substring(2, 4)) ?? 0;
    final slotStart = DateTime(now.year, now.month, now.day, hh, mm);

    // treat "now == start" as past/unavailable:
    return !now.isBefore(slotStart);
  }

  // ================================
  // Small helpers (mirroring WebEditBooking)
// ================================
  String _normalizeHHmm(String s) {
    var t = s.trim().replaceAll(' ', '').replaceAll('.', ':').replaceAll('-', ':');
    if (!t.contains(':')) {
      var d = t.replaceAll(RegExp(r'[^0-9]'), '');
      if (d.length == 3) d = '0$d';
      if (d.length >= 4) return '${d.substring(0, 2)}:${d.substring(2, 4)}';
      return t;
    } else {
      final p = t.split(':');
      final hh = (p.isNotEmpty ? p[0] : '0').padLeft(2, '0');
      final mm = (p.length > 1 ? p[1] : '0').padLeft(2, '0');
      return '$hh:$mm';
    }
  }

  int _hmToMinutes(String s) {
    final n = _normalizeHHmm(s);
    final p = n.split(':');
    final h = int.tryParse(p[0]) ?? 0;
    final m = int.tryParse(p[1]) ?? 0;
    return h * 60 + m;
  }

  String _minToHHmm(int mins) {
    final h = (mins ~/ 60) % 24;
    final m = mins % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  String _fmtHHmm(String s) {
    final n = _normalizeHHmm(s);
    final p = n.split(':');
    return (p.length >= 2) ? '${p[0].padLeft(2, '0')}.${p[1].padLeft(2, '0')}' : n;
  }

  String _fmtTimeLabel(String v) {
    final s = v.trim();
    if (s.contains(':')) {
      final p = s.split(':');
      if (p.length >= 2) {
        return '${p[0].padLeft(2, '0')}.${p[1].padLeft(2, '0')}';
      }
    }
    return s.contains('.') ? s : s;
  }

  String _slotKeyFromStart(String start) {
    var s = start.trim();
    if (s.contains('.')) s = s.replaceAll('.', ':');
    final p = s.split(':');
    if (p.length >= 2) {
      return p[0].padLeft(2, '0') + p[1].padLeft(2, '0');
    } else {
      return s.replaceAll(RegExp(r'[^0-9]'), '');
    }
  }

  bool _isHoliday(DateTime d) => _offDateYMD.contains(_toYMD(d));
  bool _isWorkingDay(DateTime d) {
    final idx = d.weekday - 1;
    if (idx < 0 || idx >= _weekdayOpen.length) return true;
    return _weekdayOpen[idx] == true;
  }

  String _toYMD(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  bool _readBool(Map<String, dynamic>? m, String key, bool def) {
    if (m == null) return def;
    if (!m.containsKey(key)) return def;
    final v = m[key];
    if (v is bool) return v;
    if (v is String) {
      final s = v.trim().toLowerCase();
      if (s == 'true') return true;
      if (s == 'false') return false;
    }
    return def;
  }

  int _readInt(Map<String, dynamic>? m, String key, int def) {
    if (m == null) return def;
    if (!m.containsKey(key)) return def;
    final v = m[key];
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) {
      final s = v.trim();
      return int.tryParse(s) ?? def;
    }
    return def;
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
