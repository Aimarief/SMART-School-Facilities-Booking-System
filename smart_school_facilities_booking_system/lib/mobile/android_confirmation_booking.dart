import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';  // .w .h .sp .sw .sh

import 'android_bottom_menu.dart';
import 'android_agenda.dart';
import 'android_view_booking.dart';
import 'android_notifications.dart';
import 'android_account.dart';
import 'android_list_of_facilities.dart';

import 'package:smart_school_facilities_booking_system/booking_service.dart';
import 'package:smart_school_facilities_booking_system/notification_service.dart';


class ConfirmBooking extends StatefulWidget {
  final String facilityId;
  final String facilityName;

  final String dateYMD;
  final List<String> startTimes;


  final bool autoAssign;
  final Map<String, int>? seatPicks;

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

class _ConfirmBookingState extends State<ConfirmBooking> {
//---------------------------------------
// current page
//---------------------------------------
  int _currentIndex = 2;

  String _userId = '';
  String _userName = '';
  String _userEmail = '';
  String _userContact = '';

  bool _loadingFacility = true;
  Map<String, dynamic> _facility = {};
  String _facilityName = '';
  String _facilityImagePath = '';
  String _location = '';
  String _description = '';
  String _managerId = '';

  // manager info
  bool _loadingManager = true;
  Map<String, dynamic> _manager = {};

  // approval reason
  final TextEditingController _reasonCtrl = TextEditingController();
  int _reasonLen = 0;

  // saving flag
  bool _saving = false;

//---------------------------------------
// do init state first
//---------------------------------------

  @override
  void initState() {
    super.initState();
    _loadUser();
//---------------------------------------
// add listener so that when the reason text change it set state
//---------------------------------------

    _reasonCtrl.addListener(() {
      final int len = _reasonCtrl.text.characters.length;
      setState(() => _reasonLen = len.clamp(0, 99));
    });

    _loadFacilityInformation();
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

//---------------------------------------
// read current user
//---------------------------------------
  Future<void> _loadUser() async {
    try {
      final User? u = FirebaseAuth.instance.currentUser;

      if (u != null) {
        _userId = u.uid;
      }

      if (_userId.isNotEmpty) {
        final ds = await FirebaseFirestore.instance.collection(
            'UserInformation').doc(_userId).get();
        if (ds.exists) {
          final m = ds.data();
          if (m != null) {
            final un = (m['username'] as String?)?.trim();
            if (un != null && un.isNotEmpty) _userName = un;
            final em = (m['email'] as String?)?.trim();
            if (em != null && em.isNotEmpty) _userEmail = em;
            final ct = (m['contact'] as String?)?.trim();
            if (ct != null && ct.isNotEmpty) _userContact = ct;
          }
        }
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

//---------------------------------------
// load the facility info and manager info
//---------------------------------------

  Future<void> _loadFacilityInformation() async {
    await _loadFacilityOnce();
    await _loadManagerOnce();
  }

//---------------------------------------
// load facility info
//---------------------------------------

  Future<void> _loadFacilityOnce() async {
    setState(() => _loadingFacility = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('Facilities')
          .doc(widget.facilityId)
          .get();
      if (snap.exists) {
        final data = snap.data();
        if (data != null) {
          _facility = data;
          _facilityName = (data['name'] as String?) ?? widget.facilityName;
          final imageName = (data['imageName'] as String?)?.trim() ?? '';
          _facilityImagePath =
          imageName.isNotEmpty ? 'asset/image/$imageName' : '';
          _location = (data['location'] as String?) ?? '';
          _description = (data['details'] as String?) ?? '';
          _managerId = (data['managerId'] as String?) ?? '';
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingFacility = false);
  }

//---------------------------------------
// load manager information
//---------------------------------------

  Future<void> _loadManagerOnce() async {
    setState(() => _loadingManager = true);
    try {
      if (_managerId.isNotEmpty) {
        final snap = await FirebaseFirestore.instance.collection(
            'UserInformation').doc(_managerId).get();
        if (snap.exists) _manager = snap.data() ?? {};
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingManager = false);
  }

//---------------------------------------
// change year month day to correct day month year format
//---------------------------------------

  String _niceDate(String ymd) {
    try {
      final p = ymd.split('-');
      final y = int.parse(p[0]);
      final m = int.parse(p[1]);
      final d = int.parse(p[2]);
      const months = [
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'
      ];
      return '$d ${months[m - 1]} $y';
    } catch (_) {
      return ymd;
    }
  }

//---------------------------------------
// get am and pm
//---------------------------------------

  String _toAmPm(String hhmm) {
    final p = hhmm.split(':');
    int h = int.tryParse(p[0]) ?? 0;
    final m = int.tryParse(p.length > 1 ? p[1] : '0') ?? 0;
    final suffix = (h >= 12) ? 'pm' : 'am';
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(
        2, '0')} $suffix';
  }

//---------------------------------------
// change to hh:mm format
//---------------------------------------

  String _normalizeHHmm(String s) {
    var t = s.trim();
    if (t.contains(':')) {
      final p = t.split(':');
      final hh = (p.isNotEmpty ? p[0] : '00').padLeft(2, '0');
      final mm = (p.length > 1 ? p[1] : '00').padLeft(2, '0');
      return '$hh:$mm';
    } else if (t.contains('.')) {
      return _normalizeHHmm(t.replaceAll('.', ':'));
    } else {
      final only = t.replaceAll(' ', '');
      if (only.length >= 4) {
        return '${only.substring(0, 2).padLeft(2, '0')}:${only
            .substring(2, 4)
            .padLeft(2, '0')}';
      }
      return '00:00';
    }
  }

  //---------------------------------------
// change format to minute
//---------------------------------------

  int _hmToMinutes(String s) {
    final p = _normalizeHHmm(s).split(':');
    int h = int.tryParse(p[0]) ?? 0;
    int m = int.tryParse(p.length > 1 ? p[1] : '0') ?? 0;
    h = h.clamp(0, 23);
    m = m.clamp(0, 59);
    return h * 60 + m;
  }

//---------------------------------------
// change hhmm to hhmm format
//---------------------------------------

  String _minutesToHHmm(int mins) {
    int h = mins ~/ 60;
    int m = mins % 60;
    h = h.clamp(0, 23);
    m = m.clamp(0, 59);
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

//---------------------------------------
// change time format to slotkey format
//---------------------------------------

  String _slotKey4FromHHmm(String s) {
    var t = s.replaceAll(':', '');
    if (t.length < 4) t = t.padLeft(4, '0');
    return t;
  }

//---------------------------------------
// get the end time using start
//---------------------------------------
  String _lookupEndFromFacilityByStart(String start) {
    final want = _normalizeHHmm(start);
    final raw = _facility['customTimeSlots'];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map<String, dynamic>) {
          final st = item['start'];
          final ed = item['end'];
          if (st is String && ed is String) {
            if (_normalizeHHmm(st) == want) return _normalizeHHmm(ed);
          }
        }
      }
    }
    return '';
  }

  //---------------------------------------
// check for the end time for the facility
//---------------------------------------
  String _endForStartForConflict(String startHHmm) {
    final fromTpl = _lookupEndFromFacilityByStart(startHHmm);
    if (fromTpl.isNotEmpty)
      return fromTpl;
    final sM = _hmToMinutes(_normalizeHHmm(startHHmm));
    return _minutesToHHmm(sM + 60);
  }

  //---------------------------------------
// check if overlap
//---------------------------------------

  bool _rangesOverlap(int aStart, int aEnd, int bStart, int bEnd) {
    return aStart < bEnd && aEnd > bStart;
  }

  //---------------------------------------
// display the range
//---------------------------------------

  String _rangeText(String s, String e) => '${_toAmPm(s)} - ${_toAmPm(e)}';

//---------------------------------------
// get the user booking on the same day with approval is accepted or pending
//---------------------------------------

  Future<List<Map<String, dynamic>>> _getMyBookingsSameDay() async {
    final out = <Map<String, dynamic>>[];
    try {
      if (_userId.isEmpty) return out;
      final qs = await FirebaseFirestore.instance
          .collection('Bookings')
          .where('userId', isEqualTo: _userId)
          .where('bookingDate', isEqualTo: widget.dateYMD)
          .get();
      for (final d in qs.docs) {
        final m = d.data();
        if (m['deleted'] == true) continue;
        final ap = (m['approval'] ?? '').toString().toLowerCase().trim();
        if (ap == 'accepted' || ap == 'pending') out.add(m);
      }
    } catch (_) {}
    return out;
  }

//---------------------------------------
// get the available slot for that facility
//---------------------------------------

  Future<int> _facilityBaseCapacity() async {
    int cap = 1;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('Facilities')
          .doc(widget.facilityId)
          .get();
      final data = doc.data();
      if (data != null) {
        final v1 = data['availableSlots'];

        if (v1 is int && v1 > 0) return v1;
        if (v1 is num && v1.toInt() > 0) return v1.toInt();
      }
    } catch (_) {}
    return cap;
  }

//---------------------------------------
// check taken slot
//---------------------------------------

  Future<Set<int>> _takenSeatsForSlot(String startHHmm) async {
    final slotKey4 = _slotKey4FromHHmm(_normalizeHHmm(startHHmm));
    final out = <int>{};
    try {
      final qs = await FirebaseFirestore.instance
          .collection('Facilities').doc(widget.facilityId)
          .collection('Days').doc(widget.dateYMD)
          .collection('Slots').doc(slotKey4)
          .collection('Seats')
          .get();

      for (final d in qs.docs) {
        int? idx = int.tryParse(d.id);
        if (idx == null || idx <= 0) continue;

        final m = d.data();
        bool taken = false;
        final v = m['taken'];
        if (v is bool) {
          taken = v;
        }
        if (taken) out.add(idx);
      }
    } catch (_) {}
    return out;
  }

//---------------------------------------
// get the booked then get the taken seat, will return the seat that is not taken
//---------------------------------------

  Future<int?> _autoPickSeatForStart(String startHHmm) async {
    final capacity = await _facilityBaseCapacity();
    final taken = await _takenSeatsForSlot(startHHmm);
    for (int i = 1; i <= capacity; i++) {
      if (!taken.contains(i)) return i;
    }
    return null; // fully booked
  }

//---------------------------------------
// when confirm button press
//---------------------------------------

  Future<void> _onConfirmPressed() async {
    if (_saving) return;
    if (_loadingFacility) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please wait, loading facility.')));
      return;
    }

//---------------------------------------
// check reason
//---------------------------------------

    final String reason = _reasonCtrl.text.trim();
    if (reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter your reason')));
      return;
    }

    //---------------------------------------
// if not auto assign and tehre is no slot
//---------------------------------------

    if (!widget.autoAssign) {
      for (final raw in widget.startTimes) {
        final start = _normalizeHHmm(raw);
        final seat = _seatFor(start);
        if (seat == null || seat <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(
                'Please select a slot number for ${_toAmPm(start)}')),
          );
          return;
        }
      }
    }

//---------------------------------------
// check booking conflict
//---------------------------------------

    try {
      final existing = await _getMyBookingsSameDay();
      for (final raw in widget.startTimes) {
//---------------------------------------
// get the hh mm of start time
//---------------------------------------
        final newStart = _normalizeHHmm(raw);
        //---------------------------------------
// then get the end time from database
//---------------------------------------
        final newEnd = _endForStartForConflict(newStart);
//---------------------------------------
// convert to minute for both
//---------------------------------------
        final newS = _hmToMinutes(newStart);
        final newE = _hmToMinutes(newEnd);

        for (final b in existing) {
          var s = '', e = '';

          final st = b['start'];
          if (st is String)
            s = _normalizeHHmm(st);
          final ed = b['end'];
          if (ed is String)
            e = _normalizeHHmm(ed);

          if (s.isEmpty) continue;
          if (e.isEmpty) {
            final fromTpl = _lookupEndFromFacilityByStart(s);
            e = fromTpl.isNotEmpty ? _normalizeHHmm(fromTpl) : _minutesToHHmm(
                _hmToMinutes(s) + 60);
          }
          if (_rangesOverlap(newS, newE, _hmToMinutes(s), _hmToMinutes(e))) {
            final msg = 'Overlap with your booking ${_rangeText(s, e)}. '
                'New request ${_rangeText(newStart, newEnd)} is not allowed.';
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(msg, style: TextStyle(fontSize: 13.sp))));
            return;
          }
        }
      }
      //---------------------------------------
// check between the picked time if overlap each other (normally dun exist just cehck for safe)
//---------------------------------------
      for (int i = 0; i < widget.startTimes.length; i++) {
        final aStart = _normalizeHHmm(widget.startTimes[i]);
        final aEnd = _endForStartForConflict(aStart);
        final aS = _hmToMinutes(aStart);
        final aE = _hmToMinutes(aEnd);
        for (int j = i + 1; j < widget.startTimes.length; j++) {
          final bStart = _normalizeHHmm(widget.startTimes[j]);
          final bEnd = _endForStartForConflict(bStart);
          if (_rangesOverlap(
              aS, aE, _hmToMinutes(bStart), _hmToMinutes(bEnd))) {
            final msg = 'Your selected times overlap: ${_rangeText(
                aStart, aEnd)} vs ${_rangeText(bStart, bEnd)}.';
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(msg, style: TextStyle(fontSize: 13.sp))));
            return;
          }
        }
      }
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Could not verify your other bookings. Try again.',
            style: TextStyle(fontSize: 13)),
      ));
      return;
    }

    setState(() => _saving = true);

    //---------------------------------------
// start saving to fire base
//---------------------------------------
    try {
      final String managerName = (_facility['managerName'] as String?) ?? '';

      for (final raw in widget.startTimes) {
        final String start = _normalizeHHmm(raw);
        final String slotKey = _slotKey4FromHHmm(start);
//---------------------------------------
// get the end time again using the start
//---------------------------------------
        String end = _lookupEndFromFacilityByStart(start);
        if (end.isEmpty)
          end = _endForStartForConflict(start);

//---------------------------------------
// get the seat
//---------------------------------------

        int? seatIndex = _seatFor(start);

 //---------------------------------------
// if no seat means uses auto pick
//---------------------------------------
        if ((seatIndex == null || seatIndex <= 0) && widget.autoAssign) {
          seatIndex = await _autoPickSeatForStart(start);
//---------------------------------------
// if null means fully book
//---------------------------------------
          if (seatIndex == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('No free slots left at ${_toAmPm(
                  start)}. Please choose another time.')),
            );
            setState(() => _saving = false);
            return;
          }
        }

//---------------------------------------
// seat index is null and still not auto pick (normally wont happend)
//---------------------------------------
        if (seatIndex == null || seatIndex <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(
                'Please select a slot number for ${_toAmPm(start)}')),
          );
          setState(() => _saving = false);
          return;
        }
//---------------------------------------
// save into firebase
//---------------------------------------

        final Map<String, dynamic> bookingBase = <String, dynamic>{
          'userId': _userId,
          'userName': _userName,
          'bookedByEmail': _userEmail,
          'userContact': _userContact,
          'facilityId': widget.facilityId,
          'facilityName': _facilityName,
          'managerId': _managerId,
          'managerName': managerName,
          'bookingDate': widget.dateYMD,
          'slotKey': slotKey,
          'start': start,
          'end': end,
          'seatIndex': seatIndex,
          'rated': false,
          'createdAt': FieldValue.serverTimestamp(),
          'deleted': false,
          'approval': 'pending',
          'status': 'upcoming',
          'approvalReason': reason,
        };

        final String bookingId = await BookingService.createBookingPending(
          bookingBase: bookingBase,
        );

//---------------------------------------
// also send meails
//---------------------------------------

        try {
          await NotificationService.sendBookingCreatedMails(
            bookingId: bookingId,
            userId: _userId,
            bookedBy: _userId,
            facilityId: widget.facilityId,
            managerId: _managerId,
            approval: 'pending',
            seatIndex: seatIndex,
            bookingDate: widget.dateYMD,
            start: start,
            end: end,
          );
        } catch (_) {}
      }
//---------------------------------------
// after save then go to view booking page
//---------------------------------------

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Request sent. An admin will review it.')));
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => AndroidViewBooking()),
            (route) => false,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to create booking: $e')));
      }
    }

    if (mounted) setState(() => _saving = false);
  }

  //---------------------------------------
// get the seat that is picked
//---------------------------------------

  int? _seatFor(String hhmm) {
    if (widget.seatPicks == null) return null;
    final norm = _normalizeHHmm(hhmm); // "08:00"
    final key4 = _slotKey4FromHHmm(norm); // "0800"
    final raw = widget.seatPicks!;
    if (raw.containsKey(norm)) return raw[norm];
    if (raw.containsKey(hhmm)) return raw[hhmm];
    if (raw.containsKey(key4)) return raw[key4];
    final alt = '${int.parse(norm.substring(0, 2))}:${norm.substring(
        3, 5)}'; // "8:00"
    if (raw.containsKey(alt)) return raw[alt];
    return null;
  }

//---------------------------------------
// navigation bar
//---------------------------------------

  void _onTabSelected(int i) {
    if (i == 2) {
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => AndroidListOfFacilities()));
    } else if (i == 0) {
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => AndroidAgenda()));
    } else if (i == 1) {
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => AndroidViewBooking()));
    } else if (i == 3) {
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => AndroidNotifications()));
    } else if (i == 4) {
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => AndroidAccount()));
    }
  }

//---------------------------------------
// align key and value for card
//---------------------------------------

  Widget _kvLine({required String label, required String value}) {
    return Padding(
      padding: EdgeInsets.only(bottom: 6.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start, // top-align when wrapped
        children: <Widget>[
          //---------------------------------------
// label
//---------------------------------------
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 13.sp,
              fontWeight: FontWeight.w700,
              color: Colors.black,
            ),
            softWrap: true,        // allow label to wrap (usually short anyway)
            maxLines: null,        // no max lines -> can grow if needed
            textAlign: TextAlign.left,
          ),

          //---------------------------------------
// then the value
//---------------------------------------

          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 13.sp, color: Colors.black87),
              softWrap: true,       // wrap onto next line if too long
              maxLines: null,       // unlimited lines (no ellipsis)
              textAlign: TextAlign.left,
            ),
          ),
        ],
      ),
    );
  }


// ---------------------------------------
// main build
// ---------------------------------------
  @override
  Widget build(BuildContext context) {
    // get bottom bar height using screen height (for Samsung A32 scaling)
    final double barHeight = 0.07.sh;

    // get screen width to compute image height
    final double sw = 1.0.sw;

    // compute image height in a simple way and clamp it to avoid overflow
    double imgH = sw * 0.75; // make image proportional to width
    if (imgH < 240.h) imgH = 240.h; // minimum height to look good
    if (imgH > 420.h) imgH = 420.h; // maximum height to avoid giant image

//---------------------------------------
// get manager info
//---------------------------------------

    String managerName = '';
    String managerEmail = '';
    String managerContact = '';
    String managerAssetPath = '';

    if (_manager.isNotEmpty) {
      final String? n = (_manager['username'] as String?);
      if (n != null) managerName = n;
      final String? e = (_manager['email'] as String?);
      if (e != null) managerEmail = e;
      final String? c = (_manager['contact'] as String?);
      if (c != null) managerContact = c;

      final String imgName = ((_manager['profileImageName'] as String?) ?? '')
          .trim();
      if (imgName.isNotEmpty) {
        managerAssetPath = 'asset/image/$imgName';
      }
    }

//---------------------------------------
// get the time and slot form list
//---------------------------------------

    final List<Widget> timeRows = <Widget>[];
    for (final raw in widget.startTimes) {
      final start = _normalizeHHmm(raw);
      final seat  = _seatFor(start);
      final seatText = (seat == null || seat <= 0) ? 'Auto assign' : 'Slot $seat';
      timeRows.add(_kvLine(label: _toAmPm(start), value: seatText));
    }

//---------------------------------------
// body design
//---------------------------------------
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(60.h),
        child: AppBar(
          backgroundColor: const Color(0xFF9747FF),
          elevation: 0,
          centerTitle: true,
          automaticallyImplyLeading: false,
          // back button
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: Colors.white, size: 22.sp),
            onPressed: () => Navigator.pop(context),
            tooltip: 'Back',
          ),
          // title
          title: Text(
            'Confirmation',
            style: TextStyle(color: Colors.white,
                fontSize: 20.sp,
                fontWeight: FontWeight.w600),
          ),
          // close button -> go list of facilities and clear stack
          actions: <Widget>[
            IconButton(
              icon: Icon(Icons.close, color: Colors.white, size: 22.sp),
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

//---------------------------------------
// body
//---------------------------------------

      body: SafeArea(
        child: _loadingFacility
            ? Center(
          child: SizedBox(
            width: 28.w,
            height: 28.w,
            child: const CircularProgressIndicator(),
          ),
        )
        // show full scrollable content
            : SingleChildScrollView(
          padding: EdgeInsets
              .symmetric(horizontal: 16.w, vertical: 12.h)
              .copyWith(bottom: 96.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              //---------------------------------------
// display image
//---------------------------------------
              Container(
                width: 1.0.sw,
                height: imgH,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16.r),
                  color: Colors.grey.shade300,
                ),
//---------------------------------------
// palce holder if no image
//---------------------------------------
                child: _facilityImagePath.isEmpty
                    ? Center(child: Icon(Icons.image_not_supported, size: 40.sp,
                    color: Colors.white))
                    : Image.asset(_facilityImagePath, fit: BoxFit.cover),
              ),
              SizedBox(height: 16.h),
//---------------------------------------
// facility name
//---------------------------------------
              SizedBox(
                width: 0.90.sw,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      _facilityName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 20.sp, fontWeight: FontWeight.w700),
                    ),

                    SizedBox(height: 12.h),

//---------------------------------------
// display date of booking
//---------------------------------------
                    Text('Date', style: TextStyle(
                        fontSize: 16.sp, fontWeight: FontWeight.w700)),
                    SizedBox(height: 6.h),
                    Container(
                      width: 1.0.sw,
                      padding: EdgeInsets.all(12.w),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                      child: Text(
                        _niceDate(widget.dateYMD),
                        style: TextStyle(fontSize: 13.sp,
                            color: Colors.black87,
                            fontWeight: FontWeight.w600),
                      ),
                    ),

                    SizedBox(height: 18.h),

//---------------------------------------
// list the start time and slot
//---------------------------------------
                    Text('Start time(s) & slot', style: TextStyle(
                        fontSize: 16.sp, fontWeight: FontWeight.w700)),
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

//---------------------------------------
// display location
//---------------------------------------
                    Text('Location', style: TextStyle(
                        fontSize: 16.sp, fontWeight: FontWeight.w700)),
                    SizedBox(height: 6.h),
                    Container(
                      width: 1.0.sw,
                      padding: EdgeInsets.all(12.w),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                      child: Text(
                        _location,
                        style: TextStyle(fontSize: 13.sp,
                            color: Colors.black87,
                            fontWeight: FontWeight.w600),
                      ),
                    ),

                    SizedBox(height: 18.h),

//---------------------------------------
// display description
//---------------------------------------
                    Text('Description', style: TextStyle(
                        fontSize: 16.sp, fontWeight: FontWeight.w700)),
                    SizedBox(height: 6.h),
                    Container(
                      width: 1.0.sw,
                      padding: EdgeInsets.all(12.w),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                      child: Text(
                        _description,
                        style: TextStyle(fontSize: 13.sp,
                            color: Colors.black87,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                    SizedBox(height: 18.h),
//---------------------------------------
// user info display
//---------------------------------------

                    Text('Your info', style: TextStyle(
                        fontSize: 16.sp, fontWeight: FontWeight.w700)),
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

//---------------------------------------
// reason display
//---------------------------------------

                    Text('Reason (required)', style: TextStyle(
                        fontSize: 16.sp, fontWeight: FontWeight.w700)),
                    SizedBox(height: 6.h),
                    Stack(
                      children: <Widget>[
                        TextField(
                          controller: _reasonCtrl,
                          maxLength: 99,
                          maxLines: 3,
                          decoration: InputDecoration(
                            counterText: '',
                            isDense: true,
                            hintText: 'Why do you need this booking?',
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12.r)),
                            fillColor: Colors.grey.shade200,
                            filled: true,
                          ),
                        ),
//---------------------------------------
// show counter
//---------------------------------------
                        Positioned(
                          right: 10.w,
                          bottom: 8.h,
                          child: Text('$_reasonLen/99', style: TextStyle(
                              fontSize: 12.sp, color: Colors.black54)),
                        ),
                      ],
                    ),
                    SizedBox(height: 18.h),

//---------------------------------------
// manager display
//---------------------------------------
                    Text('Manager', style: TextStyle(
                        fontSize: 16.sp, fontWeight: FontWeight.w700)),
                    SizedBox(height: 6.h),
                    Container(
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
//---------------------------------------
// if no image then use place holder
//---------------------------------------
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8.r),
                            child: SizedBox(
                              width: 110.w,
                              height: 110.w,
                              child: managerAssetPath.isEmpty
                                  ? Container(
                                color: Colors.grey.shade400,
                                alignment: Alignment.center,
                                child: Icon(
                                    Icons.person_off, color: Colors.white,
                                    size: 26.sp),
                              )
                                  : Image.asset(
                                  managerAssetPath, fit: BoxFit.cover),
                            ),
                          ),
                          SizedBox(width: 15.w),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                _kvLine(label: 'Name',    value: managerName),
                                SizedBox(height: 6.h),
                                _kvLine(label: 'Email',   value: managerEmail),
                                SizedBox(height: 6.h),
                                _kvLine(label: 'Contact', value: managerContact),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height:10.h),
 //---------------------------------------
// confirm button
//---------------------------------------
              Container(
              child: SizedBox(
                width: 1.0.sw,
                height: 48.h,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF9747FF),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10.r)),
                  ),
                  onPressed: _saving ? null : _onConfirmPressed,
                  child: Text(
                    _saving ? 'Saving...' : 'Confirm',
                    style: TextStyle(fontSize: 16.sp,
                        fontWeight: FontWeight.w700,
                        color: Colors.white),
                  ),
                ),
              ),
              ),
            ],
          ),
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

