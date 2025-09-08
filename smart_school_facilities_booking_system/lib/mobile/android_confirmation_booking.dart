import 'package:cloud_firestore/cloud_firestore.dart';        // Firestore reads
import 'package:firebase_auth/firebase_auth.dart';            // Current user
import 'package:flutter/material.dart';                       // UI
import 'package:flutter_screenutil/flutter_screenutil.dart';  // .w .h .sp .sw .sh

// Bottom bar + other pages (keep navigation consistent)
import 'android_bottom_menu.dart';
import 'android_agenda.dart';
import 'android_view_booking.dart';
import 'android_notifications.dart';
import 'android_account.dart';
import 'android_list_of_facilities.dart';

// Booking service (your Firestore write helpers)
import 'package:smart_school_facilities_booking_system/booking_service.dart';
import 'package:smart_school_facilities_booking_system/notification_service.dart';

// ------------------------------ widget ------------------------------
class ConfirmBooking extends StatefulWidget {
  // facility to book
  final String facilityId;
  final String facilityName;

  // selection summary
  final String dateYMD;              // "YYYY-MM-DD"
  final List<String> startTimes;     // e.g. ["08:00","09:00"]

  // seat allocation mode
  final bool autoAssign;             // system pick seat if true
  final Map<String, int>? seatPicks; // manual picks per start

  const ConfirmBooking({
    Key? key,
    required this.facilityId,
    required this.facilityName,
    required this.dateYMD,
    required this.startTimes,
    required this.autoAssign,
    this.seatPicks,
  }) : super(key: key);

  @override
  State<ConfirmBooking> createState() => _ConfirmBookingState();
}

// ------------------------------ state ------------------------------
class _ConfirmBookingState extends State<ConfirmBooking> {
  // bottom bar index
  int _currentIndex = 2;

  // user info
  String _userId = '';
  String _userName = '';
  String _userEmail = '';
  String _userContact = '';

  // facility info
  bool _loadingFacility = true;
  Map<String, dynamic> _facility = {};
  int _facilityCapacity = 1; // fallback if slot has no capacity set
  String _facilityName = '';
  String _facilityImagePath = '';
  String _location = '';
  String _description = '';
  String _managerId = '';
  bool _requireApproval = false;

  // manager info
  bool _loadingManager = true;
  Map<String, dynamic> _manager = {};

  // auto-assign preview per start time
  bool _loadingAutoSeats = false;
  final Map<String, int?> _autoSeatByStart = {};

  // per-slot stats
  bool _loadingSlotStats = false;
  final Map<String, int> _capacityByStart = {}; // per-slot capacity
  final Map<String, int> _reserveByStart = {}; // accepted/booked count

  // approval reason
  final TextEditingController _reasonCtrl = TextEditingController();
  int _reasonLen = 0;

  // saving flag
  bool _saving = false;

  // ------------------------------ lifecycle: init ------------------------------
  @override
  void initState() {
    super.initState(); // call parent init

    _loadUser(); // read current user

    // track reason length live
    _reasonCtrl.addListener(() {
      final int len = _reasonCtrl.text.characters.length; // count UTF-16 safely
      int safe = len; // clamp 0..99
      if (safe < 0) {
        safe = 0;
      } else {
        if (safe > 99) {
          safe = 99;
        }
      }
      setState(() {
        _reasonLen = safe;
      }); // update UI count
    });

    _loadFacilityThenChain(); // fetch facility → manager → slot stats → auto seats
  }

  // ------------------------------ lifecycle: dispose ------------------------------
  @override
  void dispose() {
    _reasonCtrl.dispose(); // clean controller
    super.dispose(); // call parent dispose
  }

  // ------------------------------ user: read current user ------------------------------
  Future<void> _loadUser() async {
    try {
      final User? u = FirebaseAuth.instance.currentUser; // get firebase user

      if (u != null) {
        _userId = u.uid; // store uid

        if (u.email != null) { // read email
          _userEmail = u.email!;
        }

        if (u.displayName != null) { // read display name
          final String dn = u.displayName!.trim();
          if (dn.isNotEmpty) {
            _userName = dn;
          }
        }
      }

      if (_userName.isEmpty) { // fallback user name
        if (_userEmail.isNotEmpty) {
          _userName = _userEmail;
        } else {
          _userName = 'User';
        }
      }

      if (_userId.isNotEmpty) { // read profile doc for contact/name override
        final ds = await FirebaseFirestore.instance
            .collection('UserInformation')
            .doc(_userId)
            .get();

        if (ds.exists) {
          final Map<String, dynamic>? m = ds.data();
          if (m != null) {
            if (m.containsKey('username')) {
              final dynamic un = m['username'];
              if (un is String) {
                final String s = un.trim();
                if (s.isNotEmpty) {
                  _userName = s;
                }
              }
            }
            if (m.containsKey('contact')) {
              final dynamic c = m['contact'];
              if (c is String) {
                final String s = c.trim();
                if (s.isNotEmpty) {
                  _userContact = s;
                }
              }
            }
          }
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() {});
    } // refresh UI
  }

  // ------------------------------ chain: load facility → manager → slot stats → auto seats ------------------------------
  Future<void> _loadFacilityThenChain() async {
    await _loadFacilityOnce(); // read facility fields
    await _loadManagerOnce(); // read manager profile
    await _prefetchSlotStats(); // per-slot capacity + booked
    if (widget.autoAssign) {
      await _prefetchAutoSeats();
    } // seat preview only for auto-assign
  }

  // ------------------------------ facility: read once ------------------------------
  Future<void> _loadFacilityOnce() async {
    setState(() {
      _loadingFacility = true;
    }); // show loading

    try {
      final snap = await FirebaseFirestore.instance
          .collection('Facilities')
          .doc(widget.facilityId)
          .get();

      if (snap.exists) {
        final Map<String, dynamic>? data = snap.data();
        if (data != null) {
          _facility = data; // keep whole map

          // name
          _facilityName = (data['name'] as String?) ?? '';
          if (_facilityName.isEmpty) {
            _facilityName = widget.facilityName;
          }

          // image path
          final String imageName = (data['imageName'] as String?)?.trim() ?? '';
          _facilityImagePath =
          imageName.isNotEmpty ? 'asset/image/$imageName' : '';

          // location / description
          _location = (data['location'] as String?) ?? '';
          _description = (data['details'] as String?) ?? '';

          // capacity fallback
          _facilityCapacity = 1;
          final dynamic cap = data['availableSlots'];
          if (cap is int) {
            _facilityCapacity = cap;
          } else {
            final int? parsed = int.tryParse('$cap');
            if (parsed != null) {
              _facilityCapacity = parsed;
            }
          }
          if (_facilityCapacity <= 0) {
            _facilityCapacity = 1;
          }

          // manager id
          _managerId = (data['managerId'] as String?) ?? '';

          // require approval
          _requireApproval = false;
          final dynamic r = data['requireApproval'];
          if (r is bool) {
            _requireApproval = r;
          } else {
            if (r is String) {
              final String s = r.toLowerCase().trim();
              if (s == 'true') {
                _requireApproval = true;
              } else {
                _requireApproval = false;
              }
            }
          }
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _loadingFacility = false;
      });
    } // hide loading
  }

  // ------------------------------ manager: read once ------------------------------
  Future<void> _loadManagerOnce() async {
    setState(() {
      _loadingManager = true;
    }); // show loading

    try {
      if (_managerId.isNotEmpty) {
        final snap = await FirebaseFirestore.instance
            .collection('UserInformation')
            .doc(_managerId)
            .get();

        if (snap.exists) {
          final Map<String, dynamic>? m = snap.data();
          if (m != null) {
            _manager = m;
          } // store manager map
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _loadingManager = false;
      });
    } // hide loading
  }

  // ------------------------------ per-slot stats: capacity + booked for each selected start ------------------------------
  Future<void> _prefetchSlotStats() async {
    setState(() {
      _loadingSlotStats = true;
    }); // show loading

    try {
      int i = 0;
      while (i < widget.startTimes.length) {
        final String start = widget.startTimes[i]; // "HH:mm"
        final String key = start.replaceAll(':', '').padLeft(4, '0'); // "HHmm"

        int cap = _facilityCapacity; // default to facility cap
        int res = 0; // default 0 booked

        try {
          final slotRef = FirebaseFirestore.instance
              .collection('Facilities').doc(widget.facilityId)
              .collection('Days').doc(widget.dateYMD)
              .collection('Slots').doc(key);

          final slotSnap = await slotRef.get(); // read slot doc
          if (slotSnap.exists) {
            final Map<String, dynamic>? s = slotSnap.data();
            if (s != null) {
              // capacity override
              if (s.containsKey('capacity')) {
                final dynamic c = s['capacity'];
                if (c is int) {
                  cap = c;
                } else {
                  final int? p = int.tryParse('$c');
                  if (p != null) {
                    cap = p;
                  }
                }
              }
              // booked/reserve count
              if (s.containsKey('reserve')) {
                final dynamic r = s['reserve'];
                if (r is int) {
                  res = r;
                } else {
                  final int? p = int.tryParse('$r');
                  if (p != null) {
                    res = p;
                  }
                }
              } else {
                if (s.containsKey('booked')) {
                  final dynamic b = s['booked'];
                  if (b is int) {
                    res = b;
                  } else {
                    final int? p = int.tryParse('$b');
                    if (p != null) {
                      res = p;
                    }
                  }
                }
              }
            }
          }
        } catch (_) {}

        if (cap <= 0) {
          cap = 1;
        } // guard invalid cap
        if (res < 0) {
          res = 0;
        } // guard invalid count

        _capacityByStart[start] = cap; // cache cap for start
        _reserveByStart[start] = res; // cache booked for start

        i = i + 1; // move next
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _loadingSlotStats = false;
      });
    } // hide loading
  }

  // ------------------------------ auto-assign: find first seat not taken for a start ------------------------------
  Future<int?> _autoAssignSeatIndex(String start, int capacity) async {
    final String key = start.replaceAll(':', '').padLeft(
        4, '0'); // normalize to "HHmm"

    final qs = await FirebaseFirestore.instance
        .collection('Facilities').doc(widget.facilityId)
        .collection('Days').doc(widget.dateYMD)
        .collection('Slots').doc(key)
        .collection('Seats')
        .get(); // read all seat docs

    final Set<int> hardTaken = <int>{}; // seats with taken==true

    for (final d in qs.docs) {
      final int? idx = int.tryParse(d.id);
      if (idx != null) {
        bool isTaken = false;
        final Map<String, dynamic> data = d.data();
        if (data.containsKey('taken')) {
          final dynamic t = data['taken'];
          if (t is bool) {
            if (t == true) {
              isTaken = true;
            }
          }
        }
        if (isTaken) {
          hardTaken.add(idx);
        } // mark hard taken
      }
    }

    int i = 1;
    while (i <= capacity) {
      if (!hardTaken.contains(i)) {
        return i;
      } // pick first free
      i = i + 1;
    }

    return null; // no free seats
  }

  // ------------------------------ auto-assign: prefetch preview for each selected start ------------------------------
  Future<void> _prefetchAutoSeats() async {
    setState(() {
      _loadingAutoSeats = true;
    }); // show loading
    try {
      int i = 0;
      while (i < widget.startTimes.length) {
        final String s = widget.startTimes[i];

        int cap = _facilityCapacity; // fallback
        if (_capacityByStart.containsKey(s)) {
          cap = _capacityByStart[s]!;
        }

        final int? idx = await _autoAssignSeatIndex(
            s, cap); // preview seat index
        _autoSeatByStart[s] = idx; // can be null (full)

        i = i + 1;
      }
    } catch (_) {}
    if (mounted) {
      setState(() {
        _loadingAutoSeats = false;
      });
    } // hide loading
  }

  // ------------------------------ formatting: "HH:mm" -> "hh:mm am/pm" ------------------------------
  String _toAmPm(String hhmm) {
    final List<String> p = hhmm.split(':');
    int h = 0;
    int m = 0;

    if (p.isNotEmpty) {
      final int? hh = int.tryParse(p[0]);
      if (hh != null) {
        h = hh;
      }
    }
    if (p.length > 1) {
      final int? mm = int.tryParse(p[1]);
      if (mm != null) {
        m = mm;
      }
    }

    String suffix = 'am';
    if (h >= 12) {
      suffix = 'pm';
    }

    final String hh2 = h.toString().padLeft(2, '0');
    final String mm2 = m.toString().padLeft(2, '0');
    return '$hh2:$mm2 $suffix';
  }

  // ------------------------------ pretty date: "YYYY-MM-DD" -> "d Month yyyy" ------------------------------
  String _niceDate(String ymd) {
    try {
      final List<String> parts = ymd.split('-');
      final int y = int.parse(parts[0]);
      final int m = int.parse(parts[1]);
      final int d = int.parse(parts[2]);

      const List<String> months = <String>[
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'
      ];

      return '$d ${months[m - 1]} $y';
    } catch (_) {
      return ymd;
    }
  }

  // ------------------------------ time utils: normalize "HH:mm" from variants ------------------------------
  String _normalizeHHmm(String s) {
    String txt = s.trim();
    if (txt.contains(':')) { // already HH:mm-ish
      final List<String> p = txt.split(':');
      String hh = '00';
      String mm = '00';
      if (p.isNotEmpty) {
        hh = p[0].padLeft(2, '0');
      }
      if (p.length > 1) {
        mm = p[1].padLeft(2, '0');
      }
      return '$hh:$mm';
    } else {
      if (txt.contains('.')) { // allow HH.mm
        txt = txt.replaceAll('.', ':');
        return _normalizeHHmm(txt);
      } else {
        final String only = txt.replaceAll(' ', ''); // allow HHmm
        if (only.length >= 4) {
          final String hh = only.substring(0, 2);
          final String mm = only.substring(2, 4);
          return '${hh.padLeft(2, '0')}:${mm.padLeft(2, '0')}';
        } else {
          return '00:00'; // safe fallback
        }
      }
    }
  }

  // ------------------------------ time utils: "HH:mm" -> minutes since midnight ------------------------------
  int _hmToMinutes(String s) {
    final String norm = _normalizeHHmm(s);
    final List<String> p = norm.split(':');
    int h = 0;
    int m = 0;

    if (p.isNotEmpty) {
      final int? hh = int.tryParse(p[0]);
      if (hh != null) {
        h = hh;
      }
    }
    if (p.length > 1) {
      final int? mm = int.tryParse(p[1]);
      if (mm != null) {
        m = mm;
      }
    }

    if (h < 0) {
      h = 0;
    } else {
      if (h > 23) {
        h = 23;
      }
    }
    if (m < 0) {
      m = 0;
    } else {
      if (m > 59) {
        m = 59;
      }
    }

    return h * 60 + m;
  }

  // ------------------------------ time utils: minutes -> "HH:mm" ------------------------------
  String _minutesToHHmm(int mins) {
    int h = mins ~/ 60;
    int m = mins % 60;
    if (h < 0) {
      h = 0;
    } else {
      if (h > 23) {
        h = 23;
      }
    }
    if (m < 0) {
      m = 0;
    } else {
      if (m > 59) {
        m = 59;
      }
    }
    final String hh = h.toString().padLeft(2, '0');
    final String mm = m.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  // ------------------------------ time utils: get end for start (facility template or +60m) ------------------------------
  String _endForStartForConflict(String startHHmm) {
    String end = _lookupEndFromFacilityByStart(startHHmm); // try template
    if (end.isEmpty) {
      final int sM = _hmToMinutes(_normalizeHHmm(startHHmm)); // fallback +60
      final int eM = sM + 60;
      end = _minutesToHHmm(eM);
    } else {
      end = _normalizeHHmm(end);
    }
    return end;
  }

  // ------------------------------ time utils: overlap check [aStart,aEnd) vs [bStart,bEnd) ------------------------------
  bool _rangesOverlap(int aStart, int aEnd, int bStart, int bEnd) {
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

  // ------------------------------ text utils: "12:00 pm - 2:00 pm" ------------------------------
  String _rangeText(String s, String e) {
    return '${_toAmPm(s)} - ${_toAmPm(e)}';
  }

  // ------------------------------ facility helper: find end by start in customTimeSlots ------------------------------
  String _lookupEndFromFacilityByStart(String start) {
    String end = '';
    if (_facility.containsKey('customTimeSlots')) {
      final dynamic raw = _facility['customTimeSlots'];
      if (raw is List) {
        int i = 0;
        while (i < raw.length) {
          final dynamic item = raw[i];
          if (item is Map<String, dynamic>) {
            if (item.containsKey('start')) {
              final dynamic st = item['start'];
              if (st is String) {
                final String stNorm = _normalizeHHmm(st);
                final String want = _normalizeHHmm(start);
                if (stNorm == want) {
                  if (item.containsKey('end')) {
                    final dynamic ed = item['end'];
                    if (ed is String) {
                      end = _normalizeHHmm(ed);
                    }
                  }
                }
              }
            }
          }
          i = i + 1;
        }
      }
    }
    return end;
  }

  // ------------------------------ bookings: get user's bookings on same day (accepted + pending) ------------------------------
  Future<List<Map<String, dynamic>>> _getMyBookingsSameDay() async {
    final out = <Map<String, dynamic>>[];
    try {
      if (_userId.isEmpty) return out;

      final qs = await FirebaseFirestore.instance
          .collection('Bookings')
          .where('userId', isEqualTo: _userId)
          .where('bookingDate', isEqualTo: widget.dateYMD)
      // OPTIONAL (requires backfill + index):
      // .where('deleted', isEqualTo: false)
          .get();

      for (final d in qs.docs) {
        final m = d.data();
        if (m == null) continue;

        // Skip soft-deleted
        if (m['deleted'] == true) continue;

        final ap = (m['approval'] ?? '').toString().toLowerCase().trim();
        final keep = (ap == 'accepted' || ap == 'pending');
        if (keep) out.add(m);
      }
    } catch (_) {}
    return out;
  }


  // ------------------------------ confirm: conflict reason vs existing bookings for a new start ------------------------------
  String _conflictReasonForStart(List<Map<String, dynamic>> existing,
      String newStart) {
    final String newS = _normalizeHHmm(newStart); // normalize start
    final int newM = _hmToMinutes(newS); // to minutes

    int i = 0;
    while (i < existing.length) {
      final Map<String, dynamic> b = existing[i];

      String s = '';
      if (b.containsKey('start')) {
        final dynamic st = b['start'];
        if (st is String) {
          s = _normalizeHHmm(st);
        }
      }
      if (s.isEmpty) {
        i = i + 1;
        continue;
      } // skip invalid

      String e = '';
      if (b.containsKey('end')) {
        final dynamic ed = b['end'];
        if (ed is String) {
          e = _normalizeHHmm(ed);
        }
      }
      if (e.isEmpty) {
        final String fromFac = _lookupEndFromFacilityByStart(s);
        if (fromFac.isNotEmpty) {
          e = fromFac;
        }
      }

      final int sM = _hmToMinutes(s);
      final int eM = e.isNotEmpty ? _hmToMinutes(e) : sM + 60; // 60m default

      if (newM == sM) { // same start
        return 'You already have a booking ${_toAmPm(s)} - ${_toAmPm(e)}.';
      }

      if (newM > sM) { // inside interval
        if (newM < eM) {
          return 'You already have a booking ${_toAmPm(s)} - ${_toAmPm(e)}.';
        }
      }

      i = i + 1;
    }
    return ''; // ok
  }

  // ------------------------------ confirm: tap handler to create bookings ------------------------------
  Future<void> _onConfirmPressed() async {
    if (_saving) {
      return;
    } // ignore double taps

    if (_loadingFacility) { // wait facility
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Please wait, loading facility.')));
      return;
    }

    if (widget.autoAssign) { // need stats if auto + approval
      if (_requireApproval) {
        if (_loadingSlotStats) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Please wait, checking availability.')));
          return;
        }
      }
    }

    if (_requireApproval) { // reason required
      final String reason = _reasonCtrl.text.trim();
      if (reason.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Please enter your reason')));
        return;
      }
    }

    // strict conflict checks
    try {
      final List<Map<String,
          dynamic>> existing = await _getMyBookingsSameDay(); // user's bookings for the day

      int i = 0;
      while (i < widget.startTimes.length) {
        final String newStart = _normalizeHHmm(
            widget.startTimes[i]); // normalize new start
        final String newEnd = _endForStartForConflict(
            newStart); // compute new end
        final int newS = _hmToMinutes(newStart);
        final int newE = _hmToMinutes(newEnd);

        int j = 0;
        while (j < existing.length) {
          final Map<String, dynamic> b = existing[j];

          String s = '';
          if (b.containsKey('start')) {
            final dynamic st = b['start'];
            if (st is String) {
              s = _normalizeHHmm(st);
            }
          }
          if (s.isEmpty) {
            j = j + 1;
            continue;
          }

          String e = '';
          if (b.containsKey('end')) {
            final dynamic ed = b['end'];
            if (ed is String) {
              e = _normalizeHHmm(ed);
            }
          }
          if (e.isEmpty) {
            final String fromFac = _lookupEndFromFacilityByStart(s);
            if (fromFac.isNotEmpty) {
              e = _normalizeHHmm(fromFac);
            } else {
              final int sM = _hmToMinutes(s);
              e = _minutesToHHmm(sM + 60);
            }
          }

          final int oldS = _hmToMinutes(s);
          final int oldE = _hmToMinutes(e);

          if (_rangesOverlap(newS, newE, oldS, oldE) == true) { // overlap found
            final String msg = 'Overlap with your existing booking ${_rangeText(
                s, e)}. '
                'New request ${_rangeText(newStart, newEnd)} is not allowed.';
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(msg, style: TextStyle(fontSize: 13.sp))));
            return;
          }

          j = j + 1;
        }

        i = i + 1;
      }

      // cross-check among new selections themselves
      int a = 0;
      while (a < widget.startTimes.length) {
        final String aStart = _normalizeHHmm(widget.startTimes[a]);
        final String aEnd = _endForStartForConflict(aStart);
        final int aS = _hmToMinutes(aStart);
        final int aE = _hmToMinutes(aEnd);

        int bIdx = a + 1;
        while (bIdx < widget.startTimes.length) {
          final String bStart = _normalizeHHmm(widget.startTimes[bIdx]);
          final String bEnd = _endForStartForConflict(bStart);
          final int bS = _hmToMinutes(bStart);
          final int bE = _hmToMinutes(bEnd);

          if (_rangesOverlap(aS, aE, bS, bE) == true) { // overlap among picks
            final String msg = 'Your selected times overlap: ${_rangeText(
                aStart, aEnd)} vs ${_rangeText(bStart, bEnd)}.';
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(msg, style: TextStyle(fontSize: 13.sp))));
            return;
          }

          bIdx = bIdx + 1;
        }

        a = a + 1;
      }
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
          'Could not verify your other bookings. Try again.',
          style: TextStyle(fontSize: 13.sp))));
      return;
    }

    // build seat picks to save
    final Map<String, int> seatByStart = <String, int>{};

    if (widget.autoAssign) {
      if (_requireApproval) {
        // pre-pick a TEMP seat now using slot capacity
        int i = 0;
        while (i < widget.startTimes.length) {
          final String s = widget.startTimes[i];

          int cap = _facilityCapacity;
          if (_capacityByStart.containsKey(s)) {
            cap = _capacityByStart[s]!;
          }

          final int? idx = await _autoAssignSeatIndex(
              s, cap); // preview seat index
          if (idx == null) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('Time ${_toAmPm(s)} is full. Choose another.')));
            return;
          } else {
            seatByStart[s] = idx; // keep temp seat
          }
          i = i + 1;
        }
      } else {
        // no approval: transaction in service will assign during write
      }
    } else {
      // manual picks must cover all starts
      if (widget.seatPicks == null) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Please pick a seat for every time.')));
        return;
      }
      if (widget.seatPicks!.length != widget.startTimes.length) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Please pick a seat for every time.')));
        return;
      }

      int i = 0;
      while (i < widget.startTimes.length) {
        final String s = widget.startTimes[i];
        final int? idx = widget.seatPicks![s];
        if (idx == null) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Please pick a seat for every time.')));
          return;
        } else {
          seatByStart[s] = idx; // keep manual seat
        }
        i = i + 1;
      }
    }

    // start saving
    setState(() {
      _saving = true;
    }); // lock button

    try {
      // optional manager name from facility
      final String managerName = (_facility['managerName'] as String?) ?? '';

      int i = 0;
      while (i < widget.startTimes.length) {
        final String start = widget.startTimes[i];
        final String slotKey = start.replaceAll(':', '').padLeft(
            4, '0'); // "HHmm"

        // try end from template
        String end = '';
        final dynamic raw = _facility['customTimeSlots'];
        if (raw is List) {
          for (final item in raw) {
            if (item is Map<String, dynamic>) {
              final st = item['start'];
              if (st is String && st == start) {
                final ed = item['end'];
                if (ed is String) end = ed;
              }
            }
          }
        }


        // right after you validated reason is required & non-empty
        final String approvalReason =
        _requireApproval ? _reasonCtrl.text.trim() : '';

        // base fields (unchanged)
        final Map<String, dynamic> bookingBase = <String, dynamic>{
          'userId': _userId,
          'userName': _userName,
          'userEmail': _userEmail,
          'userContact': _userContact,
          'facilityId': widget.facilityId,
          'facilityName': _facilityName,
          'managerId': _managerId,
          'managerName': managerName,
          'bookingDate': widget.dateYMD,
          'slotKey': slotKey,
          'start': start,
          'rated': false,
          'autoAssigned': widget.autoAssign,
          'createdAt': FieldValue.serverTimestamp(),
          'deleted':false,
          if (end.isNotEmpty) 'end': end,
          if (_requireApproval && approvalReason.isNotEmpty) 'approvalReason': approvalReason,
        };

        late String bookingId;

        if (_requireApproval) {
          // pending path
          bookingBase['approval'] = 'pending';
          bookingBase['status']   = 'upcoming';

          // keep your current seatIndex behavior for pending
          if (widget.autoAssign) {
            final int? tempSeat = seatByStart[start];
            if (tempSeat != null) bookingBase['seatIndex'] = tempSeat;
          } else {
            final int? manualSeat = seatByStart[start];
            if (manualSeat != null) bookingBase['seatIndex'] = manualSeat;
          }

          bookingId = await BookingService.createBookingPending(bookingBase: bookingBase);

          // inbox mail (PENDING)
          try {
            await NotificationService.sendBookingCreatedMails(
              bookingId: bookingId,
              userId: _userId,
              bookedBy: _userId,
              facilityId: widget.facilityId,
              managerId: _managerId,
              approval: 'pending',
            );
          } catch (_) {}

        } else {
          // accepted now
          bookingBase['approval'] = 'accepted';
          bookingBase['status']   = 'upcoming';

          if (widget.autoAssign) {
            bookingId = await BookingService.createBookingAutoAssignTx(
              facilityId: widget.facilityId,
              dateYMD: widget.dateYMD,
              slotKey: slotKey,
              bookingBase: bookingBase,
            );
          } else {
            final int seatIdx = seatByStart[start]!;
            bookingBase['seatIndex'] = seatIdx;

            bookingId = await BookingService.createBookingPickSeatTx(
              facilityId: widget.facilityId,
              dateYMD: widget.dateYMD,
              slotKey: slotKey,
              seatIndex: seatIdx,
              bookingBase: bookingBase,
            );
          }

          // inbox mail (ACCEPTED)
          try {
            await NotificationService.sendBookingCreatedMails(
              bookingId: bookingId,
              userId: _userId,
              bookedBy: _userId,
              facilityId: widget.facilityId,
              managerId: _managerId,
              approval: 'accepted',
            );
          } catch (_) {}
        }

        i++;
      }

      if (mounted) {
        final msg = _requireApproval
            ? 'Request sent. An admin will review it.'
            : 'Booking created';
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg)));
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => AndroidViewBooking()),
              (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(
            SnackBar(content: Text('Failed to create booking: $e')));
      }
    }



    if (mounted) { setState(() { _saving = false; }); }                             // unlock button
  }

  // ------------------------------ bottom bar: switch tab ------------------------------
  void _onTabSelected(int i) {
    if (i == 2) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidListOfFacilities()));    // go Facilities
    } else {
      if (i == 0) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidAgenda()));            // go Agenda
      } else {
        if (i == 1) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidViewBooking()));     // go My Bookings
        } else {
          if (i == 3) {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidNotifications())); // go Notifications
          } else {
            if (i == 4) {
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidAccount()));     // go Account
            }
          }
        }
      }
    }
  }

  // ------------------------------ UI helper: label:value line ------------------------------
  Widget _kvLine({required String label, required String value, Color? color}) {
    Color labelColor = color ?? Colors.black;
    Color valueColor = color ?? Colors.black87;

    return Padding(
      padding: EdgeInsets.only(bottom: 6.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('$label: ', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: labelColor)),
          Expanded(child: Text(value, style: TextStyle(fontSize: 13.sp, color: valueColor), softWrap: true)),
        ],
      ),
    );
  }

  // ------------------------------ UI helper: grey box ------------------------------
  Widget _box(String text) {
    return Container(
      width: 1.0.sw,
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Text(text, style: TextStyle(fontSize: 14.sp)),
    );
  }

  // ------------------------------ build ------------------------------
  @override
  Widget build(BuildContext context) {
    final double barHeight = 0.07.sh;                                    // bottom bar height (responsive)
    final double sw = 1.0.sw;                                            // screen width

    // facility image child
    Widget imageChild;
    if (_facilityImagePath.isEmpty) {
      imageChild = Center(child: Icon(Icons.image_not_supported, size: 40.sp, color: Colors.white)); // show placeholder
    } else {
      imageChild = Image.asset(_facilityImagePath, fit: BoxFit.cover);                                 // show asset image
    }

    // responsive image height
    double imgH = sw * 0.75;
    if (imgH < 240.h) { imgH = 240.h; } else { if (imgH > 420.h) { imgH = 420.h; } }

    // build time rows (seat preview + reserve stats)
    final List<Widget> timeRows = <Widget>[];
    int t = 0;
    while (t < widget.startTimes.length) {
      final String start = widget.startTimes[t];

      // seat preview text
      String seatTxt = '-';
      if (widget.autoAssign) {
        if (_loadingAutoSeats) {
          seatTxt = 'Checking...';
        } else {
          if (_autoSeatByStart.containsKey(start)) {
            final int? idx = _autoSeatByStart[start];
            if (idx == null) { seatTxt = 'Full'; } else { seatTxt = 'Slot $idx'; }
          } else {
            seatTxt = 'Checking...';
          }
        }
      } else {
        if (widget.seatPicks != null) {
          final int? idx = widget.seatPicks![start];
          if (idx == null) { seatTxt = '-'; } else { seatTxt = 'Slot $idx'; }
        } else {
          seatTxt = '-';
        }
      }
      timeRows.add(_kvLine(label: _toAmPm(start), value: seatTxt));      // add seat line


      t = t + 1;
    }

    // manager card prep
    String managerName = '';
    String managerEmail = '';
    String managerContact = '';
    String managerAssetPath = '';

    if (_manager.isNotEmpty) {
      managerName = (_manager['username'] as String?) ?? '';
      if (managerName.isEmpty) { managerName = (_manager['name'] as String?) ?? ''; }
      managerEmail = (_manager['email'] as String?) ?? '';
      managerContact = (_manager['contact'] as String?) ?? '';

      final String imgName = (_manager['profileImageName'] as String?)?.trim() ?? '';
      managerAssetPath = imgName.isNotEmpty ? 'asset/image/$imgName' : '';
    }

    // manager image
    Widget managerImage;
    if (managerAssetPath.isEmpty) {
      managerImage = Container(
        color: Colors.grey.shade400,
        alignment: Alignment.center,
        child: Icon(Icons.person_off, color: Colors.white, size: 26.sp),
      );
    } else {
      managerImage = Image.asset(managerAssetPath, fit: BoxFit.cover);
    }

    // approval UI group
    final List<Widget> approvalWidgets = <Widget>[];
    if (_requireApproval) {
      approvalWidgets.add(Text('Reason (required)', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700))); // label
      approvalWidgets.add(SizedBox(height: 6.h));                                                                     // space
      approvalWidgets.add(
        Stack(
          children: <Widget>[
            TextField(
              controller: _reasonCtrl,                                                                              // reason input
              maxLength: 99,
              maxLines: 3,
              decoration: InputDecoration(
                counterText: '',
                isDense: true,
                hintText: 'Why do you need this booking?',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r)),
                fillColor: Colors.grey.shade200,
                filled: true,
              ),
            ),
            Positioned(
              right: 10.w,
              bottom: 8.h,
              child: Text('$_reasonLen/99', style: TextStyle(fontSize: 12.sp, color: Colors.black54)),               // live counter
            ),
          ],
        ),
      );
      approvalWidgets.add(SizedBox(height: 18.h));                                                                   // space under
    }


    // body content
    Widget bodyChild;
    if (_loadingFacility) {
      bodyChild = Center(child: SizedBox(width: 28.w, height: 28.w, child: CircularProgressIndicator()));            // loading
    } else {
      bodyChild = SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h).copyWith(bottom: 96.h),                      // scroll with bottom gap
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            // facility image
            Container(
              width: 1.0.sw,
              height: imgH,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16.r),
                color: Colors.grey.shade300,
              ),
              child: imageChild,
            ),

            SizedBox(height: 16.h),

            // narrow content
            SizedBox(
              width: 0.90.sw,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // name
                  Text(
                    _facilityName,
                    style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.w700),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),

                  SizedBox(height: 12.h),

                  // date
                  Text('Date', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
                  SizedBox(height: 6.h),
                  _box(_niceDate(widget.dateYMD)),

                  SizedBox(height: 18.h),

                  // start times & slot
                  Text('Start time(s) & slot', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
                  SizedBox(height: 6.h),
                  Container(
                    width: 1.0.sw,
                    padding: EdgeInsets.all(12.w),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: timeRows,
                    ),
                  ),

                  SizedBox(height: 18.h),

                  // location
                  Text('Location', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
                  SizedBox(height: 6.h),
                  _box(_location),

                  SizedBox(height: 18.h),

                  // description
                  Text('Description', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
                  SizedBox(height: 6.h),
                  _box(_description),

                  SizedBox(height: 18.h),

                  // user info
                  Text('Your info', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
                  SizedBox(height: 6.h),
                  Container(
                    width: 1.0.sw,
                    padding: EdgeInsets.all(12.w),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _kvLine(label: 'Username', value: _userName),
                        SizedBox(height: 6.h),
                        _kvLine(label: 'Email', value: _userEmail),
                        SizedBox(height: 6.h),
                        _kvLine(label: 'Contact', value: _userContact),
                      ],
                    ),
                  ),

                  SizedBox(height: 18.h),

                  // approval reason block if required
                  ...approvalWidgets,

                  // manager header
                  Text('Manager', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
                  SizedBox(height: 6.h),

                  // manager card
                  Builder(
                    builder: (context) {
                      if (_loadingManager) {
                        return SizedBox(width: 28.w, height: 28.w, child: CircularProgressIndicator()); // manager loading
                      }

                      return Container(
                        width: 1.0.sw,
                        constraints: BoxConstraints(minHeight: 135.h),
                        padding: EdgeInsets.all(10.w),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE2CCFF),
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8.r),
                              child: SizedBox(width: 110.w, height: 110.w, child: managerImage), // image or placeholder
                            ),
                            SizedBox(width: 15.w),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  _kvLine(label: 'Name',   value: managerName),
                                  SizedBox(height: 6.h),
                                  _kvLine(label: 'Email',  value: managerEmail),
                                  SizedBox(height: 6.h),
                                  _kvLine(label: 'Contact',value: managerContact),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // button text without ternary
    String btnText = 'Confirm';
    if (_saving) { btnText = 'Saving...'; }

    // scaffold
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(60.h),
        child: AppBar(
          backgroundColor: const Color(0xFF9747FF),
          elevation: 0,
          centerTitle: true,
          automaticallyImplyLeading: false,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: Colors.white, size: 22.sp), // back
            onPressed: () { Navigator.pop(context); },
            tooltip: 'Back',
          ),
          title: Text('Confirmation', style: TextStyle(color: Colors.white, fontSize: 20.sp, fontWeight: FontWeight.w600)), // title
          actions: <Widget>[
            IconButton(
              icon: Icon(Icons.close, color: Colors.white, size: 22.sp), // close
              onPressed: () {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => AndroidListOfFacilities()),
                      (route) => false,
                );
              },
              tooltip: 'Close',
            ),
          ],
        ),
      ),

      body: bodyChild,                                                    // main body

      bottomNavigationBar: BottomMenuBar(
        height: barHeight,                                               // responsive height
        currentIndex: _currentIndex,                                     // active tab
        onTabSelected: _onTabSelected,                                   // switch tab
      ),

      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat, // center bottom
      floatingActionButton: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.w),                 // side padding
        child: SizedBox(
          width: 1.0.sw,
          height: 48.h,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF9747FF),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
            ),
            onPressed: () {
              if (_saving) {
                // ignore while saving
              } else {
                _onConfirmPressed();                                      // create bookings
              }
            },
            child: Text(btnText, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700, color: Colors.white)), // button text
          ),
        ),
      ),
    );
  }
}
