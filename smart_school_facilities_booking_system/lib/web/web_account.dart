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

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? user;
  String? userDocId;

  bool isLoading = true;
  bool isEditing = false;

  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _contactController = TextEditingController();
  final TextEditingController _imageNameController = TextEditingController();
  final GlobalKey<FormState> _editFormKey = GlobalKey<FormState>();

  String profileImage = '';
  String profileImageName = '';
  String username = 'Loading...';
  String contact = 'Loading...';
  String role = 'Loading...';
  bool use24HourFormat = true;

  bool _editWorkingHour = false;
  bool _editWorkingDays = false;
  bool _editHolidays = false;

  TimeOfDay? _origStartTime;
  TimeOfDay? _origEndTime;

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

  DateTime _offCalVisibleMonthFirst = DateTime(DateTime.now().year, DateTime.now().month, 1);
  final Set<String> _offDaysYMD = <String>{};
  bool _loadingOffDays = true;
  Set<String> _offDaysSaved = <String>{};
  bool _offDirty = false;

//---------------------------------------
// init state run this first
//---------------------------------------

  @override
  void initState() {
    super.initState();
    user = _auth.currentUser;
    _loadAll();
  }

  Future<void> _loadAll() async {
    final email = user?.email;

    if (email == null) {
      setState(() {
        isLoading = false;
        username = 'N/A';
        contact = 'N/A';
        role = 'N/A';
      });
      return; // stop here if no user or no email
    }

    await _loadUserInfo(email);
    await _loadSystemSettings();
    await _loadOffDays();

    setState(() {
      isLoading = false;
    });
  }
//---------------------------------------
// load user information
//---------------------------------------

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
//---------------------------------------
// set user name contact role
//---------------------------------------

    String newUsername = (data['username'] ?? 'N/A').toString();
    String newContact = (data['contact'] ?? 'N/A').toString();
    String newRole = (data['role'] ?? 'N/A').toString();
    String newImageName = (data['profileImageName'] ?? '').toString();

    bool newUse24 = data['timeFormat24'] is bool ? (data['timeFormat24'] as bool) : true;

    setState(() {
      username = newUsername;
      contact = newContact;
      role = newRole;
      profileImageName = newImageName;

      _imageNameController.text = profileImageName;

      use24HourFormat = newUse24;
      _usernameController.text = username;
      _contactController.text = contact;
    });
  }
//---------------------------------------
// load setting from database
//---------------------------------------

  Future<void> _loadSystemSettings() async {
    final snap = await _firestore.collection('SystemInformation').doc('Setting').get();
    if (!snap.exists) return;

    final data = snap.data()!;

    final s = data['start'] is String ? data['start'] as String : null;
    final e = data['end'] is String ? data['end'] as String : null;

    bool sun = data['Sunday'];
    bool mon = data['Monday'] ;
    bool tue = data['Tuesday'] ;
    bool wed = data['Wednesday'];
    bool thu = data['Thursday'] ;
    bool fri = data['Friday'] ;
    bool sat = data['Saturday'] ;

    setState(() {
      startTime = (s != null) ? _parseTime(s) : null;
      endTime = (e != null) ? _parseTime(e) : null;
//---------------------------------------
// get the working day
//---------------------------------------

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
//---------------------------------------
// get all the off day
//---------------------------------------

  Future<void> _loadOffDays() async {
    setState(() => _loadingOffDays = true);
    try {
      final doc = await _firestore.collection('SystemInformation').doc('OffDays').get();

      final Set<String> tmp = <String>{};// make a set, set will not have duplicate
      if (doc.exists) {
        final data = doc.data();
        if (data != null && data['offDays'] is List) { //if it is no null means not empty
          for (final v in (data['offDays'] as List)) { //for all the off day,
            final s = v?.toString().trim(); //will be turn into string and trim so that there is no spacing
            if (s != null && s.isNotEmpty) tmp.add(s); // check again makesure not null then add into temp so the set can prevent duplicate off day
          }
        }
      }

      // all of it will save into the this offdayssaved
      _offDaysSaved = Set<String>.from(tmp);

//---------------------------------------
// add the off day to tmp list
//---------------------------------------
      _offDaysYMD
        ..clear() //clear all old value
        ..addAll(tmp); // add the new off day

      _offDirty = false; // nothing pending
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _loadingOffDays = false);
    }
  }

//---------------------------------------
// when confirm press show pop up
//---------------------------------------

  Future<bool> _confirmAction(String title, String message) async {
    final bool? res = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: Text(title, style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w600)),
        content: Text(message, style: TextStyle(fontSize: 14.sp)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel', style: TextStyle(fontSize: 14.sp)),
          ),
          //---------------------------------------
// confirm button press return true
//---------------------------------------
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF0707),
              foregroundColor: Colors.white,
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Confirm', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    return res ?? false;
  }
//---------------------------------------
// asset name from asset folder
//---------------------------------------
  String _assetFromName(String name) {
    if (name.isEmpty) return '';
    return 'asset/image/$name';
  }
//---------------------------------------
// set empty when no profle yet or else place the image
//---------------------------------------

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
      //---------------------------------------
// display image
//---------------------------------------
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        path,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) => const Center(child: Text('empty')),
      ),
    );
  }
  //---------------------------------------
// check username exist
//---------------------------------------
  Future<bool> _usernameExists(String username, userId) async {
    final String u = username.trim();
    if (u.isEmpty) {
      return false;
    }
    try {
      final qs = await FirebaseFirestore.instance
          .collection("UserInformation")
          .where("username", isEqualTo: u)
          .limit(2)
          .get();

      for (final d in qs.docs) {
        if (d.id != userId) return true;
      }
      return false;
  }
    catch (e) {
      return false;
    }
  }


//---------------------------------------
// save account
//---------------------------------------
  Future<void> _saveAccountInfo() async {
    if (userDocId == null) return;

    final bool taken = await _usernameExists(_usernameController.text,userDocId);
    if (taken == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Username already taken.', style: TextStyle(fontSize: 14.sp))),
      );
      setState(() {});
      return;
    }

    final String fname = _imageNameController.text.trim();
//---------------------------------------
// if image not in image
//---------------------------------------
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
//---------------------------------------
// update firebase
//---------------------------------------
    await _firestore
        .collection('UserInformation')
        .doc(userDocId)
        .set(payload, SetOptions(merge: true));
//---------------------------------------
// set user name same as the controller
//---------------------------------------
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
//---------------------------------------
// load the image from asset
//---------------------------------------
  Future<bool> _assetExistsInBundle(String name) async {
    if (name.isEmpty) return false;
    try {
      await rootBundle.load('asset/image/$name');
      return true;
    } catch (_) {
      return false;
    }
  }
//---------------------------------------
// pick image from file
//---------------------------------------

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

//---------------------------------------
// save the start and end time of the system
//---------------------------------------

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
//---------------------------------------
// send passwrod reset email
//---------------------------------------

  Future<void> _sendPasswordReset() async {
    if (user == null || user!.email == null) return;
    await _auth.sendPasswordResetEmail(email: user!.email!);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Reset email sent to ${user!.email!}')),
    );
  }

  //---------------------------------------
// log out navigate user to log in page
//---------------------------------------

  Future<void> _logout() async {
    await _auth.signOut();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }
//---------------------------------------
// parse time for mat to hhmm and get the hour and minute
//---------------------------------------

  TimeOfDay _parseTime(String hhmm) {
    final p = hhmm.split(':');
    return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
  }
  //---------------------------------------
// format time to hh:mm
//---------------------------------------

  String _formatTime(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
//---------------------------------------
// convert hour to minute
//---------------------------------------
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

//---------------------------------------
// get facility available time
//---------------------------------------
  Map<String, String> _readFacilityAvailableTimes(Map<String, dynamic> data) {
    String s = '';
    String e = '';

    final at = data['availableTime'] as Map<String, dynamic>;

      s = (at['start'] as String).trim();
      e = (at['end'] as String).trim();

    return <String, String>{'start': s, 'end': e};
  }

//---------------------------------------
// check if tehre is facility available time conflict
//---------------------------------------

  Future<List<String>> _findFacilityConflicts(String newStart, String newEnd) async {
    //---------------------------------------
// convert the time to minute
//---------------------------------------
    final int sysStart = _timeToMinutes(newStart);
    final int sysEnd = _timeToMinutes(newEnd);
//---------------------------------------
// get the facilities from database
//---------------------------------------
    final qs = await _firestore.collection('Facilities').get();
    final List<String> conflicts = <String>[];

    for (final d in qs.docs) {
      final m = d.data();
//---------------------------------------
// ingnore deletec facilities
//---------------------------------------

      if (m['deleted'] is bool && m['deleted'] == true) continue;

      String name = d.id;
        name = (m['name'] as String).trim();

      final at = _readFacilityAvailableTimes(m);
      final fs = (at['start'] ?? '').trim();
      final fe = (at['end'] ?? '').trim();
      if (fs.isEmpty || fe.isEmpty) continue;

      final facStart = _timeToMinutes(fs);
      final facEnd = _timeToMinutes(fe);
//---------------------------------------
// check if they are conflict if yes add to conflicts list then return conflict
//---------------------------------------
      if (facStart < sysStart || facEnd > sysEnd) {
        conflicts.add(name);
      }
    }
    return conflicts;
  }
//---------------------------------------
// get all the booking time
//---------------------------------------

  Map<String, String> _readBookingTimes(Map<String, dynamic> m) {
    String s = '';
    String e = '';
    s = (m['start'] as String).trim();
    e = (m['end'] as String).trim();

    return <String, String>{'start': s, 'end': e};
  }
//---------------------------------------
// set to hh :mm format
//---------------------------------------

  String _normalizeToHHmm(String raw) {
    if (raw.isEmpty) return '';
    String s = raw.toLowerCase().trim();

      final p = s.split(':');
      String hh = p[0].trim();
      String mm = p.length > 1 ? p[1].trim() : '00';
      int h = int.tryParse(hh) ?? 0;
      int m = int.tryParse(mm) ?? 0;
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

  }
//---------------------------------------
// get the hour to minute
//---------------------------------------
  int _safeMinutes(String raw) {
    final hhmm = _normalizeToHHmm(raw);
    if (hhmm.isEmpty) return -1;
    return _timeToMinutes(hhmm);
  }
//---------------------------------------
// read the booking date and parse to date format
//---------------------------------------
  DateTime? _readBookingDateFromAny(Map<String, dynamic> m) {
    final v = m['bookingDate'];
    if (v is String && v.trim().isNotEmpty) {
      try {
        final p = DateTime.tryParse(v.trim());
        if (p != null) return DateTime(p.year, p.month, p.day);
      } catch (_) {}
    }
    return null;
  }
//---------------------------------------
// find if there is any booking conflicts
//---------------------------------------
  Future<List<String>> _findBookingConflicts(String newStart, String newEnd) async {
    final int sysStart = _timeToMinutes(newStart);
    final int sysEnd = _timeToMinutes(newEnd);
//---------------------------------------
// get today time adn date
//---------------------------------------
    final DateTime now = DateTime.now();
    final DateTime todayStart = DateTime(now.year, now.month, now.day);
    final DateTime cutoff = todayStart.subtract(const Duration(days: 8));
//---------------------------------------
// get booking database
//---------------------------------------
    final QuerySnapshot<Map<String, dynamic>> qs =
    await _firestore.collection('Bookings').get();

    final List<String> conflicts = <String>[];

    for (final doc in qs.docs) {
      final Map<String, dynamic> m = doc.data();
//---------------------------------------
// ignore deleted, rejected and ended booking
//---------------------------------------
      if (m['deleted'] == true) continue;
      final String approval = m['approval'] .toString().toLowerCase();
      if (approval.contains('reject')) continue;
      final String status = (m['status'] ).toString().toLowerCase();
      if (status == 'ended') continue;

      //---------------------------------------
// parse the booking date to date format
//---------------------------------------
      final DateTime? bDate = _readBookingDateFromAny(m);
      if (bDate == null) continue;

      final DateTime bStart = DateTime(bDate.year, bDate.month, bDate.day);
      if (bStart.isBefore(cutoff)) continue;

      final tt = _readBookingTimes(m);
      final int bStartMin = _safeMinutes(tt['start'] ?? '');
      final int bEndMin = _safeMinutes(tt['end'] ?? '');
      if (bStartMin < 0 || bEndMin < 0) continue;
//---------------------------------------
// check if it is within the system start and end time, if yes  add into conflict list
//---------------------------------------
      if (bStartMin < sysStart || bEndMin > sysEnd) {
        conflicts.add(doc.id);
      }
    }
    return conflicts;
  }
//---------------------------------------
// for defacult working days set all to false then set state
//---------------------------------------
  void _defaultWorkingDays() {
    setState(() {
      for (final String k in workingDays.keys.toList()) {
        workingDays[k] = false;
      }
    });
  }
//---------------------------------------
// cancel will revert the original working day to current working day
//---------------------------------------
  void _cancelWorkingDays() {
    setState(() {
      // revert back to DB snapshot
      workingDays = Map<String, bool>.from(_originalWorkingDays);
    });
  }
//---------------------------------------
// make default for all holiday, clear the list
//---------------------------------------
  void _defaultHolidays() {
    setState(() {
      // clear the UI-only set
      _offDaysYMD.clear();
      _offDirty = !_setsEqual(_offDaysYMD, _offDaysSaved);
    });
  }
//---------------------------------------
// cancel holiday, make the list back to previous
//---------------------------------------
  void _cancelHolidays() {
    setState(() {
      // revert UI to DB snapshot
      _offDaysYMD
        ..clear()
        ..addAll(_offDaysSaved);
      _offDirty = false;
    });
  }

  //---------------------------------------
//when apply working hour, check both must have value
//---------------------------------------
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
    //---------------------------------------
// make sure end time but bigger then start time when turn into minute
//---------------------------------------
    if (eMin <= sMin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End time must be later than start time.')),
      );
      return;
    }

//---------------------------------------
// check if there is facility conflict
//---------------------------------------
    final conflictsFacilities = await _findFacilityConflicts(newStartStr, newEndStr);
    if (conflictsFacilities.isNotEmpty) {
      setState(() {
        // revert UI back to original snapshot
        startTime = _origStartTime;
        endTime   = _origEndTime;
        _editWorkingHour = false; // optional: leave edit mode
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Some facilities have available time outside the new window. Reverted changes.'),
        ),
      );
      return;
    }
//---------------------------------------
// check if there is booking conflict
//---------------------------------------
    final conflictsBookings = await _findBookingConflicts(newStartStr, newEndStr);
    if (conflictsBookings.isNotEmpty) {
      setState(() {
        // revert UI back to original snapshot
        startTime = _origStartTime;
        endTime   = _origEndTime;
        _editWorkingHour = false; // optional
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('There are bookings outside the new working hour. Reverted changes.'),
        ),
      );
      return;
    }
//---------------------------------------
// if not conflict set the state and save the system time
//---------------------------------------
    await _saveSystemTimes();
    setState(() {
      // new values become the new "original" baseline for future edits
      _origStartTime = startTime;
      _origEndTime   = endTime;
      _editWorkingHour = false; // exit edit mode after success
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Working hour saved')),
    );
  }
//---------------------------------------
// when apply working day
//---------------------------------------

  Future<void> _applyWorkingDays() async {
    //---------------------------------------
// set the working day into database
//---------------------------------------
    await _firestore.collection('SystemInformation').doc('Setting').set(
      Map<String, dynamic>.from(workingDays),
      SetOptions(merge: true),
    );

    //---------------------------------------
// check which day is disable now
//---------------------------------------

    final Set<String> disabled = workingDays.entries
        .where((e) => e.value == false)
        .map((e) => e.key)
        .toSet();

//---------------------------------------
// process teh day that just disable only
//---------------------------------------
    final Set<String> newlyDisabled = disabled
      ..removeWhere((d) => _originalWorkingDays[d] == false);

    //---------------------------------------
// get the day taht is newly disable
//---------------------------------------
    final Set<String> targetDays = newlyDisabled.isEmpty ? disabled : newlyDisabled;
//---------------------------------------
// if nothing return
//---------------------------------------
    if (targetDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Working days saved')),
      );
      _originalWorkingDays = Map<String, bool>.from(workingDays);
      return;
    }
//---------------------------------------
// if tehre is new disable day,  send out the request mail for update booking
//---------------------------------------

    await _fanOutRequestUpdatesForDaysOfWeek(targetDays);

    _originalWorkingDays = Map<String, bool>.from(workingDays);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Working days saved & users notified')),
    );
  }
//---------------------------------------
// when apply holiday save to database
//---------------------------------------
  Future<void> _applyHolidays() async {
    try {
//---------------------------------------
// set new off day to database
//---------------------------------------

      await _firestore
          .collection('SystemInformation')
          .doc('OffDays')
          .set({'offDays': _offDaysYMD.toList()}, SetOptions(merge: true));

      //---------------------------------------
// send out to booking taht is on that off day
//---------------------------------------
      await _fanOutRequestUpdatesForHolidayDates(_offDaysYMD);

//---------------------------------------
// set state to refresh teh calender
//---------------------------------------
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

  //---------------------------------------
// week day name
//---------------------------------------
  String _weekdayName(int weekday) {
    const names = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
    return names[weekday - 1];
  }
//---------------------------------------
// chechk if the booking should be ingnore
//---------------------------------------
  bool _isBookingIgnored(Map<String, dynamic> m) {
    if (m['deleted'] == true) return true;
    final String approval = (m['approval']).toString().toLowerCase();
    if (approval.contains('reject')) return true;
    final String status = (m['status'] ).toString().toLowerCase();
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
//---------------------------------------
// send out notification taht needs update (in teh set week day)
//---------------------------------------
  Future<void> _fanOutRequestUpdatesForDaysOfWeek(Set<String> disabledDays) async {
    if (disabledDays.isEmpty) return;
//---------------------------------------
// get the booking is bookings database
//---------------------------------------
    final qs = await _firestore.collection('Bookings').get();

    final List<Future<void>> tasks = [];

    for (final doc in qs.docs) {
      final Map<String, dynamic> b = doc.data();
      //---------------------------------------
// if the booking should be ignnore then skip
//---------------------------------------
      if (_isBookingIgnored(b)) continue;
//---------------------------------------
// get the booking date in date format
//---------------------------------------
      final DateTime? d = _readBookingDateFromAny(b);
      if (d == null) continue;

//---------------------------------------
// get the day name for the booking and which contain the off in day
//---------------------------------------
      final String dayName = _weekdayName(d.weekday);
      if (!disabledDays.contains(dayName)) continue;
//---------------------------------------
// add the booking to the send email list
//---------------------------------------
      tasks.add(_emitRequestUpdateForBooking(doc.id, b));
    }

    await Future.wait(tasks);
  }

  //---------------------------------------
// check if there is holiday in the set holiday
//---------------------------------------

  Future<void> _fanOutRequestUpdatesForHolidayDates(Set<String> holidaysYmd) async {
    if (holidaysYmd.isEmpty) return;

    final qs = await _firestore.collection('Bookings').get();
    final List<Future<void>> tasks = [];

    for (final doc in qs.docs) {
      final Map<String, dynamic> b = doc.data();
      if (_isBookingIgnored(b)) continue;
//---------------------------------------
// get booking date
//---------------------------------------
      final DateTime? d = _readBookingDateFromAny(b);
      if (d == null) continue;

      final String y = d.year.toString().padLeft(4, '0');
      final String m = d.month.toString().padLeft(2, '0');
      final String da = d.day.toString().padLeft(2, '0');
      final String ymd = '$y-$m-$da';
//---------------------------------------
// if hiliday same date as booking add to the list
//---------------------------------------
      if (!holidaysYmd.contains(ymd)) continue;
      tasks.add(_emitRequestUpdateForBooking(doc.id, b));
    }

    await Future.wait(tasks);
  }
//---------------------------------------
// send mail to booking that have conflict
//---------------------------------------
  Future<void> _emitRequestUpdateForBooking(String bookingId, Map<String, dynamic> b) async {
    //---------------------------------------
// get user id, facility id, booking date, end , start, seat index
//---------------------------------------
    final String userUid = _readFirstStr(b, ['userId']);
    if (userUid.isEmpty) return;

    final String facilityId = _readFirstStr(b, ['facilityId']);
    if (facilityId.isEmpty) return;

    final String adminUid = _auth.currentUser?.uid ?? '';

    // booking date/time
    final String bookingDateStr = (b['bookingDate']).toString();
    final times = _readBookingTimes(b);
    final String start = (times['start'] ).toString();
    final String end   = (times['end']).toString();

    String seat = '-';
    if (b['seatIndex'] != null) {
      seat = b['seatIndex'].toString();
    }

//---------------------------------------
// also get the facility name
//---------------------------------------
    String facilityName = '';
    try {
      final snap = await _firestore.collection('Facilities').doc(facilityId).get();
      final m = snap.data();
      if (m != null) facilityName = (m['name']).toString();
    } catch (_) {}

//---------------------------------------
// add the new inbox into user database
//---------------------------------------
    final inboxRef = _firestore
        .collection('UserInformation')
        .doc(userUid)
        .collection('Inbox')
        .doc();
    await inboxRef.set({
      'type': 'request_update',
      'recipientId': userUid,
      'bookedBy': userUid,
      'createdBy': adminUid,
      'managerId': adminUid,
      'userId': userUid,
      'facilityId': facilityId,
      'facilityName': facilityName,
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
  Future<void> sendRequestUpdateMails({
    required String bookingId,
    required String userId,
    required String facilityId,
    required String bookingDateIso,
  }) async {
    return;
  }

//---------------------------------------
// main build
//---------------------------------------
  @override
  Widget build(BuildContext context) {
    final double screenHeight = MediaQuery.of(context).size.height;
//---------------------------------------
// check user role
//---------------------------------------
    bool isAdmin = false;
    if (role.isNotEmpty) {
      isAdmin = role.toLowerCase() == 'admin';
    }

//---------------------------------------
// get user email
//---------------------------------------
    final String? email = user?.email;
    String emailStr = email ?? 'N/A';


    //---------------------------------------
// main design 1
//---------------------------------------
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(70.h),
        child: WebCustomTopBar(use24HourFormat: use24HourFormat),
      ),
      body: isLoading ? const Center(child: CircularProgressIndicator()) : ( isAdmin
//---------------------------------------
// if is admin build right and left
//---------------------------------------
          ? SingleChildScrollPane(
        leftChild: _buildLeftColumn(true,  screenHeight, emailStr),
        rightChild: _buildRightColumn(true),
      )
//---------------------------------------
// if not only build one
//---------------------------------------
          : Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 520.w),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 16.h, horizontal: 20.w),
            child: _buildLeftColumn(false, screenHeight, emailStr),
          ),
        ),
      )
      ),

    );
  }

//---------------------------------------
// check strong password
//---------------------------------------
  bool _isPasswordStrong(String password) {
    final RegExp regex =
    RegExp(r'^(?=.*[A-Z])(?=.*[!@#\$%^&*(),.?":{}|<>]).{8,}$');
    return regex.hasMatch(password);
  }
//---------------------------------------
// show the pop up for change password
//---------------------------------------
  Future<void> _openChangePasswordDialog() async {
    // controllers
    final TextEditingController _oldCtrl = TextEditingController();
    final TextEditingController _newCtrl = TextEditingController();
    final TextEditingController _confirmCtrl = TextEditingController();

    // show/hide toggles
    bool _hideOld = true;
    bool _hideNew = true;
    bool _hideConfirm = true;

    // inline errors (red text under fields)
    String? _oldErr;
    String? _newErr;
    String? _confirmErr;
//---------------------------------------
// show pop up dialog
//---------------------------------------
    await showDialog<void>( //show pop up
      context: context,
      barrierDismissible: false, // press outside wont close the pop up
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {

            Future<void> _attemptChange() async {
              setStateDialog(() {
                _oldErr = null;
                _newErr = null;
                _confirmErr = null;
              });

              bool ok = true;
//---------------------------------------
// validation for empty , and strong password and confirm password
//---------------------------------------

              if (_oldCtrl.text.isEmpty) {
                _oldErr = "Old password cannot be empty";
                ok = false;
              }

              if (!_isPasswordStrong(_newCtrl.text)) {
                _newErr = "Min 8 chars, 1 uppercase, 1 special";
                ok = false;
              }

              if (_confirmCtrl.text.isEmpty) {
                _confirmErr = "Confirm password cannot be empty";
                ok = false;
              } else if (_confirmCtrl.text != _newCtrl.text) {
                _confirmErr = "Passwords do not match";
                ok = false;
              }

              if (!ok) {
                setStateDialog(() {});
                return;
              }

              final user = _auth.currentUser;
              if (user == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("No user logged in", style: TextStyle(fontSize: 12.sp))),
                );
                return;
              }

              if (user.email == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("This account does not use email/password", style: TextStyle(fontSize: 12.sp))),
                );
                return;
              }

              try {
                //---------------------------------------
// save into auth fire store
//---------------------------------------
                final cred = EmailAuthProvider.credential(
                  email: user.email!,
                  password: _oldCtrl.text,
                );
                await user.reauthenticateWithCredential(cred);
                await user.updatePassword(_newCtrl.text);
//---------------------------------------
// update success close pop up
//---------------------------------------
                Navigator.of(context).pop(); // close dialog
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Password updated successfully", style: TextStyle(fontSize: 12.sp))),
                );
              } on FirebaseAuthException catch (e) {
                if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
                  setStateDialog(() { _oldErr = "Old password is incorrect"; });
                } else if (e.code == 'weak-password') {
                  setStateDialog(() { _newErr = "New password too weak"; });
                } else if (e.code == 'too-many-requests') {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Too many attempts. Try again later.", style: TextStyle(fontSize: 12.sp))),
                  );
                } else if (e.code == 'requires-recent-login') {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Please log in again and retry.", style: TextStyle(fontSize: 12.sp))),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Failed to change password", style: TextStyle(fontSize: 12.sp))),
                  );
                }
              } catch (_) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Unexpected error", style: TextStyle(fontSize: 12.sp))),
                );
              }
            }
//---------------------------------------
// pop  up change password design
//---------------------------------------
            return AlertDialog(
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              title: Text("Change Password", style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w600)),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
//---------------------------------------
// display old password text field
//---------------------------------------
                      Text("Old Password", style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w500)),
                      TextField(
                        controller: _oldCtrl,
                        obscureText: _hideOld,
                        decoration: InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(borderSide: BorderSide(width: 1.w)),
                          errorText: _oldErr,
                          suffixIcon: IconButton(
                            icon: Icon(_hideOld ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setStateDialog(() => _hideOld = !_hideOld),
                          ),
                        ),
                      ),
                      SizedBox(height: 12.h),
//---------------------------------------
// new password text field
//---------------------------------------
                      Text("New Password", style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w500)),
                      TextField(
                        controller: _newCtrl,
                        obscureText: _hideNew,
                        decoration: InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(borderSide: BorderSide(width: 1.w)),
                          errorText: _newErr,
                          suffixIcon: IconButton(
                            icon: Icon(_hideNew ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setStateDialog(() => _hideNew = !_hideNew),
                          ),
                        ),
                      ),
                      SizedBox(height: 12.h),
//---------------------------------------
// confirm password text field
//---------------------------------------
                      Text("Confirm New Password", style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w500)),
                      TextField(
                        controller: _confirmCtrl,
                        obscureText: _hideConfirm,
                        decoration: InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(borderSide: BorderSide(width: 1.w)),
                          errorText: _confirmErr,
                          suffixIcon: IconButton(
                            icon: Icon(_hideConfirm ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setStateDialog(() => _hideConfirm = !_hideConfirm),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
//---------------------------------------
// cancel button
//---------------------------------------
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text("Cancel", style: TextStyle(fontSize: 14.sp)),
                ),
//---------------------------------------
// confirm button
//---------------------------------------

                ElevatedButton(
                  onPressed: _attemptChange, // start to validate all the password stuff
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8620E5),
                    foregroundColor: Colors.white,
                    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                  ),
                  child: Text("Confirm", style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
                ),
              ],
            );
          },
        );
      },
    );
  }
//---------------------------------------
// main build 2 left list for account page
//---------------------------------------
  Widget _buildLeftColumn(bool isAdmin, double screenHeight, String emailStr) {
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
//---------------------------------------
// display Account setting
//---------------------------------------
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
//---------------------------------------
// if in edditing mode allow to pick image button
//---------------------------------------
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
//---------------------------------------
// display user name text fied
//---------------------------------------
                            TextFormField(
                              controller: _usernameController,
                              decoration: const InputDecoration(labelText: "Username"),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return 'Username cannot be empty';
                                return null;
                              },
                            ),
                            SizedBox(height: 12.h),
//---------------------------------------
// display contact text field
//---------------------------------------
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
//---------------------------------------
// display save account  button
//---------------------------------------
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
//---------------------------------------
// if not in edit mode
//---------------------------------------
                    } else {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
//---------------------------------------
// display user information
//---------------------------------------
                          _detailRow("Username:", username),
                          _detailRow("Email:", emailStr),
                          _detailRow("Contact:", contact),
                          _detailRow("Role:", role),
                          SizedBox(height: 16.h),
//---------------------------------------
// show edit button
//---------------------------------------
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
//---------------------------------------
// below display change password button
//---------------------------------------
                SizedBox(
                  width: double.infinity,
                  height: 48.h,
                  child: ElevatedButton(
 //---------------------------------------
// for admin will send reset password to email, for manager will get the change passwrod pop up
//---------------------------------------
                  onPressed: isAdmin
                        ? _sendPasswordReset
                        : _openChangePasswordDialog,
                    child: const Text("Change Password"),
                  ),
                ),
                SizedBox(height: 16.h),
//---------------------------------------
// log out pop up
//---------------------------------------
                SizedBox(
                  width: double.infinity,
                  height: 48.h,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    onPressed: () async {
                      final ok = await _confirmAction(
                        'Log out?',
                        'Are you sure you want to log out?',
                      );
                      if (!ok) return;
                      await _logout();
                    },

                    child: Text("Log Out", style: TextStyle(color: Colors.white),),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
//---------------------------------------
// main design 3 right column
//---------------------------------------
  Widget _buildRightColumn(bool isAdmin) {
      return Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 1100.w),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 16.h, horizontal: 20.w),
            child: SingleChildScrollView(
              primary: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
//---------------------------------------
// display system setting at center
//---------------------------------------
                  Text(
                    "System Setting",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 26.sp, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 30.h),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
//---------------------------------------
// left part of system setting
//---------------------------------------
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
//---------------------------------------
// working hour
//---------------------------------------
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
 //---------------------------------------
// edit working hout button , in edit mode only allow to press or it will show null (start button)
//---------------------------------------
                                        onPressed: _editWorkingHour ? () => _pickTime(isStart: true) : null,
//---------------------------------------
// if no start time display select normally we should ahve already
//---------------------------------------

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
//---------------------------------------
// this too edit mode only allow to press or it will show null (end button)
//---------------------------------------
                                          onPressed: _editWorkingHour ? () => _pickTime(isStart: false) : null,
                                          child: Text((endTime == null) ? "Select" : _formatTime(endTime!)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 10.h),
//---------------------------------------
// if edit hour is press also show cancel button
//---------------------------------------
                            _editWorkingHour ?
                            Row(
                              children: [
                                SizedBox(
                                  height: 40.h,
                                  child: TextButton(
                                    onPressed: () {
                                      setState(() {
                                        startTime = _origStartTime;
                                        endTime = _origEndTime;
                                        _editWorkingHour = false;
                                      });
                                    },
                                    child: const Text('Cancel'),
                                  ),
                                ),
                                const Spacer(), // push the confirm button to the far right
                                SizedBox(
                                  height: 40.h,
                                  child: ElevatedButton(
//---------------------------------------
// pop up when apply working hour
//---------------------------------------
                                    onPressed: () async {
                                      final ok = await _confirmAction(
                                        'Apply working hour?',
                                        'Are you sure you want to apply the new working hour?',
                                      );
                                      if (!ok) return;
                                      await _applyWorkingHours();
//---------------------------------------
// after apply set edit working hour to false
//---------------------------------------
                                      if (!mounted) return;
                                      setState(() => _editWorkingHour = false);
                                    },
                                    child: const Text('Apply Working Hour'),
                                  ),
                                ),
                              ],
                            )
//---------------------------------------
// while still false show edit button
//---------------------------------------
                                : Align(
                              alignment: Alignment.centerRight,
                              child: SizedBox(
                                height: 40.h,
                                child: ElevatedButton(
                                  onPressed: () {
                                    setState(() {
                                      _origStartTime = startTime;
                                      _origEndTime = endTime;
                                      _editWorkingHour = true;
                                    });
                                  },
                                  child: const Text('Edit'),
                                ),
                              ),
                            ),

                            SizedBox(height: 75.h),

//---------------------------------------
// working day
//---------------------------------------
                            Text("Workdays",
                                style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold)),
                            Column(
                              children: workingDays.keys.map((day) {
                                final bool v = workingDays[day] == true;
                                return SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(day),
                                  value: v,
 //---------------------------------------
// while  edit working days still false set all teh switch to  null
//---------------------------------------
                                  onChanged: _editWorkingDays
                                      ? (bool nv) => setState(() { workingDays[day] = nv; })
                                      : null,
                                );
                              }).toList(),
                            ),
//---------------------------------------
// while edit working days is  true
//---------------------------------------
                            _editWorkingDays
                                ? Row(
                              children: [
  //---------------------------------------
// show reset button
//---------------------------------------
                                SizedBox(
                                  height: 40.h,
                                  child: OutlinedButton(
                                    onPressed: _defaultWorkingDays,//show default working day
                                    child: const Text('Reset'),
                                  ),
                                ),
                                SizedBox(width: 8.w),
//---------------------------------------
// show cancel button
//---------------------------------------
                                SizedBox(
                                  height: 40.h,
                                  child: TextButton(
                                    onPressed: () {
                                      _cancelWorkingDays(); // when cancel button press
                                      setState(() => _editWorkingDays = false);
                                    },
                                    child: const Text('Cancel'),
                                  ),
                                ),
                                const Spacer(),
                                SizedBox(
                                  height: 40.h,
                                  child: ElevatedButton(
//---------------------------------------
// pop up when press confirm
//---------------------------------------
                                    onPressed: () async {
                                      final ok = await _confirmAction(
                                        'Apply working days?',
                                        'Are you sure you want to apply the new working days?',
                                      );
                                      if (!ok) return;
                                      await _applyWorkingDays();
                                      if (!mounted) return;
                                      setState(() => _editWorkingDays = false);
                                    },
                                    child: const Text('Apply Working Days'),
                                  ),
                                ),
                              ],
                            )
//---------------------------------------
// while edit working hour still false
//---------------------------------------
                                : Align(
                              alignment: Alignment.centerRight,
                              child: SizedBox(
                                height: 40.h,
                                child: ElevatedButton(
                                  onPressed: () => setState(() => _editWorkingDays = true),
                                  child: const Text('Edit'),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      SizedBox(width: 24.w),
//---------------------------------------
// right side of system setting
//---------------------------------------
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
//---------------------------------------
// deisplay pick holiday
//---------------------------------------
                            Text("Pick Off Days (Holidays)",
                                style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold)),
                            SizedBox(height: 10.h),
//---------------------------------------
// build teh calender design
//---------------------------------------
                            _buildOffDaysCalendarCard(),
                            SizedBox(height: 6.h),
                            Text(
                              'Tip: Click a future day to toggle holiday. Blue = holiday. Past days are disabled.',
                              style: TextStyle(fontSize: 11.sp, color: const Color(0xFF6B7280)),
                            ),
                            SizedBox(height: 8.h),
//---------------------------------------
// if edit holiday is true
//---------------------------------------

                            _editHolidays
                                ? Row(
//---------------------------------------
// display reset button
//---------------------------------------
                            children: [
                                SizedBox(
                                  height: 40.h,
                                  child: OutlinedButton(
                                    onPressed: _defaultHolidays,
                                    child: const Text('Reset'),
                                  ),
                                ),
                                SizedBox(width: 8.w),
 //---------------------------------------
// cancel button
//---------------------------------------
                              SizedBox(
                                  height: 40.h,
                                  child: TextButton(
                                    onPressed: () {
                                      _cancelHolidays();
                                      setState(() => _editHolidays = false);
                                    },
                                    child: const Text('Cancel'),
                                  ),
                                ),
                                const Spacer(),
                                SizedBox(
                                  height: 40.h,
                                  child: ElevatedButton(
//---------------------------------------
// pop up when apply holiday is press
//---------------------------------------
                                    onPressed: () async {
                                      final ok = await _confirmAction(
                                        'Apply holidays?',
                                        'Are you sure you want to apply the selected holidays?',
                                      );
                                      if (!ok) return;
                                      await _applyHolidays();
                                      if (!mounted) return;
                                      setState(() => _editHolidays = false);
                                    },
                                    child: const Text('Apply Holidays'),
                                  ),
                                ),
                              ],
                            )
 //---------------------------------------
// if its not in edit mode show edit button
//---------------------------------------
                                : Align(
                              alignment: Alignment.centerRight,
                              child: SizedBox(
                                height: 40.h,
                                child: ElevatedButton(
                                  onPressed: () => setState(() => _editHolidays = true),
                                  child: const Text('Edit'),
                                ),
                              ),
                            ),


                            SizedBox(height: 24.h),

                            // // Time Format (moved to the right column per your spec)
                            // Text("Time Format",
                            //     style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold)),
                            // CheckboxListTile(
                            //   contentPadding: EdgeInsets.zero,
                            //   title: const Text("Use 24-Hour Format"),
                            //   value: use24HourFormat,
                            //   onChanged: (bool? v) => _saveTimeFormat(v ?? true),
                            // ),
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


//---------------------------------------
// while pick time is press, show time picker
//---------------------------------------

  Future<void> _pickTime({required bool isStart}) async {
    if (!_editWorkingHour) return;
    //---------------------------------------
// default start on 9 and end on 5 but normally we already have time
//---------------------------------------
    final TimeOfDay initial = isStart
        ? (startTime ?? const TimeOfDay(hour: 9, minute: 0))
        : (endTime ?? const TimeOfDay(hour: 17, minute: 0));
//---------------------------------------
// time picker display
//---------------------------------------
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
//---------------------------------------
// when its picked set state
//---------------------------------------
    setState(() {
      if (isStart) {
        startTime = picked;
      } else {
        endTime = picked;
      }
    });
  }

//---------------------------------------
// build the calender
//---------------------------------------
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
        //---------------------------------------
// 3 component to build the calender
//---------------------------------------
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
//---------------------------------------
// set the label on top calender header
//---------------------------------------
  Widget _buildOffDaysCalendarHeader() {
    final m = _offCalVisibleMonthFirst;
    final label = '${_monthName(m.month)} ${m.year}';

    return Row(
      children: <Widget>[
        Expanded(
          //---------------------------------------
// show month year and button for next and prev
//---------------------------------------
        child: Text(
            label,
            style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600),
          ),
        ),
        //---------------------------------------
// button for prev and next
//---------------------------------------
        TextButton(onPressed: _prevMonthOffCal, child: Text('Prev', style: TextStyle(fontSize: 12.sp))),
        SizedBox(width: 4.w),
        TextButton(onPressed: _nextMonthOffCal, child: Text('Next', style: TextStyle(fontSize: 12.sp))),
      ],
    );
  }
//---------------------------------------
// build the week day
//---------------------------------------
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
//---------------------------------------
// show Sun to Sat
//---------------------------------------

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
//---------------------------------------
// build each cell for calender
//---------------------------------------
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
        double cellW = (c.maxWidth - totalGapW) / 7.0; //find each column width
        if (cellW < 10.w) cellW = 10.w;
        final gridH = (rows * cellW) + ((rows - 1) * gap); //its s square so width can be use as high, then calculate the whole calender high
//---------------------------------------
// display calender cell
//---------------------------------------
        return SizedBox(
          height: gridH,
          child: Column(
            children: List.generate(rows, (r) {
              return Padding(
                padding: EdgeInsets.only(bottom: r == rows - 1 ? 0 : gap),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(7, (cIdx) {
                    final cellIndex = (r * 7) + cIdx; // calender date
                    final dayNum = cellIndex - lead + 1; // calender start of the first date

                    final inMonth = (dayNum >= 1 && dayNum <= days);
                    final DateTime? cellDate =
                    inMonth ? DateTime(f.year, f.month, dayNum) : null;
//---------------------------------------
// get today date
//---------------------------------------
                    final todayOnly = DateUtils.dateOnly(DateTime.now());
                    final cellOnly  = (cellDate == null) ? null : DateUtils.dateOnly(cellDate);
//---------------------------------------
// disable cell for is before today
//---------------------------------------
                    final bool isDisabled = (cellOnly == null) ? true : !cellOnly.isAfter(todayOnly);

                    final String ymd = (cellDate != null) ? _ymd(cellDate) : '';
//---------------------------------------
// check if it is holiday
//---------------------------------------

                    final bool isHoliday =
                        cellDate != null && _offDaysYMD.contains(ymd);
//---------------------------------------
// design each of the cell button
//---------------------------------------
                    return _offDayCell(
                      width: cellW,
                      height: cellW,
                      label: inMonth ? '$dayNum' : '', // day number
                      inMonth: inMonth, // the day is in month
                      isDisabled: isDisabled, // past day and today
                      isHoliday: isHoliday, // wether this day is in the offdayymd after converting to string
                      date: cellDate, //the date
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

//---------------------------------------
// set off day cell
//---------------------------------------
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
//---------------------------------------
// set colour to grey for unable date
//---------------------------------------
    if (!inMonth) text = const Color(0xFF9CA3AF);
    if (isDisabled && inMonth) text = const Color(0xFF9CA3AF);

//---------------------------------------
// save colour for picked holiday cell
//---------------------------------------
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
          //---------------------------------------
// only allow to toggle only if its in active day, and is edit holiday mode
//---------------------------------------
          onTap: (!inMonth || isDisabled || date == null || !_editHolidays)
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

//---------------------------------------
// convert to string pattern for date
//---------------------------------------
  String _ymd(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final da = d.day.toString().padLeft(2, '0');
    return '$y-$m-$da';
  }

  //---------------------------------------
// get the first dat in month then subtract 1 day to get total day for that month
//---------------------------------------

  int _daysInMonth(DateTime firstOfMonth) {
    final firstNext = DateTime(firstOfMonth.year, firstOfMonth.month + 1, 1);
    final lastCurrent = firstNext.subtract(const Duration(days: 1));
    return lastCurrent.day;
  }

  int _leadingEmptyCells(DateTime firstOfMonth) {
    return firstOfMonth.weekday % 7; //This return value tells you how many empty boxes to put before “1” of the month.
  }
//---------------------------------------
// set month name
//---------------------------------------
  String _monthName(int m) {
    const names = [
      'January','February','March','April','May','June',
      'July','August','September','October','November','December'
    ];
    return names[m - 1];
  }
//---------------------------------------
// - 1 month
//---------------------------------------

  void _prevMonthOffCal() {
    final f = _offCalVisibleMonthFirst;
    setState(() => _offCalVisibleMonthFirst = DateTime(f.year, f.month - 1, 1));
  }
//---------------------------------------
// + 1 month
//---------------------------------------

  void _nextMonthOffCal() {
    final f = _offCalVisibleMonthFirst;
    setState(() => _offCalVisibleMonthFirst = DateTime(f.year, f.month + 1, 1));
  }

//---------------------------------------
//if both set is same return true to see if wehter it will have new save or not
//---------------------------------------

  bool _setsEqual(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    for (final x in a) {
      if (!b.contains(x)) return false;
    }
    return true;
  }
//---------------------------------------
// check if it can be holiday, block past and today
//---------------------------------------
  Future<void> _toggleOffDay(DateTime date) async {

    final todayOnly = DateUtils.dateOnly(DateTime.now());
    final dateOnly  = DateUtils.dateOnly(date);
    if (!dateOnly.isAfter(todayOnly)) {
      return; // block past days AND today

    }

    final ymd = _ymd(date);
    final willAdd = !_offDaysYMD.contains(ymd);
//---------------------------------------
// if its no holiday add to off day , if it is tehn remove form holiday
//---------------------------------------

    setState(() {
      if (willAdd) {
        _offDaysYMD.add(ymd);
      } else {
        _offDaysYMD.remove(ymd);
      }
      _offDirty = !_setsEqual(_offDaysYMD, _offDaysSaved); // mark unsaved changes
    });
  }


//---------------------------------------
// display user details nice ly
//---------------------------------------

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

//---------------------------------------
//  main build part that decide which at the left amd right
//---------------------------------------

class SingleChildScrollPane extends StatelessWidget {
  // left side content (Account panel)
  final Widget leftChild;
  // right side content (System Settings panel)
  final Widget rightChild;

  const SingleChildScrollPane({
    Key? key,
    // required = must pass a value (beginner friendly)
    required this.leftChild,
    required this.rightChild,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // SingleChildScrollView = allow page to scroll vertically if content is tall
    return SingleChildScrollView(
      // Padding = give space around content that scales with screen
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 16.h, horizontal: 20.w),
        // Row = horizontal layout (two columns)
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start, // align to top
          children: <Widget>[
            // LEFT 1/3: Account panel
            Expanded(
              flex: 1,            // take 1 part of the width
              child: leftChild,   // show left panel content
            ),

            SizedBox(width: 12.w),                       // small gap
            Container(width: 1.w, color: Colors.black12),// vertical divider
            SizedBox(width: 12.w),                       // small gap

            // RIGHT 2/3: System Settings panel
            Expanded(
              flex: 2,             // take 2 parts of the width
              child: rightChild,   // show right panel content
            ),
          ],
        ),
      ),
    );
  }
}

