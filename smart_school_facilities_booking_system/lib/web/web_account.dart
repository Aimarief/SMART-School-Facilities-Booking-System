// lib/web/web_account.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart' show rootBundle;


import 'web_top_bar.dart';

class WebAccount extends StatefulWidget {
  const WebAccount({Key? key}) : super(key: key);

  @override
  State<WebAccount> createState() => _AdminWebAccountState();
}

class _AdminWebAccountState extends State<WebAccount> {
  // -------------------------------------------------------------------------
  // FIREBASE REFERENCES
  // -------------------------------------------------------------------------
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? user;
  String? userDocId;

  // -------------------------------------------------------------------------
  // SIMPLE UI STATE FLAGS
  // -------------------------------------------------------------------------
  bool isLoading = true;
  bool isEditing = false;

  // -------------------------------------------------------------------------
  // ACCOUNT INFO
  // -------------------------------------------------------------------------
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _contactController = TextEditingController();
  final TextEditingController _imageNameController = TextEditingController();
  final GlobalKey<FormState> _editFormKey = GlobalKey<FormState>();

  String profileImage = '';
  String profileImageName = '';
  String username = 'Loading...';
  String contact = 'Loading...';
  String role = 'Loading...';

  // -------------------------------------------------------------------------
  // TIME FORMAT (User setting)
  // -------------------------------------------------------------------------
  bool use24HourFormat = true;

  // -------------------------------------------------------------------------
  // WORKING TIME & DAYS (SystemInformation/Setting)
  // -------------------------------------------------------------------------
  TimeOfDay? startTime;
  TimeOfDay? endTime;
  Map<String, bool> workingDays = <String, bool>{
    'Sunday': false,
    'Monday': false,
    'Tuesday': false,
    'Wednesday': false,
    'Thursday': false,
    'Friday': false,
    'Saturday': false,
  };
  // keep original working days so we know which were newly disabled on apply
  late Map<String, bool> _originalWorkingDays;

  // -------------------------------------------------------------------------
  // OFF DAYS (SystemInformation/OffDays.offDays = ["YYYY-MM-DD", ...])
  // (UI/calendar remains the same, still toggles DB immediately. Apply button
  // will only fan-out request_update to users who booked on holiday dates.)
  // -------------------------------------------------------------------------
  DateTime _offCalVisibleMonthFirst =
  DateTime(DateTime.now().year, DateTime.now().month, 1);
  final Set<String> _offDaysYMD = <String>{};
  bool _loadingOffDays = true;
  Set<String> _offDaysSaved = <String>{};     // snapshot from DB
  bool _offDirty = false;                     // true if user changed but not applied

  // ---- Notification toggles (right column) — removed for Admin layout
  bool notifAll = true;
  bool notifNewBooking = true;
  bool notifPending = true;
  bool notifIssue = true;

  @override
  void initState() {
    super.initState();
    user = _auth.currentUser;
    _loadAll();
  }

  // =========================================================================
  // LOADERS
  // =========================================================================
  Future<void> _loadAll() async {
    if (user == null || user!.email == null) {
      setState(() {
        isLoading = false;
        username = 'N/A';
        contact = 'N/A';
        role = 'N/A';
      });
      return;
    }

    await _loadUserInfo(user!.email!);
    await _loadSystemSettings();
    await _loadOffDays();

    setState(() {
      isLoading = false;
    });
  }

  Future<void> _loadUserInfo(String email) async {
    final QuerySnapshot<Map<String, dynamic>> qs = await _firestore
        .collection('UserInformation')
        .where('email', isEqualTo: email)
        .limit(1)
        .get();

    if (qs.docs.isEmpty) {
      setState(() {
        username = 'N/A';
        contact = 'N/A';
        role = 'N/A';
        profileImageName = '';
        _imageNameController.text = '';
      });
      return;
    }

    final doc = qs.docs.first;
    final data = doc.data();
    userDocId = doc.id;

    String newUsername = (data['username'] ?? 'N/A').toString();
    String newContact = (data['contact'] ?? 'N/A').toString();
    String newRole = (data['role'] ?? 'N/A').toString();
    String newImageName = (data['profileImageName'] ?? '').toString();

    bool newUse24 = data['timeFormat24'] is bool ? (data['timeFormat24'] as bool) : true;

    bool newNotifAll = data['notifAll'] is bool ? (data['notifAll'] as bool) : true;
    bool newNotifNewBooking = data['notifNewBooking'] is bool ? (data['notifNewBooking'] as bool) : true;
    bool newNotifPending = data['notifPending'] is bool ? (data['notifPending'] as bool) : true;
    bool newNotifIssue = data['notifIssue'] is bool ? (data['notifIssue'] as bool) : true;

    setState(() {
      username = newUsername;
      contact = newContact;
      role = newRole;

      profileImageName = newImageName;
      _imageNameController.text = profileImageName;

      use24HourFormat = newUse24;

      notifAll = newNotifAll;
      notifNewBooking = newNotifNewBooking;
      notifPending = newNotifPending;
      notifIssue = newNotifIssue;

      _usernameController.text = username;
      _contactController.text = contact;
    });
  }

  Future<void> _loadSystemSettings() async {
    final snap = await _firestore.collection('SystemInformation').doc('Setting').get();
    if (!snap.exists) return;

    final data = snap.data()!;

    final s = data['start'] is String ? data['start'] as String : null;
    final e = data['end'] is String ? data['end'] as String : null;

    bool sun = data['Sunday'] is bool ? data['Sunday'] as bool : false;
    bool mon = data['Monday'] is bool ? data['Monday'] as bool : false;
    bool tue = data['Tuesday'] is bool ? data['Tuesday'] as bool : false;
    bool wed = data['Wednesday'] is bool ? data['Wednesday'] as bool : false;
    bool thu = data['Thursday'] is bool ? data['Thursday'] as bool : false;
    bool fri = data['Friday'] is bool ? data['Friday'] as bool : false;
    bool sat = data['Saturday'] is bool ? data['Saturday'] as bool : false;

    setState(() {
      startTime = (s != null) ? _parseTime(s) : null;
      endTime = (e != null) ? _parseTime(e) : null;

      workingDays = <String, bool>{
        'Sunday': sun,
        'Monday': mon,
        'Tuesday': tue,
        'Wednesday': wed,
        'Thursday': thu,
        'Friday': fri,
        'Saturday': sat,
      };
      _originalWorkingDays = Map<String, bool>.from(workingDays);
    });
  }

  Future<void> _loadOffDays() async {
    setState(() => _loadingOffDays = true);
    try {
      final doc = await _firestore.collection('SystemInformation').doc('OffDays').get();

      final Set<String> tmp = <String>{};
      if (doc.exists) {
        final data = doc.data();
        if (data != null && data['offDays'] is List) {
          for (final v in (data['offDays'] as List)) {
            final s = v?.toString().trim();
            if (s != null && s.isNotEmpty) tmp.add(s);
          }
        }
      }

      // baseline from DB
      _offDaysSaved = Set<String>.from(tmp);

      // working copy for UI
      _offDaysYMD
        ..clear()
        ..addAll(tmp);

      _offDirty = false; // nothing pending
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _loadingOffDays = false);
    }
  }

  String _assetFromName(String name) {
    if (name.isEmpty) return '';
    return 'asset/image/$name';
  }

  Widget _profileAvatarFromName(String name, {double size = 60}) {
    final String path = _assetFromName(name);

    if (path.isEmpty) {
      return Container(
        width: size * 2,
        height: size * 2,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.black12, width: 2),
          color: Colors.grey.shade300,
        ),
        alignment: Alignment.center,
        child: const Text('empty'),
      );
    }

    return Container(
      width: size * 2,
      height: size * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black12, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        path,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) => const Center(child: Text('empty')),
      ),
    );
  }


  // =========================================================================
  // SAVERS
  // =========================================================================
  Future<void> _saveAccountInfo() async {
    if (userDocId == null) return;

    final String fname = _imageNameController.text.trim();

    if (fname.isNotEmpty) {
      final bool exists = await _assetExistsInBundle(fname);
      if (!exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Image not found in asset/image/. Add it and restart the app.'),
          ),
        );
        return;
      }
    }

    final Map<String, dynamic> payload = <String, dynamic>{
      'username': _usernameController.text.trim(),
      'contact': _contactController.text.trim(),
      'profileImageName': fname,
    };

    await _firestore
        .collection('UserInformation')
        .doc(userDocId)
        .set(payload, SetOptions(merge: true));

    setState(() {
      username = _usernameController.text.trim();
      contact = _contactController.text.trim();
      profileImageName = fname;
      isEditing = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('User info updated')),
    );
  }

  Future<bool> _assetExistsInBundle(String name) async {
    if (name.isEmpty) return false;
    try {
      await rootBundle.load('asset/image/$name');
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _pickImageFileName() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['png', 'jpg', 'jpeg'],
      withData: false,
    );

    if (result == null || result.files.isEmpty) return;

    final String fileName = result.files.single.name;
    setState(() {
      _imageNameController.text = fileName;
    });
  }

  Future<void> _saveTimeFormat(bool value) async {
    if (userDocId == null) return;

    setState(() {
      use24HourFormat = value;
    });

    await _firestore
        .collection('UserInformation')
        .doc(userDocId)
        .set(<String, dynamic>{'timeFormat24': value}, SetOptions(merge: true));
  }

  Future<void> _saveSystemTimes() async {
    if (startTime == null || endTime == null) return;
    await _firestore
        .collection('SystemInformation')
        .doc('Setting')
        .set(
      <String, dynamic>{
        'start': _formatTime(startTime!),
        'end': _formatTime(endTime!),
      },
      SetOptions(merge: true),
    );
  }


  // =========================================================================
  // AUTH / MISC
  // =========================================================================
  Future<void> _sendPasswordReset() async {
    if (user == null || user!.email == null) return;
    await _auth.sendPasswordResetEmail(email: user!.email!);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Reset email sent to ${user!.email!}')),
    );
  }

  Future<void> _logout() async {
    await _auth.signOut();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  // =========================================================================
  // HELPERS
  // =========================================================================
  TimeOfDay _parseTime(String hhmm) {
    final p = hhmm.split(':');
    return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
  }

  String _formatTime(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  int _timeToMinutes(String hhmm) {
    try {
      final p = hhmm.split(':');
      final h = int.parse(p[0]);
      final m = int.parse(p[1]);
      return (h * 60) + m;
    } catch (_) {
      return 0;
    }
  }

  // Read facility available time from nested/flat fields
  Map<String, String> _readFacilityAvailableTimes(Map<String, dynamic> data) {
    String s = '';
    String e = '';

    if (data.containsKey('availableTime') &&
        data['availableTime'] is Map<String, dynamic>) {
      final at = data['availableTime'] as Map<String, dynamic>;
      if (at['start'] is String) s = (at['start'] as String).trim();
      if (at['end'] is String) e = (at['end'] as String).trim();
    }

    if (s.isEmpty && data['availableTimeStart'] is String) {
      s = (data['availableTimeStart'] as String).trim();
    }
    if (e.isEmpty && data['availableTimeEnd'] is String) {
      e = (data['availableTimeEnd'] as String).trim();
    }

    return <String, String>{'start': s, 'end': e};
  }

  // Check only facilities against new system hours; return list of conflicts
  Future<List<String>> _findFacilityConflicts(String newStart, String newEnd) async {
    final int sysStart = _timeToMinutes(newStart);
    final int sysEnd = _timeToMinutes(newEnd);

    final qs = await _firestore.collection('Facilities').get();
    final List<String> conflicts = <String>[];

    for (final d in qs.docs) {
      final m = d.data();

      if (m['deleted'] is bool && m['deleted'] == true) continue;

      String name = d.id;
      if (m['name'] is String && (m['name'] as String).trim().isNotEmpty) {
        name = (m['name'] as String).trim();
      }

      final at = _readFacilityAvailableTimes(m);
      final fs = (at['start'] ?? '').trim();
      final fe = (at['end'] ?? '').trim();
      if (fs.isEmpty || fe.isEmpty) continue;

      final facStart = _timeToMinutes(fs);
      final facEnd = _timeToMinutes(fe);

      if (facStart < sysStart || facEnd > sysEnd) {
        conflicts.add(name);
      }
    }

    return conflicts;
  }

  // ---------------------------------------------------------------------------
  // BOOKING TIME HELPERS (simple)
  // ---------------------------------------------------------------------------
  Map<String, String> _readBookingTimes(Map<String, dynamic> m) {
    String s = '';
    String e = '';
    if (m.containsKey('time') && m['time'] is Map<String, dynamic>) {
      final Map<String, dynamic> tm = m['time'] as Map<String, dynamic>;
      if (tm['start'] is String) s = (tm['start'] as String).trim();
      if (tm['end'] is String) e = (tm['end'] as String).trim();
    }
    if (s.isEmpty && m['start'] is String) s = (m['start'] as String).trim();
    if (e.isEmpty && m['end'] is String) e = (m['end'] as String).trim();

    if (s.isEmpty && m['startTime'] is String) s = (m['startTime'] as String).trim();
    if (e.isEmpty && m['endTime'] is String) e = (m['endTime'] as String).trim();
    return <String, String>{'start': s, 'end': e};
  }

  String _normalizeToHHmm(String raw) {
    if (raw.isEmpty) return '';
    String s = raw.toLowerCase().trim();
    s = s.replaceAll('.', ':').replaceAll('-', ':');
    if (s.contains(':')) {
      final p = s.split(':');
      String hh = p[0].trim();
      String mm = p.length > 1 ? p[1].trim() : '00';
      int h = int.tryParse(hh) ?? 0;
      int m = int.tryParse(mm) ?? 0;
      h = h.clamp(0, 23);
      m = m.clamp(0, 59);
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
    }
    final digits = s.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return '';
    if (digits.length <= 2) {
      int h = int.tryParse(digits) ?? 0;
      h = h.clamp(0, 23);
      return '${h.toString().padLeft(2, '0')}:00';
    }
    final hh = digits.substring(0, digits.length - 2);
    final mm = digits.substring(digits.length - 2);
    int h = int.tryParse(hh) ?? 0;
    int m = int.tryParse(mm) ?? 0;
    h = h.clamp(0, 23);
    m = m.clamp(0, 59);
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  int _safeMinutes(String raw) {
    final hhmm = _normalizeToHHmm(raw);
    if (hhmm.isEmpty) return -1;
    return _timeToMinutes(hhmm);
  }

  DateTime? _readBookingDateFromAny(Map<String, dynamic> m) {
    final v = m['bookingDate'] ?? m['booking_date'] ?? m['date'];
    if (v is Timestamp) return v.toDate();
    if (v is String && v.trim().isNotEmpty) {
      try {
        final p = DateTime.tryParse(v.trim());
        if (p != null) return DateTime(p.year, p.month, p.day);
      } catch (_) {}
    }
    return null;
  }

  // === existing booking conflict finder (kept) ===
  Future<List<String>> _findBookingConflicts(String newStart, String newEnd) async {
    final int sysStart = _timeToMinutes(newStart);
    final int sysEnd = _timeToMinutes(newEnd);

    final DateTime now = DateTime.now();
    final DateTime todayStart = DateTime(now.year, now.month, now.day);
    final DateTime cutoff = todayStart.subtract(const Duration(days: 8));

    final QuerySnapshot<Map<String, dynamic>> qs =
    await _firestore.collection('Bookings').get();

    final List<String> conflicts = <String>[];

    for (final doc in qs.docs) {
      final Map<String, dynamic> m = doc.data();

      if (m['deleted'] == true) continue;
      final String appr = (m['approval'] ?? m['approvalStatus'] ?? '').toString().toLowerCase();
      if (appr.contains('reject')) continue;
      final String status = (m['status'] ?? '').toString().toLowerCase();
      if (status == 'ended') continue;

      final DateTime? bDate = _readBookingDateFromAny(m);
      if (bDate == null) continue;

      final DateTime bStart = DateTime(bDate.year, bDate.month, bDate.day);
      if (bStart.isBefore(cutoff)) continue;

      final tt = _readBookingTimes(m);
      final int bStartMin = _safeMinutes(tt['start'] ?? '');
      final int bEndMin = _safeMinutes(tt['end'] ?? '');
      if (bStartMin < 0 || bEndMin < 0) continue;

      if (bStartMin < sysStart || bEndMin > sysEnd) {
        conflicts.add(doc.id);
      }
    }

    return conflicts;
  }

  // =========================================================================
  // NEW: APPLY ACTIONS
  // =========================================================================

  Future<void> _applyWorkingHours() async {
    if (startTime == null || endTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select both start and end time.')),
      );
      return;
    }

    final String newStartStr = _formatTime(startTime!);
    final String newEndStr   = _formatTime(endTime!);

    final int sMin = _timeToMinutes(newStartStr);
    final int eMin = _timeToMinutes(newEndStr);
    if (eMin <= sMin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End time must be later than start time.')),
      );
      return;
    }

    final conflictsFacilities = await _findFacilityConflicts(newStartStr, newEndStr);
    if (conflictsFacilities.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Some facilities have available time outside the new window. Reverting change.'),
        ),
      );
      return;
    }

    final conflictsBookings = await _findBookingConflicts(newStartStr, newEndStr);
    if (conflictsBookings.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('There are bookings outside the new working hour. Change rejected.'),
        ),
      );
      return;
    }

    await _saveSystemTimes();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Working hour saved')),
    );
  }

  Future<void> _applyWorkingDays() async {
    // write all days at once
    await _firestore.collection('SystemInformation').doc('Setting').set(
      Map<String, dynamic>.from(workingDays),
      SetOptions(merge: true),
    );

    // figure out which days are disabled now
    final Set<String> disabled = workingDays.entries
        .where((e) => e.value == false)
        .map((e) => e.key)
        .toSet();

    // only process days that became disabled (optional optimization)
    final Set<String> newlyDisabled = disabled
      ..removeWhere((d) => _originalWorkingDays[d] == false);

    // if nothing new disabled, we can still process, but skip for speed
    final Set<String> targetDays = newlyDisabled.isEmpty ? disabled : newlyDisabled;

    if (targetDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Working days saved')),
      );
      _originalWorkingDays = Map<String, bool>.from(workingDays);
      return;
    }

    await _fanOutRequestUpdatesForDaysOfWeek(targetDays);

    _originalWorkingDays = Map<String, bool>.from(workingDays);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Working days saved & users notified')),
    );
  }

  Future<void> _applyHolidays() async {
    try {
      // write the entire working list exactly as shown in UI
      await _firestore
          .collection('SystemInformation')
          .doc('OffDays')
          .set({'offDays': _offDaysYMD.toList()}, SetOptions(merge: true));

      // notify impacted bookings (your existing helper)
      await _fanOutRequestUpdatesForHolidayDates(_offDaysYMD);

      // update baseline -> no longer dirty
      setState(() {
        _offDaysSaved = Set<String>.from(_offDaysYMD);
        _offDirty = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Holiday changes applied & users notified')),
      );
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to apply holidays. Please try again.')),
      );
    }
  }


  // =========================================================================
  // NEW: “request_update” fan-out helpers
  // =========================================================================

  // Build weekday name like 'Monday' from DateTime.weekday (1..7 Mon..Sun)
  String _weekdayName(int weekday) {
    const names = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
    return names[weekday - 1];
  }

  bool _isBookingIgnored(Map<String, dynamic> m) {
    if (m['deleted'] == true) return true;
    final String appr = (m['approval'] ?? m['approvalStatus'] ?? '').toString().toLowerCase();
    if (appr.contains('reject')) return true;
    final String status = (m['status'] ?? '').toString().toLowerCase();
    if (status == 'ended') return true;
    return false;
  }

  String _readFirstStr(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
      if (v != null) return v.toString();
    }
    return '';
  }

  Future<void> _fanOutRequestUpdatesForDaysOfWeek(Set<String> disabledDays) async {
    if (disabledDays.isEmpty) return;

    final qs = await _firestore.collection('Bookings').get();

    final List<Future<void>> tasks = [];

    for (final doc in qs.docs) {
      final Map<String, dynamic> b = doc.data();
      if (_isBookingIgnored(b)) continue;

      final DateTime? d = _readBookingDateFromAny(b);
      if (d == null) continue;

      final String dayName = _weekdayName(d.weekday);
      if (!disabledDays.contains(dayName)) continue;

      tasks.add(_emitRequestUpdateForBooking(doc.id, b));
    }

    await Future.wait(tasks);
  }

  Future<void> _fanOutRequestUpdatesForHolidayDates(Set<String> holidaysYmd) async {
    if (holidaysYmd.isEmpty) return;

    final qs = await _firestore.collection('Bookings').get();
    final List<Future<void>> tasks = [];

    for (final doc in qs.docs) {
      final Map<String, dynamic> b = doc.data();
      if (_isBookingIgnored(b)) continue;

      final DateTime? d = _readBookingDateFromAny(b);
      if (d == null) continue;

      final String y = d.year.toString().padLeft(4, '0');
      final String m = d.month.toString().padLeft(2, '0');
      final String da = d.day.toString().padLeft(2, '0');
      final String ymd = '$y-$m-$da';

      if (!holidaysYmd.contains(ymd)) continue;

      tasks.add(_emitRequestUpdateForBooking(doc.id, b));
    }

    await Future.wait(tasks);
  }

  Future<void> _emitRequestUpdateForBooking(String bookingId, Map<String, dynamic> b) async {
    final String userUid = _readFirstStr(b, ['bookedBy','bookBy','userUid','userId','uid']);
    if (userUid.isEmpty) return;

    final String facilityId = _readFirstStr(b, ['facilityId','facilityID','facilityDocId','facility']);
    if (facilityId.isEmpty) return;

    final String adminUid = _auth.currentUser?.uid ?? '';

    // booking date/time
    final String bookingDateStr = (b['bookingDate'] ?? b['booking_date'] ?? b['date'] ?? '').toString();
    final times = _readBookingTimes(b);
    final String start = (times['start'] ?? '').toString();
    final String end   = (times['end'] ?? '').toString();

    String seat = '-';
    if (b['seatIndex'] != null) {
      seat = b['seatIndex'].toString();
    } else if (b['slotIndex'] != null) {
      seat = b['slotIndex'].toString();
    }

    // (optional) grab a friendly facility name for UI
    String facilityName = '';
    try {
      final snap = await _firestore.collection('Facilities').doc(facilityId).get();
      final m = snap.data();
      if (m != null) facilityName = (m['name'] ?? m['title'] ?? '').toString();
    } catch (_) {}

    // write the inbox doc under the booking owner
    final inboxRef = _firestore
        .collection('UserInformation')
        .doc(userUid)
        .collection('Inbox')
        .doc();

    await inboxRef.set({
      'type': 'request_update',

      // 👇 add the fields Android checks in _canSee(...)
      'recipientId': userUid,
      'bookedBy': userUid,
      'createdBy': adminUid,
      'managerId': adminUid,

      // keep your existing fields
      'userId': userUid,
      'facilityId': facilityId,
      'facilityName': facilityName, // optional but useful elsewhere
      'bookingId': bookingId,
      'bookingDate': bookingDateStr,
      'start': start,
      'end': end,
      'seatIndex': seat,

      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await sendRequestUpdateMails(
      bookingId: bookingId,
      userId: userUid,
      facilityId: facilityId,
      bookingDateIso: bookingDateStr,
    );
  }


  /// stub — replace body with your existing implementation or Cloud Function call
  Future<void> sendRequestUpdateMails({
    required String bookingId,
    required String userId,
    required String facilityId,
    required String bookingDateIso,
  }) async {
    // TODO: hook into your existing "sendRequestUpdateMails" implementation.
    // Left empty on purpose to avoid changing project-wide behavior.
    return;
  }

  // =========================================================================
  // UI
  // =========================================================================
  @override
  Widget build(BuildContext context) {
    final double screenHeight = MediaQuery.of(context).size.height;

    bool isAdmin = false;
    if (role.isNotEmpty) {
      isAdmin = role.toLowerCase() == 'admin';
    }

    bool isManager = role.trim().toLowerCase() == 'manager';

    String emailStr = (user != null && user!.email != null) ? user!.email! : 'N/A';
    String statusText = (user != null) ? 'Logged In' : 'Logged Out';

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(70.h),
        child: WebCustomTopBar(use24HourFormat: use24HourFormat),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : (
          isAdmin
          // ===== Admin keeps the 2-column layout =====
              ? SingleChildScrollPane(
            isAdmin: isAdmin,
            leftChild: _buildLeftColumn(isAdmin, screenHeight, emailStr, statusText),
            rightChild: _buildRightColumn(isAdmin),
          )

          // ===== Manager: show ONLY the Account panel centered =====
              : Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 520.w),
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 16.h, horizontal: 20.w),
                // reuse the same Account builder you already have
                child: _buildLeftColumn(false, screenHeight, emailStr, statusText),
              ),
            ),
          )
      ),

    );
  }

  // -------------- layout wrappers --------------
  Widget _buildLeftColumn(bool isAdmin, double screenHeight, String emailStr, String statusText) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 520.w),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 16.h, horizontal: 20.w),
          child: SingleChildScrollView(
            primary: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // ---- Account (unchanged) ----
                Text("Account Settings",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 26.sp, fontWeight: FontWeight.bold)),
                SizedBox(height: 35.h),

                Center(
                  child: _profileAvatarFromName(
                    isEditing ? _imageNameController.text.trim() : profileImageName,
                    size: 150,
                  ),
                ),
                SizedBox(height: 16.h),

                Builder(
                  builder: (BuildContext _) {
                    if (isEditing) {
                      return Form(
                        key: _editFormKey,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        child: Column(
                          children: <Widget>[
                            SizedBox(height: 8.h),
                            SizedBox(
                              width: double.infinity,
                              height: 40.h,
                              child: OutlinedButton(
                                onPressed: _pickImageFileName,
                                child: const Text("Choose Image"),
                              ),
                            ),
                            SizedBox(height: 12.h),

                            TextFormField(
                              controller: _usernameController,
                              decoration: const InputDecoration(labelText: "Username"),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return 'Username cannot be empty';
                                return null;
                              },
                            ),
                            SizedBox(height: 12.h),

                            TextFormField(
                              controller: _contactController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: "Contact"),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return 'Contact cannot be empty';
                                return null;
                              },
                              onChanged: (value) {
                                final digitsOnly = value.replaceAll(RegExp(r'[^0-9]'), '');
                                if (digitsOnly != value) {
                                  _contactController.text = digitsOnly;
                                  _contactController.selection =
                                      TextSelection.collapsed(offset: digitsOnly.length);
                                }
                              },
                            ),
                            SizedBox(height: 16.h),

                            SizedBox(
                              width: double.infinity,
                              height: 48.h,
                              child: ElevatedButton(
                                onPressed: () {
                                  if (_editFormKey.currentState?.validate() != true) return;
                                  _saveAccountInfo();
                                },
                                child: const Text("Save"),
                              ),
                            ),
                            SizedBox(height: 8.h),

                            TextButton(
                              onPressed: () => setState(() => isEditing = false),
                              child: const Text("Cancel"),
                            ),
                          ],
                        ),
                      );
                    } else {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          _detailRow("Username:", username),
                          _detailRow("Email:", emailStr),
                          _detailRow("Contact:", contact),
                          _detailRow("Role:", role),
                          _detailRow("Status:", statusText),
                          SizedBox(height: 16.h),
                          SizedBox(
                            width: double.infinity,
                            height: 48.h,
                            child: ElevatedButton(
                              onPressed: () => setState(() => isEditing = true),
                              child: const Text("Edit"),
                            ),
                          ),
                        ],
                      );
                    }
                  },
                ),

                SizedBox(height: 24.h),

                SizedBox(
                  width: double.infinity,
                  height: 48.h,
                  child: ElevatedButton(
                    onPressed: _sendPasswordReset,
                    child: const Text("Change Password"),
                  ),
                ),
                SizedBox(height: 16.h),

                SizedBox(
                  width: double.infinity,
                  height: 48.h,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    onPressed: _logout,
                    child: const Text("Log Out"),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRightColumn(bool isAdmin) {
    if (isAdmin) {
      return Center(
        child: ConstrainedBox(
          // a bit wider so two columns fit nicely
          constraints: BoxConstraints(maxWidth: 1100.w),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 16.h, horizontal: 20.w),
            child: SingleChildScrollView(
              primary: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // Title centered over both inner columns
                  Text(
                    "System Setting",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 26.sp, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 30.h),

                  // >>> Two-column layout inside the System Setting area <<<
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ---------------- LEFT of System Setting ----------------
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Working Hour
                            Text("Working Hour",
                                style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold)),
                            SizedBox(height: 12.h),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text("Start"),
                                      SizedBox(height: 6.h),
                                      SizedBox(
                                        width: double.infinity,
                                        child: ElevatedButton(
                                          onPressed: () => _pickTime(isStart: true),
                                          child: Text((startTime == null) ? "Select" : _formatTime(startTime!)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(width: 12.w),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text("End"),
                                      SizedBox(height: 6.h),
                                      SizedBox(
                                        width: double.infinity,
                                        child: ElevatedButton(
                                          onPressed: () => _pickTime(isStart: false),
                                          child: Text((endTime == null) ? "Select" : _formatTime(endTime!)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 10.h),
                            Align(
                              alignment: Alignment.centerRight,
                              child: SizedBox(
                                height: 40.h,
                                child: ElevatedButton(
                                  onPressed: _applyWorkingHours,
                                  child: const Text('Apply Working Hour'),
                                ),
                              ),
                            ),

                            SizedBox(height: 75.h),

                            // Working Days
                            Text("Working Days",
                                style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold)),
                            Column(
                              children: workingDays.keys.map((day) {
                                final bool v = workingDays[day] == true;
                                return CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(day),
                                  value: v,
                                  onChanged: (bool? nv) {
                                    setState(() { workingDays[day] = (nv == true); });
                                  },
                                );
                              }).toList(),
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: SizedBox(
                                height: 40.h,
                                child: ElevatedButton(
                                  onPressed: _applyWorkingDays,
                                  child: const Text('Apply Working Days'),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      SizedBox(width: 24.w),

                      // ---------------- RIGHT of System Setting ----------------
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Pick Holiday
                            Text("Pick Off Days (Holidays)",
                                style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold)),
                            SizedBox(height: 10.h),
                            _buildOffDaysCalendarCard(),
                            SizedBox(height: 6.h),
                            Text(
                              'Tip: Click a future day to toggle holiday. Blue = holiday. Past days are disabled.',
                              style: TextStyle(fontSize: 11.sp, color: const Color(0xFF6B7280)),
                            ),
                            SizedBox(height: 8.h),
                            Align(
                              alignment: Alignment.centerRight,
                              child: SizedBox(
                                height: 40.h,
                                child: ElevatedButton(
                                  onPressed: _applyHolidays,
                                  child: const Text('Apply Holidays'),
                                ),
                              ),
                            ),

                            SizedBox(height: 24.h),

                            // Time Format (moved to the right column per your spec)
                            Text("Time Format",
                                style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold)),
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text("Use 24-Hour Format"),
                              value: use24HourFormat,
                              onChanged: (bool? v) => _saveTimeFormat(v ?? true),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Non-admin path unchanged
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 520.w),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 16.h, horizontal: 20.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text("Notification Settings",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 26.sp, fontWeight: FontWeight.bold)),
              SizedBox(height: 35.h),
              SwitchListTile(
                title: const Text("Turn on sound for all notification"),
                value: notifAll,
                onChanged: (bool v) => _updateNotif('notifAll', v),
              ),
              SwitchListTile(
                title: const Text("Turn on sound for new booking"),
                value: notifNewBooking,
                onChanged: (bool v) => _updateNotif('notifNewBooking', v),
              ),
              SwitchListTile(
                title: const Text("Turn on sound for new pending booking"),
                value: notifPending,
                onChanged: (bool v) => _updateNotif('notifPending', v),
              ),
              SwitchListTile(
                title: const Text("Turn on sound for new reported issue"),
                value: notifIssue,
                onChanged: (bool v) => _updateNotif('notifIssue', v),
              ),
            ],
          ),
        ),
      ),
    );
  }


  // =========================================================================
  // Existing methods kept (some repositioned in UI)
  // =========================================================================

  Future<void> _updateNotif(String field, bool value) async {
    if (userDocId == null) return;

    setState(() {
      switch (field) {
        case 'notifAll':
          notifAll = value;
          break;
        case 'notifNewBooking':
          notifNewBooking = value;
          break;
        case 'notifPending':
          notifPending = value;
          break;
        case 'notifIssue':
          notifIssue = value;
          break;
      }
    });

    await _firestore
        .collection('UserInformation')
        .doc(userDocId)
        .set(<String, dynamic>{field: value}, SetOptions(merge: true));
  }

  // NOTE: _pickTime now ONLY sets state; saving happens on _applyWorkingHours()
  Future<void> _pickTime({required bool isStart}) async {
    final TimeOfDay initial = isStart
        ? (startTime ?? const TimeOfDay(hour: 9, minute: 0))
        : (endTime ?? const TimeOfDay(hour: 17, minute: 0));

    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;

    setState(() {
      if (isStart) {
        startTime = picked;
      } else {
        endTime = picked;
      }
    });
  }

  // -------------------- Off Days Calendar UI (unchanged) --------------------
  Widget _buildOffDaysCalendarCard() {
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
          _buildOffDaysCalendarHeader(),
          SizedBox(height: 8.h),
          _buildWeekdayRow(),
          SizedBox(height: 8.h),
          _buildOffDaysCalendarGrid(),
        ],
      ),
    );
  }

  Widget _buildOffDaysCalendarHeader() {
    final m = _offCalVisibleMonthFirst;
    final label = '${_monthName(m.month)} ${m.year}';

    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600),
          ),
        ),
        TextButton(onPressed: _prevMonthOffCal, child: Text('Prev', style: TextStyle(fontSize: 12.sp))),
        SizedBox(width: 4.w),
        TextButton(onPressed: _nextMonthOffCal, child: Text('Next', style: TextStyle(fontSize: 12.sp))),
      ],
    );
  }

  Widget _buildWeekdayRow() {
    const days = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];

    return LayoutBuilder(
      builder: (context, c) {
        final gap = 6.w;
        final totalGaps = gap * 6;
        double cellW = (c.maxWidth - totalGaps) / 7.0;
        if (cellW < 10.w) cellW = 10.w;

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(7, (i) {
            return SizedBox(
              width: cellW,
              child: Center(
                child: Text(
                  days[i],
                  style: TextStyle(
                    fontSize: 11.sp,
                    color: const Color(0xFF6B7280),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }

  Widget _buildOffDaysCalendarGrid() {
    if (_loadingOffDays) {
      return SizedBox(
        height: 160.h,
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    final f = _offCalVisibleMonthFirst;
    final days = _daysInMonth(f);
    final lead = _leadingEmptyCells(f);
    final total = lead + days;

    int rows = (total / 7.0).ceil();
    if (rows < 6) rows = 6;

    return LayoutBuilder(
      builder: (context, c) {
        final gap = 6.w;
        final totalGapW = gap * 6;
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
                  children: List.generate(7, (cIdx) {
                    final cellIndex = (r * 7) + cIdx;
                    final dayNum = cellIndex - lead + 1;

                    final inMonth = (dayNum >= 1 && dayNum <= days);
                    final DateTime? cellDate =
                    inMonth ? DateTime(f.year, f.month, dayNum) : null;

                    final today = DateTime.now();
                    final todayStart = DateTime(today.year, today.month, today.day);
                    final isDisabled = cellDate == null
                        ? true
                        : DateTime(cellDate.year, cellDate.month, cellDate.day)
                        .isBefore(todayStart);

                    final String ymd = (cellDate != null) ? _ymd(cellDate) : '';
                    final bool isHoliday =
                        cellDate != null && _offDaysYMD.contains(ymd);

                    return _offDayCell(
                      width: cellW,
                      height: cellW,
                      label: inMonth ? '$dayNum' : '',
                      inMonth: inMonth,
                      isDisabled: isDisabled,
                      isHoliday: isHoliday,
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

  Widget _offDayCell({
    required double width,
    required double height,
    required String label,
    required bool inMonth,
    required bool isDisabled,
    required bool isHoliday,
    required DateTime? date,
  }) {
    Color border = const Color(0xFFE5E7EB);
    Color bg = Colors.white;
    Color text = const Color(0xFF111827);

    if (!inMonth) text = const Color(0xFF9CA3AF);
    if (isDisabled && inMonth) text = const Color(0xFF9CA3AF);

    if (isHoliday) {
      bg = const Color(0xFFDBEAFE);
      border = const Color(0xFF1D4ED8);
      text = const Color(0xFF1E3A8A);
    }

    return SizedBox(
      width: width,
      height: height,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(8.r),
        child: InkWell(
          borderRadius: BorderRadius.circular(8.r),
          onTap: (!inMonth || isDisabled || date == null)
              ? null
              : () => _toggleOffDay(date),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8.r),
              border: Border.all(color: border),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.sp,
                fontWeight: FontWeight.w600,
                color: text,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // -------- off-days helpers (unchanged behavior) --------
  String _ymd(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final da = d.day.toString().padLeft(2, '0');
    return '$y-$m-$da';
  }

  int _daysInMonth(DateTime firstOfMonth) {
    final firstNext = DateTime(firstOfMonth.year, firstOfMonth.month + 1, 1);
    final lastCurrent = firstNext.subtract(const Duration(days: 1));
    return lastCurrent.day;
  }

  int _leadingEmptyCells(DateTime firstOfMonth) {
    return firstOfMonth.weekday % 7;
  }

  String _monthName(int m) {
    const names = [
      'January','February','March','April','May','June',
      'July','August','September','October','November','December'
    ];
    return names[m - 1];
  }

  void _prevMonthOffCal() {
    final f = _offCalVisibleMonthFirst;
    setState(() => _offCalVisibleMonthFirst = DateTime(f.year, f.month - 1, 1));
  }

  void _nextMonthOffCal() {
    final f = _offCalVisibleMonthFirst;
    setState(() => _offCalVisibleMonthFirst = DateTime(f.year, f.month + 1, 1));
  }

// small helper to compare sets
  bool _setsEqual(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    for (final x in a) {
      if (!b.contains(x)) return false;
    }
    return true;
  }

  Future<void> _toggleOffDay(DateTime date) async {
    // ONLY change local state; do NOT write to Firestore here
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);
    final dateStart  = DateTime(date.year, date.month, date.day);
    if (dateStart.isBefore(todayStart)) {
      return; // past days disabled
    }

    final ymd = _ymd(date);
    final willAdd = !_offDaysYMD.contains(ymd);

    setState(() {
      if (willAdd) {
        _offDaysYMD.add(ymd);
      } else {
        _offDaysYMD.remove(ymd);
      }
      _offDirty = !_setsEqual(_offDaysYMD, _offDaysSaved); // mark unsaved changes
    });
  }


  // ------------------- small UI helpers -------------------
  Widget _detailRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 10.h),
      child: Row(
        children: <Widget>[
          Text(label, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18.sp)),
          SizedBox(width: 12.w),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 18.sp),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class SingleChildScrollPane extends StatelessWidget {
  final bool isAdmin;
  final Widget leftChild;
  final Widget rightChild;

  const SingleChildScrollPane({
    Key? key,
    required this.isAdmin,
    required this.leftChild,
    required this.rightChild,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (isAdmin) {
      return SingleChildScrollView(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // LEFT 1/3: Account
            Expanded(flex: 1, child: leftChild),
            Container(width: 1, color: Colors.black12, margin: const EdgeInsets.symmetric(vertical: 16)),
            // RIGHT 2/3: System Setting
            Expanded(flex: 2, child: rightChild),
          ],
        ),
      );
    }

    // Non-admin unchanged (3 columns feel)
    return SingleChildScrollView(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: leftChild),
          Container(width: 1, color: Colors.black12, margin: const EdgeInsets.symmetric(vertical: 16)),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 560.w),
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 16.h, horizontal: 20.w),
                  child: SingleChildScrollView(
                    primary: false,
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Text("System Setting",
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 26.sp, fontWeight: FontWeight.bold)),
                        SizedBox(height: 35.h),
                        Text("Working Hour", style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold)),
                        SizedBox(height: 12.h),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Container(width: 1, color: Colors.black12, margin: const EdgeInsets.symmetric(vertical: 16)),
          Expanded(child: rightChild),
        ],
      ),
    );
  }
}
